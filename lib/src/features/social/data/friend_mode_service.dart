import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/intent_mode.dart';

/// Gestiona la intención del usuario (Modo Amigos) y sus preferencias sociales.
/// Escribe en `users/{uid}.profile.*` (escribible por el dueño), lo que dispara
/// la sincronización a `discovery` (Cloud Function) para que el feed filtre.
class FriendModeService {
  FriendModeService({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _firestore.collection('users').doc(uid);

  /// Cambia el modo de intención (dating | friends | both | groups).
  Future<void> setIntentMode(String uid, IntentMode mode) async {
    await _user(uid).set(<String, dynamic>{
      'profile': <String, dynamic>{'intentMode': mode.wireName},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Actualiza las preferencias sociales (intereses, tamaño de grupo,
  /// disponibilidad para planes). Solo escribe lo que se pasa.
  Future<void> setSocialPreferences(
    String uid, {
    List<String>? socialInterests,
    int? preferredGroupSize,
    bool? availableForPlans,
  }) async {
    final Map<String, dynamic> profile = <String, dynamic>{
      if (socialInterests != null) 'socialInterests': socialInterests,
      if (preferredGroupSize != null) 'preferredGroupSize': preferredGroupSize,
      if (availableForPlans != null) 'availableForPlans': availableForPlans,
    };
    if (profile.isEmpty) return;
    await _user(uid).set(<String, dynamic>{
      'profile': profile,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Lee el modo actual (default dating si no existe).
  Stream<IntentMode> observeIntentMode(String uid) {
    return _user(uid).snapshots().map(
      (DocumentSnapshot<Map<String, dynamic>> d) {
        final Map<String, dynamic> data = d.data() ?? <String, dynamic>{};
        final Object? profile = data['profile'];
        final Object? raw =
            profile is Map ? profile['intentMode'] : data['intentMode'];
        return IntentMode.fromValue(raw);
      },
    );
  }
}
