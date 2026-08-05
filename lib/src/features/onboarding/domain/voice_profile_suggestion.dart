import '../../profile/domain/profile_prompt.dart';
import 'onboarding_draft.dart';

/// Resultado editable de la configuración rápida por voz.
///
/// Solo contiene datos no sensibles que la persona ha contado de forma
/// explícita. La identidad, edad, ubicación, apariencia, orientación y
/// preferencias íntimas nunca se completan desde la IA.
class VoiceProfileSuggestion {
  const VoiceProfileSuggestion({
    required this.transcript,
    required this.bio,
    this.jobTitle = '',
    this.company = '',
    this.relationshipIntent = '',
    this.smoking = '',
    this.drinking = '',
    this.fitnessLevel = '',
    this.wantsChildren = '',
    this.socialStyle = '',
    this.travelStyle = '',
    this.fashionStyle = const <String>[],
    this.personalityTags = const <String>[],
    this.prompts = const <VoicePromptSuggestion>[],
  });

  final String transcript;
  final String bio;
  final String jobTitle;
  final String company;
  final String relationshipIntent;
  final String smoking;
  final String drinking;
  final String fitnessLevel;
  final String wantsChildren;
  final String socialStyle;
  final String travelStyle;
  final List<String> fashionStyle;
  final List<String> personalityTags;
  final List<VoicePromptSuggestion> prompts;

  static const Set<String> relationshipIntentValues = <String>{
    'serious_relationship',
    'meet_people',
    'casual',
    'open_to_see',
  };
  static const Set<String> frequencyValues = <String>{
    'never',
    'occasionally',
    'frequently',
  };
  static const Set<String> drinkingValues = <String>{
    'never',
    'socially',
    'frequently',
  };
  static const Set<String> fitnessValues = <String>{
    'low',
    'medium',
    'high',
  };
  static const Set<String> wantsChildrenValues = <String>{
    'yes',
    'no',
    'maybe',
  };
  static const Set<String> socialStyleValues = <String>{
    'calm',
    'balanced',
    'very_social',
  };
  static const Set<String> travelStyleValues = <String>{
    'homebody',
    'weekend_getaways',
    'adventurous',
  };
  static const Set<String> fashionStyleValues = <String>{
    'casual',
    'elegant',
    'urban',
    'sporty',
    'minimalist',
  };
  static const Set<String> personalityTagValues = <String>{
    'ambitious',
    'empathetic',
    'fun',
    'creative',
    'calm',
    'intense',
  };

  factory VoiceProfileSuggestion.fromMap(Map<String, dynamic> map) {
    return VoiceProfileSuggestion(
      transcript: _clean(map['transcript'], 4000),
      bio: _clean(map['bio'], 240),
      jobTitle: _clean(map['jobTitle'], 90),
      company: _clean(map['company'], 90),
      relationshipIntent:
          _enumValue(map['relationshipIntent'], relationshipIntentValues),
      smoking: _enumValue(map['smoking'], frequencyValues),
      drinking: _enumValue(map['drinking'], drinkingValues),
      fitnessLevel: _enumValue(map['fitnessLevel'], fitnessValues),
      wantsChildren: _enumValue(map['wantsChildren'], wantsChildrenValues),
      socialStyle: _enumValue(map['socialStyle'], socialStyleValues),
      travelStyle: _enumValue(map['travelStyle'], travelStyleValues),
      fashionStyle: _enumList(map['fashionStyle'], fashionStyleValues),
      personalityTags: _enumList(map['personalityTags'], personalityTagValues),
      prompts: _promptList(map['prompts']),
    );
  }

  VoiceProfileSuggestion copyWith({
    String? transcript,
    String? bio,
    String? jobTitle,
    String? company,
    String? relationshipIntent,
    String? smoking,
    String? drinking,
    String? fitnessLevel,
    String? wantsChildren,
    String? socialStyle,
    String? travelStyle,
    List<String>? fashionStyle,
    List<String>? personalityTags,
    List<VoicePromptSuggestion>? prompts,
  }) {
    return VoiceProfileSuggestion(
      transcript: transcript ?? this.transcript,
      bio: bio ?? this.bio,
      jobTitle: jobTitle ?? this.jobTitle,
      company: company ?? this.company,
      relationshipIntent: relationshipIntent ?? this.relationshipIntent,
      smoking: smoking ?? this.smoking,
      drinking: drinking ?? this.drinking,
      fitnessLevel: fitnessLevel ?? this.fitnessLevel,
      wantsChildren: wantsChildren ?? this.wantsChildren,
      socialStyle: socialStyle ?? this.socialStyle,
      travelStyle: travelStyle ?? this.travelStyle,
      fashionStyle: fashionStyle ?? this.fashionStyle,
      personalityTags: personalityTags ?? this.personalityTags,
      prompts: prompts ?? this.prompts,
    );
  }

  /// Completa los huecos de una nueva generación con lo que ya había escrito
  /// la persona, para que la pantalla de revisión muestre el resultado final
  /// exacto. Después de esa revisión, [applyTo] reemplaza estos campos tal cual.
  VoiceProfileSuggestion withDraftFallback(OnboardingDraft base) {
    String valueOrCurrent(String value, String current) =>
        value.isEmpty ? current : value;
    final List<VoicePromptSuggestion> currentPrompts = base.prompts
        .where((ProfilePrompt prompt) => prompt.isActive)
        .take(kMaxActivePrompts)
        .map(
          (ProfilePrompt prompt) => VoicePromptSuggestion(
            question: prompt.question,
            answer: prompt.answer,
          ),
        )
        .where((VoicePromptSuggestion prompt) => prompt.isValid)
        .toList(growable: false);

    return copyWith(
      bio: valueOrCurrent(bio, base.bio),
      jobTitle: valueOrCurrent(jobTitle, base.jobTitle),
      company: valueOrCurrent(company, base.company),
      relationshipIntent:
          valueOrCurrent(relationshipIntent, base.relationshipIntent),
      smoking: valueOrCurrent(smoking, base.smoking),
      drinking: valueOrCurrent(drinking, base.drinking),
      fitnessLevel: valueOrCurrent(fitnessLevel, base.fitnessLevel),
      wantsChildren: valueOrCurrent(wantsChildren, base.wantsChildren),
      socialStyle: valueOrCurrent(socialStyle, base.socialStyle),
      travelStyle: valueOrCurrent(travelStyle, base.travelStyle),
      fashionStyle: fashionStyle.isEmpty ? base.fashionStyle : fashionStyle,
      personalityTags:
          personalityTags.isEmpty ? base.personalityTags : personalityTags,
      prompts: prompts.isEmpty ? currentPrompts : prompts,
    );
  }

  /// Aplica únicamente campos seguros al borrador actual.
  ///
  /// Esta instancia ya representa la revisión final y editable, por lo que los
  /// campos gestionados aquí se reemplazan exactamente (también si la persona
  /// los ha borrado). Los sensibles ni siquiera forman parte del contrato.
  OnboardingDraft applyTo(OnboardingDraft base) {
    final List<ProfilePrompt> generatedPrompts = prompts
        .take(kMaxActivePrompts)
        .toList(growable: false)
        .asMap()
        .entries
        .map((MapEntry<int, VoicePromptSuggestion> entry) {
      final VoicePromptSuggestion prompt = entry.value;
      return ProfilePrompt(
        id: 'voice_${DateTime.now().millisecondsSinceEpoch}_${entry.key}',
        question: prompt.question,
        answer: prompt.answer,
        category: 'custom',
        isCustom: true,
        order: entry.key,
      );
    }).toList(growable: false);

    return base.copyWith(
      setupMode: 'quick',
      voiceProfileGenerated: true,
      bio: bio,
      jobTitle: jobTitle,
      company: company,
      relationshipIntent: relationshipIntent,
      smoking: smoking,
      drinking: drinking,
      fitnessLevel: fitnessLevel,
      wantsChildren: wantsChildren,
      socialStyle: socialStyle,
      travelStyle: travelStyle,
      fashionStyle: fashionStyle,
      personalityTags: personalityTags,
      prompts: generatedPrompts,
    );
  }

  static String _clean(Object? raw, int maxLength) {
    final String value =
        (raw ?? '').toString().trim().replaceAll(RegExp(r'\s+'), ' ');
    if (value.length <= maxLength) return value;
    return value.substring(0, maxLength).trim();
  }

  static String _enumValue(Object? raw, Set<String> allowed) {
    final String value = (raw ?? '').toString().trim().toLowerCase();
    return allowed.contains(value) ? value : '';
  }

  static List<String> _enumList(Object? raw, Set<String> allowed) {
    if (raw is! List) return const <String>[];
    final List<String> output = <String>[];
    for (final Object? item in raw) {
      final String value = (item ?? '').toString().trim().toLowerCase();
      if (allowed.contains(value) && !output.contains(value)) {
        output.add(value);
      }
    }
    return output;
  }

  static List<VoicePromptSuggestion> _promptList(Object? raw) {
    if (raw is! List) return const <VoicePromptSuggestion>[];
    final List<VoicePromptSuggestion> output = <VoicePromptSuggestion>[];
    for (final Object? item in raw) {
      if (item is! Map) continue;
      final Map<String, dynamic> map = item.map(
        (dynamic key, dynamic value) => MapEntry(key.toString(), value),
      );
      final VoicePromptSuggestion prompt = VoicePromptSuggestion.fromMap(map);
      if (prompt.isValid &&
          !output.any((VoicePromptSuggestion p) =>
              p.question.toLowerCase() == prompt.question.toLowerCase())) {
        output.add(prompt);
      }
      if (output.length == kMaxActivePrompts) break;
    }
    return output;
  }
}

class VoicePromptSuggestion {
  const VoicePromptSuggestion({
    required this.question,
    required this.answer,
  });

  final String question;
  final String answer;

  bool get isValid =>
      question.isNotEmpty &&
      answer.isNotEmpty &&
      ProfilePromptValidator.validateCustomQuestion(question) == null &&
      ProfilePromptValidator.validateAnswer(answer) == null;

  factory VoicePromptSuggestion.fromMap(Map<String, dynamic> map) {
    return VoicePromptSuggestion(
      question: VoiceProfileSuggestion._clean(
          map['question'], kMaxPromptQuestionChars),
      answer:
          VoiceProfileSuggestion._clean(map['answer'], kMaxPromptAnswerChars),
    );
  }

  VoicePromptSuggestion copyWith({
    String? question,
    String? answer,
  }) {
    return VoicePromptSuggestion(
      question: question ?? this.question,
      answer: answer ?? this.answer,
    );
  }
}
