import 'package:attra/src/features/anti_ghosting/domain/closure_templates.dart';
import 'package:attra/src/features/chat/domain/chat.dart';
import 'package:attra/src/features/chat/domain/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClosureTemplates (Attra Clear §3)', () {
    test('hay 5 plantillas: 4 fijas + custom', () {
      expect(kClosureTemplates.length, 5);
      expect(kClosureTemplates.last.isCustom, isTrue);
      expect(kClosureTemplates.last.message, isEmpty);
    });

    test('todos los reason son válidos (espejo del backend)', () {
      for (final ClosureTemplate t in kClosureTemplates) {
        expect(kClosureReasons.contains(t.reason), isTrue,
            reason: 'reason desconocido: ${t.reason}');
      }
    });

    test('las plantillas fijas tienen mensaje no vacío', () {
      for (final ClosureTemplate t
          in kClosureTemplates.where((ClosureTemplate t) => !t.isCustom)) {
        expect(t.message.trim(), isNotEmpty);
      }
    });
  });

  group('Chat cierre con elegancia (§3, parseo defensivo)', () {
    test('parsea metadatos de cierre y marca isGracefullyClosed', () {
      final Chat c = Chat.fromMap('m1', <String, dynamic>{
        'matchId': 'm1',
        'users': <String>['a', 'b'],
        'status': 'closed',
        'closedByUserId': 'a',
        'closedReason': 'no_connection',
        'closedMessage': 'Te deseo lo mejor.',
        'lastMessageType': 'closure',
      });
      expect(c.status, ChatStatus.closed);
      expect(c.isGracefullyClosed, isTrue);
      expect(c.closedByMe('a'), isTrue);
      expect(c.closedByMe('b'), isFalse);
      expect(c.closedReason, 'no_connection');
      expect(c.lastMessageType, MessageType.closure);
    });

    test('chat sin metadatos de cierre no es graceful (fallback)', () {
      final Chat c = Chat.fromMap('m2', <String, dynamic>{
        'users': <String>['a', 'b'],
        'status': 'active',
      });
      expect(c.isGracefullyClosed, isFalse);
      expect(c.closedReason, isNull);
    });

    test('MessageType.closure se reconoce', () {
      expect(MessageType.fromValue('closure'), MessageType.closure);
      expect(MessageType.closure.isClosure, isTrue);
    });
  });
}
