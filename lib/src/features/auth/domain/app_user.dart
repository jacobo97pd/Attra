import 'package:cloud_firestore/cloud_firestore.dart';

import '../../geo/domain/travel_rules.dart';
import '../../monetization/domain/subscription_tier.dart';
import '../../social/domain/intent_mode.dart';
import 'location_refresh_policy.dart';

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
    this.chatSuggestionsConsent = false,
    this.chatSuggestionsConsentVersion = 0,
    this.aiVisualEnabled = false,
    this.gender = '',
    this.interestedIn = const <String>[],
    this.latitude,
    this.longitude,
    this.locationUpdatedAt,
    this.locationMeasuredAt,
    this.locationPermissionStatus = 'unknown',
    this.placeLatitude,
    this.placeLongitude,
    this.countryName = '',
    this.countryIso2 = '',
    this.maxDistanceKm,
    this.age,
    this.preferredAgeMin,
    this.preferredAgeMax,
    this.savedFeedFilters = const <String, dynamic>{},
    this.slowDatingEnabled = false,
    this.tutorialCompleted = false,
    this.screenshotProtectionEnabled = false,
    this.analyticsConsent = true,
    this.aiPersonalization = true,
    this.themeModeWire = 'dark',
    this.relationshipIntent = '',
    this.interests = const <String>[],
    this.intentMode = IntentMode.dating,
    this.socialInterests = const <String>[],
    this.preferredGroupSize = 0,
    this.availableForPlans = false,
    this.city = '',
    this.boostBalance = 0,
    this.swipeBalance = 0,
    this.travelActive = false,
    this.travelIso2 = '',
    this.travelCity = '',
    this.travelCountry = '',
    this.travelUntil,
    this.travelLat,
    this.travelLng,
    this.travelGeoSource = '',
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

  /// Consentimiento para que la IA lea la conversación y proponga respuestas.
  /// Independiente del de la IA visual: son dos tratamientos distintos.
  final bool chatSuggestionsConsent;
  final int chatSuggestionsConsentVersion;
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

  /// Tutorial de bienvenida completado (`settings['tutorial.completed']`). Los
  /// nuevos usuarios lo ven obligatoriamente hasta terminarlo.
  final bool tutorialCompleted;

  /// Protección anti-captura global (`settings['security.screenshotProtection']`).
  final bool screenshotProtectionEnabled;

  /// Consentimiento de analítica (`settings['data.analyticsConsent']`, default
  /// true). Si es false, no se registra telemetría del feed.
  final bool analyticsConsent;

  /// Consentimiento de personalización con IA (`settings['data.aiPersonalization']`,
  /// default true). Si es false, el feed no usa señales personalizadas.
  final bool aiPersonalization;

  /// Modo de tema elegido: 'system' | 'light' | 'dark'. De
  /// `settings['appearance.themeMode']`. Default 'dark': Attra es una marca de
  /// fondo negro y arrancar en claro rompía la identidad.
  final String themeModeWire;

  /// Qué busca (relationshipIntent) — para afinidad intencional en Slow Dating.
  final String relationshipIntent;

  /// Intereses del perfil — para afinidad por temas en Slow Dating.
  final List<String> interests;

  /// Modo Amigos: intención del usuario (dating | friends | both | groups).
  /// Default `dating` → usuarios antiguos se comportan igual que siempre.
  final IntentMode intentMode;

  /// Intereses SOCIALES (para amistad/grupos). Puede solaparse con [interests].
  final List<String> socialInterests;

  /// Tamaño de grupo preferido (0 = sin preferencia).
  final int preferredGroupSize;

  /// ¿Disponible para planes/quedadas ahora?
  final bool availableForPlans;

  /// Ciudad del usuario (profile.currentCity/city). Para recomendar grupos.
  final String city;

  /// Géneros en los que tiene interés (de preferences.interestedIn).
  /// Vacío = sin filtro (muestra todos).
  final List<String> interestedIn;

  /// Ubicación aproximada (de location.latitude/longitude) para calcular
  /// distancia en el feed. null = sin ubicación.
  final double? latitude;
  final double? longitude;

  /// Cuándo se guardó esa ubicación (`location.updatedAt`). Sin esta marca no se
  /// puede distinguir una ubicación de hoy de una de hace tres meses, que es
  /// justo por lo que la ubicación se quedaba congelada: solo se capturaba
  /// cuando FALTABA, nunca cuando estaba rancia.
  final DateTime? locationUpdatedAt;

  /// Cuándo se MIDIÓ la posición (`location.fixedAt`). No es lo mismo que
  /// [locationUpdatedAt], que es cuándo la confirmó el servidor: sin cobertura la
  /// escritura se resuelve al recuperar red, ya en otra ciudad, y la posición
  /// vieja quedaba sellada como recién medida.
  final DateTime? locationMeasuredAt;

  /// Estado del permiso guardado (`location.permissionStatus`): 'granted',
  /// 'denied', 'denied_forever', 'service_disabled' o 'unknown'.
  final String locationPermissionStatus;

  /// Dónde se resolvió por última vez la ciudad/país (`location.placeLat/Lng`).
  /// Si las coordenadas se alejan de este punto es que el último intento del
  /// geocodificador falló y el país guardado puede ser el de antes.
  final double? placeLatitude;
  final double? placeLongitude;

  /// Ubicación guardada tal cual, para la política de refresco.
  StoredLocation get storedLocation => StoredLocation(
        latitude: latitude,
        longitude: longitude,
        updatedAt: locationUpdatedAt,
        measuredAt: locationMeasuredAt,
        placeLatitude: placeLatitude,
        placeLongitude: placeLongitude,
      );

  /// País del usuario (profile.currentCountryName). Fallback de relevancia
  /// geográfica cuando no hay coordenadas para calcular distancia.
  final String countryName;

  /// ISO2 del país (`profile.currentCountryIso2`, que escribe el geocodificador,
  /// o `profile.currentCountryCode`, que escribe el onboarding). Es lo que se
  /// compara en el feed: el nombre sale en el idioma del teléfono ('Espanya',
  /// 'Spanien') y con él un catalán dejaba de ver a los de su propia ciudad.
  final String countryIso2;

  /// Radio máximo preferido en km (preferences.maxDistanceKm). null = usa el
  /// radio por defecto del feed. Es la ÚNICA verdad del radio: la escriben el
  /// onboarding y el filtro "Distancia" del feed.
  final int? maxDistanceKm;

  /// Edad propia (profile.age, o calculada de la fecha de nacimiento). La usa
  /// el feed para la reciprocidad: si no cabes en el rango de alguien, no le
  /// sales ni te sale. null = sin dato (permisivo).
  final int? age;

  /// Rango de edad que busca (`preferences.preferredAgeMin/Max`, obligatorio
  /// en el onboarding y editable desde el filtro "Edad" del feed). Antes solo
  /// lo leía el directo: el feed empezaba siempre en 18-80.
  final int? preferredAgeMin;
  final int? preferredAgeMax;

  /// Resto de filtros del feed guardados (`preferences.feedFilters`), en
  /// crudo: los interpreta `FeedFilters.fromPreferences`. Antes vivían solo en
  /// memoria y un "no negociable" puesto el viernes desaparecía el sábado.
  final Map<String, dynamic> savedFeedFilters;

  /// Modo viajes (Plus/Pro): si está activo, el feed se centra en el destino
  /// elegido y tu perfil aparece allí "de viaje". De `users/{uid}.travel`.
  final bool travelActive;
  final String travelIso2;
  final String travelCity;
  final String travelCountry;

  /// Fin del viaje: el más tardío entre `settings.travel.untilAt` y el ISO
  /// `until` de versiones anteriores ([TravelRules.effectiveUntil]); 30 días
  /// al activarlo.
  final DateTime? travelUntil;

  /// Centro de la ciudad de destino (`settings.travel.lat/lng`). NUNCA es la
  /// ubicación real: el feed del viaje se mide desde aquí y la ficha pública se
  /// publica aquí. null = viaje sin coordenadas (a un país entero, antiguo, o
  /// con un centro que era de OTRO destino: ver
  /// [TravelRules.centerMatchesDestination]).
  final double? travelLat;
  final double? travelLng;

  /// De dónde salió ese centro: 'asset' | 'device' | 'server' | 'none'.
  final String travelGeoSource;

  /// Sin ciudad no hay centro que valga, igual que en el backend: un viaje a
  /// un país entero con un `lat/lng` sobrante se medía desde la ciudad vieja.
  bool get hasTravelOrigin =>
      travelLat != null && travelLng != null && travelCity.trim().isNotEmpty;

  /// El viaje sigue marcado como activo pero su fecha ya pasó (o es
  /// imposible, ver [TravelRules.isOver]): hay que apagarlo (el backend lo
  /// hace en su barrido; el cliente lo hace al verlo para no esperar y para
  /// devolver al usuario a su ubicación real).
  bool get travelExpired =>
      travelActive && TravelRules.isOver(travelUntil, DateTime.now());

  /// True si el modo viaje está vigente. Expiración **defensiva en cliente**
  /// (igual que [busyModeActive]): el backend ya caduca el viaje al publicar la
  /// ficha (functions/src/discovery.ts → `travelExpired`), así que sin este
  /// control el cliente y el backend discrepaban en el caso más común de todos —
  /// quien activó el viaje y nunca lo apagó:
  /// el backend publicaba su ciudad y sus coordenadas REALES mientras el cliente
  /// seguía anclando su feed al destino, no gastaba GPS (la política evita el fix
  /// viajando) y le silenciaba el aviso, así que sus coordenadas se congelaban
  /// para siempre: justo el fallo que este módulo viene a arreglar.
  bool get isTraveling =>
      travelActive &&
      travelCountry.trim().isNotEmpty &&
      !TravelRules.isOver(travelUntil, DateTime.now());

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
    // Un centro que se resolvió para otro destino no se usa (ver
    // TravelRules.centerMatchesDestination): así hasTravelOrigin es false, el
    // feed se queda en el país o en el centro resuelto al vuelo y la sesión lo
    // vuelve a situar.
    final bool centerOk = TravelRules.centerMatchesDestination(
      city: travel['city'],
      iso2: travel['iso2'],
      geoCity: travel['geoCity'],
      geoIso2: travel['geoIso2'],
    );
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
      chatSuggestionsConsent: _asBool(data['chatSuggestionsConsent']),
      chatSuggestionsConsentVersion:
          _asInt(data['chatSuggestionsConsentVersion']),
      aiVisualEnabled: _asBool(data['aiVisualEnabled']),
      gender: (profile['gender'] as String?) ?? '',
      interestedIn: _asStringList(preferences['interestedIn']),
      latitude: _asDouble(location['latitude']),
      longitude: _asDouble(location['longitude']),
      locationUpdatedAt: _asEpochDate(location['updatedAt']),
      locationMeasuredAt: _asEpochDate(location['fixedAt']),
      locationPermissionStatus:
          (location['permissionStatus'] as String?)?.trim().isNotEmpty == true
              ? location['permissionStatus'] as String
              : 'unknown',
      placeLatitude: _asLatitude(location['placeLat']),
      placeLongitude: _asLongitude(location['placeLng']),
      countryName: (profile['currentCountryName'] as String?) ??
          (profile['currentCountry'] as String?) ??
          '',
      // El del geocodificador primero: es el que se refresca al moverse. El
      // del onboarding se escribe una vez y, tras cruzar una frontera, miente.
      countryIso2: _asIso2(profile['currentCountryIso2']).isNotEmpty
          ? _asIso2(profile['currentCountryIso2'])
          : _asIso2(profile['currentCountryCode']),
      maxDistanceKm: _asIntOrNull(preferences['maxDistanceKm']),
      // Misma prioridad que la ficha pública (discovery.ts): edad declarada y,
      // si no, la de la fecha de nacimiento.
      age: _asIntOrNull(profile['age']) ??
          _asIntOrNull(data['age']) ??
          _ageFromBirthDate(_asEpochDate(profile['birthDate']) ??
              _asEpochDate(data['birthDate'])),
      preferredAgeMin: _asIntOrNull(preferences['preferredAgeMin']),
      preferredAgeMax: _asIntOrNull(preferences['preferredAgeMax']),
      savedFeedFilters: _asMap(preferences['feedFilters']),
      slowDatingEnabled: _asBool(settings['privacy.slowDating']),
      tutorialCompleted: _asBool(settings['tutorial.completed']),
      screenshotProtectionEnabled:
          _asBool(settings['security.screenshotProtection']),
      analyticsConsent: settings['data.analyticsConsent'] != false,
      aiPersonalization: settings['data.aiPersonalization'] != false,
      themeModeWire:
          (settings['appearance.themeMode'] as String?)?.trim().isNotEmpty ==
                  true
              ? settings['appearance.themeMode'] as String
              // Sin ajuste guardado, OSCURO (ver ThemeController).
              : 'dark',
      relationshipIntent: (profile['relationshipIntent'] as String?) ??
          (preferences['relationshipIntent'] as String?) ??
          '',
      interests: _asStringList(profile['interests']),
      intentMode: IntentMode.fromValue(profile['intentMode']),
      socialInterests: _asStringList(profile['socialInterests']),
      preferredGroupSize: _asInt(profile['preferredGroupSize']),
      availableForPlans: _asBool(profile['availableForPlans']),
      city: (profile['currentCity'] as String?) ??
          (profile['city'] as String?) ??
          '',
      boostBalance: _asInt(wallet['boosts']),
      swipeBalance: _asInt(wallet['swipes']),
      travelActive: _asBool(travel['active']),
      travelIso2: ((travel['iso2'] as String?) ?? '').toUpperCase(),
      travelCity: (travel['city'] as String?) ?? '',
      travelCountry: (travel['country'] as String?) ?? '',
      // `untilAt` (Timestamp) es el nuevo; `until` (ISO) lo siguen escribiendo
      // y leyendo las versiones anteriores de la app. Manda el más tardío.
      travelUntil: TravelRules.effectiveUntil(
        _asEpochDate(travel['untilAt']),
        _asEpochDate(travel['until']),
      ),
      travelLat: centerOk ? _asLatitude(travel['lat']) : null,
      travelLng: centerOk ? _asLongitude(travel['lng']) : null,
      travelGeoSource: (travel['geoSource'] as String?)?.trim() ?? '',
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

  static int? _ageFromBirthDate(DateTime? birthDate) {
    if (birthDate == null) return null;
    final DateTime now = DateTime.now();
    final DateTime local = birthDate.toLocal();
    int age = now.year - local.year;
    final bool birthdayPassed = now.month > local.month ||
        (now.month == local.month && now.day >= local.day);
    if (!birthdayPassed) age -= 1;
    return age < 0 || age > 120 ? null : age;
  }

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// `settings` no valida tipos en las reglas: una coordenada fuera de rango
  /// no puede convertirse en el centro del feed.
  static double? _asLatitude(dynamic value) {
    final double? v = _asDouble(value);
    return v != null && v.isFinite && v >= -90 && v <= 90 ? v : null;
  }

  static double? _asLongitude(dynamic value) {
    final double? v = _asDouble(value);
    return v != null && v.isFinite && v >= -180 && v <= 180 ? v : null;
  }

  static String _asIso2(dynamic value) {
    final String s = value is String ? value.trim().toUpperCase() : '';
    return s.length == 2 ? s : '';
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
