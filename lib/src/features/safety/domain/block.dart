import 'package:cloud_firestore/cloud_firestore.dart';

import '../../match/domain/pair_id.dart';

/// Bloqueo de un usuario sobre otro. Cierra match/chat existentes y evita
/// futuros matches y mensajes. El `id` es direccional (`blocker_blocked`).
class Block {
  const Block({
    required this.blockerUid,
    required this.blockedUid,
    this.matchId,
    this.chatId,
    this.createdAt,
  });

  final String blockerUid;
  final String blockedUid;
  final String? matchId;
  final String? chatId;
  final DateTime? createdAt;

  static String idFor(String blockerUid, String blockedUid) =>
      directedId(blockerUid, blockedUid);

  String get id => idFor(blockerUid, blockedUid);

  factory Block.fromMap(Map<String, dynamic> map) {
    return Block(
      blockerUid: (map['blockerUid'] as String?) ?? '',
      blockedUid: (map['blockedUid'] as String?) ?? '',
      matchId: map['matchId'] as String?,
      chatId: map['chatId'] as String?,
      createdAt: _asDate(map['createdAt']),
    );
  }

  Map<String, dynamic> toCreateMap() {
    return <String, dynamic>{
      'blockerUid': blockerUid,
      'blockedUid': blockedUid,
      if (matchId != null) 'matchId': matchId,
      if (chatId != null) 'chatId': chatId,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  static DateTime? _asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }
}
