import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../domain/app_notification.dart';

/// Bandeja de notificaciones in-app: `notifications/{uid}/items/{id}`.
///
/// El backend (Cloud Functions, futuro) escribirá la MISMA forma vía Admin SDK
/// cuando llegue un like/match/mensaje; mientras, el cliente puede crear las
/// suyas (re-engagement local, pruebas). Streams eficientes (limit + orderBy).
class NotificationService {
  NotificationService({required FirebaseFirestore firestore}) : _db = firestore;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _items(String uid) =>
      _db.collection('notifications').doc(uid).collection('items');

  /// Últimas notificaciones (desc por fecha).
  Stream<List<AppNotification>> watch(String uid, {int limit = 50}) {
    if (uid.isEmpty) return const Stream<List<AppNotification>>.empty();
    return _items(uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snap) => snap.docs
            .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                AppNotification.fromMap(d.id, d.data()))
            .toList(growable: false));
  }

  /// Nº de no leídas (para el badge de la campana).
  Stream<int> watchUnreadCount(String uid) {
    if (uid.isEmpty) return Stream<int>.value(0);
    return _items(uid)
        .where('read', isEqualTo: false)
        .limit(50)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snap) => snap.docs.length);
  }

  /// Crea una notificación (cliente). Fire-and-forget seguro.
  Future<void> push(String uid, AppNotification n) async {
    if (uid.isEmpty) return;
    try {
      await _items(uid).add(n.toCreateMap());
    } catch (e) {
      if (kDebugMode) debugPrint('NotificationService: push falló -> $e');
    }
  }

  Future<void> markRead(String uid, String id) async {
    if (uid.isEmpty || id.isEmpty) return;
    await _items(uid).doc(id).set(<String, dynamic>{'read': true},
        SetOptions(merge: true)).catchError((_) {});
  }

  Future<void> markAllRead(String uid) async {
    if (uid.isEmpty) return;
    final QuerySnapshot<Map<String, dynamic>> snap =
        await _items(uid).where('read', isEqualTo: false).limit(200).get();
    if (snap.docs.isEmpty) return;
    final WriteBatch batch = _db.batch();
    for (final QueryDocumentSnapshot<Map<String, dynamic>> d in snap.docs) {
      batch.set(d.reference, <String, dynamic>{'read': true},
          SetOptions(merge: true));
    }
    await batch.commit().catchError((_) {});
  }

  Future<void> delete(String uid, String id) async {
    if (uid.isEmpty || id.isEmpty) return;
    await _items(uid).doc(id).delete().catchError((_) {});
  }
}
