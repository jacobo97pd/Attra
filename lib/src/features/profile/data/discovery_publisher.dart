import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/profile_trait.dart';
import '../domain/profile_traits_catalog.dart';
import '../domain/profile_visibility.dart';
import '../domain/public_identity.dart';

/// Construye el documento PUBLICO de `discovery/{uid}` a partir de
/// `users/{uid}`, respetando visibilidad/consentimiento. PURO (sin I/O) para
/// ser testeable.
///
/// Garantias:
/// - NUNCA publica email, nombre legal/Auth, tokens, selfie privada ni lat/lng.
/// - El nombre es el PUBLICO elegido ([resolvePublicDisplayName]).
/// - Un rasgo sensible solo se publica si visibleInProfile=true.
/// - Un valor `prefer_not_to_say` (o vacío) no se publica.
class DiscoveryPublisher {
  const DiscoveryPublisher._();

  static Map<String, dynamic> buildPayload(
    String uid,
    Map<String, dynamic> userData,
  ) {
    final Map<String, dynamic> profile = _map(userData['profile']);
    final Map<String, dynamic> prefs = _map(userData['preferences']);
    final ProfileVisibility vis = ProfileVisibility.fromUserData(userData);
    final DateTime? birthDate =
        _asDate(profile['birthDate']) ?? _asDate(userData['birthDate']);
    final int? age = _asInt(profile['age']) ??
        _asInt(userData['age']) ??
        _ageFromBirthDate(birthDate);

    // Núcleo público no sensible (identidad/matching mínimos).
    final Map<String, dynamic> out = <String, dynamic>{
      'uid': uid,
      'isBot': false,
      'displayName': resolvePublicDisplayName(userData),
      'photoUrl': userData['photoUrl'] ?? userData['profilePhotoUrl'] ?? '',
      'photos': userData['photos'] ?? <dynamic>[],
      'gender': profile['gender'] ?? '',
      'interestedIn': prefs['interestedIn'] ?? <dynamic>[],
      'age': age,
      'bio': profile['bio'] ?? '',
      'currentCity': profile['currentCity'] ?? profile['city'] ?? '',
      'currentCountryName': profile['currentCountryName'] ?? '',
    };

    // Rasgos del catálogo: se publican bajo su `field` si son utilizables y
    // visibles (los sensibles requieren visibleInProfile explícito).
    // Además, los SENSIBLES con consentimiento useForFilters se publican en un
    // mapa aparte `filterTraits` (para poder filtrar por ellos sin exponerlos
    // si solo se quería matching).
    final Map<String, dynamic> filterTraits = <String, dynamic>{};
    for (final ProfileTraitDefinition def in ProfileTraitsCatalog.all) {
      final Object? value = _map(userData[def.group])[def.field];
      if (!isUsableTraitValue(value)) continue;
      final FieldVisibility fv = vis.effectiveFor(def);
      if (fv.visibleInProfile) {
        out[def.field] = _clean(value);
      }
      if (def.sensitive && fv.useForFilters && value is String) {
        filterTraits[def.field] = value;
      }
    }
    if (filterTraits.isNotEmpty) out['filterTraits'] = filterTraits;

    // Prompts de perfil (pregunta+respuesta): públicos por diseño, solo los
    // activos y con campos mínimos (sin metadatos internos).
    final List<dynamic> rawPrompts =
        (userData['profilePrompts'] as List<dynamic>?) ?? <dynamic>[];
    final List<Map<String, dynamic>> publicPrompts = rawPrompts
        .whereType<Map>()
        .map((Map<dynamic, dynamic> e) =>
            e.map((dynamic k, dynamic v) => MapEntry(k.toString(), v)))
        .where((Map<String, dynamic> m) => (m['isActive'] as bool?) ?? true)
        .map((Map<String, dynamic> m) => <String, dynamic>{
              'id': m['id'] ?? '',
              'question': m['question'] ?? '',
              'answer': m['answer'] ?? '',
            })
        .where((Map<String, dynamic> m) =>
            (m['question'] as String).isNotEmpty &&
            (m['answer'] as String).isNotEmpty)
        .toList(growable: false);
    if (publicPrompts.isNotEmpty) out['profilePrompts'] = publicPrompts;

    // Media de presentación (audio/vídeo): pública por diseño. Se publica el
    // mapa tal cual (url/storagePath/durationMs) si existe.
    final Object? introAudio = profile['introAudio'];
    if (introAudio is Map && (introAudio['url'] ?? '').toString().isNotEmpty) {
      out['introAudio'] = introAudio;
    }
    final Object? introVideo = profile['introVideo'];
    if (introVideo is Map && (introVideo['url'] ?? '').toString().isNotEmpty) {
      out['introVideo'] = introVideo;
    }

    // Verificación (selfie/identidad) — bool público.
    final Map<String, dynamic> verification = _map(userData['verification']);
    final String selfie =
        (verification['liveSelfiePublicPhotoUrl'] as String?)?.trim() ?? '';
    if (selfie.isNotEmpty) out['verified'] = true;

    // Ubicación APROXIMADA (coords redondeadas ~1.1km) para distancia. NUNCA
    // exacta. Solo si el usuario tiene ubicación.
    final Map<String, dynamic> location = _map(userData['location']);
    final double? lat = _asDouble(location['latitude']);
    final double? lng = _asDouble(location['longitude']);
    if (lat != null && lng != null) {
      out['geo'] = <String, dynamic>{
        'lat': _round2(lat),
        'lng': _round2(lng),
      };
    }

    return out;
  }

  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  static double? _asDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static int? _asInt(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static DateTime? _asDate(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static int? _ageFromBirthDate(DateTime? birthDate) {
    if (birthDate == null) return null;
    final DateTime now = DateTime.now();
    final DateTime localBirthDate = birthDate.toLocal();
    int age = now.year - localBirthDate.year;
    final bool hasBirthdayPassed = now.month > localBirthDate.month ||
        (now.month == localBirthDate.month && now.day >= localBirthDate.day);
    if (!hasBirthdayPassed) age -= 1;
    if (age < 0 || age > 120) return null;
    return age;
  }

  /// Quita valores prefer_not_to_say de las listas antes de publicar.
  static Object? _clean(Object? value) {
    if (value is List) {
      return value
          .whereType<String>()
          .where((String e) => e.trim().isNotEmpty && e != 'prefer_not_to_say')
          .toList(growable: false);
    }
    return value;
  }

  static Map<String, dynamic> _map(Object? v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) {
      return v.map((dynamic k, dynamic val) => MapEntry(k.toString(), val));
    }
    return <String, dynamic>{};
  }
}
