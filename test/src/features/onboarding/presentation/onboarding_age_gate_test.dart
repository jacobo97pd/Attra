import 'dart:async';
import 'dart:typed_data';

import 'package:attra/src/features/onboarding/domain/onboarding_draft.dart';
import 'package:attra/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'un borrador sin fecha muestra el gate +18 antes de intención o voz',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final _OnboardingHarness harness = _OnboardingHarness();
      await tester.pumpWidget(
        harness.host(
          draft: const OnboardingDraft(),
          textScale: 1.6,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Primero, confirmemos tu edad'), findsOneWidget);
      expect(find.textContaining('mayores de 18'), findsOneWidget);
      expect(find.text('Seleccionar fecha'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.text('Amistades'), findsNothing);
      expect(find.textContaining('Grabar mi historia'), findsNothing);
      expect(harness.voiceRequests, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'guarda la fecha de nacimiento antes de avanzar a intención',
    (WidgetTester tester) async {
      final Completer<void> saveCompleter = Completer<void>();
      final _OnboardingHarness harness = _OnboardingHarness(
        onSave: (OnboardingDraft draft) {
          return saveCompleter.future;
        },
      );
      await tester.pumpWidget(
        harness.host(draft: const OnboardingDraft()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Seleccionar fecha'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoDatePicker), findsOneWidget);

      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar y continuar'));
      await tester.pump();

      expect(harness.savedDrafts, hasLength(1));
      final DateTime? savedBirthDate = harness.savedDrafts.single.birthDate;
      expect(savedBirthDate, isNotNull);
      expect(_ageOn(savedBirthDate!, DateTime.now()), greaterThanOrEqualTo(18));
      expect(find.text('Primero, confirmemos tu edad'), findsOneWidget);
      expect(find.text('Amistades'), findsNothing);
      expect(harness.voiceRequests, 0);

      saveCompleter.complete();
      await tester.pumpAndSettle();

      expect(find.text('Amistades'), findsOneWidget);
      expect(find.text('Primero, confirmemos tu edad'), findsNothing);
      expect(harness.voiceRequests, 0);
    },
  );

  testWidgets(
    'si falla el guardado mantiene el gate y permite reintentar',
    (WidgetTester tester) async {
      final _OnboardingHarness harness = _OnboardingHarness(
        onSave: (_) async => throw StateError('sin conexión'),
      );
      await tester.pumpWidget(
        harness.host(draft: const OnboardingDraft()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Seleccionar fecha'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar y continuar'));
      await tester.pumpAndSettle();

      expect(harness.savedDrafts, hasLength(1));
      expect(find.text('Primero, confirmemos tu edad'), findsOneWidget);
      expect(
        find.textContaining('No hemos podido verificar la edad'),
        findsOneWidget,
      );
      expect(find.text('Amistades'), findsNothing);
      expect(find.text('Confirmar y continuar'), findsOneWidget);
      expect(harness.voiceRequests, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

int _ageOn(DateTime birthDate, DateTime now) {
  int age = now.year - birthDate.year;
  final bool birthdayPassed = now.month > birthDate.month ||
      (now.month == birthDate.month && now.day >= birthDate.day);
  if (!birthdayPassed) age -= 1;
  return age;
}

class _OnboardingHarness {
  _OnboardingHarness({
    Future<void> Function(OnboardingDraft draft)? onSave,
  }) : _onSave = onSave;

  final Future<void> Function(OnboardingDraft draft)? _onSave;
  final List<OnboardingDraft> savedDrafts = <OnboardingDraft>[];
  int voiceRequests = 0;

  Widget host({
    required OnboardingDraft draft,
    double textScale = 1,
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
      home: OnboardingScreen(
        onLoadDraft: () async => draft,
        onSaveDraft: (OnboardingDraft value) async {
          savedDrafts.add(value);
          await _onSave?.call(value);
        },
        onUploadLiveSelfieDraft: ({
          required Uint8List liveSelfieBytes,
          required String liveSelfieFileExtension,
        }) async {
          throw StateError('La selfie no forma parte de este test.');
        },
        onGenerateVoiceProfile: ({
          required Uint8List bytes,
          required String contentType,
          required String extension,
          required int durationMs,
          required String intentMode,
        }) async {
          voiceRequests += 1;
          throw StateError('La voz no forma parte de este test.');
        },
        onSubmitOnboarding: ({
          required OnboardingDraft draft,
          Uint8List? liveSelfieBytes,
          String? liveSelfieFileExtension,
        }) async {},
        onLogout: () {},
      ),
    );
  }
}
