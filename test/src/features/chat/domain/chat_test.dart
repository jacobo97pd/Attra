import 'package:attra/src/features/chat/domain/chat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Chat build(Map<String, dynamic> overrides) {
    return Chat.fromMap('a_b', <String, dynamic>{
      'matchId': 'a_b',
      'users': <String>['a', 'b'],
      'status': 'active',
      ...overrides,
    });
  }

  group('Chat.isUnreadFor', () {
    test('hay mensajes sin leer => no leido', () {
      final Chat c = build(<String, dynamic>{
        'unreadCountByUser': <String, dynamic>{'a': 2},
      });
      expect(c.unreadFor('a'), 2);
      expect(c.isUnreadFor('a'), isTrue);
      expect(c.isUnreadFor('b'), isFalse);
    });

    test('marcado manualmente como no leido (sin mensajes) => no leido', () {
      final Chat c = build(<String, dynamic>{
        'unreadCountByUser': <String, dynamic>{'a': 0},
        'manuallyUnreadByUser': <String, dynamic>{'a': true},
      });
      expect(c.unreadFor('a'), 0);
      expect(c.manuallyUnreadFor('a'), isTrue);
      expect(c.isUnreadFor('a'), isTrue);
    });

    test('sin mensajes y sin marca manual => leido', () {
      final Chat c = build(<String, dynamic>{
        'unreadCountByUser': <String, dynamic>{'a': 0},
        'manuallyUnreadByUser': <String, dynamic>{'a': false},
      });
      expect(c.isUnreadFor('a'), isFalse);
    });

    test('marcar no leido es por participante, no global', () {
      final Chat c = build(<String, dynamic>{
        'manuallyUnreadByUser': <String, dynamic>{'a': true},
      });
      expect(c.isUnreadFor('a'), isTrue);
      expect(c.isUnreadFor('b'), isFalse);
    });
  });
}
