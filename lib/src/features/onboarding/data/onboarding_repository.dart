import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../auth/data/user_document_defaults.dart';
import '../../auth/domain/app_user.dart';
import '../../profile/domain/profile_completion.dart';
import '../domain/onboarding_draft.dart';
import 'onboarding_user_store.dart';

class OnboardingRepositoryException implements Exception {
  const OnboardingRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LiveSelfieDraftUpload {
  const LiveSelfieDraftUpload({
    required this.publicPhotoUrl,
    required this.publicStoragePath,
    required this.privatePhotoUrl,
    required this.privateStoragePath,
    required this.capturedAt,
    required this.captureMethod,
    required this.status,
  });

  final String publicPhotoUrl;
  final String publicStoragePath;
  final String privatePhotoUrl;
  final String privateStoragePath;
  final DateTime capturedAt;
  final String captureMethod;
  final String status;
}

class OnboardingRepository {
  OnboardingRepository({
    required FirebaseFirestore firestore,
    required FirebaseStorage storage,
  }) : this.withStore(
          userStore: FirestoreOnboardingUserStore(firestore),
          storage: storage,
        );

  @visibleForTesting
  OnboardingRepository.withStore({
    required OnboardingUserStore userStore,
    FirebaseStorage? storage,
  })  : _userStore = userStore,
        _storage = storage;

  final OnboardingUserStore _userStore;
  final FirebaseStorage? _storage;

  static const Map<String, String> _genderMap = <String, String>{
    'mujer': 'female',
    'female': 'female',
    'hombre': 'male',
    'male': 'male',
    'no_binario': 'non_binary',
    'no_binario_': 'non_binary',
    'nobinario': 'non_binary',
    'non_binary': 'non_binary',
  };

  static const Map<String, String> _relationshipIntentMap = <String, String>{
    'relacion_seria': 'serious_relationship',
    'serious_relationship': 'serious_relationship',
    'conocer_gente': 'meet_people',
    'meet_people': 'meet_people',
    'algo_casual': 'casual',
    'casual': 'casual',
    'abierto_a_ver_que_surge': 'open_to_see',
    'open_to_see': 'open_to_see',
  };

  static const Map<String, String> _smokingMap = <String, String>{
    'nunca': 'never',
    'never': 'never',
    'ocasional': 'occasionally',
    'occasionally': 'occasionally',
    'frecuente': 'frequently',
    'frequently': 'frequently',
  };

  static const Map<String, String> _drinkingMap = <String, String>{
    'nunca': 'never',
    'never': 'never',
    'social': 'socially',
    'socially': 'socially',
    'frecuente': 'frequently',
    'frequently': 'frequently',
  };

  static const Map<String, String> _fitnessMap = <String, String>{
    'bajo': 'low',
    'low': 'low',
    'medio': 'medium',
    'medium': 'medium',
    'alto': 'high',
    'high': 'high',
  };

  static const Map<String, String> _wantsChildrenMap = <String, String>{
    'si': 'yes',
    'yes': 'yes',
    'no': 'no',
    'quizas': 'maybe',
    'maybe': 'maybe',
  };

  static const Map<String, String> _socialStyleMap = <String, String>{
    'tranquilo': 'calm',
    'calm': 'calm',
    'equilibrado': 'balanced',
    'balanced': 'balanced',
    'muy_social': 'very_social',
    'very_social': 'very_social',
  };

  static const Map<String, String> _travelStyleMap = <String, String>{
    'hogareno': 'homebody',
    'homebody': 'homebody',
    'escapadas': 'weekend_getaways',
    'weekend_getaways': 'weekend_getaways',
    'aventurero': 'adventurous',
    'adventurous': 'adventurous',
  };

  static const Map<String, String> _eyeColorMap = <String, String>{
    'marron': 'brown',
    'brown': 'brown',
    'azul': 'blue',
    'blue': 'blue',
    'verde': 'green',
    'green': 'green',
    'gris': 'gray',
    'gray': 'gray',
    'avellana': 'hazel',
    'hazel': 'hazel',
  };

  static const Map<String, String> _hairColorMap = <String, String>{
    'negro': 'black',
    'black': 'black',
    'castano': 'brown',
    'brown': 'brown',
    'rubio': 'blonde',
    'blonde': 'blonde',
    'pelirrojo': 'red',
    'red': 'red',
    'canoso': 'gray',
    'gray': 'gray',
  };

  static const Map<String, String> _hairTypeMap = <String, String>{
    'liso': 'straight',
    'straight': 'straight',
    'ondulado': 'wavy',
    'wavy': 'wavy',
    'rizado': 'curly',
    'curly': 'curly',
    'afro': 'coily',
    'coily': 'coily',
    'rapado': 'shaved',
    'shaved': 'shaved',
  };

  static const Map<String, String> _bodyTypeMap = <String, String>{
    'delgado': 'slim',
    'slim': 'slim',
    'atletico': 'athletic',
    'athletic': 'athletic',
    'medio': 'average',
    'average': 'average',
    'curvy': 'curvy',
    'grande': 'plus_size',
    'plus_size': 'plus_size',
  };

  static const Map<String, String> _languageMap = <String, String>{
    'espanol': 'es',
    'es': 'es',
    'spanish': 'es',
    'ingles': 'en',
    'en': 'en',
    'english': 'en',
    'frances': 'fr',
    'fr': 'fr',
    'french': 'fr',
    'italiano': 'it',
    'it': 'it',
    'italian': 'it',
    'aleman': 'de',
    'de': 'de',
    'german': 'de',
    'portugues': 'pt',
    'pt': 'pt',
    'portuguese': 'pt',
  };

  static const Map<String, String> _fashionStyleMap = <String, String>{
    'casual': 'casual',
    'elegante': 'elegant',
    'elegant': 'elegant',
    'urbano': 'urban',
    'urban': 'urban',
    'deportivo': 'sporty',
    'sporty': 'sporty',
    'minimalista': 'minimalist',
    'minimalist': 'minimalist',
  };

  static const Map<String, String> _personalityTagMap = <String, String>{
    'ambicioso': 'ambitious',
    'ambitious': 'ambitious',
    'empatico': 'empathetic',
    'empathetic': 'empathetic',
    'divertido': 'fun',
    'fun': 'fun',
    'creativo': 'creative',
    'creative': 'creative',
    'tranquilo': 'calm',
    'calm': 'calm',
    'intenso': 'intense',
    'intense': 'intense',
  };

  static const Map<String, String> _interestedInMap = <String, String>{
    'mujer': 'female',
    'female': 'female',
    'hombre': 'male',
    'male': 'male',
    'no_binario': 'non_binary',
    'non_binary': 'non_binary',
  };

  static const Map<String, String> _lifestylePreferenceMap = <String, String>{
    'activo': 'active',
    'active': 'active',
    'hogareno': 'homebody',
    'homebody': 'homebody',
    'viajero': 'traveler',
    'traveler': 'traveler',
    'social': 'social',
    'saludable': 'healthy',
    'healthy': 'healthy',
  };

  static const Map<String, String> _appearancePreferenceMap = <String, String>{
    'mirada_intensa': 'intense_eyes',
    'intense_eyes': 'intense_eyes',
    'look_natural': 'natural_look',
    'natural_look': 'natural_look',
    'look_elegante': 'elegant_look',
    'elegant_look': 'elegant_look',
    'estilo_urbano': 'urban_style',
    'urban_style': 'urban_style',
    'vibe_deportiva': 'sporty_vibe',
    'sporty_vibe': 'sporty_vibe',
  };
  static const Map<String, String> _locationPermissionStatusMap =
      <String, String>{
    'unknown': 'unknown',
    'granted': 'granted',
    'denied': 'denied',
    'denied_forever': 'denied_forever',
    'while_in_use': 'granted',
    'always': 'granted',
    'restricted': 'restricted',
    'service_disabled': 'service_disabled',
    'unavailable': 'unavailable',
    'error': 'error',
  };

  Future<OnboardingDraft?> loadDraft(String uid) async {
    final String normalizedUid = _requireUid(
      uid,
      'cargar onboarding',
    );
    final Map<String, dynamic>? data =
        await _userStore.getUserData(normalizedUid);
    if (data == null) {
      return null;
    }
    final dynamic rawDraft = data['onboardingDraft'];
    if (rawDraft is Map<String, dynamic>) {
      return _normalizeDraft(OnboardingDraft.fromMap(rawDraft));
    }
    if (rawDraft is Map) {
      return _normalizeDraft(
        OnboardingDraft.fromMap(
          rawDraft.map((dynamic key, dynamic value) {
            return MapEntry(key.toString(), value);
          }),
        ),
      );
    }
    return null;
  }

  Future<void> saveDraftForUser(AppUser? user, OnboardingDraft draft) async {
    final String uid = _requireUid(
      user?.uid,
      'guardar onboarding',
    );
    await saveDraft(uid, draft);
  }

  Future<void> saveDraft(String uid, OnboardingDraft draft) async {
    final String normalizedUid = _requireUid(
      uid,
      'guardar onboarding',
    );
    final OnboardingDraft normalized = _normalizeDraft(draft);
    final Map<String, dynamic> payload = <String, dynamic>{
      ...UserDocumentDefaults.requiredFields(normalizedUid),
      'onboardingDraft': _sanitizeFirestoreMap(normalized.toMap()),
      'onboardingDraftUpdatedAt': FieldValue.serverTimestamp(),
    };
    final String path = _userStore.userPath(normalizedUid);
    _logPayload(
      operation: 'saveDraft',
      path: path,
      payload: payload,
    );

    try {
      await _userStore.setUserData(
        normalizedUid,
        payload,
        merge: true,
      );
    } catch (error, stack) {
      _logFirestoreError(
        operation: 'saveDraft',
        path: path,
        error: error,
        stack: stack,
        payload: payload,
      );
      rethrow;
    }
  }

  Future<LiveSelfieDraftUpload> uploadDraftLiveSelfie({
    required String uid,
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    final String normalizedUid = _requireUid(
      uid,
      'subir la selfie en vivo',
    );
    if (bytes.isEmpty) {
      throw const OnboardingRepositoryException(
        'La selfie en vivo es obligatoria para completar el onboarding.',
      );
    }

    return _uploadLiveSelfiePair(
      uid: normalizedUid,
      bytes: bytes,
      fileExtension: fileExtension,
    );
  }

  Future<void> submitOnboarding({
    required String uid,
    required OnboardingDraft draft,
    Uint8List? liveSelfieBytes,
    String? liveSelfieFileExtension,
  }) async {
    final String normalizedUid = _requireUid(
      uid,
      'completar onboarding',
    );
    final OnboardingDraft normalized = _normalizeDraft(draft);

    if (normalized.birthDate == null) {
      throw const OnboardingRepositoryException(
        'La fecha de nacimiento es obligatoria para completar onboarding.',
      );
    }

    final bool hasDraftSelfie =
        normalized.liveSelfiePublicPhotoUrl.isNotEmpty &&
            normalized.liveSelfiePrivatePhotoUrl.isNotEmpty &&
            normalized.liveSelfiePublicStoragePath.isNotEmpty &&
            normalized.liveSelfiePrivateStoragePath.isNotEmpty;

    final LiveSelfieDraftUpload selfieAssets;
    if (hasDraftSelfie) {
      selfieAssets = LiveSelfieDraftUpload(
        publicPhotoUrl: normalized.liveSelfiePublicPhotoUrl,
        publicStoragePath: normalized.liveSelfiePublicStoragePath,
        privatePhotoUrl: normalized.liveSelfiePrivatePhotoUrl,
        privateStoragePath: normalized.liveSelfiePrivateStoragePath,
        capturedAt: normalized.liveSelfieCapturedAt ?? DateTime.now(),
        captureMethod: normalized.liveSelfieCaptureMethod.isEmpty
            ? 'camera'
            : normalized.liveSelfieCaptureMethod,
        status: normalized.liveSelfieStatus.isEmpty
            ? 'captured_not_biometrically_verified'
            : normalized.liveSelfieStatus,
      );
    } else {
      if (liveSelfieBytes == null || liveSelfieBytes.isEmpty) {
        throw const OnboardingRepositoryException(
          'Debes capturar la selfie en vivo para completar onboarding.',
        );
      }
      selfieAssets = await _uploadLiveSelfiePair(
        uid: normalizedUid,
        bytes: liveSelfieBytes,
        fileExtension: liveSelfieFileExtension ?? 'jpg',
      );
    }

    final DateTime selfieCapturedAt =
        normalized.liveSelfieCapturedAt ?? selfieAssets.capturedAt;
    final String birthCity = _cleanText(normalized.birthCity);
    final String birthCityNormalized = normalized.birthCityNormalized.isEmpty
        ? _normalizeToken(birthCity)
        : normalized.birthCityNormalized;
    final String currentCity = _cleanText(normalized.currentCity);
    final String currentCityNormalized =
        normalized.currentCityNormalized.isEmpty
            ? _normalizeToken(currentCity)
            : normalized.currentCityNormalized;

    final Map<String, dynamic> submitPayload = <String, dynamic>{
      ...UserDocumentDefaults.requiredFields(normalizedUid),
      'displayName': _cleanText(normalized.visibleName),
      'photoUrl': selfieAssets.publicPhotoUrl,
      'profilePhotoUrl': selfieAssets.publicPhotoUrl,
      'onboardingCompleted': true,
      'profileCompleted': true,
      'onboardingCompletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'profile': <String, dynamic>{
        'visibleName': _cleanText(normalized.visibleName),
        'birthDate': Timestamp.fromDate(normalized.birthDate!),
        'gender': normalized.gender,
        'birthCity': birthCity,
        'birthCityNormalized': birthCityNormalized,
        'currentCity': currentCity,
        'currentCityNormalized': currentCityNormalized,
        'city': currentCity,
        'cityName': currentCity,
        'cityNormalized': currentCityNormalized,
        'languages': normalized.languages,
        'bio': _cleanText(normalized.bio),
        'relationshipIntent': normalized.relationshipIntent,
        'relationshipType': normalized.relationshipType,
        'pronouns': normalized.pronouns,
        'orientation': List<String>.from(normalized.orientation),
        'jobTitle': _cleanText(normalized.jobTitle),
        'company': _cleanText(normalized.company),
        'educationLevel': normalized.educationLevel,
        'zodiac': normalized.zodiac,
        'birthCountryCode': normalized.birthCountryCode,
        'birthCountryName': normalized.birthCountryName,
        'currentCountryCode': normalized.currentCountryCode,
        'currentCountryName': normalized.currentCountryName,
      },
      'appearance': <String, dynamic>{
        'heightCm': _asFirestoreIntOrNull(normalized.heightCm),
        'eyeColor': normalized.eyeColor,
        'hairColor': normalized.hairColor,
        'hairType': normalized.hairType,
        'bodyType': normalized.bodyType,
      },
      'lifestyle': <String, dynamic>{
        'smoking': normalized.smoking,
        'drinking': normalized.drinking,
        'fitnessLevel': normalized.fitnessLevel,
        'wantsChildren': normalized.wantsChildren,
        'socialStyle': normalized.socialStyle,
        'travelStyle': normalized.travelStyle,
        'hasChildren': normalized.hasChildren,
        'cannabis': normalized.cannabis,
        'drugs': normalized.drugs,
        'pets': List<String>.from(normalized.pets),
      },
      'style': <String, dynamic>{
        'fashionStyle': normalized.fashionStyle,
        'personalityTags': normalized.personalityTags,
      },
      'preferences': <String, dynamic>{
        'interestedIn': List<String>.from(normalized.interestedIn),
        'preferredAgeMin': _asFirestoreInt(normalized.preferredAgeMin),
        'preferredAgeMax': _asFirestoreInt(normalized.preferredAgeMax),
        'maxDistanceKm': _asFirestoreInt(normalized.maxDistanceKm),
        'preferredLanguages': List<String>.from(normalized.preferredLanguages),
        'lifestylePreferences':
            List<String>.from(normalized.lifestylePreferences),
        'appearancePreferences':
            List<String>.from(normalized.appearancePreferences),
      },
      'location': <String, dynamic>{
        'permissionGranted': normalized.locationPermissionGranted,
        'permissionStatus': normalized.locationPermissionStatus,
        'latitude': normalized.locationLatitude,
        'longitude': normalized.locationLongitude,
        'updatedAt': normalized.locationUpdatedAt == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(normalized.locationUpdatedAt!),
      },
      'isBot': false,
      'botProfileVersion': _asFirestoreInt(0),
      'botScenario': '',
      'seedQualityScore': _asFirestoreInt(0),
      'photos': <Map<String, dynamic>>[],
      'profileCompletionRewardsClaimed': <String>[],
      'availableProfileRewards': <String>[],
      'verification': <String, dynamic>{
        'liveSelfiePhotoUrl': selfieAssets.privatePhotoUrl,
        'liveSelfiePublicPhotoUrl': selfieAssets.publicPhotoUrl,
        'liveSelfiePublicStoragePath': selfieAssets.publicStoragePath,
        'liveSelfiePrivatePhotoUrl': selfieAssets.privatePhotoUrl,
        'liveSelfiePrivateStoragePath': selfieAssets.privateStoragePath,
        'liveSelfieCaptured': true,
        'liveSelfieCapturedAt': Timestamp.fromDate(selfieCapturedAt),
        'liveSelfieVerified': false,
        'liveSelfieVersion': _asFirestoreInt(normalized.liveSelfieVersion),
        'lastLiveSelfieAt': Timestamp.fromDate(
          normalized.lastLiveSelfieAt ?? selfieCapturedAt,
        ),
        'liveSelfieCaptureMethod': selfieAssets.captureMethod,
        'liveSelfieStatus': selfieAssets.status,
      },
      'aiData': <String, dynamic>{
        'referenceEmbeddings': <double>[],
        'preferenceVector': <double>[],
      },
      'onboardingDraft': FieldValue.delete(),
      'onboardingDraftUpdatedAt': FieldValue.delete(),
    };
    final String path = _userStore.userPath(normalizedUid);
    _logPayload(
      operation: 'submitOnboarding:setMain',
      path: path,
      payload: submitPayload,
    );

    try {
      await _userStore.setUserData(
        normalizedUid,
        _sanitizeFirestoreMap(submitPayload),
        merge: true,
      );
    } catch (error, stack) {
      _logFirestoreError(
        operation: 'submitOnboarding:setMain',
        path: path,
        error: error,
        stack: stack,
        payload: submitPayload,
      );
      rethrow;
    }

    final Map<String, dynamic> finalDoc =
        await _userStore.getUserData(normalizedUid) ?? <String, dynamic>{};
    final ProfileCompletionResult completion =
        ProfileCompletionCalculator.calculate(finalDoc);
    final Map<String, dynamic> completionPayload = <String, dynamic>{
      ...UserDocumentDefaults.requiredFields(normalizedUid),
      'profileCompletionPercent': completion.percent,
      'profileCompletionChecklist': completion.pendingTaskLabels,
      'pendingProfileTasks': completion.pendingTaskIds,
      'availableProfileRewards': completion.availableRewards,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    _logPayload(
      operation: 'submitOnboarding:setCompletion',
      path: path,
      payload: completionPayload,
    );

    try {
      await _userStore.setUserData(
        normalizedUid,
        _sanitizeFirestoreMap(completionPayload),
        merge: true,
      );
    } catch (error, stack) {
      _logFirestoreError(
        operation: 'submitOnboarding:setCompletion',
        path: path,
        error: error,
        stack: stack,
        payload: completionPayload,
      );
      rethrow;
    }
  }

  Future<LiveSelfieDraftUpload> _uploadLiveSelfiePair({
    required String uid,
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    final FirebaseStorage storage = _requireStorage();
    final String normalizedExt =
        fileExtension.toLowerCase().replaceAll('.', '').trim();
    final String extension = normalizedExt.isEmpty ? 'jpg' : normalizedExt;
    final String fileName =
        '${DateTime.now().millisecondsSinceEpoch}.$extension';

    final Reference privateRef =
        storage.ref().child('users/$uid/private/live_selfie/$fileName');
    final Reference publicRef =
        storage.ref().child('users/$uid/public/profile/$fileName');

    final String contentType = _contentTypeFor(extension);
    final DateTime capturedAt = DateTime.now();

    await Future.wait(<Future<void>>[
      privateRef.putData(
        bytes,
        SettableMetadata(
          contentType: contentType,
          customMetadata: <String, String>{
            'assetType': 'live_selfie',
            'assetVisibility': 'private',
            'uploadedBy': uid,
            'captureMethod': 'camera',
          },
        ),
      ),
      publicRef.putData(
        bytes,
        SettableMetadata(
          contentType: contentType,
          customMetadata: <String, String>{
            'assetType': 'profile_photo',
            'assetVisibility': 'public',
            'uploadedBy': uid,
            'source': 'live_selfie',
          },
        ),
      ),
    ]);

    final List<String> urls = await Future.wait<String>(<Future<String>>[
      publicRef.getDownloadURL(),
      privateRef.getDownloadURL(),
    ]);

    return LiveSelfieDraftUpload(
      publicPhotoUrl: urls[0],
      publicStoragePath: publicRef.fullPath,
      privatePhotoUrl: urls[1],
      privateStoragePath: privateRef.fullPath,
      capturedAt: capturedAt,
      captureMethod: 'camera',
      status: 'captured_not_biometrically_verified',
    );
  }

  OnboardingDraft _normalizeDraft(OnboardingDraft draft) {
    final String cleanVisibleName = _cleanText(draft.visibleName);
    final String cleanBirthCity = _cleanText(draft.birthCity);
    final String cleanCurrentCity = _cleanText(draft.currentCity);
    final String normalizedBirthCity = draft.birthCityNormalized.isEmpty
        ? _normalizeToken(cleanBirthCity)
        : _normalizeToken(draft.birthCityNormalized);
    final String normalizedCurrentCity = draft.currentCityNormalized.isEmpty
        ? _normalizeToken(cleanCurrentCity)
        : _normalizeToken(draft.currentCityNormalized);

    return draft.copyWith(
      visibleName: cleanVisibleName,
      birthCity: cleanBirthCity,
      birthCityNormalized: normalizedBirthCity,
      currentCity: cleanCurrentCity,
      currentCityNormalized: normalizedCurrentCity,
      locationPermissionStatus: _normalizeValue(
        draft.locationPermissionStatus,
        _locationPermissionStatusMap,
      ),
      bio: _cleanText(draft.bio),
      gender: _normalizeValue(draft.gender, _genderMap),
      eyeColor: _normalizeValue(draft.eyeColor, _eyeColorMap),
      hairColor: _normalizeValue(draft.hairColor, _hairColorMap),
      hairType: _normalizeValue(draft.hairType, _hairTypeMap),
      bodyType: _normalizeValue(draft.bodyType, _bodyTypeMap),
      relationshipIntent:
          _normalizeValue(draft.relationshipIntent, _relationshipIntentMap),
      smoking: _normalizeValue(draft.smoking, _smokingMap),
      drinking: _normalizeValue(draft.drinking, _drinkingMap),
      fitnessLevel: _normalizeValue(draft.fitnessLevel, _fitnessMap),
      wantsChildren: _normalizeValue(draft.wantsChildren, _wantsChildrenMap),
      socialStyle: _normalizeValue(draft.socialStyle, _socialStyleMap),
      travelStyle: _normalizeValue(draft.travelStyle, _travelStyleMap),
      languages: _normalizeList(draft.languages, _languageMap),
      preferredLanguages:
          _normalizeList(draft.preferredLanguages, _languageMap),
      fashionStyle: _normalizeList(draft.fashionStyle, _fashionStyleMap),
      personalityTags:
          _normalizeList(draft.personalityTags, _personalityTagMap),
      interestedIn: _normalizeList(draft.interestedIn, _interestedInMap),
      lifestylePreferences:
          _normalizeList(draft.lifestylePreferences, _lifestylePreferenceMap),
      appearancePreferences:
          _normalizeList(draft.appearancePreferences, _appearancePreferenceMap),
      liveSelfieCaptured: draft.liveSelfieCaptured ||
          draft.liveSelfiePublicPhotoUrl.isNotEmpty ||
          draft.liveSelfiePrivatePhotoUrl.isNotEmpty,
      liveSelfieCaptureMethod: draft.liveSelfieCaptureMethod.isEmpty
          ? 'camera'
          : _normalizeToken(draft.liveSelfieCaptureMethod),
      liveSelfieStatus: draft.liveSelfieStatus.isEmpty
          ? 'captured_not_biometrically_verified'
          : _normalizeToken(draft.liveSelfieStatus),
    );
  }

  List<String> _normalizeList(
    List<String> values,
    Map<String, String> mapping,
  ) {
    final List<String> normalized = <String>[];
    for (final String value in values) {
      final String normalizedValue = _normalizeValue(value, mapping);
      if (normalizedValue.isEmpty || normalized.contains(normalizedValue)) {
        continue;
      }
      normalized.add(normalizedValue);
    }
    return normalized;
  }

  String _normalizeValue(String value, Map<String, String> mapping) {
    final String token = _normalizeToken(value);
    if (token.isEmpty) {
      return '';
    }
    return mapping[token] ?? token;
  }

  String _cleanText(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normalizeToken(String value) {
    final String lower = value.toLowerCase().trim();
    if (lower.isEmpty) {
      return '';
    }

    final StringBuffer buffer = StringBuffer();
    for (final int codePoint in lower.runes) {
      final String char = String.fromCharCode(codePoint);
      buffer.write(_latinMap[char] ?? char);
    }

    final String normalized = buffer
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return normalized;
  }

  String _contentTypeFor(String extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'jpeg':
      case 'jpg':
      default:
        return 'image/jpeg';
    }
  }

  int _asFirestoreInt(num value) {
    return value.toInt();
  }

  int? _asFirestoreIntOrNull(num? value) {
    if (value == null) {
      return null;
    }
    return value.toInt();
  }

  Map<String, dynamic> _sanitizeFirestoreMap(Map<String, dynamic> input) {
    return input.map((String key, dynamic value) {
      return MapEntry<String, dynamic>(key, _sanitizeFirestoreValue(value));
    });
  }

  dynamic _sanitizeFirestoreValue(dynamic value) {
    if (value is Map<String, dynamic>) {
      return _sanitizeFirestoreMap(value);
    }
    if (value is Map) {
      final Map<String, dynamic> mapped = <String, dynamic>{};
      value.forEach((dynamic k, dynamic v) {
        mapped[k.toString()] = _sanitizeFirestoreValue(v);
      });
      return mapped;
    }
    if (value is List<String>) {
      return List<String>.from(value);
    }
    if (value is List) {
      return value
          .map<dynamic>(_sanitizeFirestoreValue)
          .toList(growable: false);
    }
    return value;
  }

  String _requireUid(String? uid, String operation) {
    final String? normalizedUid = uid?.trim();
    if (normalizedUid == null || normalizedUid.isEmpty) {
      throw OnboardingRepositoryException(
        'No hay sesion activa para $operation.',
      );
    }
    return normalizedUid;
  }

  FirebaseStorage _requireStorage() {
    final FirebaseStorage? storage = _storage;
    if (storage == null) {
      throw const OnboardingRepositoryException(
        'Firebase Storage no esta configurado para onboarding.',
      );
    }
    return storage;
  }

  void _logPayload({
    required String operation,
    required String path,
    required Map<String, dynamic> payload,
  }) {
    if (!kDebugMode) {
      return;
    }
    debugPrint(
      '[Attra][Onboarding][$operation] path=$path '
      'payloadKeys=${payload.keys.toList()} '
      'payloadShape=${_payloadShape(payload)}',
    );
  }

  void _logFirestoreError({
    required String operation,
    required String path,
    required Object error,
    required StackTrace stack,
    Map<String, dynamic>? payload,
  }) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('[Attra][Onboarding][$operation] Firestore error path=$path');
    if (error is FirebaseException) {
      debugPrint(
        'FirebaseException(plugin=${error.plugin}, code=${error.code}, '
        'message=${error.message})',
      );
    } else {
      debugPrint('${error.runtimeType}: $error');
    }
    debugPrint(stack.toString());
    if (payload != null) {
      debugPrint('Failed payload keys: ${payload.keys.toList()}');
      debugPrint('Failed payload shape: ${_payloadShape(payload)}');
    }
  }

  Map<String, Object?> _payloadShape(Map<String, dynamic> payload) {
    return payload.map((String key, dynamic value) {
      if (value is Map) {
        return MapEntry<String, Object?>(key, 'map:${value.keys.toList()}');
      }
      if (value is List) {
        return MapEntry<String, Object?>(key, 'list:${value.length}');
      }
      return MapEntry<String, Object?>(key, value.runtimeType.toString());
    });
  }
}

const Map<String, String> _latinMap = <String, String>{
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ñ': 'n',
  'ç': 'c',
};
