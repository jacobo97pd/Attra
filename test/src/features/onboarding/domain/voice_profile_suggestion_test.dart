import 'package:attra/src/features/onboarding/domain/onboarding_draft.dart';
import 'package:attra/src/features/onboarding/domain/voice_profile_suggestion.dart';
import 'package:attra/src/features/profile/domain/profile_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoiceProfileSuggestion.fromMap', () {
    test('acepta solo enums y prompts públicos válidos', () {
      final VoiceProfileSuggestion suggestion =
          VoiceProfileSuggestion.fromMap(<String, dynamic>{
        'transcript': 'Me encanta cocinar y conocer sitios pequeños.',
        'bio':
            'Cocino para desconectar y siempre guardo un sitio por descubrir.',
        'relationshipIntent': 'serious_relationship',
        'smoking': 'invented_value',
        'personalityTags': <String>['creative', 'unknown', 'creative'],
        'fashionStyle': <String>['casual', 'hacker'],
        'prompts': <Map<String, String>>[
          <String, String>{
            'question': 'Un domingo perfecto incluye…',
            'answer': 'Mercado, cocinar sin prisa y una sobremesa larga.',
          },
          <String, String>{
            'question': 'Escríbeme al teléfono',
            'answer': '+34 600 123 123',
          },
        ],
      });

      expect(suggestion.relationshipIntent, 'serious_relationship');
      expect(suggestion.smoking, isEmpty);
      expect(suggestion.personalityTags, <String>['creative']);
      expect(suggestion.fashionStyle, <String>['casual']);
      expect(suggestion.prompts, hasLength(1));
    });

    test('recorta texto y tolera una respuesta parcial', () {
      final VoiceProfileSuggestion suggestion =
          VoiceProfileSuggestion.fromMap(<String, dynamic>{
        'transcript': List<String>.filled(5000, 'a').join(),
        'bio': 'Una bio suficientemente larga para revisar con calma.',
      });

      expect(suggestion.transcript.length, 4000);
      expect(suggestion.bio, contains('suficientemente'));
      expect(suggestion.prompts, isEmpty);
    });
  });

  group('VoiceProfileSuggestion.applyTo', () {
    test('no toca identidad, ubicación, orientación ni apariencia', () {
      final OnboardingDraft base = OnboardingDraft(
        setupMode: 'quick',
        visibleName: 'Alex',
        birthDate: DateTime(1994, 5, 2),
        gender: 'non_binary',
        orientation: const <String>['bisexual'],
        currentCity: 'Madrid',
        currentCountryCode: 'ES',
        heightCm: 172,
        eyeColor: 'brown',
        cannabis: 'prefer_not_to_say',
        bio: '',
      );
      const VoiceProfileSuggestion suggestion = VoiceProfileSuggestion(
        transcript: 'audio',
        bio:
            'Me gusta crear cosas, cocinar para mis amigos y perderme andando.',
        relationshipIntent: 'open_to_see',
        personalityTags: <String>['creative', 'empathetic'],
      );

      final OnboardingDraft applied = suggestion.applyTo(base);

      expect(applied.voiceProfileGenerated, isTrue);
      expect(applied.setupMode, 'quick');
      expect(applied.visibleName, 'Alex');
      expect(applied.birthDate, DateTime(1994, 5, 2));
      expect(applied.gender, 'non_binary');
      expect(applied.orientation, <String>['bisexual']);
      expect(applied.currentCity, 'Madrid');
      expect(applied.currentCountryCode, 'ES');
      expect(applied.heightCm, 172);
      expect(applied.eyeColor, 'brown');
      expect(applied.cannabis, 'prefer_not_to_say');
      expect(applied.bio, suggestion.bio);
      expect(applied.personalityTags, suggestion.personalityTags);
    });

    test('la revisión final puede borrar un valor previo de forma explícita',
        () {
      const OnboardingDraft base = OnboardingDraft(
        bio: 'Esta bio ya la había escrito yo y quiero conservarla.',
        travelStyle: 'adventurous',
      );
      const VoiceProfileSuggestion suggestion = VoiceProfileSuggestion(
        transcript: 'audio',
        bio: '',
        travelStyle: '',
      );

      final OnboardingDraft applied = suggestion.applyTo(base);

      expect(applied.bio, isEmpty);
      expect(applied.travelStyle, isEmpty);
    });

    test('una segunda generación enseña los valores previos antes de aplicar',
        () {
      const OnboardingDraft base = OnboardingDraft(
        bio: 'Esta bio previa debe aparecer en la revisión final.',
        smoking: 'never',
        personalityTags: <String>['creative'],
        prompts: <ProfilePrompt>[
          ProfilePrompt(
            id: 'old',
            question: 'Mi domingo perfecto incluye…',
            answer: 'Cocinar sin prisa.',
          ),
        ],
      );
      const VoiceProfileSuggestion generated = VoiceProfileSuggestion(
        transcript: 'Segundo audio',
        bio: '',
      );

      final VoiceProfileSuggestion review = generated.withDraftFallback(base);

      expect(review.bio, base.bio);
      expect(review.smoking, base.smoking);
      expect(review.personalityTags, base.personalityTags);
      expect(review.prompts.single.answer, 'Cocinar sin prisa.');
    });
  });

  test('OnboardingDraft conserva el modo rápido al serializar', () {
    const OnboardingDraft draft = OnboardingDraft(
      setupMode: 'quick',
      voiceProfileGenerated: true,
      quickRemainingSteps: <int>[0, 1, 2, 6],
    );

    final OnboardingDraft restored = OnboardingDraft.fromMap(draft.toMap());

    expect(restored.setupMode, 'quick');
    expect(restored.voiceProfileGenerated, isTrue);
    expect(restored.quickRemainingSteps, <int>[0, 1, 2, 6]);
  });
}
