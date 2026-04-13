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

class SeedProfile {
  const SeedProfile({
    required this.id,
    required this.displayName,
    required this.city,
    required this.bio,
    required this.isBot,
    required this.botProfileVersion,
    required this.botScenario,
    required this.seedQualityScore,
    required this.photos,
  });

  final String id;
  final String displayName;
  final String city;
  final String bio;
  final bool isBot;
  final int botProfileVersion;
  final String botScenario;
  final int seedQualityScore;
  final List<AdditionalPhoto> photos;

  factory SeedProfile.fromMap(String id, Map<String, dynamic> data) {
    final List<dynamic> rawPhotos =
        (data['photos'] as List<dynamic>?) ?? <dynamic>[];
    return SeedProfile(
      id: id,
      displayName: (data['displayName'] as String?) ?? 'Seed',
      city: (data['currentCity'] as String?) ?? '',
      bio: (data['bio'] as String?) ?? '',
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
