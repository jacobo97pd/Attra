import 'package:cloud_firestore/cloud_firestore.dart';

import '../../social/domain/intent_mode.dart';
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
    // Tolerante al tipo: llega de documentos públicos sin validar y una foto
    // mal formada no puede tumbar la ficha (ni la carga del feed) entera.
    final Object? url = map['url'];
    final Object? storagePath = map['storagePath'];
    final Object? source = map['source'];
    final Object? order = map['order'];
    return AdditionalPhoto(
      url: url is String ? url : '',
      storagePath: storagePath is String ? storagePath : '',
      source: source is String ? source : 'unknown',
      order: order is num ? order.toInt() : 0,
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
    final Object? id = map['id'];
    final Object? question = map['question'];
    final Object? answer = map['answer'];
    return PublicPrompt(
      id: id is String ? id : '',
      question: question is String ? question : '',
      answer: answer is String ? answer : '',
    );
  }
}

class SeedProfile {
  const SeedProfile({
    required this.id,
    required this.displayName,
    required this.city,
    required this.country,
    this.countryIso2 = '',
    required this.bio,
    required this.gender,
    required this.interestedIn,
    required this.orientation,
    this.relationshipGoal = '',
    this.intentMode = IntentMode.dating,
    this.socialInterests = const <String>[],
    this.smoking = '',
    this.drinking = '',
    this.educationLevel = '',
    this.heightCm,
    this.ethnicity = '',
    this.religion = '',
    this.verified = false,
    this.instagram = '',
    this.traveling = false,
    this.travelUntil,
    this.showDistance = true,
    this.showActiveStatus = true,
    this.lat,
    this.lng,
    required this.age,
    this.preferredAgeMin,
    this.preferredAgeMax,
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

  /// ISO2 del país publicado (`countryIso2` en discovery; en seeds,
  /// `currentCountryIso2`/`currentCountryCode`). Vacío = sin código: el feed
  /// cae entonces a comparar el nombre.
  final String countryIso2;
  final String bio;
  final String gender;

  /// Géneros en los que este perfil tiene interés (de preferences.interestedIn).
  /// Vacío = sin datos (no se filtra por este lado).
  final List<String> interestedIn;
  final List<String> orientation;

  /// Qué busca (relationshipIntent). Vacío = sin dato.
  final String relationshipGoal;

  /// Modo Amigos: intención del perfil. Default `dating` (compat).
  final IntentMode intentMode;

  /// Intereses sociales (amistad/grupos).
  final List<String> socialInterests;

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

  /// @usuario de Instagram (sin @). Vacío = no enlazado. Solo enlace, sin API.
  final String instagram;

  /// Modo viajes: el perfil aparece "de viaje" en este destino (discovery).
  /// Ya descuenta un viaje caducado (ver [travelExpired]).
  final bool traveling;

  /// Fin del viaje publicado (`travelUntil`). Sirve para no enseñar a alguien
  /// "de viaje en Cádiz" semanas después de que se acabara, mientras el
  /// barrido del backend no ha pasado todavía.
  final DateTime? travelUntil;

  /// La ficha dice "de viaje" pero el viaje ya terminó: la ficha está
  /// publicada en un destino donde esa persona ya no está.
  bool get travelExpired =>
      travelUntil != null && !travelUntil!.isAfter(DateTime.now());

  /// Visibilidad (Privacidad del dueño): si false, no se muestra su distancia
  /// ni su estado de actividad a otros. Default true (compat docs antiguos).
  final bool showDistance;
  final bool showActiveStatus;

  /// Ubicación aproximada (coords redondeadas) para distancia.
  final double? lat;
  final double? lng;
  final int? age;

  /// Rango de edad que busca esta persona (`preferredAgeMin/Max` publicados
  /// en discovery; en seeds, `preferences.*`). Sirve para la reciprocidad del
  /// feed: si mi edad no cabe en su rango, no le salgo ni me sale. null = sin
  /// dato (fichas antiguas, seeds): permisivo.
  final int? preferredAgeMin;
  final int? preferredAgeMax;
  final String jobTitle;
  final String company;
  final List<String> interests;
  final String photoUrl;

  /// Perfil semilla (mock de `seed_profiles`). Solo cuenta si el documento lo
  /// dice: el feed rellena con semillas un Descubrir vacío
  /// (`FeedFilter.sampleProfiles`) y una ficha real sin el campo no puede
  /// colarse ahí como "semilla" de otro país.
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

  static int? _ageBound(Object? value) {
    if (value is! num || !value.isFinite) return null;
    final int v = value.toInt();
    return v >= 18 && v <= 120 ? v : null;
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

  /// Lecturas TOLERANTES al tipo. `discovery` y `seed_profiles` no se validan
  /// en las reglas (y `users/{uid}`, de donde el backend copia, tampoco): con
  /// casts duros (`as String?`) un solo documento con `bio: 123` hacía lanzar
  /// a toda la carga y el feed se quedaba sin NINGÚN usuario real. Un valor del
  /// tipo equivocado cuenta como ausente.
  static String? _str(Object? v) => v is String ? v : null;
  static bool? _bool(Object? v) => v is bool ? v : null;
  static List<String>? _strList(Object? v) =>
      v is List ? v.whereType<String>().toList(growable: false) : null;
  static Map<String, dynamic> _map(Object? v) => v is Map
      ? v.map((dynamic k, dynamic val) => MapEntry(k.toString(), val))
      : <String, dynamic>{};
  static double? _coord(Object? v, double limit) {
    if (v is! num) return null;
    final double d = v.toDouble();
    return d.isFinite && d.abs() <= limit ? d : null;
  }

  /// La media de presentación tiene su propio parser: un `durationMs` con
  /// tipo raro no puede tumbar la ficha entera, solo quedarse sin audio/vídeo.
  static T? _safeMedia<T>(T? Function() build) {
    try {
      return build();
    } catch (_) {
      return null;
    }
  }

  static String _iso2(Object? v) {
    final String s = (_str(v) ?? '').trim().toUpperCase();
    return s.length == 2 ? s : '';
  }

  factory SeedProfile.fromMap(String id, Map<String, dynamic> data) {
    final List<dynamic> rawPhotos =
        data['photos'] is List ? data['photos'] as List<dynamic> : <dynamic>[];
    final Map<String, dynamic> profile = _map(data['profile']);
    final Map<String, dynamic> lifestyle = _map(data['lifestyle']);
    final Map<String, dynamic> appearance = _map(data['appearance']);
    final Map<String, dynamic> filterTraits = _map(data['filterTraits']);
    final Map<String, dynamic> geo = _map(data['geo']);
    String pick(String key) => _str(data[key]) ?? _str(profile[key]) ?? '';
    // Plano (discovery) con fallback a anidado (seed_profiles).
    String pickNested(String key, Map<String, dynamic> nested) =>
        _str(data[key]) ?? _str(nested[key]) ?? '';
    final DateTime? birthDate =
        _asDate(data['birthDate']) ?? _asDate(profile['birthDate']);
    final int? age = _asInt(data['age']) ??
        _asInt(profile['age']) ??
        _ageFromBirthDate(birthDate);
    // Discovery publica `countryIso2`; los seeds lo traen anidado con la clave
    // del onboarding o la del geocodificador.
    final String countryIso2 = <String>[
      _iso2(data['countryIso2']),
      _iso2(data['currentCountryIso2']),
      _iso2(profile['currentCountryIso2']),
      _iso2(data['currentCountryCode']),
      _iso2(profile['currentCountryCode']),
    ].firstWhere((String s) => s.isNotEmpty, orElse: () => '');
    final DateTime? travelUntil = _asDate(data['travelUntil']);
    final bool travelOver =
        travelUntil != null && !travelUntil.isAfter(DateTime.now());
    return SeedProfile(
      id: id,
      displayName: _str(data['displayName']) ?? 'Seed',
      city: pick('currentCity').isNotEmpty ? pick('currentCity') : pick('city'),
      country: pick('currentCountryName'),
      countryIso2: countryIso2,
      bio: pick('bio'),
      gender: pick('gender'),
      interestedIn: _strList(data['interestedIn']) ??
          _strList(_asPrefsMap(data)['interestedIn']) ??
          const <String>[],
      orientation: _strList(data['orientation']) ??
          _strList(profile['orientation']) ??
          const <String>[],
      relationshipGoal: pick('relationshipIntent').isNotEmpty
          ? pick('relationshipIntent')
          : pick('relationshipGoal'),
      intentMode:
          IntentMode.fromValue(data['intentMode'] ?? profile['intentMode']),
      socialInterests: _strList(data['socialInterests']) ??
          _strList(profile['socialInterests']) ??
          const <String>[],
      smoking: pickNested('smoking', lifestyle),
      drinking: pickNested('drinking', lifestyle),
      educationLevel: pick('educationLevel'),
      heightCm: _asInt(data['heightCm']) ?? _asInt(appearance['heightCm']),
      ethnicity: _str(filterTraits['ethnicity']) ?? '',
      religion: _str(filterTraits['religion']) ?? '',
      verified: _bool(data['verified']) ?? false,
      instagram: _str(data['instagram'])?.trim() ?? '',
      // Un viaje caducado ya no es "de viaje": el barrido del backend lo
      // republicará en casa, pero hasta entonces no se le enseña como tal.
      traveling: (_bool(data['traveling']) ?? false) && !travelOver,
      travelUntil: travelUntil,
      showDistance: _bool(data['showDistance']) ?? true,
      showActiveStatus: _bool(data['showActiveStatus']) ?? true,
      lat: _coord(geo['lat'], 90),
      lng: _coord(geo['lng'], 180),
      age: age,
      // Plano (discovery) con fallback a `preferences` (seed_profiles). Un
      // valor absurdo (fuera de 18-120) cuenta como ausente: la reciprocidad
      // es permisiva sin dato, y un rango roto no puede vaciar el feed de
      // nadie.
      preferredAgeMin: _ageBound(data['preferredAgeMin']) ??
          _ageBound(_asPrefsMap(data)['preferredAgeMin']),
      preferredAgeMax: _ageBound(data['preferredAgeMax']) ??
          _ageBound(_asPrefsMap(data)['preferredAgeMax']),
      jobTitle: pick('jobTitle'),
      company: pick('company'),
      interests: _strList(data['interests']) ??
          _strList(profile['interests']) ??
          const <String>[],
      photoUrl: _str(data['photoUrl']) ?? _str(data['profilePhotoUrl']) ?? '',
      isBot: _bool(data['isBot']) ?? false,
      botProfileVersion: _asInt(data['botProfileVersion']) ?? 1,
      botScenario: _str(data['botScenario']) ?? 'generic',
      seedQualityScore: _asInt(data['seedQualityScore']) ?? 0,
      photos: rawPhotos
          .whereType<Map>()
          .map((Map<dynamic, dynamic> e) => AdditionalPhoto.fromMap(
                e.map((dynamic key, dynamic value) =>
                    MapEntry(key.toString(), value)),
              ))
          .toList(growable: false),
      profilePrompts: (data['profilePrompts'] is List
              ? data['profilePrompts'] as List<dynamic>
              : <dynamic>[])
          .whereType<Map>()
          .map((Map<dynamic, dynamic> e) =>
              e.map((dynamic k, dynamic v) => MapEntry(k.toString(), v)))
          .where((Map<String, dynamic> m) => _bool(m['isActive']) ?? true)
          .map(PublicPrompt.fromMap)
          .where(
              (PublicPrompt p) => p.question.isNotEmpty && p.answer.isNotEmpty)
          .toList(growable: false),
      // Plano (discovery, top-level) con fallback a anidado (seed_profiles).
      introAudio: _safeMedia(() =>
          IntroAudio.fromMap(data['introAudio'] ?? profile['introAudio'])),
      introVideo: _safeMedia(() =>
          IntroVideo.fromMap(data['introVideo'] ?? profile['introVideo'])),
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
