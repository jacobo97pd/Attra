import 'package:flutter_test/flutter_test.dart';

import 'package:attra/src/features/live/domain/live_constants.dart';
import 'package:attra/src/features/live/domain/live_session.dart';

/// Timestamp "de mentira": imita al de cloud_firestore SOLO con `toDate()`.
/// Sirve para probar que el dominio (Dart puro) lo entiende por duck typing
/// sin importar Firebase.
class _FakeTimestamp {
  const _FakeTimestamp(this._value);
  final DateTime _value;
  DateTime toDate() => _value;
}

Map<String, dynamic> sessionMap({
  String userA = 'aaa',
  String userB = 'bbb',
  String status = 'active',
  Object? endReason,
  Object? startedAt,
  Object? endsAt,
  Object? endedBy,
  List<String>? users,
}) {
  return <String, dynamic>{
    'users': users ?? <String>[userA, userB],
    'userA': userA,
    'userB': userB,
    'status': status,
    if (endReason != null) 'endReason': endReason,
    if (startedAt != null) 'startedAt': startedAt,
    if (endsAt != null) 'endsAt': endsAt,
    if (endedBy != null) 'endedBy': endedBy,
  };
}

void main() {
  group('LiveSessionStatus.fromValue', () {
    test('lee los tres estados del contrato', () {
      expect(LiveSessionStatus.fromValue('ringing'), LiveSessionStatus.ringing);
      expect(LiveSessionStatus.fromValue('active'), LiveSessionStatus.active);
      expect(LiveSessionStatus.fromValue('ended'), LiveSessionStatus.ended);
    });

    test('tolera mayusculas y espacios', () {
      expect(LiveSessionStatus.fromValue('  ACTIVE '), LiveSessionStatus.active);
    });

    test('desconocido/nulo cae a ended (fail-closed: nunca abrir video)', () {
      expect(LiveSessionStatus.fromValue(null), LiveSessionStatus.ended);
      expect(LiveSessionStatus.fromValue(''), LiveSessionStatus.ended);
      expect(LiveSessionStatus.fromValue('connecting'), LiveSessionStatus.ended);
      expect(LiveSessionStatus.fromValue(42), LiveSessionStatus.ended);
    });

    test('isLive / isTerminal', () {
      expect(LiveSessionStatus.ringing.isLive, isTrue);
      expect(LiveSessionStatus.active.isLive, isTrue);
      expect(LiveSessionStatus.ended.isLive, isFalse);
      expect(LiveSessionStatus.ended.isTerminal, isTrue);
      expect(LiveSessionStatus.active.isTerminal, isFalse);
    });
  });

  group('LiveEndReason', () {
    test('lee los cinco motivos del contrato', () {
      expect(LiveEndReason.fromValue('left'), LiveEndReason.left);
      expect(LiveEndReason.fromValue('timeout'), LiveEndReason.timeout);
      expect(LiveEndReason.fromValue('reported'), LiveEndReason.reported);
      expect(LiveEndReason.fromValue('moderation'), LiveEndReason.moderation);
      expect(LiveEndReason.fromValue('matched'), LiveEndReason.matched);
    });

    test('desconocido cae a left, nunca a un motivo acusatorio', () {
      expect(LiveEndReason.fromValue('exploded'), LiveEndReason.left);
      expect(LiveEndReason.fromValue(null), LiveEndReason.left);
      expect(LiveEndReason.fromValue('exploded').isPunitive, isFalse);
    });

    test('tryFromValue distingue ausencia de motivo raro', () {
      expect(LiveEndReason.tryFromValue(null), isNull);
      expect(LiveEndReason.tryFromValue('   '), isNull);
      expect(LiveEndReason.tryFromValue('nope'), LiveEndReason.left);
    });

    test('isPunitive solo en moderacion y denuncia', () {
      expect(LiveEndReason.moderation.isPunitive, isTrue);
      expect(LiveEndReason.reported.isPunitive, isTrue);
      expect(LiveEndReason.timeout.isPunitive, isFalse);
      expect(LiveEndReason.matched.isPunitive, isFalse);
      expect(LiveEndReason.left.isPunitive, isFalse);
    });
  });

  group('LiveVerdict', () {
    test('lee like y pass', () {
      expect(LiveVerdict.fromValue('like'), LiveVerdict.like);
      expect(LiveVerdict.fromValue('PASS'), LiveVerdict.pass);
    });

    test('desconocido cae a pass (jamas fabricar un match)', () {
      expect(LiveVerdict.fromValue('superlike'), LiveVerdict.pass);
      expect(LiveVerdict.fromValue(null), LiveVerdict.pass);
      expect(LiveVerdict.fromValue(true), LiveVerdict.pass);
    });

    test('tryFromValue devuelve null cuando aun no hay veredicto', () {
      expect(LiveVerdict.tryFromValue(null), isNull);
      expect(LiveVerdict.tryFromValue(''), isNull);
      expect(LiveVerdict.tryFromValue('like'), LiveVerdict.like);
      // Un valor raro SI es un veredicto emitido: cuenta como pass.
      expect(LiveVerdict.tryFromValue('???'), LiveVerdict.pass);
    });
  });

  group('LiveVerdictEntry', () {
    test('round-trip fromMap/toMap', () {
      final DateTime at = DateTime(2026, 3, 1, 12, 30);
      final LiveVerdictEntry entry = LiveVerdictEntry.fromMap(
        'aaa',
        <String, dynamic>{'verdict': 'like', 'decidedAt': at},
      );
      expect(entry.uid, 'aaa');
      expect(entry.verdict, LiveVerdict.like);
      expect(entry.decidedAt, at);
      expect(entry.toMap()['verdict'], 'like');
      expect(entry.toMap()['decidedAt'], at);
    });
  });

  group('LiveSession.fromMap', () {
    test('parsea el documento completo', () {
      final DateTime started = DateTime(2026, 5, 1, 10);
      final LiveSession s = LiveSession.fromMap(
        'aaa_bbb',
        sessionMap(
          startedAt: started,
          endsAt: started.add(LiveConstants.sessionMax),
        ),
      );
      expect(s.id, 'aaa_bbb');
      expect(s.userA, 'aaa');
      expect(s.userB, 'bbb');
      expect(s.users, <String>['aaa', 'bbb']);
      expect(s.status, LiveSessionStatus.active);
      expect(s.startedAt, started);
      expect(s.isLive, isTrue);
      expect(s.isEnded, isFalse);
    });

    test('deriva los uids del array users cuando faltan userA/userB', () {
      final LiveSession s = LiveSession.fromMap('x', <String, dynamic>{
        'users': <String>['zzz', 'yyy'],
        'status': 'ringing',
      });
      expect(s.userA, 'zzz');
      expect(s.userB, 'yyy');
    });

    test('documento vacio no revienta y queda cerrado', () {
      final LiveSession s = LiveSession.fromMap('x', <String, dynamic>{});
      expect(s.userA, isEmpty);
      expect(s.userB, isEmpty);
      expect(s.status, LiveSessionStatus.ended);
      expect(s.endReason, isNull);
      expect(s.effectiveEndsAt, isNull);
    });

    test('involves / otherUid', () {
      final LiveSession s = LiveSession.fromMap('x', sessionMap());
      expect(s.involves('aaa'), isTrue);
      expect(s.involves('bbb'), isTrue);
      expect(s.involves('ccc'), isFalse);
      expect(s.otherUid('aaa'), 'bbb');
      expect(s.otherUid('bbb'), 'aaa');
    });

    test('toMap escribe los nombres del contrato', () {
      final DateTime started = DateTime(2026, 5, 1, 10);
      final LiveSession s = LiveSession.fromMap(
        'aaa_bbb',
        sessionMap(
          status: 'ended',
          endReason: 'moderation',
          endedBy: 'aaa',
          startedAt: started,
        ),
      );
      final Map<String, dynamic> map = s.toMap();
      expect(map['status'], 'ended');
      expect(map['endReason'], 'moderation');
      expect(map['endedBy'], 'aaa');
      expect(map['users'], <String>['aaa', 'bbb']);
      expect(map['userA'], 'aaa');
      expect(map['userB'], 'bbb');
    });
  });

  group('fechas tolerantes (sin importar cloud_firestore)', () {
    final DateTime ref = DateTime.utc(2026, 5, 1, 10);

    test('acepta DateTime tal cual', () {
      expect(liveDateFromValue(ref), ref);
    });

    test('acepta epoch en milisegundos', () {
      expect(
        liveDateFromValue(ref.millisecondsSinceEpoch)!.toUtc(),
        ref,
      );
    });

    test('acepta ISO-8601', () {
      expect(liveDateFromValue(ref.toIso8601String())!.toUtc(), ref);
    });

    test('acepta el Timestamp serializado {_seconds,_nanoseconds}', () {
      final Map<String, Object> raw = <String, Object>{
        '_seconds': ref.millisecondsSinceEpoch ~/ 1000,
        '_nanoseconds': 0,
      };
      expect(liveDateFromValue(raw)!.toUtc(), ref);
    });

    test('acepta un Timestamp real por duck typing (toDate)', () {
      expect(liveDateFromValue(_FakeTimestamp(ref)), ref);
    });

    test('valores no interpretables devuelven null en vez de lanzar', () {
      expect(liveDateFromValue(null), isNull);
      expect(liveDateFromValue(''), isNull);
      expect(liveDateFromValue('no soy fecha'), isNull);
      expect(liveDateFromValue(<String, Object>{'foo': 'bar'}), isNull);
      expect(liveDateFromValue(Object()), isNull);
    });
  });

  group('caducidad de la sesion por tiempo (3 min)', () {
    final DateTime started = DateTime(2026, 5, 1, 10);

    LiveSession active({DateTime? endsAt, DateTime? startedAt}) {
      return LiveSession(
        id: 'aaa_bbb',
        userA: 'aaa',
        userB: 'bbb',
        status: LiveSessionStatus.active,
        startedAt: startedAt,
        endsAt: endsAt,
      );
    }

    test('el tope del contrato son exactamente 3 minutos', () {
      expect(LiveConstants.sessionMax, const Duration(minutes: 3));
      expect(LiveConstants.sessionMaxMs, 180000);
    });

    test('usa endsAt del servidor cuando existe (autoridad)', () {
      final DateTime endsAt = started.add(const Duration(minutes: 1));
      final LiveSession s = active(startedAt: started, endsAt: endsAt);
      expect(s.effectiveEndsAt, endsAt);
      expect(s.isExpired(now: endsAt.subtract(const Duration(seconds: 1))),
          isFalse);
      expect(s.isExpired(now: endsAt.add(const Duration(seconds: 1))), isTrue);
    });

    test('deriva el vencimiento de startedAt + 3 min si falta endsAt', () {
      final LiveSession s = active(startedAt: started);
      expect(s.effectiveEndsAt, started.add(const Duration(minutes: 3)));
    });

    test('a los 2:59 sigue viva, a los 3:00 esta caducada (limite corta)', () {
      final LiveSession s = active(startedAt: started);
      expect(
        s.isExpired(now: started.add(const Duration(seconds: 179))),
        isFalse,
      );
      expect(
        s.isExpired(now: started.add(const Duration(minutes: 3))),
        isTrue,
      );
      expect(
        s.isExpired(now: started.add(const Duration(minutes: 3, seconds: 1))),
        isTrue,
      );
    });

    test('remaining nunca es negativo y llega a cero', () {
      final LiveSession s = active(startedAt: started);
      expect(
        s.remaining(now: started.add(const Duration(minutes: 1))),
        const Duration(minutes: 2),
      );
      expect(
        s.remaining(now: started.add(const Duration(minutes: 10))),
        Duration.zero,
      );
    });

    test('sin reloj (ringing sin endsAt) no hay caducidad calculable', () {
      const LiveSession s = LiveSession(
        id: 'aaa_bbb',
        userA: 'aaa',
        userB: 'bbb',
        status: LiveSessionStatus.ringing,
      );
      expect(s.effectiveEndsAt, isNull);
      expect(s.remaining(now: started), isNull);
      expect(s.isExpired(now: started), isFalse);
      expect(s.shouldAutoEnd(now: started), isFalse);
    });

    test('shouldAutoEnd solo si sigue viva', () {
      final DateTime late = started.add(const Duration(minutes: 5));
      expect(active(startedAt: started).shouldAutoEnd(now: late), isTrue);

      final LiveSession ended = LiveSession(
        id: 'aaa_bbb',
        userA: 'aaa',
        userB: 'bbb',
        status: LiveSessionStatus.ended,
        startedAt: started,
      );
      // Ya cerrada: caducada si, pero no hay nada que auto-cerrar.
      expect(ended.isExpired(now: late), isTrue);
      expect(ended.shouldAutoEnd(now: late), isFalse);
    });
  });
}
