import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attra/src/features/live/domain/live_block_notice.dart';
import 'package:attra/src/features/live/domain/live_constants.dart';
import 'package:attra/src/features/live/domain/live_flags.dart';
import 'package:attra/src/features/live/domain/live_rules.dart';
import 'package:attra/src/features/live/domain/live_strikes.dart';
import 'package:attra/src/features/live/presentation/live_rules_view.dart';

void main() {
  final DateTime now = DateTime(2026, 5, 1, 10);

  group('LiveFlags: dark launch', () {
    test('sin config remota el directo esta APAGADO', () {
      // Es la garantia del dark launch: si el doc no carga, no hay entrada.
      expect(LiveFlags.fromMap(const <String, dynamic>{}).active, isFalse);
      expect(const LiveFlags().active, isFalse);
      expect(LiveFlags.disabled.active, isFalse);
    });

    test('solo se enciende con feature_live_enabled en true', () {
      expect(
        LiveFlags.fromMap(const <String, dynamic>{'feature_live_enabled': true})
            .active,
        isTrue,
      );
    });

    test('un valor que no sea booleano NO enciende nada', () {
      // Una errata en la consola ("true" como string) no puede abrir el
      // directo a todo el mundo por accidente.
      final LiveFlags flags = LiveFlags.fromMap(
        const <String, dynamic>{'feature_live_enabled': 'true'},
      );
      expect(flags.enabled, isFalse);
      expect(flags.active, isFalse);
    });

    test('el kill switch gana al master switch', () {
      final LiveFlags flags = LiveFlags.fromMap(const <String, dynamic>{
        'feature_live_enabled': true,
        'feature_live_kill_switch': true,
      });
      expect(flags.enabled, isTrue);
      expect(flags.active, isFalse);
    });
  });

  group('LiveBlockNotice: temporal vs permanente', () {
    test('sin sancion no hay aviso que pintar', () {
      expect(
        LiveBlockNotice.fromStrikes(const LiveStrikes.clean('u1'), now),
        isNull,
      );
    });

    test('bloqueo temporal: conserva el vencimiento y cuenta lo que queda', () {
      final LiveBlockNotice? notice = LiveBlockNotice.fromStrikes(
        LiveStrikes(
          uid: 'u1',
          count: 2,
          blockedUntil: now.add(const Duration(hours: 5)),
        ),
        now,
      );
      expect(notice, isNotNull);
      expect(notice!.permanent, isFalse);
      expect(notice.temporary, isTrue);
      expect(notice.durationUnknown, isFalse);
      expect(notice.remaining(now), const Duration(hours: 5));
    });

    test('bloqueo temporal vencido deja de bloquear', () {
      expect(
        LiveBlockNotice.fromStrikes(
          LiveStrikes(
            uid: 'u1',
            count: 2,
            blockedUntil: now.subtract(const Duration(minutes: 1)),
          ),
          now,
        ),
        isNull,
      );
    });

    test('permanente: sin cuenta atras que ofrecer', () {
      // Enseñar un plazo invitaria a esperar a que caduque algo que no caduca.
      final LiveBlockNotice? notice = LiveBlockNotice.fromStrikes(
        LiveStrikes(
          uid: 'u1',
          count: LiveConstants.maxStrikes,
          permanentlyBlocked: true,
          blockedUntil: now.add(const Duration(hours: 5)),
        ),
        now,
      );
      expect(notice!.permanent, isTrue);
      expect(notice.until, isNull);
      expect(notice.remaining(now), Duration.zero);
    });

    test('veto del backend sin detalle: ni permanente ni con plazo', () {
      expect(LiveBlockNotice.unknown.permanent, isFalse);
      expect(LiveBlockNotice.unknown.durationUnknown, isTrue);
    });
  });

  group('Normas del directo', () {
    test('cubren lo que exige la guideline 1.2', () {
      // Si alguien borra una norma, esto cae: prohibicion, analisis automatico,
      // consecuencias y como denunciar son el minimo que hay que enseñar ANTES
      // de encender la camara.
      expect(
        LiveRules.all.map((LiveRule r) => r.id).toSet(),
        LiveRuleId.values.toSet(),
      );
      expect(LiveRules.all.first.id, LiveRuleId.nudity);
      for (final LiveRule rule in LiveRules.all) {
        expect(rule.title, isNotEmpty);
        expect(rule.body, isNotEmpty);
      }
    });

    test('la sancion se cuenta con las constantes del contrato', () {
      // Escrita a mano, el dia que cambie el bloqueo el aviso mentiria.
      final LiveRule rule = LiveRules.all
          .firstWhere((LiveRule r) => r.id == LiveRuleId.sanctions);
      expect(rule.body, contains('${LiveConstants.strikeBlock.inHours} horas'));
      expect(rule.body, contains('${LiveConstants.maxStrikes}.ª'));
    });

    test('el consentimiento arranca sin aceptar y vive solo en memoria', () {
      LiveRulesConsent.reset();
      expect(LiveRulesConsent.accepted, isFalse);
      LiveRulesConsent.accept();
      expect(LiveRulesConsent.accepted, isTrue);
      LiveRulesConsent.reset();
      expect(LiveRulesConsent.accepted, isFalse);
    });
  });

  group('LiveRulesView', () {
    testWidgets('muestra todas las normas y avisa de los permisos', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: LiveRulesView(onAccept: () {}, onCancel: () {}),
        ),
      ));

      for (final LiveRule rule in LiveRules.all) {
        await tester.scrollUntilVisible(find.text(rule.title), 120);
        expect(find.text(rule.title), findsOneWidget);
      }
      expect(
        find.text('Al continuar te pediremos permiso de cámara y micrófono.'),
        findsOneWidget,
      );
    });

    testWidgets('no hay camino a la camara sin aceptar', (
      WidgetTester tester,
    ) async {
      bool accepted = false;
      bool cancelled = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: LiveRulesView(
            onAccept: () => accepted = true,
            onCancel: () => cancelled = true,
          ),
        ),
      ));

      await tester.tap(find.byKey(const ValueKey<String>('live-rules-cancel')));
      expect(cancelled, isTrue);
      expect(accepted, isFalse);

      await tester.tap(find.byKey(const ValueKey<String>('live-rules-accept')));
      expect(accepted, isTrue);
    });
  });
}
