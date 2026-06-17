import 'package:cloud_firestore/cloud_firestore.dart';

/// Estado de una story. La autoridad es el backend; el cliente ademas oculta
/// las caducadas (expiresAt < now) aunque sigan `active`.
enum StoryStatus {
  active('active'),
  expired('expired'),
  deleted('deleted');

  const StoryStatus(this.wireName);
  final String wireName;

  static StoryStatus fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final StoryStatus s in StoryStatus.values) {
      if (s.wireName == raw || s.name == raw) return s;
    }
    return StoryStatus.active;
  }
}

/// A quien es visible la story.
enum StoryVisibility {
  discovery('discovery'),
  matches('matches');

  const StoryVisibility(this.wireName);
  final String wireName;

  static StoryVisibility fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final StoryVisibility v in StoryVisibility.values) {
      if (v.wireName == raw || v.name == raw) return v;
    }
    return StoryVisibility.discovery;
  }
}

/// Story de vídeo 24h. `stories/{storyId}` (escritura solo backend).
class Story {
  const Story({
    required this.storyId,
    required this.ownerUid,
    required this.displayName,
    required this.videoPath,
    required this.thumbnailPath,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.status,
    required this.visibility,
    this.caption = '',
    this.durationSeconds = 0,
    this.viewsCount = 0,
    this.repliesCount = 0,
    this.createdAt,
    this.expiresAt,
  });

  final String storyId;
  final String ownerUid;
  final String displayName;
  final String videoPath;
  final String thumbnailPath;
  final String videoUrl;
  final String thumbnailUrl;
  final String caption;
  final StoryStatus status;
  final StoryVisibility visibility;
  final int durationSeconds;
  final int viewsCount;
  final int repliesCount;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  /// Visible de verdad: backend la marca active Y no ha caducado.
  bool get isLive {
    if (status != StoryStatus.active) return false;
    final DateTime? exp = expiresAt;
    return exp == null || exp.isAfter(DateTime.now());
  }

  factory Story.fromMap(String id, Map<String, dynamic> map) {
    return Story(
      storyId: id,
      ownerUid: (map['ownerUid'] as String?) ?? '',
      displayName: (map['displayName'] as String?) ?? '',
      videoPath: (map['videoPath'] as String?) ?? '',
      thumbnailPath: (map['thumbnailPath'] as String?) ?? '',
      videoUrl: (map['videoUrl'] as String?) ?? '',
      thumbnailUrl: (map['thumbnailUrl'] as String?) ?? '',
      caption: (map['caption'] as String?) ?? '',
      status: StoryStatus.fromValue(map['status']),
      visibility: StoryVisibility.fromValue(map['visibility']),
      durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
      viewsCount: (map['viewsCount'] as num?)?.toInt() ?? 0,
      repliesCount: (map['repliesCount'] as num?)?.toInt() ?? 0,
      createdAt: _asDate(map['createdAt']),
      expiresAt: _asDate(map['expiresAt']),
    );
  }

  static DateTime? _asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }
}
