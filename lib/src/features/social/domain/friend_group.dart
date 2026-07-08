import 'package:cloud_firestore/cloud_firestore.dart';

/// Modo Amigos — grupo/plan social (`friendGroups/{groupId}`). Backend-
/// autoritativo: el cliente lee, y crear/unirse/responder pasa por Cloud
/// Functions. Nunca guarda ubicación exacta (solo ciudad/zona).
enum FriendGroupStatus {
  open('open'),
  full('full'),
  closed('closed');

  const FriendGroupStatus(this.wireName);
  final String wireName;

  bool get isJoinable => this == FriendGroupStatus.open;

  static FriendGroupStatus fromValue(Object? v) {
    final String raw = (v ?? '').toString().trim().toLowerCase();
    for (final FriendGroupStatus s in FriendGroupStatus.values) {
      if (s.wireName == raw || s.name.toLowerCase() == raw) return s;
    }
    return FriendGroupStatus.open;
  }
}

class FriendGroup {
  const FriendGroup({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.status,
    this.description = '',
    this.city = '',
    this.interests = const <String>[],
    this.memberIds = const <String>[],
    this.pendingIds = const <String>[],
    this.maxMembers = 8,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String description;
  final String city;
  final List<String> interests;
  final List<String> memberIds;
  final List<String> pendingIds;
  final int maxMembers;
  final String createdBy;
  final FriendGroupStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  int get memberCount => memberIds.length;
  bool get isFull => memberIds.length >= maxMembers;
  bool get isJoinable => status.isJoinable && !isFull;

  bool isMember(String uid) => memberIds.contains(uid);
  bool isPending(String uid) => pendingIds.contains(uid);
  bool isAdmin(String uid) => createdBy == uid;

  /// Estado del usuario respecto al grupo, para la UI.
  FriendGroupMembership membershipFor(String uid) {
    if (isMember(uid)) return FriendGroupMembership.member;
    if (isPending(uid)) return FriendGroupMembership.pending;
    return FriendGroupMembership.none;
  }

  factory FriendGroup.fromMap(String id, Map<String, dynamic> map) {
    List<String> strList(Object? v) => v is List
        ? v.map((Object? e) => e.toString()).toList()
        : const <String>[];
    return FriendGroup(
      id: id,
      name: (map['name'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      city: (map['city'] ?? '').toString(),
      interests: strList(map['interests']),
      memberIds: strList(map['memberIds']),
      pendingIds: strList(map['pendingIds']),
      maxMembers: map['maxMembers'] is num ? (map['maxMembers'] as num).toInt() : 8,
      createdBy: (map['createdBy'] ?? '').toString(),
      status: FriendGroupStatus.fromValue(map['status']),
      createdAt: _asDate(map['createdAt']),
      updatedAt: _asDate(map['updatedAt']),
    );
  }

  static DateTime? _asDate(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }
}

enum FriendGroupMembership { none, pending, member }
