import 'package:cloud_firestore/cloud_firestore.dart';

abstract class OnboardingUserStore {
  String userPath(String uid);

  Future<Map<String, dynamic>?> getUserData(String uid);

  Future<void> setUserData(
    String uid,
    Map<String, dynamic> data, {
    required bool merge,
  });
}

class FirestoreOnboardingUserStore implements OnboardingUserStore {
  FirestoreOnboardingUserStore(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) {
    return _firestore.collection('users').doc(uid);
  }

  @override
  String userPath(String uid) => 'users/$uid';

  @override
  Future<Map<String, dynamic>?> getUserData(String uid) async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await _userDoc(uid).get();
    return snapshot.data();
  }

  @override
  Future<void> setUserData(
    String uid,
    Map<String, dynamic> data, {
    required bool merge,
  }) async {
    await _userDoc(uid).set(
      data,
      merge ? SetOptions(merge: true) : null,
    );
  }
}
