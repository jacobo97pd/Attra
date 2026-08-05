import 'package:attra/src/features/onboarding/domain/voice_profile_suggestion.dart';
import 'package:attra/src/features/onboarding/presentation/voice_profile_setup.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'el briefing explica el audio, el borrador editable y la privacidad',
    (WidgetTester tester) async {
      await tester.pumpWidget(_host());

      expect(
        find.text('Cuéntanos quién eres.\nNosotros ordenamos el resto.'),
        findsOneWidget,
      );
      expect(
          find.textContaining('Habla entre 60 y 90 segundos'), findsOneWidget);
      expect(find.textContaining('editar antes de publicar'), findsOneWidget);
      expect(find.text('Puedes contarnos…'), findsOneWidget);
      expect(
        find.text('Qué valoras y qué te gustaría encontrar.'),
        findsOneWidget,
      );
      expect(find.text('Para un audio limpio'), findsOneWidget);
      expect(
          find.textContaining('lugar tranquilo, sin música'), findsOneWidget);
      expect(
        find.textContaining('Evita apellidos, teléfono, dirección exacta'),
        findsOneWidget,
      );
      expect(
          find.textContaining('procesa el audio una sola vez'), findsOneWidget);
      expect(find.textContaining('No clonamos tu voz'), findsOneWidget);
      expect(
          find.textContaining('backend solicita su borrado'), findsOneWidget);
      expect(find.textContaining('siguiente barrido de seguridad'),
          findsOneWidget);
      expect(find.text('Grabar mi historia'), findsOneWidget);
      expect(find.text('Prefiero hacerlo paso a paso'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'el briefing sigue siendo usable en viewport pequeño con texto grande',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_host(textScale: 2));

      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.text('Paso a paso'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        find.text('Prefiero hacerlo paso a paso'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      expect(find.text('Prefiero hacerlo paso a paso'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('la alternativa paso a paso invoca su callback',
      (WidgetTester tester) async {
    int manualRequests = 0;
    await tester.pumpWidget(
      _host(onUseManual: () => manualRequests += 1),
    );

    await tester.tap(find.text('Paso a paso'));
    await tester.pump();

    expect(manualRequests, 1);
  });
}

Widget _host({
  double textScale = 1,
  VoidCallback? onUseManual,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    builder: (BuildContext context, Widget? child) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: child!,
      );
    },
    home: VoiceProfileSetup(
      intentMode: 'dating',
      onGenerate: ({
        required bytes,
        required contentType,
        required extension,
        required durationMs,
        required intentMode,
      }) async {
        throw StateError('La generación no forma parte de este test.');
      },
      onAccepted: (VoiceProfileSuggestion suggestion) async {},
      onUseManual: onUseManual ?? () {},
      onBack: () {},
    ),
  );
}
