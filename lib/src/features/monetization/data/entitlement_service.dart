import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/user_entitlements.dart';

abstract class EntitlementService {
  Future<UserEntitlements> getEntitlements(String uid);

  Stream<UserEntitlements> watchEntitlements(String uid);
}

class FirestoreEntitlementService implements EntitlementService {
  FirestoreEntitlementService({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _firestore.collection('userEntitlements').doc(uid);

  @override
  Future<UserEntitlements> getEntitlements(String uid) async {
    final String normalizedUid = _requireUid(uid);
    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await _doc(normalizedUid).get();
    return _fromSnapshot(normalizedUid, snapshot);
  }

  @override
  Stream<UserEntitlements> watchEntitlements(String uid) {
    final String normalizedUid = _requireUid(uid);
    return _doc(normalizedUid).snapshots().map(
          (DocumentSnapshot<Map<String, dynamic>> snapshot) =>
              _fromSnapshot(normalizedUid, snapshot),
        );
  }

  UserEntitlements _fromSnapshot(
    String uid,
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final Map<String, dynamic>? data = snapshot.data();
    if (!snapshot.exists || data == null) {
      return UserEntitlements.free(uid: uid);
    }
    return UserEntitlements.fromMap(uid, _normalizeTimestamps(data));
  }

  Map<String, dynamic> _normalizeTimestamps(Map<String, dynamic> data) {
    return data.map((String key, dynamic value) {
      if (value is Timestamp) {
        return MapEntry<String, dynamic>(key, value.toDate());
      }
      return MapEntry<String, dynamic>(key, value);
    });
  }

  String _requireUid(String uid) {
    final String normalized = uid.trim();
    if (normalized.isEmpty) {
      throw StateError('No hay uid para cargar entitlements.');
    }
    return normalized;
  }
}
