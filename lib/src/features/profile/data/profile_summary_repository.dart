import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/profile_summary.dart';

/// Resuelve nombre + foto de un uid para listas. Busca en `discovery` (perfiles
/// reales, lectura publica) y, si no, en `seed_profiles` (mocks). NO usa `users`
/// porque es owner-read-only: leer el doc de OTRO usuario da permission-denied.
/// Cachea en memoria para no releer.
class ProfileSummaryRepository {
  ProfileSummaryRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;
  final Map<String, ProfileSummary> _cache = <String, ProfileSummary>{};
  // Peticiones en vuelo: cuando un grid pinta N tarjetas del mismo uid a la vez,
  // se comparte UNA sola lectura en lugar de lanzar N idénticas.
  final Map<String, Future<ProfileSummary>> _inFlight =
      <String, Future<ProfileSummary>>{};

  /// Lectura síncrona de la caché (sin red). Útil para pintar al instante y
  /// evitar el parpadeo de "Alguien" cuando el dato ya se conoce.
  ProfileSummary? peek(String uid) => _cache[uid];

  Future<ProfileSummary> fetch(String uid) {
    if (uid.isEmpty) return Future<ProfileSummary>.value(ProfileSummary.unknown);
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
      final ProfileSummary summary =
          await _fromCollection('discovery', uid) ??
              await _fromCollection('seed_profiles', uid) ??
              ProfileSummary.unknown.copyWith(uid: uid);
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

  Future<ProfileSummary?> _fromCollection(String collection, String uid) async {
    final DocumentSnapshot<Map<String, dynamic>> snap =
        await _firestore.collection(collection).doc(uid).get();
    if (!snap.exists) return null;
    final Map<String, dynamic> data = snap.data() ?? <String, dynamic>{};
    return ProfileSummary(
      uid: uid,
      displayName: (data['displayName'] as String?)?.trim().isNotEmpty == true
          ? data['displayName'] as String
          : 'Alguien',
      photoUrl: _photoFrom(data),
      age: _asInt(data['age']),
      // discovery publica `jobTitle`; seed_profiles también lo trae.
      headline: (data['jobTitle'] as String?)?.trim() ?? '',
      // discovery: currentCity/currentCountryName · seed_profiles: city/country.
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
