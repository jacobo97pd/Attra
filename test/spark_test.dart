import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attra/src/features/monetization/domain/monetization_feature_flags.dart';
import 'package:attra/src/features/spark/domain/spark_round.dart';
import 'package:attra/src/features/spark/domain/spark_session.dart';
import 'package:attra/src/features/spark/domain/spark_summary.dart';

/// Construye un mapa de sesión como el que produce el repositorio, para probar
/// el parseo y la lógica pura sin Firestore.
Map<String, dynamic> sessionMap({
  required String a,
  required String b,
  String status = 'active',
  int currentRound = 0,
  Map<String, dynamic>? answers,
  bool aAccepted = true,
  bool bAccepted = true,
  DateTime? expiresAt,
}) {
  return <String, dynamic>{
    'matchId': 'm1',
    'userAId': a,
    'userBId': b,
    'invitedBy': a,
    'status': status,
    'currentRound': currentRound,
    'totalRounds': 5,
    'countdownSeconds': 300,
    'participants': <String, dynamic>{
      a: <String, dynamic>{
        'accepted': aAccepted,
        'lastSeenAt': Timestamp.fromDate(DateTime.now()),
      },
      b: <String, dynamic>{
        'accepted': bAccepted,
        'lastSeenAt': Timestamp.fromDate(DateTime.now()),
      },
    },
    'answers': answers ?? <String, dynamic>{},
    'reactions': <String, dynamic>{},
    if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
  };
}

void main() {
  group('Feature flag spark_enabled', () {
    test('por defecto está desactivado (app igual que antes)', () {
      expect(const MonetizationFeatureFlags().sparkEnabled, isFalse);
    });

    test('lee spark_enabled (snake_case) y sparkEnabled (camelCase)', () {
      expect(
        MonetizationFeatureFlags.fromMap(
            <String, dynamic>{'spark_enabled': true}).sparkEnabled,
        isTrue,
      );
      expect(
        MonetizationFeatureFlags.fromMap(
            <String, dynamic>{'sparkEnabled': true}).sparkEnabled,
        isTrue,
      );
    });

    test('disabled() deja spark off', () {
      expect(const MonetizationFeatureFlags.disabled().sparkEnabled, isFalse);
    });
  });

  group('Catálogo de rondas', () {
    test('siempre 5 rondas', () {
      expect(SparkRoundCatalog.buildRounds('abc').length, 5);
    });

    test('es determinista: misma sesión -> mismas rondas', () {
      final List<SparkRound> r1 = SparkRoundCatalog.buildRounds('session-xyz');
      final List<SparkRound> r2 = SparkRoundCatalog.buildRounds('session-xyz');
      expect(r1.map((SparkRound r) => r.id).toList(),
          r2.map((SparkRound r) => r.id).toList());
    });

    test('cubre las 5 mecánicas del MVP', () {
      final List<SparkRound> r = SparkRoundCatalog.buildRounds('s');
      expect(r.map((SparkRound e) => e.kind).toSet(), <SparkRoundKind>{
        SparkRoundKind.vibe,
        SparkRoundKind.guess,
        SparkRoundKind.react,
        SparkRoundKind.phrase,
        SparkRoundKind.nextStep,
      });
    });
  });

  group('SparkSession: pertenencia y aceptación', () {
    test('involves / otherUid / isHostUid', () {
      final SparkSession s =
          SparkSession.fromMap('s1', sessionMap(a: 'A', b: 'B'));
      expect(s.involves('A'), isTrue);
      expect(s.involves('B'), isTrue);
      expect(s.involves('C'), isFalse);
      expect(s.otherUid('A'), 'B');
      expect(s.isHostUid('A'), isTrue);
      expect(s.isHostUid('B'), isFalse);
    });

    test('bothAccepted refleja la aceptación de ambos', () {
      final SparkSession waiting = SparkSession.fromMap(
          's', sessionMap(a: 'A', b: 'B', status: 'waiting', bAccepted: false));
      expect(waiting.bothAccepted, isFalse);
      final SparkSession ready = SparkSession.fromMap(
          's', sessionMap(a: 'A', b: 'B', status: 'waiting', bAccepted: true));
      expect(ready.bothAccepted, isTrue);
    });
  });

  group('SparkSession: respuestas y avance', () {
    test('guardar respuestas: hasAnswered / answerOf / bothAnswered', () {
      final SparkSession s = SparkSession.fromMap(
        's',
        sessionMap(
          a: 'A',
          b: 'B',
          answers: <String, dynamic>{
            'r1_vibe': <String, dynamic>{'A': 'calm'},
          },
        ),
      );
      expect(s.hasAnswered('r1_vibe', 'A'), isTrue);
      expect(s.hasAnswered('r1_vibe', 'B'), isFalse);
      expect(s.answerOf('r1_vibe', 'A'), 'calm');
      expect(s.bothAnswered('r1_vibe'), isFalse);

      final SparkSession both = SparkSession.fromMap(
        's',
        sessionMap(
          a: 'A',
          b: 'B',
          answers: <String, dynamic>{
            'r1_vibe': <String, dynamic>{'A': 'calm', 'B': 'calm'},
          },
        ),
      );
      expect(both.bothAnswered('r1_vibe'), isTrue);
    });

    test('countdown: remainingSeconds nunca negativo', () {
      final SparkSession past = SparkSession.fromMap(
          's',
          sessionMap(
              a: 'A',
              b: 'B',
              expiresAt: DateTime.now().subtract(const Duration(seconds: 5))));
      expect(past.remainingSeconds(), 0);
      final SparkSession future = SparkSession.fromMap(
          's',
          sessionMap(
              a: 'A',
              b: 'B',
              expiresAt: DateTime.now().add(const Duration(seconds: 120))));
      expect(future.remainingSeconds(), greaterThan(100));
    });
  });

  group('SparkStatus', () {
    test('terminal vs vivo', () {
      expect(SparkStatus.completed.isTerminal, isTrue);
      expect(SparkStatus.abandoned.isTerminal, isTrue);
      expect(SparkStatus.expired.isTerminal, isTrue);
      expect(SparkStatus.active.isLive, isTrue);
      expect(SparkStatus.waiting.isLive, isTrue);
    });

    test('fromValue tolera desconocidos -> waiting', () {
      expect(SparkStatus.fromValue('???'), SparkStatus.waiting);
      expect(SparkStatus.fromValue('completed'), SparkStatus.completed);
    });
  });

  group('Resumen final (reglas locales)', () {
    test('coincidencia genera etiqueta + chatLine', () {
      final List<SparkRound> rounds = SparkRoundCatalog.buildRounds('seed');
      final SparkRound r1 = rounds.first; // vibe
      final SparkSession s = SparkSession.fromMap(
        's',
        sessionMap(
          a: 'A',
          b: 'B',
          status: 'completed',
          answers: <String, dynamic>{
            r1.id: <String, dynamic>{'A': 'calm', 'B': 'calm'},
          },
        ),
      );
      final SparkSummary sum =
          SparkSummaryBuilder.build(session: s, rounds: rounds);
      expect(sum.coincidences, contains('planes tranquilos'));
      expect(sum.chatLine, contains('Coincidencias'));
      expect(sum.suggestedQuestions, isNotEmpty);
    });

    test('sin coincidencias: chatLine amable de complemento', () {
      final List<SparkRound> rounds = SparkRoundCatalog.buildRounds('seed2');
      final SparkRound r1 = rounds.first;
      final SparkSession s = SparkSession.fromMap(
        's',
        sessionMap(
          a: 'A',
          b: 'B',
          status: 'completed',
          answers: <String, dynamic>{
            r1.id: <String, dynamic>{'A': 'calm', 'B': 'adventure'},
          },
        ),
      );
      final SparkSummary sum =
          SparkSummaryBuilder.build(session: s, rounds: rounds);
      expect(sum.chatLine.toLowerCase(), contains('complement'));
    });
  });
}
