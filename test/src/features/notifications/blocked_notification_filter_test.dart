import 'package:attra/src/features/notifications/domain/app_notification.dart';
import 'package:attra/src/features/notifications/domain/blocked_notification_filter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tras bloquear a alguien, la bandeja seguía diciendo "X te ha escrito" o
/// "¡Nuevo match con X!" con nombre y vista previa. El backend las borra al
/// bloquear; el cliente las aparta también (las antiguas, y las que se crucen).
AppNotification _n(String id, Map<String, dynamic> data) =>
    AppNotification.fromMap(id, <String, dynamic>{
      'kind': 'new_message',
      'title': 't',
      'body': 'b',
      'read': false,
      'data': data,
    });

void main() {
  const BlockedNotificationFilter filter = BlockedNotificationFilter(
    blockedUids: <String>{'bloqueado'},
    blockedPairIds: <String>{'bloqueado_yo'},
  );

  test('like o Attra de un bloqueado (fromUid): fuera', () {
    expect(filter.hides(_n('1', <String, dynamic>{'fromUid': 'bloqueado'})),
        isTrue);
  });

  test('match o Spark con un bloqueado (matchId): fuera', () {
    expect(filter.hides(_n('2', <String, dynamic>{'matchId': 'bloqueado_yo'})),
        isTrue);
  });

  test('mensaje de un chat bloqueado (chatId): fuera', () {
    expect(filter.hides(_n('3', <String, dynamic>{'chatId': 'bloqueado_yo'})),
        isTrue);
  });

  test('lo demás se queda, en su orden', () {
    final List<AppNotification> visible = filter.apply(<AppNotification>[
      _n('a', <String, dynamic>{'fromUid': 'otra'}),
      _n('b', <String, dynamic>{'chatId': 'bloqueado_yo'}),
      _n('c', <String, dynamic>{}),
      _n('d', <String, dynamic>{'matchId': 'otra_yo'}),
    ]);
    expect(visible.map((AppNotification n) => n.id), <String>['a', 'c', 'd']);
  });

  test('sin nada bloqueado no esconde nada (ni las que no llevan datos)', () {
    expect(
      BlockedNotificationFilter.none.apply(<AppNotification>[
        _n('a', <String, dynamic>{'fromUid': ''}),
        _n('b', <String, dynamic>{}),
      ]).length,
      2,
    );
  });
}
