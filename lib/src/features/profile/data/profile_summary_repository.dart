import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../domain/profile_summary.dart';

/// Lee un documento público: sus datos, o null si no existe.
typedef PublicProfileDocReader = Future<Map<String, dynamic>?> Function(
    String collection, String uid);

/// Dónde se busca la ficha pública de un uid, por orden:
///  1. `discovery`: quien sale en el feed (cualquier sesión la lee).
///  2. `seed_profiles`: perfiles de prueba.
///  3. `profileCards`: la ficha de quien NO sale en el feed (perfil oculto,
///     cuenta pausada, sin recomendaciones o incógnito). Antes esas cuentas no
///     tenían ninguna ficha legible: sus matches y a quien habían dado like
///     veían "Alguien" sin foto y "No se pudo cargar el perfil". La escribe
///     solo el backend y las reglas solo dejan leerla a su match activo y a
///     las personas a las que dio like.
///
/// NO se usa `users`: es owner-read-only y el doc de OTRO usuario da
/// permission-denied.
const List<String> kPublicProfileCollections = <String>[
  'discovery',
  'seed_profiles',
  'profileCards',
];

/// Lector real de Firestore para [findPublicProfileDoc].
PublicProfileDocReader firestoreProfileDocReader(FirebaseFirestore firestore) {
  return (String collection, String uid) async {
    final DocumentSnapshot<Map<String, dynamic>> snap =
        await firestore.collection(collection).doc(uid).get();
    return snap.exists ? (snap.data() ?? <String, dynamic>{}) : null;
  };
}

/// Primera ficha pública de [uid] según [kPublicProfileCollections]: la
/// colección donde está y sus datos, o null si no hay ninguna para quien
/// pregunta.
///
/// Un `permission-denied` en `profileCards` es la respuesta normal cuando no
/// hay relación con esa persona (p. ej. un like que ya se canceló): equivale a
/// "no hay ficha", no a un error. Cualquier otro fallo se propaga, como antes.
Future<MapEntry<String, Map<String, dynamic>>?> findPublicProfileDoc(
  String uid,
  PublicProfileDocReader read,
) async {
  if (uid.isEmpty) return null;
  for (final String collection in kPublicProfileCollections) {
    Map<String, dynamic>? data;
    try {
      data = await read(collection, uid);
    } on FirebaseException catch (error) {
      if (collection != 'profileCards' || error.code != 'permission-denied') {
        rethrow;
      }
      return null;
    }
    if (data != null) {
      return MapEntry<String, Map<String, dynamic>>(collection, data);
    }
  }
  return null;
}

/// Resuelve nombre + foto de un uid para listas (ver
/// [kPublicProfileCollections]). Cachea en memoria para no releer.
class ProfileSummaryRepository {
  ProfileSummaryRepository({required FirebaseFirestore firestore})
      : _read = firestoreProfileDocReader(firestore);

  /// Con un lector propio: para probar la cadena de búsqueda sin Firestore.
  @visibleForTesting
  ProfileSummaryRepository.withReader(PublicProfileDocReader read)
      : _read = read;

  final PublicProfileDocReader _read;
  final Map<String, ProfileSummary> _cache = <String, ProfileSummary>{};
  // Peticiones en vuelo: cuando un grid pinta N tarjetas del mismo uid a la vez,
  // se comparte UNA sola lectura en lugar de lanzar N idénticas.
  final Map<String, Future<ProfileSummary>> _inFlight =
      <String, Future<ProfileSummary>>{};

  /// Lectura síncrona de la caché (sin red). Útil para pintar al instante y
  /// evitar el parpadeo de "Alguien" cuando el dato ya se conoce.
  ProfileSummary? peek(String uid) => _cache[uid];

  Future<ProfileSummary> fetch(String uid) {
    if (uid.isEmpty) {
      return Future<ProfileSummary>.value(ProfileSummary.unknown);
    }
    final ProfileSummary? cached = _cache[uid];
    if (cached != null) return Future<ProfileSummary>.value(cached);

    // Reusa la lectura en vuelo si ya hay una para este uid.
    final Future<ProfileSummary>? pending = _inFlight[uid];
    if (pending != null) return pending;

    final Future<ProfileSummary> future = _load(uid);
    _inFlight[uid] = future;
    return future;
  }

  Future<ProfileSummary> _load(String uid) async {
    try {
      final MapEntry<String, Map<String, dynamic>>? found =
          await findPublicProfileDoc(uid, _read);
      final ProfileSummary summary = found == null
          ? ProfileSummary.unknown.copyWith(uid: uid)
          : _summaryFrom(uid, found.value);
      // Solo cachea si se resolvio (evita fijar "Alguien" si discovery aun no
      // estaba sincronizado en el momento de la primera lectura).
      if (summary.displayName != 'Alguien') {
        _cache[uid] = summary;
      }
      return summary;
    } finally {
      _inFlight.remove(uid);
    }
  }

  ProfileSummary _summaryFrom(String uid, Map<String, dynamic> data) {
    return ProfileSummary(
      uid: uid,
      displayName: (data['displayName'] as String?)?.trim().isNotEmpty == true
          ? data['displayName'] as String
          : 'Alguien',
      photoUrl: _photoFrom(data),
      age: _asInt(data['age']),
      // discovery/profileCards publican `jobTitle`; seed_profiles también.
      headline: (data['jobTitle'] as String?)?.trim() ?? '',
      // discovery/profileCards: currentCity/currentCountryName ·
      // seed_profiles: city/country.
      city: ((data['currentCity'] ?? data['city']) as String?)?.trim() ?? '',
      country: ((data['currentCountryName'] ?? data['country']) as String?)
              ?.trim() ??
          '',
      verified: data['verified'] == true,
      interests: _stringList(data['interests']),
    );
  }

  static int? _asInt(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static List<String> _stringList(Object? v) {
    if (v is List) {
      return v
          .whereType<String>()
          .map((String s) => s.trim())
          .where((String s) => s.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  String _photoFrom(Map<String, dynamic> data) {
    final String direct = (data['photoUrl'] as String?) ??
        (data['profilePhotoUrl'] as String?) ??
        '';
    if (direct.isNotEmpty) return direct;
    final List<dynamic> photos =
        (data['photos'] as List<dynamic>?) ?? <dynamic>[];
    for (final dynamic p in photos) {
      if (p is Map && (p['url'] as String?)?.isNotEmpty == true) {
        return p['url'] as String;
      }
    }
    return '';
  }
}
