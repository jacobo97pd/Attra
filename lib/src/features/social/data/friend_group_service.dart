import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../domain/friend_group.dart';
import '../domain/group_message.dart';

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
    required FirebaseStorage storage,
  })  : _firestore = firestore,
        _functions = functions,
        _storage = storage;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final FirebaseStorage _storage;

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

  /// Sube la foto elegida por el creador a Storage y la fija en el grupo (vía
  /// Cloud Function que valida que es el creador). Devuelve la URL pública.
  Future<String> updateGroupPhoto(
    String groupId, {
    required String uid,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final String ext = contentType.endsWith('png') ? 'png' : 'jpg';
    final String path =
        'groups/$groupId/photo/$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final Reference ref = _storage.ref().child(path);
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    final String url = await ref.getDownloadURL();
    await _call('setFriendGroupPhoto', <String, dynamic>{
      'groupId': groupId,
      'photoUrl': url,
      'photoStoragePath': path,
    });
    return url;
  }

  /// Fija una imagen PRESET (bundled, `asset:...`) como foto del grupo. Solo el
  /// creador (validado en la Cloud Function).
  Future<void> setGroupPreset(String groupId, String presetValue) =>
      _call('setFriendGroupPhoto', <String, dynamic>{
        'groupId': groupId,
        'photoUrl': presetValue,
        'photoStoragePath': '',
      });

  /// Quita la foto del grupo (solo el creador).
  Future<void> removeGroupPhoto(String groupId) =>
      _call('setFriendGroupPhoto', <String, dynamic>{
        'groupId': groupId,
        'photoUrl': '',
        'photoStoragePath': '',
      });

  // --- Lecturas ---

  Stream<FriendGroup?> observeGroup(String groupId) {
    return _groups.doc(groupId).snapshots().map(
        (DocumentSnapshot<Map<String, dynamic>> d) =>
            d.exists ? FriendGroup.fromMap(d.id, d.data()!) : null);
  }

  // --- Chat de grupo ---

  /// Mensajes del chat de un grupo, más recientes al final. Reglas: solo
  /// miembros leen. Se limita a los últimos 100 para no crecer sin control.
  Stream<List<GroupMessage>> observeGroupMessages(String groupId) {
    return _groups
        .doc(groupId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snap) => snap.docs
            .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                GroupMessage.fromMap(d.id, d.data()))
            .toList(growable: false)
            .reversed
            .toList(growable: false));
  }

  /// Envía un mensaje al chat del grupo. Escritura directa (reglas: solo un
  /// miembro puede crear su propio mensaje). El nombre se denormaliza.
  Future<void> sendGroupMessage(
    String groupId, {
    required String senderId,
    required String senderName,
    required String text,
  }) async {
    final String clean = text.trim();
    if (clean.isEmpty) return;
    await _groups.doc(groupId).collection('messages').add(<String, dynamic>{
      'senderId': senderId,
      'senderName': senderName,
      'text': clean.length > 2000 ? clean.substring(0, 2000) : clean,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Grupos donde el usuario es MIEMBRO.
  Stream<List<FriendGroup>> observeMyGroups(String uid) {
    return _groups.where('memberIds', arrayContains: uid).snapshots().map(
        (QuerySnapshot<Map<String, dynamic>> snap) => snap.docs
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
