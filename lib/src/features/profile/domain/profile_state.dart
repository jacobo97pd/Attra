import 'package:cloud_firestore/cloud_firestore.dart';

import 'intro_media.dart';

class AdditionalPhoto {
  const AdditionalPhoto({
    required this.url,
    required this.storagePath,
    required this.source,
    required this.order,
    this.createdAtIso,
  });

  final String url;
  final String storagePath;
  final String source;
  final int order;
  final String? createdAtIso;

  factory AdditionalPhoto.fromMap(Map<String, dynamic> map) {
    return AdditionalPhoto(
      url: (map['url'] as String?) ?? '',
      storagePath: (map['storagePath'] as String?) ?? '',
      source: (map['source'] as String?) ?? 'unknown',
      order: (map['order'] as num?)?.toInt() ?? 0,
      createdAtIso: map['createdAt']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'url': url,
      'storagePath': storagePath,
      'source': source,
      'order': order,
      'createdAt': createdAtIso,
    };
  }
}

/// Prompt público (pregunta + respuesta) tal y como se muestra en el perfil.
class PublicPrompt {
  const PublicPrompt({
    required this.id,
    required this.question,
    required this.answer,
  });

  final String id;
  final String question;
  final String answer;

  factory PublicPrompt.fromMap(Map<String, dynamic> map) {
    return PublicPrompt(
      id: (map['id'] as String?) ?? '',
      question: (map['question'] as String?) ?? '',
      answer: (map['answer'] as String?) ?? '',
    );
  }
}

class SeedProfile {
  const SeedProfile({
    required this.id,
    required this.displayName,
    required this.city,
    required this.country,
    required this.bio,
    required this.gender,
    required this.interestedIn,
    required this.orientation,
    this.relationshipGoal = '',
    this.smoking = '',
    this.drinking = '',
    this.educationLevel = '',
    this.heightCm,
    this.ethnicity = '',
    this.religion = '',
    this.verified = false,
    this.lat,
    this.lng,
    required this.age,
    required this.jobTitle,
    required this.company,
    required this.interests,
    required this.photoUrl,
    required this.isBot,
    required this.botProfileVersion,
    required this.botScenario,
    required this.seedQualityScore,
    required this.photos,
    this.profilePrompts = const <PublicPrompt>[],
    this.introAudio,
    this.introVideo,
  });

  final String id;
  final String displayName;
  final String city;
  final String country;
  final String bio;
  final String gender;

  /// Géneros en los que este perfil tiene interés (de preferences.interestedIn).
  /// Vacío = sin datos (no se filtra por este lado).
  final List<String> interestedIn;
  final List<String> orientation;

  /// Qué busca (relationshipIntent). Vacío = sin dato.
  final String relationshipGoal;

  /// Estilo de vida / estudios (para filtros avanzados). Vacío = sin dato.
  final String smoking;
  final String drinking;
  final String educationLevel;
  final int? heightCm;

  /// Rasgos sensibles FILTRABLES (solo presentes si el dueño consintió
  /// useForFilters). Vacío = no usar en filtros.
  final String ethnicity;
  final String religion;

  /// Verificado (selfie/identidad).
  final bool verified;

  /// Ubicación aproximada (coords redondeadas) para distancia.
  final double? lat;
  final double? lng;
  final int? age;
  final String jobTitle;
  final String company;
  final List<String> interests;
  final String photoUrl;
  final bool isBot;
  final int botProfileVersion;
  final String botScenario;
  final int seedQualityScore;
  final List<AdditionalPhoto> photos;

  /// Prompts públicos (pregunta+respuesta) que se muestran en el perfil.
  final List<PublicPrompt> profilePrompts;

  /// Media de presentación pública (audio "voice prompt" y/o vídeo corto).
  final IntroAudio? introAudio;
  final IntroVideo? introVideo;

  /// Foto principal: la explícita, o la primera adicional, o vacío.
  String get primaryPhotoUrl {
    if (photoUrl.isNotEmpty) {
      return photoUrl;
    }
    if (photos.isNotEmpty) {
      return photos.first.url;
    }
    return '';
  }

  /// URLs para la galería deslizable (todas las fotos del perfil).
  List<String> get galleryUrls {
    final List<String> urls = photos
        .map((AdditionalPhoto p) => p.url)
        .where((String u) => u.isNotEmpty)
        .toList(growable: true);
    if (urls.isEmpty && photoUrl.isNotEmpty) {
      urls.add(photoUrl);
    }
    return urls;
  }

  static Map<String, dynamic> _asPrefsMap(Map<String, dynamic> data) {
    final dynamic prefs = data['preferences'];
    if (prefs is Map) {
      return prefs.map((dynamic k, dynamic v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }

  static int? _asInt(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime? _asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static int? _ageFromBirthDate(DateTime? birthDate) {
    if (birthDate == null) return null;
    final DateTime now = DateTime.now();
    final DateTime localBirthDate = birthDate.toLocal();
    int age = now.year - localBirthDate.year;
    final bool hasBirthdayPassed = now.month > localBirthDate.month ||
        (now.month == localBirthDate.month && now.day >= localBirthDate.day);
    if (!hasBirthdayPassed) age -= 1;
    if (age < 0 || age > 120) return null;
    return age;
  }

  factory SeedProfile.fromMap(String id, Map<String, dynamic> data) {
    final List<dynamic> rawPhotos =
        (data['photos'] as List<dynamic>?) ?? <dynamic>[];
    final Map<String, dynamic> profile = data['profile'] is Map
        ? (data['profile'] as Map)
            .map((dynamic k, dynamic v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};
    final Map<String, dynamic> lifestyle = data['lifestyle'] is Map
        ? (data['lifestyle'] as Map)
            .map((dynamic k, dynamic v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};
    final Map<String, dynamic> appearance = data['appearance'] is Map
        ? (data['appearance'] as Map)
            .map((dynamic k, dynamic v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};
    final Map<String, dynamic> filterTraits = data['filterTraits'] is Map
        ? (data['filterTraits'] as Map)
            .map((dynamic k, dynamic v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};
    final Map<String, dynamic> geo = data['geo'] is Map
        ? (data['geo'] as Map)
            .map((dynamic k, dynamic v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};
    String pick(String key) =>
        (data[key] as String?) ?? (profile[key] as String?) ?? '';
    // Plano (discovery) con fallback a anidado (seed_profiles).
    String pickNested(String key, Map<String, dynamic> nested) =>
        (data[key] as String?) ?? (nested[key] as String?) ?? '';
    final DateTime? birthDate =
        _asDate(data['birthDate']) ?? _asDate(profile['birthDate']);
    final int? age = _asInt(data['age']) ??
        _asInt(profile['age']) ??
        _ageFromBirthDate(birthDate);
    return SeedProfile(
      id: id,
      displayName: (data['displayName'] as String?) ?? 'Seed',
      city: pick('currentCity').isNotEmpty ? pick('currentCity') : pick('city'),
      country: pick('currentCountryName'),
      bio: pick('bio'),
      gender: pick('gender'),
      interestedIn: (data['interestedIn'] as List<dynamic>?)
              ?.whereType<String>()
              .toList(growable: false) ??
          (_asPrefsMap(data)['interestedIn'] as List<dynamic>?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const <String>[],
      orientation: (data['orientation'] as List<dynamic>?)
              ?.whereType<String>()
              .toList(growable: false) ??
          (profile['orientation'] as List<dynamic>?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const <String>[],
      relationshipGoal: pick('relationshipIntent').isNotEmpty
          ? pick('relationshipIntent')
          : pick('relationshipGoal'),
      smoking: pickNested('smoking', lifestyle),
      drinking: pickNested('drinking', lifestyle),
      educationLevel: pick('educationLevel'),
      heightCm: (data['heightCm'] as num?)?.toInt() ??
          (appearance['heightCm'] as num?)?.toInt(),
      ethnicity: (filterTraits['ethnicity'] as String?) ?? '',
      religion: (filterTraits['religion'] as String?) ?? '',
      verified: (data['verified'] as bool?) ?? false,
      lat: (geo['lat'] as num?)?.toDouble(),
      lng: (geo['lng'] as num?)?.toDouble(),
      age: age,
      jobTitle: pick('jobTitle'),
      company: pick('company'),
      interests: (data['interests'] as List<dynamic>?)
              ?.whereType<String>()
              .toList(growable: false) ??
          (profile['interests'] as List<dynamic>?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const <String>[],
      photoUrl: (data['photoUrl'] as String?) ??
          (data['profilePhotoUrl'] as String?) ??
          '',
      isBot: (data['isBot'] as bool?) ?? true,
      botProfileVersion: (data['botProfileVersion'] as num?)?.toInt() ?? 1,
      botScenario: (data['botScenario'] as String?) ?? 'generic',
      seedQualityScore: (data['seedQualityScore'] as num?)?.toInt() ?? 0,
      photos: rawPhotos
          .whereType<Map>()
          .map((Map<dynamic, dynamic> e) => AdditionalPhoto.fromMap(
                e.map((dynamic key, dynamic value) =>
                    MapEntry(key.toString(), value)),
              ))
          .toList(growable: false),
      profilePrompts: ((data['profilePrompts'] as List<dynamic>?) ??
              <dynamic>[])
          .whereType<Map>()
          .map((Map<dynamic, dynamic> e) =>
              e.map((dynamic k, dynamic v) => MapEntry(k.toString(), v)))
          .where((Map<String, dynamic> m) => (m['isActive'] as bool?) ?? true)
          .map(PublicPrompt.fromMap)
          .where(
              (PublicPrompt p) => p.question.isNotEmpty && p.answer.isNotEmpty)
          .toList(growable: false),
      // Plano (discovery, top-level) con fallback a anidado (seed_profiles).
      introAudio:
          IntroAudio.fromMap(data['introAudio'] ?? profile['introAudio']),
      introVideo:
          IntroVideo.fromMap(data['introVideo'] ?? profile['introVideo']),
    );
  }
}

class ProfileCompletionState {
  const ProfileCompletionState({
    required this.percent,
    required this.pendingTasks,
    required this.availableRewards,
    required this.claimedRewards,
    required this.additionalPhotos,
    required this.prompts,
    required this.locationPermissionStatus,
    required this.locationGranted,
  });

  final int percent;
  final List<String> pendingTasks;
  final List<String> availableRewards;
  final List<String> claimedRewards;
  final List<AdditionalPhoto> additionalPhotos;
  final List<String> prompts;
  final String locationPermissionStatus;
  final bool locationGranted;
}
