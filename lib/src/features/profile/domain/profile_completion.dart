class CompletionTask {
  const CompletionTask({
    required this.id,
    required this.label,
    required this.weight,
    required this.completed,
  });

  final String id;
  final String label;
  final int weight;
  final bool completed;
}

class ProfileCompletionResult {
  const ProfileCompletionResult({
    required this.percent,
    required this.pendingTaskLabels,
    required this.pendingTaskIds,
    required this.availableRewards,
  });

  final int percent;
  final List<String> pendingTaskLabels;
  final List<String> pendingTaskIds;
  final List<String> availableRewards;
}

class ProfileCompletionCalculator {
  static const List<_RewardMilestone> _milestones = <_RewardMilestone>[
    _RewardMilestone(id: 'profile_70', threshold: 70),
    _RewardMilestone(id: 'profile_80', threshold: 80),
    _RewardMilestone(id: 'profile_90', threshold: 90),
    _RewardMilestone(id: 'profile_100', threshold: 100),
  ];

  static ProfileCompletionResult calculate(Map<String, dynamic> userData) {
    final Map<String, dynamic> profile =
        _asMap(userData['profile'] as Map<dynamic, dynamic>?);
    final Map<String, dynamic> appearance =
        _asMap(userData['appearance'] as Map<dynamic, dynamic>?);
    final Map<String, dynamic> lifestyle =
        _asMap(userData['lifestyle'] as Map<dynamic, dynamic>?);
    final Map<String, dynamic> style =
        _asMap(userData['style'] as Map<dynamic, dynamic>?);
    final Map<String, dynamic> preferences =
        _asMap(userData['preferences'] as Map<dynamic, dynamic>?);
    final Map<String, dynamic> verification =
        _asMap(userData['verification'] as Map<dynamic, dynamic>?);
    final Map<String, dynamic> location =
        _asMap(userData['location'] as Map<dynamic, dynamic>?);

    final List<dynamic> rawPhotos =
        (userData['photos'] as List<dynamic>?) ?? <dynamic>[];
    final List<Map<String, dynamic>> photos = rawPhotos
        .whereType<Map>()
        .map((Map<dynamic, dynamic> e) => _asMap(e))
        .toList(growable: false);
    final List<dynamic> prompts =
        (profile['prompts'] as List<dynamic>?) ?? <dynamic>[];
    final List<dynamic> claimedRewards =
        (userData['profileCompletionRewardsClaimed'] as List<dynamic>?) ??
            <dynamic>[];

    final List<CompletionTask> tasks = <CompletionTask>[
      CompletionTask(
        id: 'live_selfie',
        label: 'Selfie principal verificada',
        weight: 20,
        completed: _isNonEmptyString(verification['liveSelfiePublicPhotoUrl']),
      ),
      CompletionTask(
        id: 'identity',
        label: 'Identidad basica completa',
        weight: 10,
        completed: _isNonEmptyString(profile['visibleName']) &&
            profile['birthDate'] != null &&
            _isNonEmptyString(profile['gender']) &&
            _isNonEmptyString(profile['birthCity']) &&
            _isNonEmptyString(profile['currentCity']) &&
            _hasAnyString(profile['languages']),
      ),
      CompletionTask(
        id: 'appearance',
        label: 'Apariencia completa',
        weight: 8,
        completed: appearance['heightCm'] != null &&
            _isNonEmptyString(appearance['eyeColor']) &&
            _isNonEmptyString(appearance['hairColor']) &&
            _isNonEmptyString(appearance['hairType']) &&
            _isNonEmptyString(appearance['bodyType']),
      ),
      CompletionTask(
        id: 'bio_intent',
        label: 'Bio e intencion de relacion',
        weight: 8,
        completed: _isNonEmptyString(profile['bio']) &&
            _isNonEmptyString(profile['relationshipIntent']),
      ),
      CompletionTask(
        id: 'lifestyle',
        label: 'Estilo de vida completo',
        weight: 6,
        completed: _isNonEmptyString(lifestyle['smoking']) &&
            _isNonEmptyString(lifestyle['drinking']) &&
            _isNonEmptyString(lifestyle['fitnessLevel']) &&
            _isNonEmptyString(lifestyle['wantsChildren']) &&
            _isNonEmptyString(lifestyle['socialStyle']) &&
            _isNonEmptyString(lifestyle['travelStyle']),
      ),
      CompletionTask(
        id: 'style_vibe',
        label: 'Estilo y vibe completos',
        weight: 4,
        completed: _hasAnyString(style['fashionStyle']) &&
            _hasAnyString(style['personalityTags']),
      ),
      CompletionTask(
        id: 'preferences_core',
        label: 'Preferencias principales definidas',
        weight: 4,
        completed: _hasAnyString(preferences['interestedIn']) &&
            preferences['preferredAgeMin'] != null &&
            preferences['preferredAgeMax'] != null &&
            preferences['maxDistanceKm'] != null,
      ),
      CompletionTask(
        id: 'location_permission_decision',
        label: 'Decision de ubicacion tomada',
        weight: 4,
        completed: _isNonEmptyString(location['permissionStatus']) &&
            (location['permissionStatus'] as String) != 'unknown',
      ),
      CompletionTask(
        id: 'location_coordinates',
        label: 'Ubicacion aproximada disponible',
        weight: 4,
        completed:
            location['latitude'] != null && location['longitude'] != null,
      ),
      CompletionTask(
        id: 'extra_photo_1',
        label: 'Sube 1 foto adicional',
        weight: 6,
        completed: photos.isNotEmpty,
      ),
      CompletionTask(
        id: 'extra_photo_3',
        label: 'Sube 3 fotos adicionales',
        weight: 8,
        completed: photos.length >= 3,
      ),
      CompletionTask(
        id: 'extra_photo_5',
        label: 'Sube 5 fotos adicionales',
        weight: 10,
        completed: photos.length >= 5,
      ),
      CompletionTask(
        id: 'optional_prompts',
        label: 'Anade prompts opcionales',
        weight: 8,
        completed: prompts
                .whereType<String>()
                .where((String e) => e.trim().isNotEmpty)
                .length >=
            2,
      ),
    ];

    final int score = tasks
        .where((CompletionTask t) => t.completed)
        .fold<int>(0, (int value, CompletionTask t) => value + t.weight);

    final int percent = score.clamp(0, 100);
    final List<String> pendingLabels = tasks
        .where((CompletionTask t) => !t.completed)
        .map((CompletionTask t) => t.label)
        .toList(growable: false);
    final List<String> pendingIds = tasks
        .where((CompletionTask t) => !t.completed)
        .map((CompletionTask t) => t.id)
        .toList(growable: false);
    final Set<String> claimedSet = claimedRewards.whereType<String>().toSet();
    final List<String> availableRewards = _milestones
        .where((_RewardMilestone m) =>
            percent >= m.threshold && !claimedSet.contains(m.id))
        .map((_RewardMilestone m) => m.id)
        .toList(growable: false);

    return ProfileCompletionResult(
      percent: percent,
      pendingTaskLabels: pendingLabels,
      pendingTaskIds: pendingIds,
      availableRewards: availableRewards,
    );
  }

  static Map<String, dynamic> _asMap(Map<dynamic, dynamic>? raw) {
    if (raw == null) {
      return <String, dynamic>{};
    }
    return raw.map((dynamic key, dynamic value) {
      return MapEntry(key.toString(), value);
    });
  }

  static bool _isNonEmptyString(dynamic value) {
    return value is String && value.trim().isNotEmpty;
  }

  static bool _hasAnyString(dynamic value) {
    if (value is! List) {
      return false;
    }
    return value.whereType<String>().any((String e) => e.trim().isNotEmpty);
  }
}

class _RewardMilestone {
  const _RewardMilestone({
    required this.id,
    required this.threshold,
  });

  final String id;
  final int threshold;
}
