import 'package:cloud_firestore/cloud_firestore.dart';

import '../../chat_game/domain/chat_game.dart';
import '../domain/chat.dart';
import '../domain/chat_message.dart';

/// Lecturas en vivo de chats y mensajes. SOLO lectura: enviar/leer pasa por
/// Cloud Functions (ChatService).
class ChatRepository {
  ChatRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _chats =>
      _firestore.collection('chats');

  /// Chats del usuario, ordenados por ultimo mensaje (cliente, sin indice).
  Stream<List<Chat>> observeChats(String uid) {
    return _chats
        .where('users', arrayContains: uid)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snap) {
      final List<Chat> items = snap.docs
          .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
              Chat.fromMap(d.id, d.data()))
          .where((Chat c) => c.status != ChatStatus.deleted)
          .toList(growable: true)
        ..sort((Chat a, Chat b) => _millis(b.lastMessageAt ?? b.createdAt)
            .compareTo(_millis(a.lastMessageAt ?? a.createdAt)));
      return items;
    });
  }

  Stream<Chat?> observeChatById(String chatId) {
    return _chats.doc(chatId).snapshots().map(
        (DocumentSnapshot<Map<String, dynamic>> d) =>
            d.exists ? Chat.fromMap(d.id, d.data()!) : null);
  }

  /// Mensajes de un chat en orden cronologico (orderBy de campo unico: no
  /// requiere indice compuesto).
  Stream<List<ChatMessage>> observeMessages(String chatId, {int limit = 100}) {
    return _chats
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .limitToLast(limit)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snap) => snap.docs
            .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                ChatMessage.fromMap(d.id, d.data()))
            .toList(growable: false));
  }

  /// Observa una sesión del "Duelo de Química" (lectura en vivo del estado y el
  /// resultado de la IA). Escritura solo backend.
  Stream<ChatGameSession?> observeGameSession(String chatId, String sessionId) {
    return _chats
        .doc(chatId)
        .collection('gameSessions')
        .doc(sessionId)
        .snapshots()
        .map((DocumentSnapshot<Map<String, dynamic>> snap) {
      final Map<String, dynamic>? data = snap.data();
      if (!snap.exists || data == null) return null;
      return ChatGameSession.fromMap(snap.id, data);
    });
  }

  static int _millis(DateTime? d) => d?.millisecondsSinceEpoch ?? 0;
}
