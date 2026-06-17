/// Filtros del feed (estilo Hinge). BÁSICOS (gratis): edad, géneros,
/// solo-con-foto, distancia. AVANZADOS (Plus): qué busca, tabaco, alcohol,
/// estudios, altura, etnicidad, religión, verificación.
///
/// "No negociable" (deal-breaker): cada filtro con valor solo EXCLUYE de verdad
/// si su clave está en [dealbreakers]; si no, es una preferencia blanda (no
/// excluye). El género ("mostrarme") y "solo con foto" siempre son duros.
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

  static const int ageFloor = 18;
  static const int ageCeil = 80;
  static const int heightFloor = 140;
  static const int heightCeil = 210;

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
    return n;
  }

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
    );
  }
}
