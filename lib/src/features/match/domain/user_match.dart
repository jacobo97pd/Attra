import 'package:cloud_firestore/cloud_firestore.dart';

import 'like.dart';
import 'pair_id.dart';

/// Estado de una relacion de match (bilateral confirmada).
enum MatchStatus {
  active('active'),
  unmatched('unmatched'),
  blocked('blocked'),
  reported('reported'),
  deleted('deleted');

  const MatchStatus(this.wireName);

  final String wireName;

  bool get isActive => this == MatchStatus.active;

  static MatchStatus fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final MatchStatus status in MatchStatus.values) {
      if (status.wireName == raw || status.name == raw) {
        return status;
      }
    }
    return MatchStatus.active;
  }
}

/// Relacion bilateral confirmada entre dos usuarios. Se llama `UserMatch` (no
/// `Match`) para no chocar con el tipo `Match` de dart:core (regex).
///
/// `id`/`chatId` son deterministas ([pairId]) ⇒ idempotente, sin duplicados.
class UserMatch {
  const UserMatch({
    required this.id,
    required this.users,
    required this.userA,
    required this.userB,
    required this.status,
    required this.createdBy,
    required this.createdByAction,
    required this.hasAttra,
    this.attraSenderUid,
    this.chatId,
    this.originLikeId,
    this.originTargetType = LikeTargetType.profile,
    this.originPhotoId,
    this.originPhotoUrlSnapshot,
    this.originCommentText,
    this.journeyStatus,
    this.createdAt,
    this.updatedAt,
    this.lastMessageAt,
  });

  final String id;
  final List<String> users;
  final String userA;
  final String userB;
  final MatchStatus status;
  final String createdBy;
  final LikeType createdByAction;
  final bool hasAttra;
  final String? attraSenderUid;
  final String? chatId;

  // Origen del match (si nacio de un like a una foto con comentario).
  final String? originLikeId;
  final LikeTargetType originTargetType;
  final String? originPhotoId;
  final String? originPhotoUrlSnapshot;
  final String? originCommentText;
  final String? journeyStatus;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastMessageAt;

  bool get bornFromPhotoComment =>
      originTargetType == LikeTargetType.photo &&
      (originCommentText ?? '').trim().isNotEmpty;

  /// ID determinista del match/chat para el par (a, b).
  static String idFor(String a, String b) => pairId(a, b);

  /// El otro participante distinto de [uid].
  String otherUid(String uid) => userA == uid ? userB : userA;

  bool involves(String uid) => users.contains(uid);

  factory UserMatch.fromMap(String id, Map<String, dynamic> map) {
    return UserMatch(
      id: id,
      users: ((map['users'] as List<dynamic>?) ?? <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
      userA: (map['userA'] as String?) ?? '',
      userB: (map['userB'] as String?) ?? '',
      status: MatchStatus.fromValue(map['status']),
      createdBy: (map['createdBy'] as String?) ?? '',
      createdByAction: LikeType.fromValue(map['createdByAction']),
      hasAttra: (map['hasAttra'] as bool?) ?? false,
      attraSenderUid: map['attraSenderUid'] as String?,
      chatId: map['chatId'] as String?,
      originLikeId: map['originLikeId'] as String?,
      originTargetType: LikeTargetType.fromValue(map['originTargetType']),
      originPhotoId: map['originPhotoId'] as String?,
      originPhotoUrlSnapshot: map['originPhotoUrlSnapshot'] as String?,
      originCommentText: map['originCommentText'] as String?,
      journeyStatus: map['journeyStatus'] as String?,
      createdAt: _asDate(map['createdAt']),
      updatedAt: _asDate(map['updatedAt']),
      lastMessageAt: _asDate(map['lastMessageAt']),
    );
  }

  static DateTime? _asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }
}
