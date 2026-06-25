import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as img;

import '../../chat_game/domain/chat_game.dart';
import '../domain/chat.dart';
import '../domain/chat_message.dart';
import 'chat_repository.dart';

class ChatServiceException implements Exception {
  const ChatServiceException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => 'ChatServiceException($code): $message';
}

/// Resultado de procesar una imagen antes de subirla.
class _ProcessedImage {
  const _ProcessedImage({
    required this.bytes,
    required this.width,
    required this.height,
  });
  final Uint8List bytes;
  final int width;
  final int height;
}

/// Fachada de chat para la UI: enviar/leer/typing via Cloud Functions +
/// streams de lectura via ChatRepository.
class ChatService {
  ChatService({
    required ChatRepository repository,
    required FirebaseFunctions functions,
    required FirebaseStorage storage,
  })  : _repository = repository,
        _functions = functions,
        _storage = storage;

  final ChatRepository _repository;
  final FirebaseFunctions _functions;
  final FirebaseStorage _storage;

  /// Lado mayor maximo de una imagen tras redimensionar (px).
  static const int _maxImageDimension = 1600;

  // --- Escrituras (backend) ---

  /// Devuelve el id del mensaje creado.
  Future<String> sendMessage({
    required String chatId,
    required String text,
    String? gameSessionId,
  }) async {
    final Map<String, dynamic> data =
        await _call('sendMessage', <String, dynamic>{
      'chatId': chatId,
      'text': text,
      if (gameSessionId != null) 'gameSessionId': gameSessionId,
    });
    return (data['messageId'] as String?) ?? '';
  }

  /// Envia una FOTO: redimensiona + recomprime a JPEG (esto ELIMINA el EXIF al
  /// re-codificar), sube a Storage en ruta segura por uid y crea el mensaje via
  /// `sendMediaMessage` (que valida tamaño/MIME real del objeto). Devuelve el id.
  Future<String> sendImage({
    required String chatId,
    required String senderUid,
    required Uint8List bytes,
    String? fileName,
  }) async {
    final _ProcessedImage processed = _processImage(bytes);
    final String messageId = _genId();
    final String path = 'chats/$chatId/images/$senderUid/$messageId.jpg';
    final String url =
        await _uploadToStorage(path, processed.bytes, 'image/jpeg');
    await _call('sendMediaMessage', <String, dynamic>{
      'chatId': chatId,
      'messageId': messageId,
      'type': 'image',
      'storagePath': path,
      'downloadUrl': url,
      'mimeType': 'image/jpeg',
      'width': processed.width,
      'height': processed.height,
      if (fileName != null) 'fileName': fileName,
    });
    return messageId;
  }

  /// Envia una FOTO BOMBA: se procesa igual que una foto normal, pero se sube a
  /// una ruta sin lectura directa y el mensaje no guarda downloadUrl. El
  /// receptor la abre con [openBombImage], que consume la unica vista.
  Future<String> sendBombImage({
    required String chatId,
    required String senderUid,
    required Uint8List bytes,
    String? fileName,
  }) async {
    final _ProcessedImage processed = _processImage(bytes);
    final String messageId = _genId();
    final String path = 'chats/$chatId/bombs/$senderUid/$messageId.jpg';
    await _uploadToStorage(
      path,
      processed.bytes,
      'image/jpeg',
      returnDownloadUrl: false,
    );
    await _call('sendMediaMessage', <String, dynamic>{
      'chatId': chatId,
      'messageId': messageId,
      'type': 'bomb_image',
      'storagePath': path,
      'mimeType': 'image/jpeg',
      'width': processed.width,
      'height': processed.height,
      if (fileName != null) 'fileName': fileName,
    });
    return messageId;
  }

  /// Envia una NOTA DE VOZ: sube el audio grabado a Storage y crea el mensaje.
  Future<String> sendVoiceNote({
    required String chatId,
    required String senderUid,
    required Uint8List bytes,
    required int durationMs,
    String contentType = 'audio/mp4',
    String extension = 'm4a',
  }) async {
    final String messageId = _genId();
    final String path = 'chats/$chatId/voice/$senderUid/$messageId.$extension';
    final String url = await _uploadToStorage(path, bytes, contentType);
    await _call('sendMediaMessage', <String, dynamic>{
      'chatId': chatId,
      'messageId': messageId,
      'type': 'voice_note',
      'storagePath': path,
      'downloadUrl': url,
      'mimeType': contentType,
      'durationMs': durationMs,
    });
    return messageId;
  }

  /// Sube bytes a Storage y devuelve la downloadUrl. Traduce los errores de
  /// Storage (reglas, CORS, red…) a un ChatServiceException legible para la UI.
  Future<String> _uploadToStorage(
    String path,
    Uint8List bytes,
    String contentType, {
    bool returnDownloadUrl = true,
  }) async {
    try {
      final Reference ref = _storage.ref().child(path);
      await ref.putData(bytes, SettableMetadata(contentType: contentType));
      if (!returnDownloadUrl) return '';
      return await ref.getDownloadURL();
    } on FirebaseException catch (e) {
      throw ChatServiceException(
        'Error al subir a Storage: ${e.code}${e.message != null ? ' — ${e.message}' : ''}',
        code: e.code,
      );
    }
  }

  /// Redimensiona (lado mayor <= [_maxImageDimension]) y re-codifica a JPEG.
  _ProcessedImage _processImage(Uint8List bytes) {
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const ChatServiceException('No se pudo procesar la imagen.');
    }
    img.Image out = decoded;
    final int longest =
        decoded.width > decoded.height ? decoded.width : decoded.height;
    if (longest > _maxImageDimension) {
      if (decoded.width >= decoded.height) {
        out = img.copyResize(decoded, width: _maxImageDimension);
      } else {
        out = img.copyResize(decoded, height: _maxImageDimension);
      }
    }
    final Uint8List jpeg = Uint8List.fromList(img.encodeJpg(out, quality: 80));
    return _ProcessedImage(bytes: jpeg, width: out.width, height: out.height);
  }

  String _genId() {
    final int ts = DateTime.now().millisecondsSinceEpoch;
    // 0x7FFFFFFF (2^31-1) es seguro en web; `1 << 32` desborda a 0 en dart2js.
    final Random rng = Random();
    final String a = rng.nextInt(0x7FFFFFFF).toRadixString(16);
    final String b = rng.nextInt(0x7FFFFFFF).toRadixString(16);
    return '${ts}_$a$b';
  }

  Future<void> markAsRead(String chatId) async {
    await _call('markMessagesAsRead', <String, dynamic>{'chatId': chatId});
  }

  /// Marca el chat como no leido solo para el usuario actual (no toca mensajes).
  Future<void> markAsUnread(String chatId) async {
    await _call('markChatAsUnread', <String, dynamic>{'chatId': chatId});
  }

  /// Consume una foto bomba y devuelve sus BYTES (una sola vez). El backend
  /// envía la imagen en base64 y borra el fichero; si ya fue abierta, rechaza.
  Future<Uint8List> openBombImage({
    required String chatId,
    required String messageId,
  }) async {
    final Map<String, dynamic> data =
        await _call('openBombImage', <String, dynamic>{
      'chatId': chatId,
      'messageId': messageId,
    });
    final String b64 = (data['imageBase64'] as String?) ?? '';
    if (b64.isEmpty) {
      throw const ChatServiceException('No se pudo abrir la foto bomba.');
    }
    return base64Decode(b64);
  }

  /// Crea una propuesta de cita (mensaje `date_proposal`) en el chat.
  Future<String> sendDateProposal({
    required String chatId,
    required String proposedDate,
    required String proposedTime,
    required String placeName,
    String placeAddress = '',
    String note = '',
  }) async {
    final Map<String, dynamic> data =
        await _call('sendDateProposal', <String, dynamic>{
      'chatId': chatId,
      'proposedDate': proposedDate,
      'proposedTime': proposedTime,
      'placeName': placeName,
      if (placeAddress.isNotEmpty) 'placeAddress': placeAddress,
      if (note.isNotEmpty) 'note': note,
    });
    return (data['messageId'] as String?) ?? '';
  }

  /// El receptor responde a una propuesta: accepted | declined | countered.
  Future<void> respondDateProposal({
    required String chatId,
    required String messageId,
    required String response,
  }) async {
    await _call('respondDateProposal', <String, dynamic>{
      'chatId': chatId,
      'messageId': messageId,
      'response': response,
    });
  }

  Future<String> startDoubleAnswer({
    required String chatId,
    required String question,
  }) async {
    final Map<String, dynamic> data =
        await _call('startDoubleAnswer', <String, dynamic>{
      'chatId': chatId,
      'question': question,
    });
    return (data['messageId'] as String?) ?? '';
  }

  Future<void> submitDoubleAnswer({
    required String chatId,
    required String messageId,
    required String answer,
  }) async {
    await _call('submitDoubleAnswer', <String, dynamic>{
      'chatId': chatId,
      'messageId': messageId,
      'answer': answer,
    });
  }

  Future<String> startTwoTruths({
    required String chatId,
    required List<String> statements,
    required int lieIndex,
  }) async {
    final Map<String, dynamic> data =
        await _call('startTwoTruths', <String, dynamic>{
      'chatId': chatId,
      'statements': statements,
      'lieIndex': lieIndex,
    });
    return (data['messageId'] as String?) ?? '';
  }

  Future<void> guessTwoTruths({
    required String chatId,
    required String messageId,
    required int guessIndex,
  }) async {
    await _call('guessTwoTruths', <String, dynamic>{
      'chatId': chatId,
      'messageId': messageId,
      'guessIndex': guessIndex,
    });
  }

  Future<void> setTyping(String chatId, bool isTyping) async {
    await _call('setTyping', <String, dynamic>{
      'chatId': chatId,
      'isTyping': isTyping,
    });
  }

  // --- Duelo de Química (reto de 5 min) ---

  /// Crea el reto e inserta la tarjeta de invitación en el chat. [mode] =
  /// 'normal' | 'coffee_challenge' (este último requiere consentimiento de ambos).
  /// Devuelve el id de la sesión.
  Future<String> startChatGame({
    required String chatId,
    String mode = 'normal',
  }) async {
    final Map<String, dynamic> data =
        await _call('startChatGame', <String, dynamic>{
      'chatId': chatId,
      'mode': mode,
    });
    return (data['sessionId'] as String?) ?? '';
  }

  /// El invitado acepta/rechaza. Si ambos aceptan, arranca el reto (tema + 5 min).
  /// Para 'coffee_challenge', [accept] true implica aceptar la regla del café.
  Future<void> respondChatGame({
    required String chatId,
    required String sessionId,
    required bool accept,
  }) async {
    await _call('respondChatGame', <String, dynamic>{
      'chatId': chatId,
      'sessionId': sessionId,
      'accept': accept,
    });
  }

  /// Cierra el reto al agotarse el tiempo: la IA analiza SOLO los mensajes de
  /// esos 5 minutos y emite el resultado. Idempotente (si ya está cerrado, no-op).
  Future<void> finishChatGame({
    required String chatId,
    required String sessionId,
  }) async {
    await _call('finishChatGame', <String, dynamic>{
      'chatId': chatId,
      'sessionId': sessionId,
    });
  }

  /// Abandona el reto en curso (sin penalización): lo deja en `abandoned`.
  Future<void> abandonChatGame({
    required String chatId,
    required String sessionId,
  }) async {
    await _call('abandonChatGame', <String, dynamic>{
      'chatId': chatId,
      'sessionId': sessionId,
    });
  }

  Stream<ChatGameSession?> observeGameSession(String chatId, String sessionId) =>
      _repository.observeGameSession(chatId, sessionId);

  // --- Lecturas ---

  Stream<List<Chat>> observeChats(String uid) => _repository.observeChats(uid);

  Stream<Chat?> observeChatById(String chatId) =>
      _repository.observeChatById(chatId);

  Stream<List<ChatMessage>> observeMessages(String chatId) =>
      _repository.observeMessages(chatId);

  Future<Map<String, dynamic>> _call(
      String name, Map<String, dynamic> data) async {
    try {
      final HttpsCallableResult<dynamic> result =
          await _functions.httpsCallable(name).call<dynamic>(data);
      final dynamic raw = result.data;
      if (raw is Map) {
        return raw.map((dynamic k, dynamic v) => MapEntry(k.toString(), v));
      }
      return <String, dynamic>{};
    } on FirebaseFunctionsException catch (error) {
      throw ChatServiceException(error.message ?? error.code, code: error.code);
    }
  }
}
