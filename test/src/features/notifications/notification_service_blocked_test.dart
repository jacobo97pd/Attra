import 'dart:async';

import 'package:attra/src/features/notifications/data/notification_service.dart';
import 'package:attra/src/features/notifications/domain/app_notification.dart';
import 'package:attra/src/features/notifications/domain/blocked_notification_filter.dart';
import 'package:attra/src/features/notifications/presentation/notifications_screen.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// La bandeja y el badge esconden lo que viene de gente bloqueada. Aquí se
/// prueba el stream combinado de verdad (no solo el filtro puro), con las tres
/// consultas sustituidas por controladores:
/// * si dejara de filtrar, o emitiera antes de saber qué esconder, falla;
/// * quien me bloqueó ANTES de hacer match también queda fuera (la fuente son
///   los matches en `blocked`, que applyBlock escribe siempre con `users`);
/// * repintar la campana ya no reabre consultas (antes eran tres por repintado).
class _NoFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sources {
  final StreamController<List<AppNotification>> all =
      StreamController<List<AppNotification>>.broadcast();
  final StreamController<List<AppNotification>> unread =
      StreamController<List<AppNotification>>.broadcast();
  final StreamController<BlockedNotificationFilter> byMe =
      StreamController<BlockedNotificationFilter>.broadcast();
  final StreamController<BlockedNotificationFilter> pairs =
      StreamController<BlockedNotificationFilter>.broadcast();

  /// Cuántas veces se ha abierto cada consulta.
  final Map<String, int> opened = <String, int>{};

  Stream<T> open<T>(String name, StreamController<T> c) {
    opened[name] = (opened[name] ?? 0) + 1;
    return c.stream;
  }

  Future<void> close() async {
    await all.close();
    await unread.close();
    await byMe.close();
    await pairs.close();
  }
}

class _TestService extends NotificationService {
  _TestService(this.s) : super(firestore: _NoFirestore());

  final _Sources s;

  @override
  Stream<List<AppNotification>> itemsSource(
    String uid, {
    required int limit,
    bool unreadOnly = false,
  }) =>
      unreadOnly ? s.open('unread', s.unread) : s.open('all', s.all);

  @override
  Stream<BlockedNotificationFilter> blockedByMeSource(String uid) =>
      s.open('byMe', s.byMe);

  @override
  Stream<BlockedNotificationFilter> blockedPairsSource(String uid) =>
      s.open('pairs', s.pairs);
}

AppNotification _n(String id, Map<String, dynamic> data) =>
    AppNotification.fromMap(id, <String, dynamic>{
      'kind': 'new_message',
      'title': 't',
      'body': 'b',
      'read': false,
      'data': data,
    });

/// Yo bloqueé a Yago (par me_yago).
final BlockedNotificationFilter _myBlocks =
    BlockedNotificationFilter.fromBlocks(<Map<String, dynamic>>[
  <String, dynamic>{'blockedUid': 'yago', 'matchId': 'me_yago'},
]);

/// Xavi me bloqueó a mí sin que hubiera match: solo existe matches/{par} con
/// `users` y `status: blocked` (su doc de `blocks` no lo puedo leer).
final BlockedNotificationFilter _pairBlocks =
    BlockedNotificationFilter.fromBlockedPairs(
        'me', <String, Map<String, dynamic>>{
  'me_xavi': <String, dynamic>{
    'users': <String>['me', 'xavi'],
    'status': 'blocked',
  },
});

final List<AppNotification> _inbox = <AppNotification>[
  _n('attra-xavi', <String, dynamic>{'fromUid': 'xavi'}),
  _n('like-ana', <String, dynamic>{'fromUid': 'ana'}),
  _n('msg-yago', <String, dynamic>{'chatId': 'me_yago'}),
  _n('match-bea', <String, dynamic>{'matchId': 'bea_me'}),
];

List<String> _ids(List<AppNotification> items) =>
    items.map((AppNotification n) => n.id).toList();

void main() {
  late _Sources s;
  late _TestService service;

  setUp(() {
    s = _Sources();
    service = _TestService(s);
  });

  tearDown(() => s.close());

  test(
      'no emite hasta saber qué esconder; luego quita a quien bloqueé y a quien '
      'me bloqueó sin match', () async {
    final List<List<AppNotification>> out = <List<AppNotification>>[];
    final StreamSubscription<List<AppNotification>> sub =
        service.watch('me').listen(out.add);
    await pumpEventQueue();

    s.all.add(_inbox);
    await pumpEventQueue();
    expect(out, isEmpty, reason: 'sin bloqueos aún, enseñaría a Xavi y Yago');

    s.byMe.add(_myBlocks);
    await pumpEventQueue();
    expect(out, isEmpty, reason: 'falta la fuente de pares bloqueados');

    s.pairs.add(_pairBlocks);
    await pumpEventQueue();
    expect(out, hasLength(1));
    expect(_ids(out.single), <String>['like-ana', 'match-bea']);
    await sub.cancel();
  });

  test('si una fuente de bloqueo falla, la bandeja sigue sin ella', () async {
    final List<List<AppNotification>> out = <List<AppNotification>>[];
    final StreamSubscription<List<AppNotification>> sub =
        service.watch('me').listen(out.add);
    await pumpEventQueue();

    s.all.add(_inbox);
    s.byMe.addError(StateError('permission-denied'));
    s.pairs.add(_pairBlocks);
    await pumpEventQueue();

    expect(_ids(out.last), <String>['like-ana', 'msg-yago', 'match-bea']);
    await sub.cancel();
  });

  test('un error de los avisos sí llega a la pantalla', () async {
    final List<Object> errors = <Object>[];
    final StreamSubscription<List<AppNotification>> sub =
        service.watch('me').listen((_) {}, onError: errors.add);
    await pumpEventQueue();

    s.all.addError(StateError('sin red'));
    await pumpEventQueue();

    expect(errors, hasLength(1));
    await sub.cancel();
  });

  test('el badge cuenta lo mismo que enseña la bandeja', () async {
    final List<int> counts = <int>[];
    final StreamSubscription<int> sub =
        service.watchUnreadCount('me').listen(counts.add);
    await pumpEventQueue();

    s.unread.add(_inbox);
    s.byMe.add(_myBlocks);
    s.pairs.add(_pairBlocks);
    await pumpEventQueue();

    expect(counts.last, 2);
    await sub.cancel();
  });

  test(
      'mismo uid, misma instancia; bandeja y campana comparten las escuchas '
      'de bloqueo', () async {
    expect(identical(service.watch('me'), service.watch('me')), isTrue);
    expect(
        identical(
            service.watchUnreadCount('me'), service.watchUnreadCount('me')),
        isTrue);

    final StreamSubscription<List<AppNotification>> inbox =
        service.watch('me').listen((_) {});
    final StreamSubscription<int> bell =
        service.watchUnreadCount('me').listen((_) {});
    final StreamSubscription<int> bell2 =
        service.watchUnreadCount('me').listen((_) {});
    await pumpEventQueue();

    expect(s.opened, <String, int>{
      'all': 1,
      'unread': 1,
      'byMe': 1,
      'pairs': 1,
    });
    await inbox.cancel();
    await bell.cancel();
    await bell2.cancel();
  });

  testWidgets('repintar la campana no reabre ninguna consulta',
      (WidgetTester tester) async {
    late StateSetter repaint;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: StatefulBuilder(builder: (BuildContext context, StateSetter set) {
          repaint = set;
          // Una campana NUEVA en cada build, como la crea el HomeShell.
          return NotificationBell(service: service, uid: 'me', onTap: () {});
        }),
      ),
    ));
    s.unread.add(_inbox);
    s.byMe.add(_myBlocks);
    s.pairs.add(_pairBlocks);
    await tester.pump();

    for (int i = 0; i < 5; i++) {
      repaint(() {});
      await tester.pump();
    }

    expect(find.text('2'), findsOneWidget);
    expect(s.opened, <String, int>{'unread': 1, 'byMe': 1, 'pairs': 1});
  });

  group('fuentes de bloqueo (puro)', () {
    test('blocks propios: la persona y el par', () {
      expect(_myBlocks.blockedUids, <String>{'yago'});
      expect(_myBlocks.blockedPairIds, <String>{'me_yago'});
    });

    test('matches bloqueados: el otro (nunca yo) y el id del par', () {
      expect(_pairBlocks.blockedUids, <String>{'xavi'});
      expect(_pairBlocks.blockedPairIds, <String>{'me_xavi'});
    });

    test('la unión suma las dos', () {
      final BlockedNotificationFilter all = _myBlocks.union(_pairBlocks);
      expect(all.blockedUids, <String>{'yago', 'xavi'});
      expect(all.blockedPairIds, <String>{'me_yago', 'me_xavi'});
    });
  });
}
