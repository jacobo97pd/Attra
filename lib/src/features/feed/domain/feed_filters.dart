import 'dart:math' as math;

/// Filtros del feed (estilo Hinge). BÁSICOS (gratis): edad, géneros,
/// solo-con-foto, distancia. AVANZADOS (Plus): qué busca, tabaco, alcohol,
/// estudios, altura, etnicidad, religión, verificación.
///
/// "No negociable" (deal-breaker): cada filtro con valor solo EXCLUYE de verdad
/// si su clave está en [dealbreakers]; si no, es una preferencia blanda (no
/// excluye). Siempre duros: el género ("mostrarme"), "solo con foto", "solo
/// verificados", la distancia y la EDAD (recíproca, como en el directo).
///
/// Persistencia: la distancia y la edad son `preferences.maxDistanceKm` y
/// `preferences.preferredAgeMin/Max` (una sola verdad con el onboarding y el
/// directo); el resto va en `preferences.feedFilters` ([toSavedMap]). Las
/// búsquedas IA no se guardan: son una búsqueda, no una preferencia, y cada
/// carga con ellas cuesta llamadas al motor.
class FeedFilters {
  const FeedFilters({
    this.minAge = ageFloor,
    this.maxAge = ageCeil,
    this.showGenders = const <String>{},
    this.onlyWithPhoto = false,
    this.maxDistanceKm,
    this.relationshipGoal,
    this.smoking,
    this.drinking,
    this.educationLevel,
    this.ethnicity,
    this.religion,
    this.verifiedOnly = false,
    this.minHeight = heightFloor,
    this.maxHeight = heightCeil,
    this.dealbreakers = const <String>{},
    this.sortByVisualReference = false,
    this.promptQuery = '',
  });

  // --- Básicos ---
  final int minAge;
  final int maxAge;
  final Set<String> showGenders;
  final bool onlyWithPhoto;
  final int? maxDistanceKm;

  // --- Avanzados (Plus) ---
  final String? relationshipGoal;
  final String? smoking;
  final String? drinking;
  final String? educationLevel;
  final String? ethnicity;
  final String? religion;
  final bool verifiedOnly;
  final int minHeight;
  final int maxHeight;

  /// Claves de filtros marcados "no negociable" (excluyen de verdad).
  final Set<String> dealbreakers;

  /// Ordenar el feed por parecido estético a la foto de referencia (Pro).
  final bool sortByVisualReference;

  /// Búsqueda por PROMPT (Pro): descripción en lenguaje natural del "tipo". Si
  /// no está vacía, el feed muestra solo los que encajan (físico + datos). Es
  /// independiente de [sortByVisualReference].
  final String promptQuery;

  static const int ageFloor = 18;
  static const int ageCeil = 80;
  static const int heightFloor = 140;
  static const int heightCeil = 210;

  /// Tope del radio: el MISMO que el slider del onboarding. Los filtros
  /// llegaban solo a 200, así que quien eligió 300 km al registrarse no podía
  /// pedir más de 200 y cualquier cambio le encogía el radio.
  static const int distanceFloor = 1;
  static const int distanceCeil = 500;

  // Claves de los filtros que admiten deal-breaker.
  static const String kAge = 'age';
  static const String kDistance = 'distance';
  static const String kGoal = 'goal';
  static const String kSmoking = 'smoking';
  static const String kDrinking = 'drinking';
  static const String kEducation = 'education';
  static const String kHeight = 'height';
  static const String kEthnicity = 'ethnicity';
  static const String kReligion = 'religion';
  static const String kVerified = 'verified';

  bool get _heightActive => minHeight != heightFloor || maxHeight != heightCeil;
  bool get heightActive => _heightActive;
  bool isDealbreaker(String key) => dealbreakers.contains(key);

  bool get isDefault => activeCount == 0;

  int get activeCount {
    int n = 0;
    if (minAge != ageFloor || maxAge != ageCeil) n++;
    if (showGenders.isNotEmpty) n++;
    if (onlyWithPhoto) n++;
    if (maxDistanceKm != null) n++;
    if (relationshipGoal != null) n++;
    if (smoking != null) n++;
    if (drinking != null) n++;
    if (educationLevel != null) n++;
    if (ethnicity != null) n++;
    if (religion != null) n++;
    if (verifiedOnly) n++;
    if (_heightActive) n++;
    // Las búsquedas IA NO se contaban: son los filtros más agresivos (dejan el
    // feed solo con quien supera el umbral, y pueden vaciarlo), pero el badge
    // de "filtros activos" marcaba 0 y el usuario no veía que los tenía puestos.
    if (aiSearchActive) n++;
    return n;
  }

  /// True si hay alguna búsqueda IA pedida (por descripción o por foto de
  /// referencia). Cuenta como UN filtro aunque se usen las dos a la vez.
  bool get aiSearchActive =>
      sortByVisualReference || promptQuery.trim().isNotEmpty;

  FeedFilters copyWith({
    int? minAge,
    int? maxAge,
    Set<String>? showGenders,
    bool? onlyWithPhoto,
    int? maxDistanceKm,
    bool clearDistance = false,
    String? relationshipGoal,
    bool clearGoal = false,
    String? smoking,
    bool clearSmoking = false,
    String? drinking,
    bool clearDrinking = false,
    String? educationLevel,
    bool clearEducation = false,
    String? ethnicity,
    bool clearEthnicity = false,
    String? religion,
    bool clearReligion = false,
    bool? verifiedOnly,
    int? minHeight,
    int? maxHeight,
    Set<String>? dealbreakers,
    bool? sortByVisualReference,
    String? promptQuery,
  }) {
    return FeedFilters(
      minAge: minAge ?? this.minAge,
      maxAge: maxAge ?? this.maxAge,
      showGenders: showGenders ?? this.showGenders,
      onlyWithPhoto: onlyWithPhoto ?? this.onlyWithPhoto,
      maxDistanceKm:
          clearDistance ? null : (maxDistanceKm ?? this.maxDistanceKm),
      relationshipGoal:
          clearGoal ? null : (relationshipGoal ?? this.relationshipGoal),
      smoking: clearSmoking ? null : (smoking ?? this.smoking),
      drinking: clearDrinking ? null : (drinking ?? this.drinking),
      educationLevel:
          clearEducation ? null : (educationLevel ?? this.educationLevel),
      ethnicity: clearEthnicity ? null : (ethnicity ?? this.ethnicity),
      religion: clearReligion ? null : (religion ?? this.religion),
      verifiedOnly: verifiedOnly ?? this.verifiedOnly,
      minHeight: minHeight ?? this.minHeight,
      maxHeight: maxHeight ?? this.maxHeight,
      dealbreakers: dealbreakers ?? this.dealbreakers,
      sortByVisualReference:
          sortByVisualReference ?? this.sortByVisualReference,
      promptQuery: promptQuery ?? this.promptQuery,
    );
  }

  /// Claves de "no negociable" de los filtros de Plus.
  static const Set<String> plusKeys = <String>{
    kGoal,
    kSmoking,
    kDrinking,
    kEducation,
    kHeight,
    kEthnicity,
    kReligion,
    kVerified,
  };

  /// ¿Hay algún filtro de Plus puesto?
  bool get hasPlusFilters =>
      relationshipGoal != null ||
      smoking != null ||
      drinking != null ||
      educationLevel != null ||
      ethnicity != null ||
      religion != null ||
      verifiedOnly ||
      _heightActive;

  /// Los mismos filtros SIN los de Plus: es lo que se aplica cuando el plan no
  /// los incluye. Antes, si Plus caducaba con la app abierta, los "no
  /// negociables" avanzados seguían excluyendo gente hasta reiniciar; y con
  /// los filtros ya guardados, habrían seguido para siempre. Lo guardado NO se
  /// borra: si vuelve a Plus, vuelven sus filtros.
  FeedFilters withoutPlus() {
    if (!hasPlusFilters && !dealbreakers.any(plusKeys.contains)) return this;
    return FeedFilters(
      minAge: minAge,
      maxAge: maxAge,
      showGenders: showGenders,
      onlyWithPhoto: onlyWithPhoto,
      maxDistanceKm: maxDistanceKm,
      dealbreakers: dealbreakers.difference(plusKeys),
      sortByVisualReference: sortByVisualReference,
      promptQuery: promptQuery,
    );
  }

  /// Lo que se guarda en `preferences.feedFilters`. Sin edad ni distancia (van
  /// en sus propias claves de `preferences`) ni búsquedas IA.
  Map<String, dynamic> toSavedMap() => <String, dynamic>{
        'v': 1,
        'showGenders': showGenders.toList()..sort(),
        'onlyWithPhoto': onlyWithPhoto,
        'relationshipGoal': relationshipGoal,
        'smoking': smoking,
        'drinking': drinking,
        'educationLevel': educationLevel,
        'ethnicity': ethnicity,
        'religion': religion,
        'verifiedOnly': verifiedOnly,
        'minHeight': minHeight,
        'maxHeight': maxHeight,
        'dealbreakers': dealbreakers.toList()..sort(),
      };

  /// Filtros de arranque de un usuario, desde lo que tiene guardado.
  ///
  /// [saved] es `preferences.feedFilters`; [maxDistanceKm] y
  /// [preferredAgeMin]/[preferredAgeMax], las claves de `preferences` que
  /// escribe el onboarding. Lectura TOLERANTE: `users/{uid}` no valida tipos en
  /// las reglas, así que un valor raro cuenta como ausente en vez de tumbar el
  /// feed.
  factory FeedFilters.fromPreferences({
    Map<String, dynamic>? saved,
    int? maxDistanceKm,
    int? preferredAgeMin,
    int? preferredAgeMax,
  }) {
    final Map<String, dynamic> s = saved ?? const <String, dynamic>{};
    String? str(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
    int? integer(Object? v) => v is num && v.isFinite ? v.toInt() : null;
    Set<String> strings(Object? v) => v is List
        ? v.whereType<String>().where((String e) => e.isNotEmpty).toSet()
        : <String>{};
    final ({int min, int max}) age =
        clampAgeRange(preferredAgeMin, preferredAgeMax);
    final int minH =
        (integer(s['minHeight']) ?? heightFloor).clamp(heightFloor, heightCeil);
    final int maxH =
        (integer(s['maxHeight']) ?? heightCeil).clamp(minH, heightCeil);
    return FeedFilters(
      minAge: age.min,
      maxAge: age.max,
      showGenders: strings(s['showGenders']),
      onlyWithPhoto: s['onlyWithPhoto'] == true,
      maxDistanceKm: maxDistanceKm?.clamp(distanceFloor, distanceCeil),
      relationshipGoal: str(s['relationshipGoal']),
      smoking: str(s['smoking']),
      drinking: str(s['drinking']),
      educationLevel: str(s['educationLevel']),
      ethnicity: str(s['ethnicity']),
      religion: str(s['religion']),
      verifiedOnly: s['verifiedOnly'] == true,
      minHeight: minH,
      maxHeight: maxH,
      dealbreakers: strings(s['dealbreakers']),
    );
  }

  /// Rango de edad válido: nunca por debajo de 18 (el rango es una
  /// preferencia, no una puerta a menores), nunca por encima de [ageCeil] y
  /// con min <= max. Lo que falte, abierto. Misma regla que `loadCriteria` del
  /// directo (functions/src/live.ts).
  static ({int min, int max}) clampAgeRange(int? min, int? max) {
    final int lo = (min ?? ageFloor).clamp(ageFloor, ageCeil);
    final int hi = (max ?? ageCeil).clamp(lo, ageCeil);
    return (min: lo, max: hi);
  }

  /// ¿Cabe [age] en el rango? [ageCeil] se lee como "80 o más": el slider no
  /// llega más allá y no puede dejar fuera a quien tiene 81.
  static bool ageInRange(int age, int min, int max) {
    if (age < math.max(min, ageFloor)) return false;
    return max >= ageCeil || age <= max;
  }
}
