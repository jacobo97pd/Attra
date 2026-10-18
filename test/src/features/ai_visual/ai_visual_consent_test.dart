import 'dart:async';

import 'package:attra/src/features/ai_visual/data/ai_visual_service.dart';
import 'package:attra/src/features/ai_visual/domain/ai_reference_state.dart';
import 'package:attra/src/features/ai_visual/domain/profile_insight.dart';
import 'package:attra/src/features/ai_visual/presentation/ai_visual_screen.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:attra/src/widgets/attra_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _AiVisual implements AiVisualService {
  int referenceLoads = 0;
  int insightLoads = 0;

  @override
  ReferenceTraits? get lastReferenceTraits => null;

  @override
  Future<AiReferenceState> loadReferenceState(String uid) async {
    referenceLoads++;
    return AiReferenceState.empty;
  }

  @override
  Future<List<ProfileInsight>> getInsights() async {
    insightLoads++;
    return const <ProfileInsight>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('No se esperaba ${invocation.memberName}');
}

void main() {
  testWidgets(
      'un fallo de consentimiento permite reintentar sin activar la IA antes de confirmarlo',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      final _AiVisual service = _AiVisual();
      final Completer<void> firstAttempt = Completer<void>();
      final Completer<void> secondAttempt = Completer<void>();
      int attempts = 0;
      final ThemeData theme = AppTheme.dark;
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: AiVisualScreen(
          uid: 'u',
          isPro: true,
          hasConsent: false,
          service: service,
          onUpgrade: () => fail('No se debe abrir el paywall'),
          onGiveConsent: () {
            attempts++;
            return attempts == 1 ? firstAttempt.future : secondAttempt.future;
          },
          onRevokeConsent: () async => fail('No se debe retirar el permiso'),
        ),
      ));

      await tester
          .tap(find.widgetWithText(FilledButton, 'Doy mi consentimiento'));
      await tester.pump();
      expect(attempts, 1);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      expect(find.byType(AttraInlineLoader), findsOneWidget);
      expect(service.referenceLoads, 0);
      expect(service.insightLoads, 0);

      firstAttempt.completeError(StateError('Sin conexión'));
      await tester.pumpAndSettle();

      const String error = 'No hemos podido guardar tu consentimiento. '
          'Comprueba tu conexión y vuelve a intentarlo.';
      expect(find.text('Consentimiento para la IA visual'), findsOneWidget);
      expect(find.text(error), findsOneWidget);
      expect(tester.getSemantics(find.text(error)),
          matchesSemantics(label: error, isLiveRegion: true));
      expect(tester.widget<Text>(find.text(error)).style?.color,
          theme.colorScheme.error);
      expect(find.byType(AttraInlineLoader), findsNothing);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNotNull);
      expect(service.referenceLoads, 0);
      expect(service.insightLoads, 0);
      expect(tester.takeException(), isNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
      await tester.pump();
      expect(attempts, 2);
      expect(find.text(error), findsNothing);
      expect(find.text('Consentimiento para la IA visual'), findsOneWidget);
      expect(service.referenceLoads, 0);

      secondAttempt.complete();
      await tester.pumpAndSettle();

      expect(find.text('Consentimiento para la IA visual'), findsNothing);
      expect(service.referenceLoads, 1);
      expect(service.insightLoads, 1);
      expect(find.text('Tu foto de referencia'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Repaso de tu perfil'),
        250,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('Repaso de tu perfil'), findsOneWidget);
      expect(find.text('Mejor foto principal'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
