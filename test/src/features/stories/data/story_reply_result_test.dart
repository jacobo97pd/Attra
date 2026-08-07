import 'package:attra/src/features/stories/data/story_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Responder a una story con ⭐ es un Attra, y un Attra CUESTA. El backend
/// escribía `type: "attra"` sin mirar el monedero: Attras infinitos gratis.
///
/// Cerrado el agujero en servidor, la regla que fija este test es la mitad del
/// cliente: sin saldo la respuesta NO sale (nada de degradarla a like normal
/// por lo bajo) y la UI solo puede cantar "Attra enviado" cuando el backend
/// confirma que lo ha cobrado.
void main() {
  group('StoryReplyResult', () {
    test('sin saldo: el envío no se hizo y se distingue del like', () {
      final StoryReplyResult r = StoryReplyResult.fromMap(
        <String, dynamic>{'outcome': 'insufficient_attras'},
      );

      expect(r.insufficientAttras, isTrue);
      expect(r.chargedAttra, isFalse);
      expect(r.isMatch, isFalse);
      expect(r.chatId, isNull);
    });

    test('Attra cobrado: la UI puede anunciarlo', () {
      final StoryReplyResult r = StoryReplyResult.fromMap(
        <String, dynamic>{'outcome': 'liked', 'chargedAttra': true},
      );

      expect(r.chargedAttra, isTrue);
      expect(r.insufficientAttras, isFalse);
    });

    test('con match ya hecho la ⭐ es un mensaje: no se cobra ni se anuncia', () {
      final StoryReplyResult r = StoryReplyResult.fromMap(
        <String, dynamic>{
          'outcome': 'message',
          'chatId': 'a_b',
          'chargedAttra': false,
        },
      );

      expect(r.outcome, 'message');
      expect(r.chargedAttra, isFalse);
      expect(r.chatId, 'a_b');
    });

    test('match creado por la respuesta', () {
      final StoryReplyResult r = StoryReplyResult.fromMap(
        <String, dynamic>{
          'outcome': 'matched',
          'chatId': 'a_b',
          'chargedAttra': true,
        },
      );

      expect(r.isMatch, isTrue);
      expect(r.chargedAttra, isTrue);
    });

    test('backend sin el flag: nunca se da un Attra por enviado', () {
      final StoryReplyResult r =
          StoryReplyResult.fromMap(<String, dynamic>{'outcome': 'liked'});

      expect(r.chargedAttra, isFalse);

      // Un valor no booleano tampoco cuela como "sí".
      expect(
        StoryReplyResult.fromMap(
          <String, dynamic>{'outcome': 'liked', 'chargedAttra': 'true'},
        ).chargedAttra,
        isFalse,
      );
    });

    test('respuesta vacía del backend: like, sin Attra', () {
      final StoryReplyResult r =
          StoryReplyResult.fromMap(const <String, dynamic>{});

      expect(r.outcome, 'liked');
      expect(r.chargedAttra, isFalse);
      expect(r.insufficientAttras, isFalse);
    });
  });
}
