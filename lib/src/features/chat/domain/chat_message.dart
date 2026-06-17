import 'package:cloud_firestore/cloud_firestore.dart';

/// Tipo de mensaje. Arrancamos con texto; image/system para el futuro;
/// like_context/attra_context son el mensaje de apertura que lleva el comentario
/// inicial de un like/Attra a una foto al chat recien creado.
enum MessageType {
  text('text'),
  image('image'),
  bombImage('bomb_image'),
  voiceNote('voice_note'),
  system('system'),
  likeContext('like_context'),
  attraContext('attra_context'),
  dateProposal('date_proposal');

  const MessageType(this.wireName);

  final String wireName;

  bool get isContext =>
      this == MessageType.likeContext || this == MessageType.attraContext;

  bool get isDateProposal => this == MessageType.dateProposal;

  bool get isImage => this == MessageType.image;

  bool get isBombImage => this == MessageType.bombImage;

  bool get isVoiceNote => this == MessageType.voiceNote;

  bool get isMedia => isImage || isBombImage || isVoiceNote;

  static MessageType fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final MessageType type in MessageType.values) {
      if (type.wireName == raw || type.name == raw) {
        return type;
      }
    }
    return MessageType.text;
  }
}

/// Ciclo de vida de entrega/lectura de un mensaje.
enum MessageStatus {
  sending('sending'),
  sent('sent'),
  delivered('delivered'),
  read('read'),
  deleted('deleted'),
  reported('reported');

  const MessageStatus(this.wireName);

  final String wireName;

  static MessageStatus fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final MessageStatus status in MessageStatus.values) {
      if (status.wireName == raw || status.name == raw) {
        return status;
      }
    }
    return MessageStatus.sent;
  }
}

/// Estado de una propuesta de cita.
enum DateProposalStatus {
  pending('pending'),
  accepted('accepted'),
  declined('declined'),
  countered('countered');

  const DateProposalStatus(this.wireName);

  final String wireName;

  static DateProposalStatus fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final DateProposalStatus s in DateProposalStatus.values) {
      if (s.wireName == raw || s.name == raw) return s;
    }
    return DateProposalStatus.pending;
  }
}

/// Estado de una foto bomba: una imagen que el receptor solo puede abrir una
/// vez. La URL real no se persiste en el mensaje.
class BombInfo {
  const BombInfo({
    required this.state,
    this.viewedBy,
    this.viewedAt,
  });

  final String state;
  final String? viewedBy;
  final DateTime? viewedAt;

  bool get isViewed => state == 'viewed' || viewedAt != null;

  factory BombInfo.fromMap(Map<String, dynamic> map) {
    return BombInfo(
      state: (map['state'] as String?) ?? 'unopened',
      viewedBy: map['viewedBy'] as String?,
      viewedAt: ChatMessage._asDate(map['viewedAt']),
    );
  }
}

/// Propuesta de cita dentro de un mensaje `date_proposal`. Modelo extensible:
/// hoy solo se propone y se responde dentro del chat (sin reservas reales).
class DateProposal {
  const DateProposal({
    required this.proposedDate,
    required this.proposedTime,
    required this.placeName,
    required this.status,
    this.placeAddress = '',
    this.note = '',
    this.proposedBy = '',
  });

  final String proposedDate; // ISO yyyy-MM-dd
  final String proposedTime; // HH:mm
  final String placeName;
  final String placeAddress;
  final String note;
  final DateProposalStatus status;
  final String proposedBy;

  bool get isPending => status == DateProposalStatus.pending;

  factory DateProposal.fromMap(Map<String, dynamic> map) {
    return DateProposal(
      proposedDate: (map['proposedDate'] as String?) ?? '',
      proposedTime: (map['proposedTime'] as String?) ?? '',
      placeName: (map['placeName'] as String?) ?? '',
      placeAddress: (map['placeAddress'] as String?) ?? '',
      note: (map['note'] as String?) ?? '',
      status: DateProposalStatus.fromValue(map['status']),
      proposedBy: (map['proposedBy'] as String?) ?? '',
    );
  }
}

/// Metadatos de un adjunto (imagen o nota de voz). NO contiene rutas locales
/// del dispositivo: solo `storagePath` (en Firebase Storage) y `downloadUrl`.
class MediaInfo {
  const MediaInfo({
    required this.storagePath,
    required this.downloadUrl,
    required this.mimeType,
    this.sizeBytes = 0,
    this.width,
    this.height,
    this.durationMs,
    this.thumbnailUrl,
    this.fileName,
  });

  final String storagePath;
  final String downloadUrl;
  final String mimeType;
  final int sizeBytes;
  final int? width;
  final int? height;
  final int? durationMs;
  final String? thumbnailUrl;
  final String? fileName;

  factory MediaInfo.fromMap(Map<String, dynamic> map) {
    int? asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : null);
    return MediaInfo(
      storagePath: (map['storagePath'] as String?) ?? '',
      downloadUrl: (map['downloadUrl'] as String?) ?? '',
      mimeType: (map['mimeType'] as String?) ?? '',
      sizeBytes: asInt(map['sizeBytes']) ?? 0,
      width: asInt(map['width']),
      height: asInt(map['height']),
      durationMs: asInt(map['durationMs']),
      thumbnailUrl: map['thumbnailUrl'] as String?,
      fileName: map['fileName'] as String?,
    );
  }
}

/// Un mensaje dentro de `chats/{chatId}/messages/{messageId}`.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.type,
    required this.text,
    required this.status,
    this.mediaUrl,
    this.relatedLikeId,
    this.relatedPhotoId,
    this.relatedPhotoUrlSnapshot,
    this.relatedPhotoDeleted = false,
    this.dateProposal,
    this.media,
    this.bomb,
    this.createdAt,
    this.deliveredAt,
    this.readAt,
    this.editedAt,
    this.deletedAt,
  });

  final String id;
  final String senderId;
  final String receiverId;
  final MessageType type;
  final String text;
  final MessageStatus status;
  final String? mediaUrl;

  // Contexto de like a foto (solo en mensajes like_context/attra_context).
  final String? relatedLikeId;
  final String? relatedPhotoId;
  final String? relatedPhotoUrlSnapshot;
  final bool relatedPhotoDeleted;

  /// Solo en mensajes `date_proposal`.
  final DateProposal? dateProposal;

  /// Solo en mensajes `image` / `voice_note`.
  final MediaInfo? media;

  /// Solo en mensajes `bomb_image`.
  final BombInfo? bomb;

  final DateTime? createdAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;

  bool get isDeleted => status == MessageStatus.deleted || deletedAt != null;

  factory ChatMessage.fromMap(String id, Map<String, dynamic> map) {
    return ChatMessage(
      id: id,
      senderId: (map['senderId'] as String?) ?? '',
      receiverId: (map['receiverId'] as String?) ?? '',
      type: MessageType.fromValue(map['type']),
      text: (map['text'] as String?) ?? '',
      status: MessageStatus.fromValue(map['status']),
      mediaUrl: map['mediaUrl'] as String?,
      relatedLikeId: map['relatedLikeId'] as String?,
      relatedPhotoId: map['relatedPhotoId'] as String?,
      relatedPhotoUrlSnapshot: map['relatedPhotoUrlSnapshot'] as String?,
      relatedPhotoDeleted: (map['relatedPhotoDeleted'] as bool?) ?? false,
      dateProposal: map['dateProposal'] is Map
          ? DateProposal.fromMap((map['dateProposal'] as Map)
              .map((dynamic k, dynamic v) => MapEntry(k.toString(), v)))
          : null,
      media: map['media'] is Map
          ? MediaInfo.fromMap((map['media'] as Map)
              .map((dynamic k, dynamic v) => MapEntry(k.toString(), v)))
          : null,
      bomb: map['bomb'] is Map
          ? BombInfo.fromMap((map['bomb'] as Map)
              .map((dynamic k, dynamic v) => MapEntry(k.toString(), v)))
          : null,
      createdAt: _asDate(map['createdAt']),
      deliveredAt: _asDate(map['deliveredAt']),
      readAt: _asDate(map['readAt']),
      editedAt: _asDate(map['editedAt']),
      deletedAt: _asDate(map['deletedAt']),
    );
  }

  /// Payload de creacion (texto). El backend pone createdAt/status finales.
  Map<String, dynamic> toCreateMap() {
    return <String, dynamic>{
      'senderId': senderId,
      'receiverId': receiverId,
      'type': type.wireName,
      'text': text,
      'status': status.wireName,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
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
