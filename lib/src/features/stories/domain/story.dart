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

/// Historia de FOTO o VÍDEO, viva 72 h. `stories/{storyId}` (escritura solo
/// backend; la caducidad la fija STORY_TTL_MS en functions/src/stories.ts, que
/// es quien manda).
enum StoryMediaType {
  video('video'),
  image('image');

  const StoryMediaType(this.wireName);
  final String wireName;

  static StoryMediaType fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final StoryMediaType t in StoryMediaType.values) {
      if (t.wireName == raw || t.name == raw) return t;
    }
    return StoryMediaType.video;
  }
}

enum StoryOverlayType {
  text('text'),
  sticker('sticker');

  const StoryOverlayType(this.wireName);
  final String wireName;

  static StoryOverlayType fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final StoryOverlayType t in StoryOverlayType.values) {
      if (t.wireName == raw || t.name == raw) return t;
    }
    return StoryOverlayType.text;
  }
}

enum StoryOverlayAlign {
  left('left'),
  center('center'),
  right('right');

  const StoryOverlayAlign(this.wireName);
  final String wireName;

  static StoryOverlayAlign fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final StoryOverlayAlign a in StoryOverlayAlign.values) {
      if (a.wireName == raw || a.name == raw) return a;
    }
    return StoryOverlayAlign.center;
  }
}

class StoryOverlay {
  const StoryOverlay({
    required this.type,
    required this.text,
    this.x = 0.5,
    this.y = 0.5,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.colorValue = 0xFFFFFFFF,
    this.background = false,
    this.align = StoryOverlayAlign.center,
  });

  final StoryOverlayType type;
  final String text;
  final double x;
  final double y;
  final double scale;
  final double rotation;
  final int colorValue;
  final bool background;
  final StoryOverlayAlign align;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': type.wireName,
      'text': text,
      'x': x,
      'y': y,
      'scale': scale,
      'rotation': rotation,
      'color': colorValue,
      'background': background,
      'align': align.wireName,
    };
  }

  static StoryOverlay fromMap(Map<String, dynamic> map) {
    return StoryOverlay(
      type: StoryOverlayType.fromValue(map['type']),
      text: ((map['text'] as String?) ?? '').trim(),
      x: _asUnit(map['x'], 0.5),
      y: _asUnit(map['y'], 0.5),
      scale: _asDouble(map['scale'], 1.0).clamp(0.4, 3.0),
      rotation: _asDouble(map['rotation'], 0.0).clamp(-6.2832, 6.2832),
      colorValue: (map['color'] as num?)?.toInt() ?? 0xFFFFFFFF,
      background: (map['background'] as bool?) ?? false,
      align: StoryOverlayAlign.fromValue(map['align']),
    );
  }

  static double _asUnit(Object? value, double fallback) {
    final double v = value is num ? value.toDouble() : fallback;
    return v.clamp(0.0, 1.0);
  }

  static double _asDouble(Object? value, double fallback) {
    return value is num ? value.toDouble() : fallback;
  }
}

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
    this.mediaType = StoryMediaType.video,
    this.imagePath = '',
    this.imageUrl = '',
    this.caption = '',
    this.captionX = 0.5,
    this.captionY = 0.85,
    this.overlays = const <StoryOverlay>[],
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
  final StoryMediaType mediaType;
  final String imagePath;
  final String imageUrl;
  final String caption;
  final List<StoryOverlay> overlays;

  /// Posición NORMALIZADA (0..1) del texto superpuesto sobre el vídeo (editor
  /// tipo Instagram). Por defecto abajo-centrado. Compat: docs antiguos sin
  /// estos campos caen al default.
  final double captionX;
  final double captionY;

  final StoryStatus status;
  final StoryVisibility visibility;
  final int durationSeconds;
  final int viewsCount;
  final int repliesCount;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  bool get isVideo => mediaType == StoryMediaType.video;
  bool get isImage => mediaType == StoryMediaType.image;

  String get previewUrl {
    if (thumbnailUrl.isNotEmpty) return thumbnailUrl;
    if (isImage && imageUrl.isNotEmpty) return imageUrl;
    return '';
  }

  List<StoryOverlay> get visualOverlays {
    if (overlays.isNotEmpty) return overlays;
    if (caption.trim().isEmpty) return const <StoryOverlay>[];
    return <StoryOverlay>[
      StoryOverlay(
        type: StoryOverlayType.text,
        text: caption.trim(),
        x: captionX,
        y: captionY,
      ),
    ];
  }

  /// Visible de verdad: backend la marca active Y no ha caducado.
  bool get isLive {
    if (status != StoryStatus.active) return false;
    final DateTime? exp = expiresAt;
    return exp == null || exp.isAfter(DateTime.now());
  }

  factory Story.fromMap(String id, Map<String, dynamic> map) {
    final String videoUrl = (map['videoUrl'] as String?) ?? '';
    final String imageUrl = (map['imageUrl'] as String?) ?? '';
    final StoryMediaType rawMediaType =
        StoryMediaType.fromValue(map['mediaType']);
    final StoryMediaType mediaType = rawMediaType == StoryMediaType.video &&
            videoUrl.isEmpty &&
            imageUrl.isNotEmpty
        ? StoryMediaType.image
        : rawMediaType;
    final List<StoryOverlay> overlays =
        ((map['overlays'] as List<dynamic>?) ?? <dynamic>[])
            .whereType<Map>()
            .map((Map<dynamic, dynamic> raw) => StoryOverlay.fromMap(
                  raw.map(
                    (dynamic k, dynamic v) => MapEntry(k.toString(), v),
                  ),
                ))
            .where((StoryOverlay overlay) => overlay.text.isNotEmpty)
            .toList(growable: false);
    return Story(
      storyId: id,
      ownerUid: (map['ownerUid'] as String?) ?? '',
      displayName: (map['displayName'] as String?) ?? '',
      videoPath: (map['videoPath'] as String?) ?? '',
      thumbnailPath: (map['thumbnailPath'] as String?) ?? '',
      videoUrl: videoUrl,
      thumbnailUrl: (map['thumbnailUrl'] as String?) ?? '',
      mediaType: mediaType,
      imagePath: (map['imagePath'] as String?) ?? '',
      imageUrl: imageUrl,
      caption: (map['caption'] as String?) ?? '',
      overlays: overlays,
      captionX: _asUnit(map['captionX'], 0.5),
      captionY: _asUnit(map['captionY'], 0.85),
      status: StoryStatus.fromValue(map['status']),
      visibility: StoryVisibility.fromValue(map['visibility']),
      durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
      viewsCount: (map['viewsCount'] as num?)?.toInt() ?? 0,
      repliesCount: (map['repliesCount'] as num?)?.toInt() ?? 0,
      createdAt: _asDate(map['createdAt']),
      expiresAt: _asDate(map['expiresAt']),
    );
  }

  /// Lee un número en [0,1] con fallback (posición normalizada del texto).
  static double _asUnit(Object? value, double fallback) {
    final double v = value is num ? value.toDouble() : fallback;
    return v.clamp(0.0, 1.0);
  }

  static DateTime? _asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }
}
