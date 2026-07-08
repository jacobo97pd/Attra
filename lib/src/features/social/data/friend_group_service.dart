import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../domain/friend_group.dart';

class FriendGroupException implements Exception {
  const FriendGroupException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => 'FriendGroupException($code): $message';
}

/// Fachada de grupos de amigos. Escrituras vía Cloud Functions (backend
/// autoritativo); lecturas vía Firestore.
class FriendGroupService {
  FriendGroupService({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
  })  : _firestore = firestore,
        _functions = functions;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _groups =>
      _firestore.collection('friendGroups');

  // --- Escrituras ---

  Future<String> createGroup({
    required String name,
    String description = '',
    String city = '',
    List<String> interests = const <String>[],
    int maxMembers = 8,
  }) async {
    final Map<String, dynamic> data =
        await _call('createFriendGroup', <String, dynamic>{
      'name': name,
      'description': description,
      'city': city,
      'interests': interests,
      'maxMembers': maxMembers,
    });
    return (data['groupId'] as String?) ?? '';
  }

  Future<void> requestJoin(String groupId) =>
      _call('requestJoinGroup', <String, dynamic>{'groupId': groupId});

  Future<void> respondJoin({
    required String groupId,
    required String targetUid,
    required bool accept,
  }) =>
      _call('respondJoinRequest', <String, dynamic>{
        'groupId': groupId,
        'targetUid': targetUid,
        'accept': accept,
      });

  Future<void> leaveGroup(String groupId) =>
      _call('leaveFriendGroup', <String, dynamic>{'groupId': groupId});

  Future<void> closeGroup(String groupId) =>
      _call('closeFriendGroup', <String, dynamic>{'groupId': groupId});

  // --- Lecturas ---

  Stream<FriendGroup?> observeGroup(String groupId) {
    return _groups.doc(groupId).snapshots().map(
        (DocumentSnapshot<Map<String, dynamic>> d) =>
            d.exists ? FriendGroup.fromMap(d.id, d.data()!) : null);
  }

  /// Grupos donde el usuario es MIEMBRO.
  Stream<List<FriendGroup>> observeMyGroups(String uid) {
    return _groups
        .where('memberIds', arrayContains: uid)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snap) => snap.docs
            .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                FriendGroup.fromMap(d.id, d.data()))
            .toList(growable: false));
  }

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
    } on FirebaseFunctionsException catch (e) {
      throw FriendGroupException(e.message ?? e.code, code: e.code);
    }
  }
}
