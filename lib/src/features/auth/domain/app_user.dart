import 'package:cloud_firestore/cloud_firestore.dart';

import '../../monetization/domain/subscription_tier.dart';

class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.photoUrl,
    required this.onboardingCompleted,
    required this.profileCompleted,
    required this.profileCompletionPercent,
    required this.isBot,
    this.subscriptionTier = SubscriptionTier.free,
    this.hasActiveSubscription = false,
    this.attrasBalance = 0,
    this.aiVisualConsent = false,
    this.aiVisualConsentVersion = 0,
    this.aiVisualEnabled = false,
    this.gender = '',
    this.interestedIn = const <String>[],
    this.latitude,
    this.longitude,
    this.countryName = '',
    this.maxDistanceKm,
    this.slowDatingEnabled = false,
    this.screenshotProtectionEnabled = false,
    this.analyticsConsent = true,
    this.aiPersonalization = true,
    this.themeModeWire = 'dark',
    this.relationshipIntent = '',
    this.interests = const <String>[],
    this.boostBalance = 0,
    this.swipeBalance = 0,
    this.travelActive = false,
    this.travelIso2 = '',
    this.travelCity = '',
    this.travelCountry = '',
    this.busyModeEnabled = false,
    this.busyModeUntil,
    this.busyModeStartedAt,
    this.busyModeReason = '',
    this.busyModeVisibleToMatches = true,
    this.hasReliabilityBadge = false,
  });

  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final bool onboardingCompleted;
  final bool profileCompleted;
  final int profileCompletionPercent;
  final bool isBot;
  final SubscriptionTier subscriptionTier;
  final bool hasActiveSubscription;
  final int attrasBalance;
  final bool aiVisualConsent;
  final int aiVisualConsentVersion;
  final bool aiVisualEnabled;

  /// Consumibles comprados (saldo en `users/{uid}.wallet`).
  final int boostBalance;
  final int swipeBalance;

  /// Identidad de género del usuario (de profile.gender).
  final String gender;

  /// Slow Dating Mode: citas con calma. Si está activo, el feed muestra menos
  /// perfiles pero más afines (ranking/visibilidad), priorizando conexiones
  /// intencionales. Opt-in desde Ajustes (`settings['privacy.slowDating']`).
  final bool slowDatingEnabled;

  /// Protección anti-captura global (`settings['security.screenshotProtection']`).
  final bool screenshotProtectionEnabled;

  /// Consentimiento de analítica (`settings['data.analyticsConsent']`, default
  /// true). Si es false, no se registra telemetría del feed.
  final bool analyticsConsent;

  /// Consentimiento de personalización con IA (`settings['data.aiPersonalization']`,
  /// default true). Si es false, el feed no usa señales personalizadas.
  final bool aiPersonalization;

  /// Modo de tema elegido: 'system' | 'light' | 'dark'. De
  /// `settings['appearance.themeMode']`. Default 'dark'.
  final String themeModeWire;

  /// Qué busca (relationshipIntent) — para afinidad intencional en Slow Dating.
  final String relationshipIntent;

  /// Intereses del perfil — para afinidad por temas en Slow Dating.
  final List<String> interests;

  /// Géneros en los que tiene interés (de preferences.interestedIn).
  /// Vacío = sin filtro (muestra todos).
  final List<String> interestedIn;

  /// Ubicación aproximada (de location.latitude/longitude) para calcular
  /// distancia en el feed. null = sin ubicación.
  final double? latitude;
  final double? longitude;

  /// País del usuario (profile.currentCountryName). Fallback de relevancia
  /// geográfica cuando no hay coordenadas para calcular distancia.
  final String countryName;

  /// Radio máximo preferido en km (preferences.maxDistanceKm). null = usa el
  /// radio por defecto del feed.
  final int? maxDistanceKm;

  /// Modo viajes (Plus/Pro): si está activo, el feed se centra en el destino
  /// elegido y tu perfil aparece allí "de viaje". De `users/{uid}.travel`.
  final bool travelActive;
  final String travelIso2;
  final String travelCity;
  final String travelCountry;

  bool get isTraveling => travelActive && travelCountry.trim().isNotEmpty;

  /// Modo ocupado (Attra Clear §4): pausa suave. De `settings.privacy.busyMode*`.
  final bool busyModeEnabled;
  final DateTime? busyModeUntil;
  final DateTime? busyModeStartedAt;
  final String busyModeReason;
  final bool busyModeVisibleToMatches;

  /// True si el modo ocupado está ACTIVO ahora. Expiración **defensiva en
  /// cliente**: si `busyModeUntil` ya pasó, se considera inactivo aunque el flag
  /// siga en `true` (no dependemos de un job de backend para apagarlo).
  bool get busyModeActive =>
      busyModeEnabled &&
      busyModeUntil != null &&
      busyModeUntil!.isAfter(DateTime.now());

  /// Etiqueta del fin de la pausa ("hasta el domingo" se compone en UI).
  DateTime? get busyModeUntilOrNull => busyModeActive ? busyModeUntil : null;

  /// Attra Clear §8: badge POSITIVO "Responde con intención". Lo calcula y
  /// escribe SOLO el backend (el `connectionReliabilityScore` es interno y nunca
  /// se expone al cliente). Aquí solo se lee este booleano.
  final bool hasReliabilityBadge;

  /// Etiqueta del destino: "Ciudad, País" o solo país.
  String get travelLabel {
    final List<String> parts = <String>[travelCity.trim(), travelCountry.trim()]
        .where((String s) => s.isNotEmpty)
        .toList(growable: false);
    return parts.join(', ');
  }

  factory AppUser.fromDocument(
      DocumentSnapshot<Map<String, dynamic>> document) {
    final Map<String, dynamic> data = document.data() ?? <String, dynamic>{};
    final Map<String, dynamic> profile = _asMap(data['profile']);
    final Map<String, dynamic> preferences = _asMap(data['preferences']);
    final Map<String, dynamic> location = _asMap(data['location']);
    final Map<String, dynamic> settings = _asMap(data['settings']);
    final Map<String, dynamic> wallet = _asMap(data['wallet']);
    // Modo viajes vive bajo `settings.travel` (settings ya es escribible por el
    // dueño, sin tocar reglas). Compat: si quedara algún doc con `travel` arriba.
    final Map<String, dynamic> travel = _asMap(settings['travel']).isNotEmpty
        ? _asMap(settings['travel'])
        : _asMap(data['travel']);
    return AppUser(
      uid: (data['uid'] as String?) ?? document.id,
      email: data['email'] as String?,
      displayName: data['displayName'] as String?,
      photoUrl: data['photoUrl'] as String?,
      onboardingCompleted: _asBool(data['onboardingCompleted']),
      profileCompleted: _asBool(data['profileCompleted']),
      profileCompletionPercent: _asInt(data['profileCompletionPercent']),
      isBot: _asBool(data['isBot']),
      subscriptionTier: SubscriptionTier.fromValue(data['subscriptionTier']),
      hasActiveSubscription: _asBool(data['hasActiveSubscription']),
      attrasBalance: _asInt(data['attrasBalance']),
      aiVisualConsent: _asBool(data['aiVisualConsent']),
      aiVisualConsentVersion: _asInt(data['aiVisualConsentVersion']),
      aiVisualEnabled: _asBool(data['aiVisualEnabled']),
      gender: (profile['gender'] as String?) ?? '',
      interestedIn: _asStringList(preferences['interestedIn']),
      latitude: _asDouble(location['latitude']),
      longitude: _asDouble(location['longitude']),
      countryName: (profile['currentCountryName'] as String?) ??
          (profile['currentCountry'] as String?) ??
          '',
      maxDistanceKm: _asIntOrNull(preferences['maxDistanceKm']),
      slowDatingEnabled: _asBool(settings['privacy.slowDating']),
      screenshotProtectionEnabled:
          _asBool(settings['security.screenshotProtection']),
      analyticsConsent: settings['data.analyticsConsent'] != false,
      aiPersonalization: settings['data.aiPersonalization'] != false,
      themeModeWire:
          (settings['appearance.themeMode'] as String?)?.trim().isNotEmpty ==
                  true
              ? settings['appearance.themeMode'] as String
              : 'dark',
      relationshipIntent: (profile['relationshipIntent'] as String?) ??
          (preferences['relationshipIntent'] as String?) ??
          '',
      interests: _asStringList(profile['interests']),
      boostBalance: _asInt(wallet['boosts']),
      swipeBalance: _asInt(wallet['swipes']),
      travelActive: _asBool(travel['active']),
      travelIso2: ((travel['iso2'] as String?) ?? '').toUpperCase(),
      travelCity: (travel['city'] as String?) ?? '',
      travelCountry: (travel['country'] as String?) ?? '',
      busyModeEnabled: _asBool(settings['privacy.busyModeEnabled']),
      busyModeUntil: _asEpochDate(settings['privacy.busyModeUntil']),
      busyModeStartedAt: _asEpochDate(settings['privacy.busyModeStartedAt']),
      busyModeReason: (settings['privacy.busyModeReason'] as String?) ?? '',
      // Default true: por defecto los matches ven que estás ocupado.
      busyModeVisibleToMatches:
          settings['privacy.busyModeVisibleToMatches'] != false,
      hasReliabilityBadge: _asBool(data['hasReliabilityBadge']),
    );
  }

  /// Parsea una fecha guardada como millis (int), Timestamp o ISO string.
  static DateTime? _asEpochDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  bool get canUseAiVisual =>
      subscriptionTier.includesAiVisual &&
      hasActiveSubscription &&
      aiVisualConsent &&
      aiVisualEnabled;

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((dynamic k, dynamic v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }

  static List<String> _asStringList(dynamic value) {
    if (value is List) {
      return value.whereType<String>().toList(growable: false);
    }
    return const <String>[];
  }

  static bool _asBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is String) {
      return value.toLowerCase() == 'true';
    }
    return false;
  }

  static int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  static int? _asIntOrNull(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
