import 'package:cloud_firestore/cloud_firestore.dart';

/// Mensaje de un chat de grupo (`friendGroups/{groupId}/messages/{id}`).
/// El nombre del emisor se denormaliza para no tener que resolver perfiles.
class GroupMessage {
  const GroupMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    this.createdAt,
  });

  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime? createdAt;

  factory GroupMessage.fromMap(String id, Map<String, dynamic> map) {
    return GroupMessage(
      id: id,
      senderId: (map['senderId'] ?? '').toString(),
      senderName: (map['senderName'] ?? '').toString(),
      text: (map['text'] ?? '').toString(),
      createdAt: _asDate(map['createdAt']),
    );
  }

  static DateTime? _asDate(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }
}
