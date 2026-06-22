import 'package:cloud_firestore/cloud_firestore.dart';

import 'chat_message.dart';

/// Estado de un chat. `chatId == matchId` (relacion 1:1 con el match).
enum ChatStatus {
  active('active'),
  blocked('blocked'),
  closed('closed'),
  deleted('deleted');

  const ChatStatus(this.wireName);

  final String wireName;

  bool get isActive => this == ChatStatus.active;
  bool get canSendMessages => this == ChatStatus.active;

  static ChatStatus fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final ChatStatus status in ChatStatus.values) {
      if (status.wireName == raw || status.name == raw) {
        return status;
      }
    }
    return ChatStatus.active;
  }
}

/// Conversacion asociada a un match. Los contadores `unreadCountByUser` y
/// `typingByUser` se indexan por uid. El cliente NO los modifica a mano: los
/// gestiona el backend (sendMessage/markAsRead) para evitar manipulacion.
class Chat {
  const Chat({
    required this.id,
    required this.matchId,
    required this.users,
    required this.status,
    required this.unreadCountByUser,
    required this.typingByUser,
    this.manuallyUnreadByUser = const <String, bool>{},
    this.lastMessage,
    this.lastMessageType,
    this.lastMessageSenderId,
    this.journeyStatus,
    this.hasAttra = false,
    this.lastMessageAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String matchId;
  final List<String> users;
  final ChatStatus status;
  final Map<String, int> unreadCountByUser;
  final Map<String, bool> typingByUser;

  /// "Marcado como no leido" manualmente por cada participante. Independiente de
  /// unreadCount (que cuenta mensajes reales sin leer).
  final Map<String, bool> manuallyUnreadByUser;
  final String? lastMessage;
  final MessageType? lastMessageType;
  final String? lastMessageSenderId;
  final String? journeyStatus;
  final bool hasAttra;
  final DateTime? lastMessageAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String otherUid(String uid) =>
      users.firstWhere((String u) => u != uid, orElse: () => '');

  int unreadFor(String uid) => unreadCountByUser[uid] ?? 0;

  bool manuallyUnreadFor(String uid) => manuallyUnreadByUser[uid] ?? false;

  /// El chat se muestra como no leido si hay mensajes sin leer O el usuario lo
  /// marco manualmente como no leido.
  bool isUnreadFor(String uid) => unreadFor(uid) > 0 || manuallyUnreadFor(uid);

  bool isTyping(String uid) => typingByUser[uid] ?? false;

  bool get hasConversation => lastMessageAt != null;

  factory Chat.fromMap(String id, Map<String, dynamic> map) {
    return Chat(
      id: id,
      matchId: (map['matchId'] as String?) ?? id,
      users: ((map['users'] as List<dynamic>?) ?? <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
      status: ChatStatus.fromValue(map['status']),
      unreadCountByUser: _asIntMap(map['unreadCountByUser']),
      typingByUser: _asBoolMap(map['typingByUser']),
      manuallyUnreadByUser: _asBoolMap(map['manuallyUnreadByUser']),
      lastMessage: map['lastMessage'] as String?,
      lastMessageType: map['lastMessageType'] == null
          ? null
          : MessageType.fromValue(map['lastMessageType']),
      lastMessageSenderId: map['lastMessageSenderId'] as String?,
      journeyStatus: map['journeyStatus'] as String?,
      hasAttra: (map['hasAttra'] as bool?) ?? false,
      lastMessageAt: _asDate(map['lastMessageAt']),
      createdAt: _asDate(map['createdAt']),
      updatedAt: _asDate(map['updatedAt']),
    );
  }

  static Map<String, int> _asIntMap(Object? value) {
    if (value is Map) {
      return value.map((dynamic k, dynamic v) => MapEntry(
            k.toString(),
            v is int ? v : (v is num ? v.toInt() : 0),
          ));
    }
    return <String, int>{};
  }

  static Map<String, bool> _asBoolMap(Object? value) {
    if (value is Map) {
      return value.map(
          (dynamic k, dynamic v) => MapEntry(k.toString(), v is bool && v));
    }
    return <String, bool>{};
  }

  static DateTime? _asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }
}
