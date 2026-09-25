import 'package:cloud_firestore/cloud_firestore.dart';

import 'chat_message.dart';

/// Estado de un chat. `chatId == matchId` (relacion 1:1 con el match).
enum ChatStatus {
  active('active'),
  blocked('blocked'),
  closed('closed'),

  /// Match deshecho. Hoy `unmatch` escribe `closed` sin firmar el cierre (ver
  /// [Chat.isUnmatched]), pero se reconoce también el valor explícito: sin él,
  /// [fromValue] lo leería como `active` y volvería a abrir el composer de un
  /// chat muerto.
  unmatched('unmatched'),
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
    this.closedAt,
    this.closedByUserId,
    this.closedReason,
    this.closedMessage,
    this.hasDateProposal = false,
    this.dateProposalStatus,
    this.dateScheduledAt,
    this.dateFollowUpStatus,
    this.dateFollowUpAnswer,
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

  // Attra Clear §3: cierre con elegancia. Solo presentes si status == closed.
  final DateTime? closedAt;
  final String? closedByUserId;
  final String? closedReason;
  final String? closedMessage;

  // Attra Clear §6: follow-up post-cita.
  final bool hasDateProposal;
  final String? dateProposalStatus;
  final DateTime? dateScheduledAt;
  final String? dateFollowUpStatus;
  final String? dateFollowUpAnswer;

  /// True si toca mostrar "¿Cómo fue la cita?": cita aceptada, fecha conocida,
  /// follow-up pendiente y han pasado ≥24h desde la cita.
  bool isDateFollowUpDue([DateTime? now]) {
    if (dateFollowUpStatus != 'pending' || dateScheduledAt == null) {
      return false;
    }
    final DateTime ref = now ?? DateTime.now();
    return ref.isAfter(dateScheduledAt!.add(const Duration(hours: 24)));
  }

  /// True si fue cerrado con elegancia (cierre respetuoso) por algún usuario.
  bool get isGracefullyClosed =>
      status == ChatStatus.closed && closedByUserId != null;

  /// True si el cierre lo hizo [uid] (para mensajes "tú cerraste" vs "X cerró").
  bool closedByMe(String uid) => closedByUserId == uid;

  /// Match deshecho: `unmatch` cierra el chat SIN firmarlo (no deja
  /// `closedByUserId`), que es justo lo que lo distingue del cierre con
  /// elegancia.
  bool get isUnmatched =>
      status == ChatStatus.unmatched ||
      (status == ChatStatus.closed && closedByUserId == null);

  /// ¿Sale en la lista de Chats (y cuenta para "Tu turno")?
  ///
  /// La lista solo quitaba `deleted`, que el backend no escribe nunca, así que
  /// tras bloquear o deshacer el match la otra persona seguía ahí con su nombre
  /// y su foto, a menudo en "Matches nuevos", para LOS DOS. El bloqueo promete
  /// "no volveréis a veros en la app". Por eso:
  /// * `blocked`, `unmatched` y `deleted` no se listan nunca, para ninguno.
  /// * `closed` solo si es un cierre con elegancia: esa conversación está hecha
  ///   para quedarse, de solo lectura y con el mensaje de despedida, en
  ///   "Conversaciones" (es el archivo que ya pintaba la UI con su banner).
  bool get isListed {
    switch (status) {
      case ChatStatus.active:
        return true;
      case ChatStatus.closed:
        return isGracefullyClosed;
      case ChatStatus.blocked:
      case ChatStatus.unmatched:
      case ChatStatus.deleted:
        return false;
    }
  }

  /// ¿Se puede abrir el perfil del otro desde este chat? Lo mismo que listarlo:
  /// si el chat ya no se enseña (bloqueo, match deshecho) tampoco su cabecera
  /// debe llevar al perfil completo, aunque se llegue por un push o un enlace.
  bool get allowsProfileAccess => isListed;

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
      closedAt: _asDate(map['closedAt']),
      closedByUserId: map['closedByUserId'] as String?,
      closedReason: map['closedReason'] as String?,
      closedMessage: map['closedMessage'] as String?,
      hasDateProposal: (map['hasDateProposal'] as bool?) ?? false,
      dateProposalStatus: map['dateProposalStatus'] as String?,
      dateScheduledAt: _asDate(map['dateScheduledAt']),
      dateFollowUpStatus: map['dateFollowUpStatus'] as String?,
      dateFollowUpAnswer: map['dateFollowUpAnswer'] as String?,
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
