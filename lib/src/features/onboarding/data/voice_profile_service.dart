import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../domain/voice_profile_suggestion.dart';

class VoiceProfileServiceException implements Exception {
  const VoiceProfileServiceException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// Sube temporalmente el audio privado y pide al backend una sugerencia de
/// perfil. El archivo se borra tanto en backend como en cliente (best-effort).
class VoiceProfileService {
  VoiceProfileService({
    required FirebaseStorage storage,
    required FirebaseFunctions functions,
  })  : _storage = storage,
        _functions = functions;

  final FirebaseStorage _storage;
  final FirebaseFunctions _functions;

  static const int minDurationMs = 12000;
  static const int maxDurationMs = 120000;
  static const int maxBytes = 10 * 1024 * 1024;
  static const String consentVersion = 'voice-profile-2026-07-29-v1';

  Future<VoiceProfileSuggestion> generate({
    required String uid,
    required Uint8List bytes,
    required String contentType,
    required String extension,
    required int durationMs,
    required String intentMode,
    String locale = 'es-ES',
  }) async {
    final String cleanUid = uid.trim();
    if (cleanUid.isEmpty) {
      throw const VoiceProfileServiceException(
        'No hay una sesión activa para crear el perfil.',
        code: 'unauthenticated',
      );
    }
    if (durationMs < minDurationMs) {
      throw const VoiceProfileServiceException(
        'Cuéntanos un poco más para poder crear un perfil fiel.',
        code: 'audio-too-short',
      );
    }
    if (durationMs > maxDurationMs || bytes.length >= maxBytes) {
      throw const VoiceProfileServiceException(
        'El audio supera el límite de dos minutos.',
        code: 'audio-too-long',
      );
    }

    final String mime = _safeContentType(contentType);
    final String ext = _safeExtension(extension, mime);
    final String fileName =
        'voice_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final Reference ref =
        _storage.ref().child('ephemeral/onboarding_voice/$cleanUid/$fileName');
    bool callableDispatched = false;

    try {
      await ref.putData(
        bytes,
        SettableMetadata(
          contentType: mime,
          cacheControl: 'private, no-store, max-age=0',
          customMetadata: <String, String>{
            'assetType': 'onboarding_voice_once',
            'uploadedBy': cleanUid,
            'retention': 'delete_after_processing',
            'durationMs': durationMs.toString(),
            'consentVersion': consentVersion,
          },
        ),
      );

      final HttpsCallable callable = _functions.httpsCallable(
        'generateProfileFromVoice',
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 120),
        ),
      );
      // Once dispatched, only the backend may delete: a local timeout does not
      // mean Vertex has stopped reading the object.
      callableDispatched = true;
      final HttpsCallableResult<dynamic> result =
          await callable.call(<String, dynamic>{
        'storagePath': ref.fullPath,
        'contentType': mime,
        'durationMs': durationMs,
        'intentMode': intentMode,
        'locale': locale,
        'consent': true,
        'consentVersion': consentVersion,
      });
      final Map<String, dynamic> data = _asMap(result.data);
      final VoiceProfileSuggestion suggestion =
          VoiceProfileSuggestion.fromMap(data);
      if (suggestion.bio.length < 20) {
        throw const VoiceProfileServiceException(
          'No hemos podido sacar suficiente contexto. Prueba con otro audio.',
          code: 'insufficient-context',
        );
      }
      return suggestion;
    } on VoiceProfileServiceException {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      throw VoiceProfileServiceException(
        _messageForFunctionsError(error),
        code: error.code,
      );
    } on FirebaseException catch (error) {
      throw VoiceProfileServiceException(
        error.code == 'unauthorized'
            ? 'No se pudo proteger el audio. Vuelve a iniciar sesión.'
            : 'No se pudo procesar el audio. Comprueba tu conexión e inténtalo otra vez.',
        code: error.code,
      );
    } catch (_) {
      throw const VoiceProfileServiceException(
        'No se pudo crear el perfil con este audio. Inténtalo otra vez.',
      );
    } finally {
      // Before dispatch, no server invocation can own cleanup. Afterwards the
      // callable's finally block and scheduled sweeper are authoritative.
      if (!callableDispatched) {
        try {
          await ref.delete();
        } catch (_) {
          // A scheduled backend sweep remains the retention fallback.
        }
      }
    }
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map(
        (dynamic key, dynamic item) => MapEntry(key.toString(), item),
      );
    }
    throw const VoiceProfileServiceException(
      'La IA devolvió una respuesta que no se puede revisar.',
      code: 'invalid-response',
    );
  }

  static String _safeContentType(String raw) {
    final String value = raw.trim().toLowerCase();
    const Set<String> allowed = <String>{
      'audio/m4a',
      'audio/mp4',
      'audio/aac',
      'audio/x-aac',
      'audio/mpeg',
      'audio/mp3',
      'audio/ogg',
      'audio/opus',
      'audio/wav',
      'audio/webm',
    };
    return allowed.contains(value) ? value : 'audio/mp4';
  }

  static String _safeExtension(String raw, String contentType) {
    final String value = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    const Set<String> allowed = <String>{
      'm4a',
      'mp4',
      'aac',
      'mp3',
      'ogg',
      'opus',
      'wav',
      'webm',
    };
    if (allowed.contains(value)) return value;
    if (contentType.contains('webm')) return 'webm';
    if (contentType.contains('wav')) return 'wav';
    if (contentType.contains('ogg')) return 'ogg';
    return 'm4a';
  }

  static String _messageForFunctionsError(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'resource-exhausted':
        return 'Has hecho varios intentos. Espera un poco antes de volver a probar.';
      case 'failed-precondition':
        return error.message ??
            'El audio no está listo para procesarse. Vuelve a grabarlo.';
      case 'permission-denied':
      case 'unauthenticated':
        return 'Tu sesión ha caducado. Inicia sesión de nuevo.';
      case 'invalid-argument':
        return error.message ?? 'El formato de audio no es compatible.';
      case 'deadline-exceeded':
      case 'unavailable':
        return 'La IA está tardando más de lo normal. Inténtalo de nuevo en un momento.';
      default:
        return error.message ??
            'No se pudo crear el perfil. Inténtalo otra vez.';
    }
  }
}
