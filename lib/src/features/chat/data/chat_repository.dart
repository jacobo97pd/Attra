import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/async/shared_latest_stream.dart';
import '../../chat_game/domain/chat_game.dart';
import '../domain/chat.dart';
import '../domain/chat_message.dart';

/// Lecturas en vivo de chats y mensajes. SOLO lectura: enviar/leer pasa por
/// Cloud Functions (ChatService).
class ChatRepository {
  ChatRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  /// Un stream por uid (ver [shareLatest]): la lista de Chats lo pide dentro
  /// de build() y el contador de "Tu turno" lo escucha a la vez; así comparten
  /// las mismas dos escuchas y un repintado no las reabre.
  final Map<String, Stream<List<Chat>>> _chatLists =
      <String, Stream<List<Chat>>>{};

  CollectionReference<Map<String, dynamic>> get _chats =>
      _firestore.collection('chats');

  /// Chats del usuario, ordenados por ultimo mensaje (cliente, sin indice).
  ///
  /// Filtra aquí (y no solo en ChatsScreen) lo que no debe listarse
  /// ([Chat.listable]: bloqueados, matches deshechos): este stream también
  /// alimenta el contador de "Tu turno", y un bloqueado no puede contar como
  /// conversación pendiente. Misma instancia para el mismo uid.
  Stream<List<Chat>> observeChats(String uid) =>
      _chatLists.putIfAbsent(uid, () => shareLatest(() => _listedChats(uid)));

  /// Cruza los chats con los matches deshechos y emite cuando tiene los dos,
  /// para no enseñar un instante una fila que se va a quitar. Si la consulta de
  /// matches falla se sigue sin ella (queda [Chat.isListed], que ya aparta
  /// bloqueos y deshechos normales); un error de los chats sí llega a la lista.
  Stream<List<Chat>> _listedChats(String uid) {
    late final StreamController<List<Chat>> controller;
    StreamSubscription<List<Chat>>? chatsSub;
    StreamSubscription<Set<String>>? undoneSub;
    List<Chat>? chats;
    Set<String>? undone;

    void emitIfReady() {
      final List<Chat>? current = chats;
      final Set<String>? undoneIds = undone;
      if (current == null || undoneIds == null || controller.isClosed) return;
      controller.add(Chat.listable(current, undoneMatchIds: undoneIds)
        ..sort((Chat a, Chat b) => _millis(b.lastMessageAt ?? b.createdAt)
            .compareTo(_millis(a.lastMessageAt ?? a.createdAt))));
    }

    controller = StreamController<List<Chat>>(
      onListen: () {
        chatsSub = chatsSource(uid).listen(
          (List<Chat> value) {
            chats = value;
            emitIfReady();
          },
          onError: controller.addError,
          // Firestore cierra el stream tras un error: se cierra también aquí
          // para que el siguiente oyente vuelva a abrir la consulta.
          onDone: controller.close,
        );
        undoneSub = unmatchedPairsSource(uid).listen(
          (Set<String> value) {
            undone = value;
            emitIfReady();
          },
          onError: (Object error) {
            if (kDebugMode) debugPrint('ChatRepository: unmatched -> $error');
            undone ??= const <String>{};
            emitIfReady();
          },
        );
      },
      onCancel: () async {
        await chatsSub?.cancel();
        await undoneSub?.cancel();
      },
    );
    return controller.stream;
  }

  /// Todos los chats donde estoy, sin filtrar. Separado para probar el filtro
  /// de la lista sin Firestore.
  @visibleForTesting
  Stream<List<Chat>> chatsSource(String uid) => _chats
      .where('users', arrayContains: uid)
      .snapshots()
      .map((QuerySnapshot<Map<String, dynamic>> snap) => snap.docs
          .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
              Chat.fromMap(d.id, d.data()))
          .toList(growable: false));

  /// Ids de mis matches en `unmatched`. Es lo único que el chat no cuenta por
  /// sí mismo: tras "Cerrar con elegancia" + "Deshacer match" el chat se queda
  /// `closed` y firmado, igual que un archivo. `blocked` y `deleted` los
  /// escribe el backend también en el chat (misma transacción), así que
  /// [Chat.isListed] ya los aparta. Misma forma de consulta que observeMatches:
  /// no necesita índice compuesto.
  @visibleForTesting
  Stream<Set<String>> unmatchedPairsSource(String uid) => _firestore
      .collection('matches')
      .where('users', arrayContains: uid)
      .where('status', isEqualTo: 'unmatched')
      .snapshots()
      .map((QuerySnapshot<Map<String, dynamic>> snap) => snap.docs
          .map((QueryDocumentSnapshot<Map<String, dynamic>> d) => d.id)
          .toSet());

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
