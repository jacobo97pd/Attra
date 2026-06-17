import 'package:cloud_firestore/cloud_firestore.dart';

import 'pair_id.dart';

/// Tipo de intencion: like normal o Attra (like destacado, consumible premium).
enum LikeType {
  like('like'),
  attra('attra');

  const LikeType(this.wireName);

  final String wireName;

  bool get isAttra => this == LikeType.attra;

  static LikeType fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final LikeType type in LikeType.values) {
      if (type.wireName == raw || type.name == raw) {
        return type;
      }
    }
    return LikeType.like;
  }
}

/// Ciclo de vida de un like.
enum LikeStatus {
  active('active'),
  matched('matched'),
  cancelled('cancelled'),
  expired('expired');

  const LikeStatus(this.wireName);

  final String wireName;

  static LikeStatus fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final LikeStatus status in LikeStatus.values) {
      if (status.wireName == raw || status.name == raw) {
        return status;
      }
    }
    return LikeStatus.active;
  }
}

/// A que responde el like: al perfil entero, a una foto concreta o a un prompt.
/// Si no se especifica, es `profile` (compatibilidad con likes existentes).
enum LikeTargetType {
  profile('profile'),
  photo('photo'),
  prompt('prompt'),
  story('story');

  const LikeTargetType(this.wireName);

  final String wireName;

  static LikeTargetType fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final LikeTargetType type in LikeTargetType.values) {
      if (type.wireName == raw || type.name == raw) {
        return type;
      }
    }
    return LikeTargetType.profile;
  }
}

/// Estado del comentario asociado al like.
enum CommentStatus {
  none('none'),
  active('active'),
  flagged('flagged'),
  removed('removed');

  const CommentStatus(this.wireName);

  final String wireName;

  static CommentStatus fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final CommentStatus status in CommentStatus.values) {
      if (status.wireName == raw || status.name == raw) {
        return status;
      }
    }
    return CommentStatus.none;
  }
}

/// Estado de moderacion del comentario.
enum CommentModerationStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected');

  const CommentModerationStatus(this.wireName);

  final String wireName;

  static CommentModerationStatus fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final CommentModerationStatus status
        in CommentModerationStatus.values) {
      if (status.wireName == raw || status.name == raw) {
        return status;
      }
    }
    return CommentModerationStatus.approved;
  }
}

/// Intencion unilateral de A hacia B. `id` es determinista (`from_to`) para
/// que un emisor no pueda duplicar su like sobre el mismo receptor.
///
/// Puede dirigirse a una foto concreta ([targetPhotoId]) y llevar un comentario
/// ([commentText]). Si no, es un like al perfil sin comentario (como antes).
class Like {
  const Like({
    required this.fromUid,
    required this.toUid,
    required this.type,
    required this.status,
    this.targetType = LikeTargetType.profile,
    this.targetPhotoId,
    this.targetPhotoUrlSnapshot,
    this.targetPhotoBlurHash,
    this.targetPhotoDeleted = false,
    this.relatedStoryId,
    this.targetPromptQuestion,
    this.targetPromptAnswer,
    this.commentText,
    this.commentStatus = CommentStatus.none,
    this.commentModerationStatus = CommentModerationStatus.approved,
    this.senderIsPlus = false,
    this.senderIsPro = false,
    this.priorityReason,
    this.compatibilityScore,
    this.senderActivityScore,
    this.senderLastActiveAt,
    this.createdAt,
    this.matchedAt,
  });

  final String fromUid;
  final String toUid;
  final LikeType type;
  final LikeStatus status;

  // Objetivo del like (foto/perfil/prompt) + snapshot resistente a borrado.
  final LikeTargetType targetType;
  final String? targetPhotoId;
  final String? targetPhotoUrlSnapshot;
  final String? targetPhotoBlurHash;
  final bool targetPhotoDeleted;

  /// Story de origen si el like vino de una story (targetType == story).
  final String? relatedStoryId;

  /// Snapshot del prompt al que respondió (targetType == prompt).
  final String? targetPromptQuestion;
  final String? targetPromptAnswer;

  // Comentario opcional asociado.
  final String? commentText;
  final CommentStatus commentStatus;
  final CommentModerationStatus commentModerationStatus;

  /// Snapshot no sensible del tier del emisor cuando se envio el like. Se usa
  /// solo para ordenar la bandeja; si falta, el like queda como normal.
  final bool senderIsPlus;
  final bool senderIsPro;
  final String? priorityReason;

  /// Señales opcionales/futuras. Fase 3 las respeta si existen, pero no depende
  /// de Fase 5 para funcionar.
  final double? compatibilityScore;
  final double? senderActivityScore;
  final DateTime? senderLastActiveAt;

  final DateTime? createdAt;
  final DateTime? matchedAt;

  /// ID determinista del documento en `likes/`.
  static String idFor(String fromUid, String toUid) =>
      directedId(fromUid, toUid);

  String get id => idFor(fromUid, toUid);

  bool get hasComment => (commentText ?? '').trim().isNotEmpty;
  bool get isPhotoTarget => targetType == LikeTargetType.photo;
  bool get isStoryTarget => targetType == LikeTargetType.story;
  bool get isPromptTarget => targetType == LikeTargetType.prompt;
  bool get isAttra => type.isAttra;

  String get effectivePriorityReason {
    if (type.isAttra) return 'attra';
    if (senderIsPro) return 'pro';
    if (senderIsPlus) return 'plus';
    final String raw = (priorityReason ?? '').trim();
    return raw.isEmpty ? 'normal' : raw;
  }

  factory Like.fromMap(Map<String, dynamic> map) {
    return Like(
      fromUid: (map['fromUid'] as String?) ?? '',
      toUid: (map['toUid'] as String?) ?? '',
      type: LikeType.fromValue(map['type']),
      status: LikeStatus.fromValue(map['status']),
      targetType: LikeTargetType.fromValue(map['targetType']),
      targetPhotoId: map['targetPhotoId'] as String?,
      targetPhotoUrlSnapshot: map['targetPhotoUrlSnapshot'] as String?,
      targetPhotoBlurHash: map['targetPhotoBlurHash'] as String?,
      targetPhotoDeleted: (map['targetPhotoDeleted'] as bool?) ?? false,
      relatedStoryId: map['relatedStoryId'] as String?,
      targetPromptQuestion: map['targetPromptQuestion'] as String?,
      targetPromptAnswer: map['targetPromptAnswer'] as String?,
      commentText: map['commentText'] as String?,
      commentStatus: CommentStatus.fromValue(map['commentStatus']),
      commentModerationStatus:
          CommentModerationStatus.fromValue(map['commentModerationStatus']),
      senderIsPlus: _asBool(map['senderIsPlus']),
      senderIsPro: _asBool(map['senderIsPro']),
      priorityReason: map['priorityReason'] as String?,
      compatibilityScore: _asDouble(map['compatibilityScore']),
      senderActivityScore: _asDouble(map['senderActivityScore']),
      senderLastActiveAt: _asDate(map['senderLastActiveAt']),
      createdAt: _asDate(map['createdAt']),
      matchedAt: _asDate(map['matchedAt']),
    );
  }

  static bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static DateTime? _asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }
}
