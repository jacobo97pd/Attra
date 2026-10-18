import 'dart:typed_data';

import 'package:attra/src/features/onboarding/domain/onboarding_draft.dart';
import 'package:attra/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('el paso queda visible sin entrada al activar Reduce Motion',
      (WidgetTester tester) async {
    final ValueNotifier<bool> reduced = ValueNotifier<bool>(true);
    final SemanticsHandle semantics = tester.ensureSemantics();
    addTearDown(reduced.dispose);
    try {
      await tester.pumpWidget(_host(reduced));
      await tester.pumpAndSettle();

      final Finder entrance =
          find.byKey(const ValueKey<String>('onboarding-step-entrance'));
      expect(entrance, findsNothing);
      expect(find.text('Tu selfie en vivo'), findsOneWidget);
      expect(find.bySemanticsLabel('Atrás'), findsOneWidget);

      reduced.value = false;
      await tester.pump();
      expect(entrance, findsWidgets);
      await tester.pump(const Duration(milliseconds: 50));

      reduced.value = true;
      await tester.pump();
      expect(entrance, findsNothing);
      expect(find.text('Tu selfie en vivo'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      semantics.dispose();
    }
  });
}

Widget _host(ValueNotifier<bool> reduced) => ValueListenableBuilder<bool>(
      valueListenable: reduced,
      builder: (BuildContext context, bool reduceMotion, _) => MaterialApp(
        theme: AppTheme.dark,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: OnboardingScreen(
          onLoadDraft: () async => OnboardingDraft(
            birthDate: DateTime(1995),
            intentMode: 'dating',
            setupMode: 'manual',
          ),
          onSaveDraft: (_) async {},
          onUploadLiveSelfieDraft: ({
            required Uint8List liveSelfieBytes,
            required String liveSelfieFileExtension,
          }) async =>
              throw StateError('No se usa cámara en esta prueba.'),
          onGenerateVoiceProfile: ({
            required Uint8List bytes,
            required String contentType,
            required String extension,
            required int durationMs,
            required String intentMode,
          }) async =>
              throw StateError('No se usa voz en esta prueba.'),
          onSubmitOnboarding: ({
            required OnboardingDraft draft,
            Uint8List? liveSelfieBytes,
            String? liveSelfieFileExtension,
          }) async {},
          onLogout: () {},
        ),
      ),
    );
