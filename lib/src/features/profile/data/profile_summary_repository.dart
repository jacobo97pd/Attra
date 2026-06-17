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

  Future<ProfileSummary> fetch(String uid) async {
    if (uid.isEmpty) return ProfileSummary.unknown;
    final ProfileSummary? cached = _cache[uid];
    if (cached != null) return cached;

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
    );
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
