import 'package:flutter_test/flutter_test.dart';

import 'package:attra/src/features/live/domain/live_constants.dart';
import 'package:attra/src/features/live/domain/live_session.dart';
import 'package:attra/src/features/live/domain/live_state_machine.dart';

LiveSession session({
  LiveSessionStatus status = LiveSessionStatus.ringing,
  DateTime? startedAt,
  DateTime? endsAt,
}) {
  return LiveSession(
    id: 'aaa_bbb',
    userA: 'aaa',
    userB: 'bbb',
    status: status,
    startedAt: startedAt,
    endsAt: endsAt,
  );
}

void main() {
  group('canTransition: solo ringing -> active -> ended', () {
    test('transiciones VALIDAS', () {
      expect(
        canTransition(LiveSessionStatus.ringing, LiveSessionStatus.active),
        isTrue,
      );
      // Nadie descuelga / uno sale / moderacion antes de conectar.
      expect(
        canTransition(LiveSessionStatus.ringing, LiveSessionStatus.ended),
        isTrue,
      );
      expect(
        canTransition(LiveSessionStatus.active, LiveSessionStatus.ended),
        isTrue,
      );
    });

    test('NADA puede revivir una sesion terminada', () {
      for (final LiveSessionStatus to in LiveSessionStatus.values) {
        expect(
          canTransition(LiveSessionStatus.ended, to),
          isFalse,
          reason: 'ended -> ${to.wireName} deberia ser imposible',
        );
      }
    });

    test('no se puede retroceder', () {
      expect(
        canTransition(LiveSessionStatus.active, LiveSessionStatus.ringing),
        isFalse,
      );
    });

    test('no hay auto-transiciones', () {
      for (final LiveSessionStatus s in LiveSessionStatus.values) {
        expect(canTransition(s, s), isFalse, reason: '${s.wireName} -> si mismo');
      }
    });

    test('la tabla cubre todos los estados (nada queda sin definir)', () {
      for (final LiveSessionStatus s in LiveSessionStatus.values) {
        expect(kLiveTransitions.containsKey(s), isTrue);
      }
      // Matriz completa: 3x3 = 9 pares, solo 3 validos.
      int valid = 0;
      for (final LiveSessionStatus from in LiveSessionStatus.values) {
        for (final LiveSessionStatus to in LiveSessionStatus.values) {
          if (canTransition(from, to)) valid++;
        }
      }
      expect(valid, 3);
    });

    test('nextStatus devuelve el estado o null si es invalida', () {
      expect(
        nextStatus(LiveSessionStatus.ringing, LiveSessionStatus.active),
        LiveSessionStatus.active,
      );
      expect(
        nextStatus(LiveSessionStatus.ended, LiveSessionStatus.active),
        isNull,
      );
    });
  });

  group('startSession', () {
    final DateTime now = DateTime(2026, 5, 1, 10);

    test('ringing -> active fija startedAt y endsAt (+3 min)', () {
      final LiveSession? s = startSession(session(), now: now);
      expect(s, isNotNull);
      expect(s!.status, LiveSessionStatus.active);
      expect(s.startedAt, now);
      expect(s.endsAt, now.add(LiveConstants.sessionMax));
      expect(s.remaining(now: now), LiveConstants.sessionMax);
    });

    test('una sesion activa no se re-arranca', () {
      expect(
        startSession(session(status: LiveSessionStatus.active), now: now),
        isNull,
      );
    });

    test('una sesion terminada NUNCA se arranca', () {
      expect(
        startSession(session(status: LiveSessionStatus.ended), now: now),
        isNull,
      );
    });

    test('respeta el endsAt que ya hubiera escrito el servidor', () {
      final DateTime serverEnd = now.add(const Duration(minutes: 1));
      final LiveSession? s =
          startSession(session(endsAt: serverEnd), now: now);
      expect(s!.endsAt, serverEnd);
    });
  });

  group('endSession', () {
    final DateTime now = DateTime(2026, 5, 1, 10);

    test('cierra una sesion activa con motivo y autor', () {
      final LiveSession? s = endSession(
        session(status: LiveSessionStatus.active, startedAt: now),
        reason: LiveEndReason.moderation,
        endedBy: 'aaa',
        now: now,
      );
      expect(s!.status, LiveSessionStatus.ended);
      expect(s.endReason, LiveEndReason.moderation);
      expect(s.endedBy, 'aaa');
      expect(s.endedAt, now);
      expect(s.isLive, isFalse);
    });

    test('cierra una sesion que solo sonaba', () {
      final LiveSession? s = endSession(
        session(),
        reason: LiveEndReason.left,
        now: now,
      );
      expect(s!.status, LiveSessionStatus.ended);
    });

    test('el segundo cierre se ignora: gana el primero', () {
      final LiveSession first = endSession(
        session(status: LiveSessionStatus.active),
        reason: LiveEndReason.moderation,
        endedBy: 'aaa',
        now: now,
      )!;
      final LiveSession? second = endSession(
        first,
        reason: LiveEndReason.left,
        endedBy: 'bbb',
        now: now,
      );
      expect(second, isNull);
      expect(first.endReason, LiveEndReason.moderation);
    });
  });

  group('expiryEndReason (caducidad por tiempo)', () {
    final DateTime started = DateTime(2026, 5, 1, 10);

    test('antes de los 3 min no cierra nada', () {
      final LiveSession s =
          session(status: LiveSessionStatus.active, startedAt: started);
      expect(
        expiryEndReason(s, now: started.add(const Duration(minutes: 2))),
        isNull,
      );
    });

    test('pasados los 3 min devuelve timeout', () {
      final LiveSession s =
          session(status: LiveSessionStatus.active, startedAt: started);
      expect(
        expiryEndReason(s, now: started.add(const Duration(minutes: 3))),
        LiveEndReason.timeout,
      );
    });

    test('una sesion ya terminada no vuelve a caducar', () {
      final LiveSession s =
          session(status: LiveSessionStatus.ended, startedAt: started);
      expect(
        expiryEndReason(s, now: started.add(const Duration(hours: 1))),
        isNull,
      );
    });

    test('caducidad + cierre encadenados dan una sesion terminada', () {
      final DateTime late = started.add(const Duration(minutes: 4));
      final LiveSession s =
          session(status: LiveSessionStatus.active, startedAt: started);
      final LiveEndReason? reason = expiryEndReason(s, now: late);
      final LiveSession? closed =
          endSession(s, reason: reason!, now: late);
      expect(closed!.status, LiveSessionStatus.ended);
      expect(closed.endReason, LiveEndReason.timeout);
      expect(closed.remaining(now: late), Duration.zero);
    });
  });

  group('resolveVerdicts', () {
    test('like + like -> match y motivo matched', () {
      final LiveVerdictResolution r = resolveVerdicts(
        uidA: 'aaa',
        uidB: 'bbb',
        verdictA: LiveVerdict.like,
        verdictB: LiveVerdict.like,
      );
      expect(r.outcome, LiveMatchOutcome.matched);
      expect(r.isMatch, isTrue);
      expect(r.dislikedBy, isEmpty);
      expect(r.endReason, LiveEndReason.matched);
    });

    test('like + pass -> no match; solo quien paso escribe dislike', () {
      final LiveVerdictResolution r = resolveVerdicts(
        uidA: 'aaa',
        uidB: 'bbb',
        verdictA: LiveVerdict.like,
        verdictB: LiveVerdict.pass,
      );
      expect(r.outcome, LiveMatchOutcome.noMatch);
      expect(r.isMatch, isFalse);
      expect(r.dislikedBy, <String>['bbb']);
    });

    test('pass + like -> no match (simetrico)', () {
      final LiveVerdictResolution r = resolveVerdicts(
        uidA: 'aaa',
        uidB: 'bbb',
        verdictA: LiveVerdict.pass,
        verdictB: LiveVerdict.like,
      );
      expect(r.outcome, LiveMatchOutcome.noMatch);
      expect(r.dislikedBy, <String>['aaa']);
    });

    test('pass + pass -> no match y dos dislikes', () {
      final LiveVerdictResolution r = resolveVerdicts(
        uidA: 'aaa',
        uidB: 'bbb',
        verdictA: LiveVerdict.pass,
        verdictB: LiveVerdict.pass,
      );
      expect(r.outcome, LiveMatchOutcome.noMatch);
      expect(r.dislikedBy, <String>['aaa', 'bbb']);
    });

    test('solo uno ha decidido -> pendiente', () {
      final LiveVerdictResolution r = resolveVerdicts(
        uidA: 'aaa',
        uidB: 'bbb',
        verdictA: LiveVerdict.like,
      );
      expect(r.outcome, LiveMatchOutcome.pending);
      expect(r.isPending, isTrue);
      expect(r.dislikedBy, isEmpty);
      expect(r.endReason, isNull);
    });

    test('pendiente pero con un pass: el dislike no se pierde', () {
      final LiveVerdictResolution r = resolveVerdicts(
        uidA: 'aaa',
        uidB: 'bbb',
        verdictB: LiveVerdict.pass,
      );
      expect(r.outcome, LiveMatchOutcome.pending);
      expect(r.dislikedBy, <String>['bbb']);
    });

    test('nadie ha decidido -> pendiente sin efectos', () {
      final LiveVerdictResolution r =
          resolveVerdicts(uidA: 'aaa', uidB: 'bbb');
      expect(r.outcome, LiveMatchOutcome.pending);
      expect(r.dislikedBy, isEmpty);
    });

    test('un veredicto ilegible cuenta como pass, jamas crea match', () {
      final LiveVerdictResolution r = resolveVerdicts(
        uidA: 'aaa',
        uidB: 'bbb',
        verdictA: LiveVerdict.like,
        verdictB: LiveVerdict.fromValue('superlike'),
      );
      expect(r.outcome, LiveMatchOutcome.noMatch);
      expect(r.dislikedBy, <String>['bbb']);
    });

    test('la lista de dislikes es inmutable', () {
      final LiveVerdictResolution r = resolveVerdicts(
        uidA: 'aaa',
        uidB: 'bbb',
        verdictA: LiveVerdict.pass,
        verdictB: LiveVerdict.pass,
      );
      expect(() => r.dislikedBy.add('ccc'), throwsUnsupportedError);
    });

    test('resolveSessionVerdicts toma los uids de la sesion', () {
      final LiveVerdictResolution r = resolveSessionVerdicts(
        session(status: LiveSessionStatus.active),
        verdictA: LiveVerdict.pass,
        verdictB: LiveVerdict.like,
      );
      expect(r.dislikedBy, <String>['aaa']);
      expect(r.outcome, LiveMatchOutcome.noMatch);
    });
  });
}
