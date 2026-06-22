import 'package:flutter_test/flutter_test.dart';

import 'package:attra/src/features/notifications/domain/app_notification.dart';

void main() {
  group('AppNotificationKind / NotifAccent parse', () {
    test('fromValue tolera snake_case y desconocidos', () {
      expect(AppNotificationKind.fromValue('new_match'),
          AppNotificationKind.newMatch);
      expect(AppNotificationKind.fromValue('???'),
          AppNotificationKind.generic);
      expect(NotifAccent.fromValue('premium'), NotifAccent.premium);
      expect(NotifAccent.fromValue('zzz'), NotifAccent.desire);
    });
  });

  group('Plantillas (chulas, con emoji + acento + ruta)', () {
    test('todas las kinds generan emoji, copy y ruta', () {
      for (final AppNotificationKind k in AppNotificationKind.values) {
        final NotifContent c = AppNotificationTemplates.build(k, name: 'Lucía');
        expect(c.emoji.isNotEmpty, isTrue, reason: '$k sin emoji');
        expect(c.title.isNotEmpty, isTrue, reason: '$k sin título');
        expect(c.body.isNotEmpty, isTrue, reason: '$k sin cuerpo');
        expect(c.route.isNotEmpty, isTrue, reason: '$k sin ruta');
      }
    });

    test('newMatch usa el nombre y acento de match', () {
      final NotifContent c =
          AppNotificationTemplates.build(AppNotificationKind.newMatch, name: 'Sara');
      expect(c.title, contains('Sara'));
      expect(c.accent, NotifAccent.match);
      expect(c.route, 'chats');
    });

    test('likesWaiting pluraliza según count', () {
      final NotifContent one = AppNotificationTemplates.build(
          AppNotificationKind.likesWaiting,
          count: 1);
      final NotifContent many = AppNotificationTemplates.build(
          AppNotificationKind.likesWaiting,
          count: 5);
      expect(one.title.toLowerCase(), contains('un like'));
      expect(many.title, contains('5'));
    });

    test('comeBack usa los días y acento calm', () {
      final NotifContent c = AppNotificationTemplates.build(
          AppNotificationKind.comeBack,
          days: 4);
      expect(c.body, contains('4'));
      expect(c.accent, NotifAccent.calm);
    });

    test('attraReceived es premium (champagne)', () {
      final NotifContent c = AppNotificationTemplates.build(
          AppNotificationKind.attraReceived);
      expect(c.accent, NotifAccent.premium);
      expect(c.emoji, '⭐');
    });
  });

  group('AppNotification fromTemplate / fromMap', () {
    test('fromTemplate rellena los campos renderizados', () {
      final AppNotification n = AppNotification.fromTemplate(
        AppNotificationKind.newLike,
      );
      expect(n.read, isFalse);
      expect(n.emoji, '👀');
      expect(n.route, 'likes');
      expect(n.toCreateMap()['kind'], 'new_like');
    });

    test('fromMap parsea y tolera campos ausentes', () {
      final AppNotification n = AppNotification.fromMap('id1', <String, dynamic>{
        'kind': 'new_message',
        'emoji': '💬',
        'title': 'Hola',
        'body': 'qué tal',
        'accent': 'desire',
        'route': 'chats',
        'read': true,
      });
      expect(n.id, 'id1');
      expect(n.kind, AppNotificationKind.newMessage);
      expect(n.read, isTrue);
    });
  });
}
