import 'dart:typed_data';

import 'package:attra/src/features/onboarding/domain/onboarding_draft.dart';
import 'package:attra/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'el perfil por voz muestra solo los cuatro pasos que quedan',
    (WidgetTester tester) async {
      final _QuickOnboardingHarness harness = _QuickOnboardingHarness();

      await tester.pumpWidget(
        harness.host(
          draft: _quickDraft(
            currentStep: 0,
            remainingSteps: const <int>[0, 1, 2, 6],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Paso 1 de 4'), findsOneWidget);
      expect(find.text('Selfie'), findsOneWidget);
      expect(find.text('Perfil'), findsNothing);
      expect(find.text('Perfil personal'), findsNothing);
      expect(find.text('Estilo de vida'), findsNothing);
      expect(find.text('Vibe'), findsNothing);
      expect(find.text('Preguntas'), findsNothing);
      expect(harness.voiceRequests, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'una lista corta salta de Apariencia a Preferencias sin repetir bloques',
    (WidgetTester tester) async {
      final _QuickOnboardingHarness harness = _QuickOnboardingHarness();

      await tester.pumpWidget(
        harness.host(
          draft: _quickDraft(
            currentStep: 2,
            remainingSteps: const <int>[2, 6],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Paso 1 de 2'), findsOneWidget);
      expect(find.text('Apariencia'), findsWidgets);

      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      expect(find.text('Paso 2 de 2'), findsOneWidget);
      expect(find.text('Preferencias'), findsWidgets);
      expect(find.text('Perfil personal'), findsNothing);
      expect(find.text('Estilo de vida'), findsNothing);
      expect(find.text('Vibe'), findsNothing);
      expect(find.text('Preguntas'), findsNothing);
      expect(harness.savedDrafts, isNotEmpty);
      expect(harness.savedDrafts.last.currentStep, 6);
      expect(harness.voiceRequests, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

OnboardingDraft _quickDraft({
  required int currentStep,
  required List<int> remainingSteps,
}) {
  final DateTime now = DateTime.now();
  return OnboardingDraft(
    currentStep: currentStep,
    setupMode: 'quick',
    voiceProfileGenerated: true,
    quickRemainingSteps: remainingSteps,
    intentMode: 'dating',
    visibleName: 'Alex',
    birthDate: DateTime(now.year - 28, 1, 1),
    gender: 'non_binary',
    birthCountryCode: 'ES',
    birthCountryName: 'España',
    birthCity: 'Madrid',
    birthCityNormalized: 'madrid',
    currentCountryCode: 'ES',
    currentCountryName: 'España',
    currentCity: 'Madrid',
    currentCityNormalized: 'madrid',
    languages: const <String>['es'],
    heightCm: 172,
    eyeColor: 'brown',
    hairColor: 'brown',
    hairType: 'wavy',
    bodyType: 'average',
    bio: 'Me entusiasman las conversaciones largas y descubrir sitios nuevos.',
    relationshipIntent: 'serious_relationship',
    smoking: 'never',
    drinking: 'socially',
    fitnessLevel: 'medium',
    wantsChildren: 'maybe',
    travelStyle: 'weekend_getaways',
    fashionStyle: const <String>['casual'],
    personalityTags: const <String>['creative'],
    interestedIn: const <String>['female'],
    liveSelfieCaptured: true,
    liveSelfieCapturedAt: now,
    liveSelfiePrivatePhotoUrl: 'gs://private/selfie.jpg',
    liveSelfieCaptureMethod: 'camera_front',
    liveSelfieStatus: 'pending',
  );
}

class _QuickOnboardingHarness {
  final List<OnboardingDraft> savedDrafts = <OnboardingDraft>[];
  int voiceRequests = 0;

  Widget host({required OnboardingDraft draft}) {
    return MaterialApp(
      theme: AppTheme.light,
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        );
      },
      home: OnboardingScreen(
        onLoadDraft: () async => draft,
        onSaveDraft: (OnboardingDraft value) async {
          savedDrafts.add(value);
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
