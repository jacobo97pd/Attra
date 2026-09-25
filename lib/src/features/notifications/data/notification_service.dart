import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../domain/app_notification.dart';
import '../domain/blocked_notification_filter.dart';

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

  /// Últimas notificaciones (desc por fecha), sin las de gente bloqueada.
  Stream<List<AppNotification>> watch(String uid, {int limit = 50}) {
    if (uid.isEmpty) return const Stream<List<AppNotification>>.empty();
    return _withoutBlocked(
      uid,
      _items(uid)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map(_parse),
    );
  }

  /// Nº de no leídas (para el badge de la campana). Cuenta lo mismo que enseña
  /// la bandeja: si el badge contara las de un bloqueado, marcaría novedades
  /// que luego no aparecen.
  Stream<int> watchUnreadCount(String uid) {
    if (uid.isEmpty) return Stream<int>.value(0);
    return _withoutBlocked(
      uid,
      _items(uid)
          .where('read', isEqualTo: false)
          .limit(50)
          .snapshots()
          .map(_parse),
    ).map((List<AppNotification> items) => items.length);
  }

  static List<AppNotification> _parse(
          QuerySnapshot<Map<String, dynamic>> snap) =>
      snap.docs
          .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
              AppNotification.fromMap(d.id, d.data()))
          .toList(growable: false);

  /// Filtra [items] con lo que el cliente SABE que está bloqueado:
  /// * a quién he bloqueado yo (`blocks` con `blockerUid == uid`), y
  /// * los chats en `blocked`, que cubren también a quien ME bloqueó a mí (su
  ///   documento de bloqueo no se puede leer desde este lado).
  ///
  /// Espera a tener las dos listas antes de emitir para no enseñar un instante
  /// lo que se va a esconder. Si alguna falla, se sigue sin ella: el backend
  /// ya borra estas notificaciones y la bandeja no debe romperse por esto.
  Stream<List<AppNotification>> _withoutBlocked(
    String uid,
    Stream<List<AppNotification>> items,
  ) {
    late final StreamController<List<AppNotification>> controller;
    StreamSubscription<List<AppNotification>>? itemsSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? blocksSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? chatsSub;

    List<AppNotification>? latest;
    Set<String> blockedByMe = const <String>{};
    Set<String> myBlockPairs = const <String>{};
    Set<String> blockedChatUids = const <String>{};
    Set<String> blockedChatIds = const <String>{};
    bool hasBlocks = false;
    bool hasChats = false;

    void emitIfReady() {
      final List<AppNotification>? current = latest;
      if (current == null || !hasBlocks || !hasChats || controller.isClosed) {
        return;
      }
      controller.add(BlockedNotificationFilter(
        blockedUids: <String>{...blockedByMe, ...blockedChatUids},
        blockedPairIds: <String>{...myBlockPairs, ...blockedChatIds},
      ).apply(current));
    }

    controller = StreamController<List<AppNotification>>(
      onListen: () {
        itemsSub = items.listen(
          (List<AppNotification> value) {
            latest = value;
            emitIfReady();
          },
          onError: controller.addError,
        );
        blocksSub = _db
            .collection('blocks')
            .where('blockerUid', isEqualTo: uid)
            .snapshots()
            .listen(
          (QuerySnapshot<Map<String, dynamic>> snap) {
            final Set<String> uids = <String>{};
            final Set<String> pairs = <String>{};
            for (final QueryDocumentSnapshot<Map<String, dynamic>> d
                in snap.docs) {
              final Object? blocked = d.data()['blockedUid'];
              final Object? matchId = d.data()['matchId'];
              if (blocked is String && blocked.isNotEmpty) uids.add(blocked);
              if (matchId is String && matchId.isNotEmpty) pairs.add(matchId);
            }
            blockedByMe = uids;
            myBlockPairs = pairs;
            hasBlocks = true;
            emitIfReady();
          },
          onError: (Object error) {
            if (kDebugMode) debugPrint('NotificationService: blocks -> $error');
            hasBlocks = true;
            emitIfReady();
          },
        );
        chatsSub = _db
            .collection('chats')
            .where('users', arrayContains: uid)
            .where('status', isEqualTo: 'blocked')
            .snapshots()
            .listen(
          (QuerySnapshot<Map<String, dynamic>> snap) {
            final Set<String> uids = <String>{};
            final Set<String> ids = <String>{};
            for (final QueryDocumentSnapshot<Map<String, dynamic>> d
                in snap.docs) {
              ids.add(d.id);
              final List<dynamic> users =
                  (d.data()['users'] as List<dynamic>?) ?? const <dynamic>[];
              for (final dynamic u in users) {
                if (u is String && u.isNotEmpty && u != uid) uids.add(u);
              }
            }
            blockedChatUids = uids;
            blockedChatIds = ids;
            hasChats = true;
            emitIfReady();
          },
          onError: (Object error) {
            if (kDebugMode) debugPrint('NotificationService: chats -> $error');
            hasChats = true;
            emitIfReady();
          },
        );
      },
      onCancel: () async {
        await itemsSub?.cancel();
        await blocksSub?.cancel();
        await chatsSub?.cancel();
      },
    );
    return controller.stream;
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
