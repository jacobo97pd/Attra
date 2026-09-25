import 'package:attra/src/features/anti_ghosting/domain/conversation_turn.dart';
import 'package:attra/src/features/chat/domain/chat.dart';
import 'package:flutter_test/flutter_test.dart';

/// C17/C24: la lista de Chats solo quitaba `deleted`, que el backend no escribe
/// nunca. Tras bloquear o deshacer el match, la otra persona seguía en la lista
/// de LOS DOS (a menudo en "Matches nuevos"), con nombre y foto, y desde la
/// cabecera del chat se podía abrir su perfil completo.
Chat _chat(
  String status, {
  Map<String, dynamic> extra = const <String, dynamic>{},
}) =>
    Chat.fromMap('a_b', <String, dynamic>{
      'matchId': 'a_b',
      'users': <String>['a', 'b'],
      'status': status,
      ...extra,
    });

void main() {
  group('Qué se lista', () {
    test('un chat activo, sí', () {
      expect(_chat('active').isListed, isTrue);
    });

    test('bloqueado: nunca, para ninguno de los dos', () {
      final Chat blocked = _chat('blocked', extra: <String, dynamic>{
        'lastMessageType': 'text',
        'lastMessageSenderId': 'b',
        'lastMessageAt': DateTime.utc(2026, 9, 1).toIso8601String(),
      });
      expect(blocked.isListed, isFalse);
    });

    test('match deshecho (`unmatch` cierra sin firmar): no', () {
      final Chat unmatched = _chat('closed');
      expect(unmatched.isUnmatched, isTrue);
      expect(unmatched.isListed, isFalse);
    });

    test('cerrado con elegancia: sí, queda archivado en Conversaciones', () {
      final Chat graceful = _chat('closed', extra: <String, dynamic>{
        'closedByUserId': 'a',
        'lastMessageType': 'closure',
      });
      expect(graceful.isGracefullyClosed, isTrue);
      expect(graceful.isUnmatched, isFalse);
      expect(graceful.isListed, isTrue);
    });

    test('borrado: no', () {
      expect(_chat('deleted').isListed, isFalse);
    });
  });

  group('Estado `unmatched` explícito', () {
    test('se reconoce en vez de caer en `active`', () {
      // fromValue cae en `active` con valores desconocidos: sin este valor, un
      // chat marcado `unmatched` reabriría el composer.
      final Chat c = _chat('unmatched');
      expect(c.status, ChatStatus.unmatched);
      expect(c.status.canSendMessages, isFalse);
      expect(c.isUnmatched, isTrue);
      expect(c.isListed, isFalse);
    });

    test('no abre turno en "Tu turno"', () {
      final Chat c = _chat('unmatched', extra: <String, dynamic>{
        'lastMessageType': 'text',
        'lastMessageSenderId': 'b',
        'lastMessageAt': DateTime.utc(2026, 9, 1).toIso8601String(),
      });
      expect(c.isMyTurn('a'), isFalse);
    });
  });

  group('Perfil desde la cabecera del chat', () {
    test('bloqueado: no se puede abrir el perfil del otro', () {
      expect(_chat('blocked').allowsProfileAccess, isFalse);
    });

    test('match deshecho: tampoco', () {
      expect(_chat('closed').allowsProfileAccess, isFalse);
      expect(_chat('unmatched').allowsProfileAccess, isFalse);
    });

    test('activo o cerrado con elegancia: sí', () {
      expect(_chat('active').allowsProfileAccess, isTrue);
      expect(
        _chat('closed', extra: <String, dynamic>{'closedByUserId': 'b'})
            .allowsProfileAccess,
        isTrue,
      );
    });
  });
}
