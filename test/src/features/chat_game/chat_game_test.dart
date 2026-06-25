import 'package:flutter_test/flutter_test.dart';
import 'package:attra/src/features/chat_game/domain/chat_game.dart';

void main() {
  group('ChatGameStatus', () {
    test('fromValue parsea wireName y nombre', () {
      expect(ChatGameStatus.fromValue('active'), ChatGameStatus.active);
      expect(ChatGameStatus.fromValue('coffee'), ChatGameStatus.pending); // fallback
      expect(ChatGameStatus.fromValue('completed').isCompleted, isTrue);
    });

    test('isTerminal cubre completed/cancelled/abandoned', () {
      expect(ChatGameStatus.completed.isTerminal, isTrue);
      expect(ChatGameStatus.cancelled.isTerminal, isTrue);
      expect(ChatGameStatus.abandoned.isTerminal, isTrue);
      expect(ChatGameStatus.active.isTerminal, isFalse);
      expect(ChatGameStatus.pending.isTerminal, isFalse);
    });
  });

  group('ChatGameMode', () {
    test('coffee_challenge', () {
      expect(ChatGameMode.fromValue('coffee_challenge').isCoffee, isTrue);
      expect(ChatGameMode.fromValue('normal').isCoffee, isFalse);
      expect(ChatGameMode.fromValue(null), ChatGameMode.normal);
    });
  });

  group('ChatGameSession.fromMap', () {
    final ChatGameSession s = ChatGameSession.fromMap('s1', <String, dynamic>{
      'chatId': 'c1',
      'matchId': 'm1',
      'creatorUserId': 'A',
      'invitedUserId': 'B',
      'status': 'active',
      'mode': 'normal',
      'acceptedBy': <String>['A', 'B'],
      'themeTitle': 'Diseñad vuestra cita perfecta con 20€',
      'endsAt': DateTime.now().add(const Duration(minutes: 3)),
    });

    test('parsea campos básicos', () {
      expect(s.id, 's1');
      expect(s.creatorUserId, 'A');
      expect(s.invitedUserId, 'B');
      expect(s.status, ChatGameStatus.active);
      expect(s.themeTitle, contains('20€'));
    });

    test('acceptedByBoth / hasAccepted / otherUid', () {
      expect(s.acceptedByBoth(), isTrue);
      expect(s.hasAccepted('A'), isTrue);
      expect(s.otherUid('A'), 'B');
      expect(s.otherUid('B'), 'A');
    });

    test('secondsLeft > 0 cuando activo y endsAt futuro', () {
      expect(s.secondsLeft(), greaterThan(0));
    });

    test('secondsLeft = 0 si no está activo', () {
      final ChatGameSession pending = ChatGameSession.fromMap('s2',
          <String, dynamic>{'status': 'pending', 'endsAt': DateTime.now()});
      expect(pending.secondsLeft(), 0);
    });
  });

  group('ChatGameResult.fromMap', () {
    test('parsea resultado completo + plan + payer', () {
      final ChatGameResult r = ChatGameResult.fromMap(<String, dynamic>{
        'winnerUserId': 'A',
        'isDraw': false,
        'chemistryScore': 82,
        'bestMoment': '¿Y tú qué plan harías?',
        'reason': 'Ha ganado A por hacer mejores preguntas.',
        'suggestedDatePlan': <String, dynamic>{
          'title': 'Café con calma',
          'description': 'Una cafetería tranquila.',
          'placeType': 'cafetería',
          'payerSuggestion': 'winner_chooses',
        },
        'followUpMessage': '¿Quién propone día y hora?',
      });
      expect(r.winnerUserId, 'A');
      expect(r.isDraw, isFalse);
      expect(r.chemistryScore, 82);
      expect(r.suggestedDatePlan?.placeType, 'cafetería');
      expect(r.suggestedDatePlan?.payerSuggestion,
          PayerSuggestion.winnerChooses);
    });

    test('empate sin ganador', () {
      final ChatGameResult r = ChatGameResult.fromMap(<String, dynamic>{
        'winnerUserId': null,
        'isDraw': true,
        'chemistryScore': 70,
      });
      expect(r.winnerUserId, isNull);
      expect(r.isDraw, isTrue);
      expect(r.suggestedDatePlan, isNull);
    });

    test('noWinner cuando faltan mensajes', () {
      final ChatGameResult r =
          ChatGameResult.fromMap(<String, dynamic>{'noWinner': true});
      expect(r.noWinner, isTrue);
    });
  });
}
