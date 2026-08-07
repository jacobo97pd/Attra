import 'package:flutter_test/flutter_test.dart';

import 'package:attra/src/features/live/domain/live_constants.dart';
import 'package:attra/src/features/live/domain/live_strikes.dart';

void main() {
  final DateTime now = DateTime(2026, 5, 1, 10);

  group('constantes del contrato', () {
    test('valores exactos compartidos con el backend', () {
      expect(LiveConstants.sessionMaxMs, 3 * 60 * 1000);
      expect(LiveConstants.sampleMs, 5000);
      expect(LiveConstants.strikeBlockMs, 24 * 60 * 60 * 1000);
      expect(LiveConstants.maxStrikes, 3);
      expect(LiveConstants.strikeBlock, const Duration(hours: 24));
      expect(LiveConstants.sampleInterval, const Duration(seconds: 5));
    });

    test('expectedSamples: un fotograma cada 5 s de sesion', () {
      expect(LiveConstants.expectedSamples(Duration.zero), 0);
      expect(LiveConstants.expectedSamples(const Duration(seconds: 4)), 0);
      expect(LiveConstants.expectedSamples(const Duration(seconds: 5)), 1);
      expect(LiveConstants.expectedSamples(LiveConstants.sessionMax), 36);
    });
  });

  group('LiveStrikePolicy.evaluate: fronteras 0..4', () {
    test('0 strikes: sin sancion, la sesion sigue', () {
      final LiveStrikeDecision d = LiveStrikePolicy.evaluate(0, now);
      expect(d.action, LiveStrikeAction.none);
      expect(d.endSession, isFalse);
      expect(d.blocksLive, isFalse);
      expect(d.blockedUntil, isNull);
      expect(d.permanentlyBlocked, isFalse);
      expect(d.reportToModeration, isFalse);
    });

    test('recuento negativo (dato corrupto) NUNCA castiga', () {
      final LiveStrikeDecision d = LiveStrikePolicy.evaluate(-3, now);
      expect(d.action, LiveStrikeAction.none);
      expect(d.blocksLive, isFalse);
      expect(d.endSession, isFalse);
    });

    test('1 strike: aviso + corte inmediato, sin bloqueo', () {
      final LiveStrikeDecision d = LiveStrikePolicy.evaluate(1, now);
      expect(d.action, LiveStrikeAction.warnAndEnd);
      expect(d.endSession, isTrue);
      expect(d.isWarningOnly, isTrue);
      expect(d.blockedUntil, isNull);
      expect(d.blocksLive, isFalse);
      expect(d.permanentlyBlocked, isFalse);
      expect(d.reportToModeration, isFalse);
    });

    test('2 strikes: bloqueo de 24 h exactas desde ahora', () {
      final LiveStrikeDecision d = LiveStrikePolicy.evaluate(2, now);
      expect(d.action, LiveStrikeAction.temporaryBlock);
      expect(d.endSession, isTrue);
      expect(d.blockedUntil, now.add(const Duration(hours: 24)));
      expect(d.blocksLive, isTrue);
      expect(d.action.isBlocking, isTrue);
      expect(d.permanentlyBlocked, isFalse);
      expect(d.reportToModeration, isFalse);
    });

    test('3 strikes: permanente + reporte automatico a moderacion', () {
      final LiveStrikeDecision d = LiveStrikePolicy.evaluate(3, now);
      expect(d.action, LiveStrikeAction.permanentBlock);
      expect(d.endSession, isTrue);
      expect(d.permanentlyBlocked, isTrue);
      expect(d.reportToModeration, isTrue);
      expect(d.blocksLive, isTrue);
      // Sin fecha de fin a proposito: el permanente no caduca solo.
      expect(d.blockedUntil, isNull);
    });

    test('4 strikes (y mas) siguen siendo permanentes, no reinician', () {
      for (final int count in <int>[4, 5, 99]) {
        final LiveStrikeDecision d = LiveStrikePolicy.evaluate(count, now);
        expect(d.action, LiveStrikeAction.permanentBlock,
            reason: 'count=$count');
        expect(d.permanentlyBlocked, isTrue);
        expect(d.reportToModeration, isTrue);
      }
    });

    test('cualquier strike corta la sesion en curso', () {
      for (final int count in <int>[1, 2, 3, 7]) {
        expect(LiveStrikePolicy.evaluate(count, now).endSession, isTrue,
            reason: 'count=$count');
      }
    });

    test('la funcion es pura: mismo count y now, mismo resultado', () {
      final LiveStrikeDecision a = LiveStrikePolicy.evaluate(2, now);
      final LiveStrikeDecision b = LiveStrikePolicy.evaluate(2, now);
      expect(a.action, b.action);
      expect(a.blockedUntil, b.blockedUntil);
    });
  });

  group('LiveStrikes: caducidad del bloqueo de 24 h', () {
    LiveStrikes blockedFrom(DateTime at) => LiveStrikes(
          uid: 'aaa',
          count: 2,
          blockedUntil: at.add(LiveConstants.strikeBlock),
        );

    test('documento limpio no bloquea', () {
      const LiveStrikes s = LiveStrikes.clean('aaa');
      expect(s.count, 0);
      expect(s.isBlockedAt(DateTime(2026, 5, 1)), isFalse);
      expect(s.remainingBlock(DateTime(2026, 5, 1)), Duration.zero);
      expect(s.permanentlyBlocked, isFalse);
    });

    test('dentro de las 24 h sigue bloqueado', () {
      final LiveStrikes s = blockedFrom(now);
      expect(s.isBlockedAt(now), isTrue);
      expect(s.isBlockedAt(now.add(const Duration(hours: 23, minutes: 59))),
          isTrue);
      expect(s.remainingBlock(now), const Duration(hours: 24));
      expect(
        s.remainingBlock(now.add(const Duration(hours: 20))),
        const Duration(hours: 4),
      );
    });

    test('en el instante exacto de vencimiento ya NO bloquea', () {
      final LiveStrikes s = blockedFrom(now);
      final DateTime expiry = now.add(const Duration(hours: 24));
      expect(s.isBlockedAt(expiry), isFalse);
      expect(s.remainingBlock(expiry), Duration.zero);
    });

    test('pasadas las 24 h deja de bloquear aunque el contador siga a 2', () {
      final LiveStrikes s = blockedFrom(now);
      final DateTime after = now.add(const Duration(hours: 25));
      expect(s.isBlockedAt(after), isFalse);
      expect(s.remainingBlock(after), Duration.zero);
      // Los strikes NO se borran: el siguiente sube a 3 y es permanente.
      expect(s.count, 2);
      expect(
        LiveStrikePolicy.evaluate(s.count + 1, after).action,
        LiveStrikeAction.permanentBlock,
      );
    });

    test('el permanente bloquea siempre, sin blockedUntil', () {
      const LiveStrikes s = LiveStrikes(
        uid: 'aaa',
        count: 3,
        permanentlyBlocked: true,
      );
      expect(s.isBlockedAt(now), isTrue);
      expect(s.isBlockedAt(now.add(const Duration(days: 3650))), isTrue);
      expect(s.remainingBlock(now), Duration.zero);
    });

    test('el permanente gana aunque haya un blockedUntil ya vencido', () {
      final LiveStrikes s = LiveStrikes(
        uid: 'aaa',
        count: 3,
        permanentlyBlocked: true,
        blockedUntil: now.subtract(const Duration(days: 2)),
      );
      expect(s.isBlockedAt(now), isTrue);
    });

    test('decisionAt deriva la sancion vigente del recuento', () {
      const LiveStrikes s = LiveStrikes(uid: 'aaa', count: 2);
      expect(s.decisionAt(now).action, LiveStrikeAction.temporaryBlock);
      expect(s.decisionAt(now).blockedUntil, now.add(const Duration(hours: 24)));
    });
  });

  group('LiveStrikes parseo/serializacion', () {
    test('fromMap tolerante con documento vacio', () {
      final LiveStrikes s = LiveStrikes.fromMap('aaa', <String, dynamic>{});
      expect(s.uid, 'aaa');
      expect(s.count, 0);
      expect(s.reasons, isEmpty);
      expect(s.blockedUntil, isNull);
      expect(s.permanentlyBlocked, isFalse);
      expect(s.isBlockedAt(now), isFalse);
    });

    test('fromMap lee el documento completo', () {
      final DateTime until = now.add(const Duration(hours: 24));
      final LiveStrikes s = LiveStrikes.fromMap('aaa', <String, dynamic>{
        'count': 2,
        'reasons': <Object?>['adult', '', null, 'racy'],
        'lastAt': now,
        'blockedUntil': until,
        'permanentlyBlocked': false,
      });
      expect(s.count, 2);
      expect(s.reasons, <String>['adult', 'racy']);
      expect(s.lastAt, now);
      expect(s.blockedUntil, until);
      expect(s.isBlockedAt(now), isTrue);
    });

    test('tipos raros no revientan (count no numerico, reasons no lista)', () {
      final LiveStrikes s = LiveStrikes.fromMap('aaa', <String, dynamic>{
        'count': 'dos',
        'reasons': 'adult',
        'permanentlyBlocked': 'si',
      });
      expect(s.count, 0);
      expect(s.reasons, isEmpty);
      // Solo el booleano true bloquea: un string no cuenta como veto.
      expect(s.permanentlyBlocked, isFalse);
    });

    test('toMap escribe los campos del contrato', () {
      final DateTime until = now.add(const Duration(hours: 24));
      final LiveStrikes s = LiveStrikes(
        uid: 'aaa',
        count: 2,
        reasons: const <String>['adult'],
        lastAt: now,
        blockedUntil: until,
      );
      final Map<String, dynamic> map = s.toMap();
      expect(map['count'], 2);
      expect(map['reasons'], <String>['adult']);
      expect(map['lastAt'], now);
      expect(map['blockedUntil'], until);
      expect(map['permanentlyBlocked'], isFalse);
    });

    test('copyWith mantiene el uid y cambia lo indicado', () {
      const LiveStrikes s = LiveStrikes.clean('aaa');
      final LiveStrikes bumped = s.copyWith(count: 1, lastAt: now);
      expect(bumped.uid, 'aaa');
      expect(bumped.count, 1);
      expect(bumped.lastAt, now);
    });
  });
}
