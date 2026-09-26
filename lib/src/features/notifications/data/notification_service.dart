import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/async/shared_latest_stream.dart';
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

  /// Un stream por uid (ver [shareLatest]). La campana y la bandeja los piden
  /// dentro de build(): sin esto, cada repintado del HomeShell cerraba y
  /// reabría TRES escuchas (avisos, bloqueos propios y pares bloqueados).
  final Map<String, Stream<List<AppNotification>>> _watchStreams =
      <String, Stream<List<AppNotification>>>{};
  final Map<String, Stream<int>> _unreadStreams = <String, Stream<int>>{};

  /// Lo bloqueado, compartido por la bandeja y la campana: con las dos
  /// abiertas sigue habiendo UNA escucha de cada fuente de bloqueo.
  final Map<String, Stream<BlockedNotificationFilter>> _blockedStreams =
      <String, Stream<BlockedNotificationFilter>>{};

  CollectionReference<Map<String, dynamic>> _items(String uid) =>
      _db.collection('notifications').doc(uid).collection('items');

  /// Últimas notificaciones (desc por fecha), sin las de gente bloqueada.
  /// Devuelve siempre la misma instancia para el mismo uid y [limit].
  Stream<List<AppNotification>> watch(String uid, {int limit = 50}) {
    if (uid.isEmpty) return const Stream<List<AppNotification>>.empty();
    return _watchStreams.putIfAbsent(
      '$uid#$limit',
      () => shareLatest(() => _withoutBlocked(
            itemsSource(uid, limit: limit),
            _blocked(uid),
          )),
    );
  }

  /// Nº de no leídas (para el badge de la campana). Cuenta lo mismo que enseña
  /// la bandeja: si el badge contara las de un bloqueado, marcaría novedades
  /// que luego no aparecen. Misma instancia para el mismo uid.
  Stream<int> watchUnreadCount(String uid) {
    if (uid.isEmpty) return Stream<int>.value(0);
    return _unreadStreams.putIfAbsent(
      uid,
      () => shareLatest(() => _withoutBlocked(
            itemsSource(uid, limit: 50, unreadOnly: true),
            _blocked(uid),
          ).map((List<AppNotification> items) => items.length)),
    );
  }

  static List<AppNotification> _parse(
          QuerySnapshot<Map<String, dynamic>> snap) =>
      snap.docs
          .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
              AppNotification.fromMap(d.id, d.data()))
          .toList(growable: false);

  /// Avisos del buzón. [unreadOnly] = solo los no leídos (badge); si no, los
  /// últimos por fecha (bandeja). Separado para probar el filtro sin Firestore.
  @visibleForTesting
  Stream<List<AppNotification>> itemsSource(
    String uid, {
    required int limit,
    bool unreadOnly = false,
  }) {
    final Query<Map<String, dynamic>> query = unreadOnly
        ? _items(uid).where('read', isEqualTo: false)
        : _items(uid).orderBy('createdAt', descending: true);
    return query.limit(limit).snapshots().map(_parse);
  }

  /// A quién he bloqueado yo (`blocks` con `blockerUid == uid`).
  @visibleForTesting
  Stream<BlockedNotificationFilter> blockedByMeSource(String uid) => _db
      .collection('blocks')
      .where('blockerUid', isEqualTo: uid)
      .snapshots()
      .map((QuerySnapshot<Map<String, dynamic>> snap) =>
          BlockedNotificationFilter.fromBlocks(snap.docs.map(
              (QueryDocumentSnapshot<Map<String, dynamic>> d) => d.data())));

  /// Pares bloqueados en cualquier sentido, con o sin match previo: `matches`
  /// en `blocked` donde estoy (ver [BlockedNotificationFilter.fromBlockedPairs]).
  /// Misma forma de consulta que observeMatches: no necesita índice compuesto.
  @visibleForTesting
  Stream<BlockedNotificationFilter> blockedPairsSource(String uid) => _db
      .collection('matches')
      .where('users', arrayContains: uid)
      .where('status', isEqualTo: 'blocked')
      .snapshots()
      .map((QuerySnapshot<Map<String, dynamic>> snap) =>
          BlockedNotificationFilter.fromBlockedPairs(
              uid, <String, Map<String, dynamic>>{
            for (final QueryDocumentSnapshot<Map<String, dynamic>> d
                in snap.docs)
              d.id: d.data(),
          }));

  Stream<BlockedNotificationFilter> _blocked(String uid) =>
      _blockedStreams.putIfAbsent(
        uid,
        () => shareLatest(() => _union(<Stream<BlockedNotificationFilter>>[
              blockedByMeSource(uid),
              blockedPairsSource(uid),
            ])),
      );

  /// Une las fuentes de bloqueo y emite cuando TODAS han contestado, para no
  /// enseñar un instante lo que se va a esconder. Una que falla cuenta como
  /// vacía (se sigue sin ella): el backend ya borra estas notificaciones y la
  /// bandeja no debe romperse por esto.
  static Stream<BlockedNotificationFilter> _union(
    List<Stream<BlockedNotificationFilter>> sources,
  ) {
    late final StreamController<BlockedNotificationFilter> controller;
    final List<StreamSubscription<BlockedNotificationFilter>> subs =
        <StreamSubscription<BlockedNotificationFilter>>[];
    final List<BlockedNotificationFilter?> latest =
        List<BlockedNotificationFilter?>.filled(sources.length, null);

    void emitIfReady() {
      if (controller.isClosed) return;
      BlockedNotificationFilter all = BlockedNotificationFilter.none;
      for (final BlockedNotificationFilter? f in latest) {
        if (f == null) return;
        all = all.union(f);
      }
      controller.add(all);
    }

    controller = StreamController<BlockedNotificationFilter>(
      onListen: () {
        for (int i = 0; i < sources.length; i++) {
          subs.add(sources[i].listen(
            (BlockedNotificationFilter value) {
              latest[i] = value;
              emitIfReady();
            },
            onError: (Object error) {
              if (kDebugMode) {
                debugPrint('NotificationService: bloqueos[$i] -> $error');
              }
              latest[i] ??= BlockedNotificationFilter.none;
              emitIfReady();
            },
          ));
        }
      },
      onCancel: () async {
        for (final StreamSubscription<BlockedNotificationFilter> s in subs) {
          await s.cancel();
        }
        subs.clear();
      },
    );
    return controller.stream;
  }

  /// Aplica lo bloqueado a [items]. No emite hasta tener las dos cosas. Un
  /// error de los avisos sí llega a la pantalla; uno de [blocked] no la tumba.
  static Stream<List<AppNotification>> _withoutBlocked(
    Stream<List<AppNotification>> items,
    Stream<BlockedNotificationFilter> blocked,
  ) {
    late final StreamController<List<AppNotification>> controller;
    StreamSubscription<List<AppNotification>>? itemsSub;
    StreamSubscription<BlockedNotificationFilter>? blockedSub;
    List<AppNotification>? latest;
    BlockedNotificationFilter? filter;

    void emitIfReady() {
      final List<AppNotification>? current = latest;
      final BlockedNotificationFilter? f = filter;
      if (current == null || f == null || controller.isClosed) return;
      controller.add(f.apply(current));
    }

    controller = StreamController<List<AppNotification>>(
      onListen: () {
        itemsSub = items.listen(
          (List<AppNotification> value) {
            latest = value;
            emitIfReady();
          },
          onError: controller.addError,
          // Firestore cierra el stream tras un error: se cierra también aquí
          // para que el siguiente oyente vuelva a abrir la consulta.
          onDone: controller.close,
        );
        blockedSub = blocked.listen(
          (BlockedNotificationFilter value) {
            filter = value;
            emitIfReady();
          },
          onError: (Object _) {
            filter ??= BlockedNotificationFilter.none;
            emitIfReady();
          },
        );
      },
      onCancel: () async {
        await itemsSub?.cancel();
        await blockedSub?.cancel();
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
