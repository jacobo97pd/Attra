import '../../auth/domain/app_user.dart';
import '../../profile/domain/profile_prompt.dart';

class OnboardingDraft {
  const OnboardingDraft({
    this.currentStep = 0,
    this.prompts = const <ProfilePrompt>[],
    this.visibleName = '',
    this.birthDate,
    this.gender = '',
    this.birthCity = '',
    this.birthCityNormalized = '',
    this.currentCity = '',
    this.currentCityNormalized = '',
    this.birthCountryCode = '',
    this.birthCountryName = '',
    this.currentCountryCode = '',
    this.currentCountryName = '',
    this.locationPermissionGranted = false,
    this.locationPermissionStatus = 'unknown',
    this.locationLatitude,
    this.locationLongitude,
    this.locationUpdatedAt,
    this.languages = const <String>[],
    this.heightCm,
    this.eyeColor = '',
    this.hairColor = '',
    this.hairType = '',
    this.bodyType = '',
    this.bio = '',
    this.relationshipIntent = '',
    this.pronouns = '',
    this.orientation = const <String>[],
    this.jobTitle = '',
    this.company = '',
    this.educationLevel = '',
    this.hasChildren = '',
    this.relationshipType = '',
    this.cannabis = '',
    this.drugs = '',
    this.pets = const <String>[],
    this.zodiac = '',
    this.smoking = '',
    this.drinking = '',
    this.fitnessLevel = '',
    this.wantsChildren = '',
    this.socialStyle = '',
    this.travelStyle = '',
    this.fashionStyle = const <String>[],
    this.personalityTags = const <String>[],
    this.interestedIn = const <String>[],
    this.preferredAgeMin = 24,
    this.preferredAgeMax = 35,
    this.maxDistanceKm = 50,
    this.preferredLanguages = const <String>[],
    this.lifestylePreferences = const <String>[],
    this.appearancePreferences = const <String>[],
    this.liveSelfieCaptured = false,
    this.liveSelfieCapturedAt,
    this.liveSelfieVerified = false,
    this.liveSelfieVersion = 1,
    this.lastLiveSelfieAt,
    this.liveSelfiePublicPhotoUrl = '',
    this.liveSelfiePublicStoragePath = '',
    this.liveSelfiePrivatePhotoUrl = '',
    this.liveSelfiePrivateStoragePath = '',
    this.liveSelfieCaptureMethod = '',
    this.liveSelfieStatus = '',
  });

  final int currentStep;

  /// Prompts de perfil elegidos en el onboarding (paso opcional). Se guardan en
  /// `users/{uid}.profilePrompts` al finalizar. Vacío = no se rellenó (saltado).
  final List<ProfilePrompt> prompts;

  final String visibleName;
  final DateTime? birthDate;
  final String gender;
  final String birthCity;
  final String birthCityNormalized;
  final String currentCity;
  final String currentCityNormalized;
  final String birthCountryCode;
  final String birthCountryName;
  final String currentCountryCode;
  final String currentCountryName;
  final bool locationPermissionGranted;
  final String locationPermissionStatus;
  final double? locationLatitude;
  final double? locationLongitude;
  final DateTime? locationUpdatedAt;
  final List<String> languages;

  final int? heightCm;
  final String eyeColor;
  final String hairColor;
  final String hairType;
  final String bodyType;

  final String bio;
  final String relationshipIntent;
  final String pronouns;
  final List<String> orientation;
  final String jobTitle;
  final String company;
  final String educationLevel;
  final String hasChildren;
  final String relationshipType;
  final String cannabis;
  final String drugs;
  final List<String> pets;
  final String zodiac;

  final String smoking;
  final String drinking;
  final String fitnessLevel;
  final String wantsChildren;
  final String socialStyle;
  final String travelStyle;

  final List<String> fashionStyle;
  final List<String> personalityTags;

  final List<String> interestedIn;
  final int preferredAgeMin;
  final int preferredAgeMax;
  final int maxDistanceKm;
  final List<String> preferredLanguages;
  final List<String> lifestylePreferences;
  final List<String> appearancePreferences;

  final bool liveSelfieCaptured;
  final DateTime? liveSelfieCapturedAt;
  final bool liveSelfieVerified;
  final int liveSelfieVersion;
  final DateTime? lastLiveSelfieAt;
  final String liveSelfiePublicPhotoUrl;
  final String liveSelfiePublicStoragePath;
  final String liveSelfiePrivatePhotoUrl;
  final String liveSelfiePrivateStoragePath;
  final String liveSelfieCaptureMethod;
  final String liveSelfieStatus;

  factory OnboardingDraft.fromUser(AppUser? user) {
    return OnboardingDraft(
      visibleName: user?.displayName?.trim() ?? '',
      preferredLanguages: const <String>['es'],
    );
  }

  factory OnboardingDraft.fromMap(Map<String, dynamic> map) {
    final String legacyCity = (map['city'] as String?) ?? '';
    final String legacyCityNormalized =
        (map['cityNormalized'] as String?) ?? '';
    final String mappedBirthCity = (map['birthCity'] as String?) ?? '';
    final String mappedCurrentCity = (map['currentCity'] as String?) ?? '';
    final String mappedBirthCityNormalized =
        (map['birthCityNormalized'] as String?) ?? '';
    final String mappedCurrentCityNormalized =
        (map['currentCityNormalized'] as String?) ?? '';

    return OnboardingDraft(
      currentStep: _asInt(map['currentStep']) ?? 0,
      prompts: _asPromptList(map['prompts']),
      visibleName: (map['visibleName'] as String?) ?? '',
      birthDate: _asDate(map['birthDate']),
      gender: (map['gender'] as String?) ?? '',
      birthCity: mappedBirthCity.isNotEmpty ? mappedBirthCity : legacyCity,
      birthCityNormalized: mappedBirthCityNormalized.isNotEmpty
          ? mappedBirthCityNormalized
          : legacyCityNormalized,
      currentCity:
          mappedCurrentCity.isNotEmpty ? mappedCurrentCity : legacyCity,
      currentCityNormalized: mappedCurrentCityNormalized.isNotEmpty
          ? mappedCurrentCityNormalized
          : legacyCityNormalized,
      birthCountryCode: (map['birthCountryCode'] as String?) ?? '',
      birthCountryName: (map['birthCountryName'] as String?) ?? '',
      currentCountryCode: (map['currentCountryCode'] as String?) ?? '',
      currentCountryName: (map['currentCountryName'] as String?) ?? '',
      locationPermissionGranted:
          (map['locationPermissionGranted'] as bool?) ?? false,
      locationPermissionStatus:
          (map['locationPermissionStatus'] as String?) ?? 'unknown',
      locationLatitude: _asDouble(map['locationLatitude']),
      locationLongitude: _asDouble(map['locationLongitude']),
      locationUpdatedAt: _asDate(map['locationUpdatedAt']),
      languages: _asStringList(map['languages']),
      heightCm: _asInt(map['heightCm']),
      eyeColor: (map['eyeColor'] as String?) ?? '',
      hairColor: (map['hairColor'] as String?) ?? '',
      hairType: (map['hairType'] as String?) ?? '',
      bodyType: (map['bodyType'] as String?) ?? '',
      bio: (map['bio'] as String?) ?? '',
      relationshipIntent: (map['relationshipIntent'] as String?) ?? '',
      pronouns: (map['pronouns'] as String?) ?? '',
      orientation: _asStringList(map['orientation']),
      jobTitle: (map['jobTitle'] as String?) ?? '',
      company: (map['company'] as String?) ?? '',
      educationLevel: (map['educationLevel'] as String?) ?? '',
      hasChildren: (map['hasChildren'] as String?) ?? '',
      relationshipType: (map['relationshipType'] as String?) ?? '',
      cannabis: (map['cannabis'] as String?) ?? '',
      drugs: (map['drugs'] as String?) ?? '',
      pets: _asStringList(map['pets']),
      zodiac: (map['zodiac'] as String?) ?? '',
      smoking: (map['smoking'] as String?) ?? '',
      drinking: (map['drinking'] as String?) ?? '',
      fitnessLevel: (map['fitnessLevel'] as String?) ?? '',
      wantsChildren: (map['wantsChildren'] as String?) ?? '',
      socialStyle: (map['socialStyle'] as String?) ?? '',
      travelStyle: (map['travelStyle'] as String?) ?? '',
      fashionStyle: _asStringList(map['fashionStyle']),
      personalityTags: _asStringList(map['personalityTags']),
      interestedIn: _asStringList(map['interestedIn']),
      preferredAgeMin: _asInt(map['preferredAgeMin']) ?? 24,
      preferredAgeMax: _asInt(map['preferredAgeMax']) ?? 35,
      maxDistanceKm: _asInt(map['maxDistanceKm']) ?? 50,
      preferredLanguages: _asStringList(map['preferredLanguages']),
      lifestylePreferences: _asStringList(map['lifestylePreferences']),
      appearancePreferences: _asStringList(map['appearancePreferences']),
      liveSelfieCaptured: (map['liveSelfieCaptured'] as bool?) ??
          (((map['liveSelfiePublicPhotoUrl'] as String?)?.isNotEmpty ??
                  false) ||
              ((map['liveSelfiePrivatePhotoUrl'] as String?)?.isNotEmpty ??
                  false)),
      liveSelfieCapturedAt: _asDate(map['liveSelfieCapturedAt']),
      liveSelfieVerified: (map['liveSelfieVerified'] as bool?) ?? false,
      liveSelfieVersion: _asInt(map['liveSelfieVersion']) ?? 1,
      lastLiveSelfieAt: _asDate(map['lastLiveSelfieAt']),
      liveSelfiePublicPhotoUrl:
          (map['liveSelfiePublicPhotoUrl'] as String?) ?? '',
      liveSelfiePublicStoragePath:
          (map['liveSelfiePublicStoragePath'] as String?) ?? '',
      liveSelfiePrivatePhotoUrl:
          (map['liveSelfiePrivatePhotoUrl'] as String?) ?? '',
      liveSelfiePrivateStoragePath:
          (map['liveSelfiePrivateStoragePath'] as String?) ?? '',
      liveSelfieCaptureMethod:
          (map['liveSelfieCaptureMethod'] as String?) ?? '',
      liveSelfieStatus: (map['liveSelfieStatus'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'currentStep': currentStep,
      'prompts': prompts.map((ProfilePrompt p) => p.toMap()).toList(),
      'visibleName': visibleName,
      'birthDate': birthDate?.toIso8601String(),
      'gender': gender,
      'birthCity': birthCity,
      'birthCityNormalized': birthCityNormalized,
      'currentCity': currentCity,
      'currentCityNormalized': currentCityNormalized,
      'birthCountryCode': birthCountryCode,
      'birthCountryName': birthCountryName,
      'currentCountryCode': currentCountryCode,
      'currentCountryName': currentCountryName,
      'locationPermissionGranted': locationPermissionGranted,
      'locationPermissionStatus': locationPermissionStatus,
      'locationLatitude': locationLatitude,
      'locationLongitude': locationLongitude,
      'locationUpdatedAt': locationUpdatedAt?.toIso8601String(),
      'languages': languages,
      'heightCm': heightCm,
      'eyeColor': eyeColor,
      'hairColor': hairColor,
      'hairType': hairType,
      'bodyType': bodyType,
      'bio': bio,
      'relationshipIntent': relationshipIntent,
      'pronouns': pronouns,
      'orientation': orientation,
      'jobTitle': jobTitle,
      'company': company,
      'educationLevel': educationLevel,
      'hasChildren': hasChildren,
      'relationshipType': relationshipType,
      'cannabis': cannabis,
      'drugs': drugs,
      'pets': pets,
      'zodiac': zodiac,
      'smoking': smoking,
      'drinking': drinking,
      'fitnessLevel': fitnessLevel,
      'wantsChildren': wantsChildren,
      'socialStyle': socialStyle,
      'travelStyle': travelStyle,
      'fashionStyle': fashionStyle,
      'personalityTags': personalityTags,
      'interestedIn': interestedIn,
      'preferredAgeMin': preferredAgeMin,
      'preferredAgeMax': preferredAgeMax,
      'maxDistanceKm': maxDistanceKm,
      'preferredLanguages': preferredLanguages,
      'lifestylePreferences': lifestylePreferences,
      'appearancePreferences': appearancePreferences,
      'liveSelfieCaptured': liveSelfieCaptured,
      'liveSelfieCapturedAt': liveSelfieCapturedAt?.toIso8601String(),
      'liveSelfieVerified': liveSelfieVerified,
      'liveSelfieVersion': liveSelfieVersion,
      'lastLiveSelfieAt': lastLiveSelfieAt?.toIso8601String(),
      'liveSelfiePublicPhotoUrl': liveSelfiePublicPhotoUrl,
      'liveSelfiePublicStoragePath': liveSelfiePublicStoragePath,
      'liveSelfiePrivatePhotoUrl': liveSelfiePrivatePhotoUrl,
      'liveSelfiePrivateStoragePath': liveSelfiePrivateStoragePath,
      'liveSelfieCaptureMethod': liveSelfieCaptureMethod,
      'liveSelfieStatus': liveSelfieStatus,
    };
  }

  OnboardingDraft copyWith({
    int? currentStep,
    List<ProfilePrompt>? prompts,
    String? visibleName,
    DateTime? birthDate,
    bool clearBirthDate = false,
    String? gender,
    String? birthCity,
    String? birthCityNormalized,
    String? currentCity,
    String? currentCityNormalized,
    String? birthCountryCode,
    String? birthCountryName,
    String? currentCountryCode,
    String? currentCountryName,
    bool? locationPermissionGranted,
    String? locationPermissionStatus,
    double? locationLatitude,
    bool clearLocationLatitude = false,
    double? locationLongitude,
    bool clearLocationLongitude = false,
    DateTime? locationUpdatedAt,
    bool clearLocationUpdatedAt = false,
    List<String>? languages,
    int? heightCm,
    bool clearHeight = false,
    String? eyeColor,
    String? hairColor,
    String? hairType,
    String? bodyType,
    String? bio,
    String? relationshipIntent,
    String? pronouns,
    List<String>? orientation,
    String? jobTitle,
    String? company,
    String? educationLevel,
    String? hasChildren,
    String? relationshipType,
    String? cannabis,
    String? drugs,
    List<String>? pets,
    String? zodiac,
    String? smoking,
    String? drinking,
    String? fitnessLevel,
    String? wantsChildren,
    String? socialStyle,
    String? travelStyle,
    List<String>? fashionStyle,
    List<String>? personalityTags,
    List<String>? interestedIn,
    int? preferredAgeMin,
    int? preferredAgeMax,
    int? maxDistanceKm,
    List<String>? preferredLanguages,
    List<String>? lifestylePreferences,
    List<String>? appearancePreferences,
    bool? liveSelfieCaptured,
    DateTime? liveSelfieCapturedAt,
    bool clearLiveSelfieCapturedAt = false,
    bool? liveSelfieVerified,
    int? liveSelfieVersion,
    DateTime? lastLiveSelfieAt,
    bool clearLastLiveSelfieAt = false,
    String? liveSelfiePublicPhotoUrl,
    String? liveSelfiePublicStoragePath,
    String? liveSelfiePrivatePhotoUrl,
    String? liveSelfiePrivateStoragePath,
    String? liveSelfieCaptureMethod,
    String? liveSelfieStatus,
  }) {
    return OnboardingDraft(
      currentStep: currentStep ?? this.currentStep,
      prompts: prompts ?? this.prompts,
      visibleName: visibleName ?? this.visibleName,
      birthDate: clearBirthDate ? null : (birthDate ?? this.birthDate),
      gender: gender ?? this.gender,
      birthCity: birthCity ?? this.birthCity,
      birthCityNormalized: birthCityNormalized ?? this.birthCityNormalized,
      currentCity: currentCity ?? this.currentCity,
      currentCityNormalized:
          currentCityNormalized ?? this.currentCityNormalized,
      birthCountryCode: birthCountryCode ?? this.birthCountryCode,
      birthCountryName: birthCountryName ?? this.birthCountryName,
      currentCountryCode: currentCountryCode ?? this.currentCountryCode,
      currentCountryName: currentCountryName ?? this.currentCountryName,
      locationPermissionGranted:
          locationPermissionGranted ?? this.locationPermissionGranted,
      locationPermissionStatus:
          locationPermissionStatus ?? this.locationPermissionStatus,
      locationLatitude: clearLocationLatitude
          ? null
          : (locationLatitude ?? this.locationLatitude),
      locationLongitude: clearLocationLongitude
          ? null
          : (locationLongitude ?? this.locationLongitude),
      locationUpdatedAt: clearLocationUpdatedAt
          ? null
          : (locationUpdatedAt ?? this.locationUpdatedAt),
      languages: languages ?? this.languages,
      heightCm: clearHeight ? null : (heightCm ?? this.heightCm),
      eyeColor: eyeColor ?? this.eyeColor,
      hairColor: hairColor ?? this.hairColor,
      hairType: hairType ?? this.hairType,
      bodyType: bodyType ?? this.bodyType,
      bio: bio ?? this.bio,
      relationshipIntent: relationshipIntent ?? this.relationshipIntent,
      pronouns: pronouns ?? this.pronouns,
      orientation: orientation ?? this.orientation,
      jobTitle: jobTitle ?? this.jobTitle,
      company: company ?? this.company,
      educationLevel: educationLevel ?? this.educationLevel,
      hasChildren: hasChildren ?? this.hasChildren,
      relationshipType: relationshipType ?? this.relationshipType,
      cannabis: cannabis ?? this.cannabis,
      drugs: drugs ?? this.drugs,
      pets: pets ?? this.pets,
      zodiac: zodiac ?? this.zodiac,
      smoking: smoking ?? this.smoking,
      drinking: drinking ?? this.drinking,
      fitnessLevel: fitnessLevel ?? this.fitnessLevel,
      wantsChildren: wantsChildren ?? this.wantsChildren,
      socialStyle: socialStyle ?? this.socialStyle,
      travelStyle: travelStyle ?? this.travelStyle,
      fashionStyle: fashionStyle ?? this.fashionStyle,
      personalityTags: personalityTags ?? this.personalityTags,
      interestedIn: interestedIn ?? this.interestedIn,
      preferredAgeMin: preferredAgeMin ?? this.preferredAgeMin,
      preferredAgeMax: preferredAgeMax ?? this.preferredAgeMax,
      maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
      preferredLanguages: preferredLanguages ?? this.preferredLanguages,
      lifestylePreferences: lifestylePreferences ?? this.lifestylePreferences,
      appearancePreferences:
          appearancePreferences ?? this.appearancePreferences,
      liveSelfieCaptured: liveSelfieCaptured ?? this.liveSelfieCaptured,
      liveSelfieCapturedAt: clearLiveSelfieCapturedAt
          ? null
          : (liveSelfieCapturedAt ?? this.liveSelfieCapturedAt),
      liveSelfieVerified: liveSelfieVerified ?? this.liveSelfieVerified,
      liveSelfieVersion: liveSelfieVersion ?? this.liveSelfieVersion,
      lastLiveSelfieAt: clearLastLiveSelfieAt
          ? null
          : (lastLiveSelfieAt ?? this.lastLiveSelfieAt),
      liveSelfiePublicPhotoUrl:
          liveSelfiePublicPhotoUrl ?? this.liveSelfiePublicPhotoUrl,
      liveSelfiePublicStoragePath:
          liveSelfiePublicStoragePath ?? this.liveSelfiePublicStoragePath,
      liveSelfiePrivatePhotoUrl:
          liveSelfiePrivatePhotoUrl ?? this.liveSelfiePrivatePhotoUrl,
      liveSelfiePrivateStoragePath:
          liveSelfiePrivateStoragePath ?? this.liveSelfiePrivateStoragePath,
      liveSelfieCaptureMethod:
          liveSelfieCaptureMethod ?? this.liveSelfieCaptureMethod,
      liveSelfieStatus: liveSelfieStatus ?? this.liveSelfieStatus,
    );
  }

  static List<String> _asStringList(dynamic value) {
    if (value is List) {
      return value.whereType<String>().toList(growable: false);
    }
    return const <String>[];
  }

  static List<ProfilePrompt> _asPromptList(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((Map<dynamic, dynamic> e) => ProfilePrompt.fromMap(
                e.map((dynamic k, dynamic v) => MapEntry(k.toString(), v)),
              ))
          .where(
              (ProfilePrompt p) => p.question.isNotEmpty && p.answer.isNotEmpty)
          .toList(growable: false);
    }
    return const <ProfilePrompt>[];
  }

  static int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static double? _asDouble(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  static DateTime? _asDate(dynamic value) {
    if (value is DateTime) {
      return value;
    }
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
