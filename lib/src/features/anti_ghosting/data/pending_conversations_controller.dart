import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../chat/data/chat_service.dart';
import '../../chat/domain/chat.dart';
import '../domain/conversation_turn.dart';

/// Observa los chats del usuario y expone cuántas conversaciones están
/// **esperando tu respuesta** (Attra Clear §2). Vive mientras la sesión esté
/// activa (lo crea HomeShell). Best-effort: si el stream falla, cuenta 0.
class PendingConversationsController extends ChangeNotifier {
  PendingConversationsController({
    required ChatService chatService,
    required String uid,
  }) : _uid = uid {
    _sub = chatService.observeChats(uid).listen(
      _onChats,
      onError: (Object _) {/* sin datos: 0 pendientes */},
    );
  }

  final String _uid;
  StreamSubscription<List<Chat>>? _sub;

  /// `waitingSince` (= lastMessageAt) de cada conversación donde TE TOCA.
  List<DateTime> _myTurnWaiting = const <DateTime>[];

  void _onChats(List<Chat> chats) {
    _myTurnWaiting = <DateTime>[
      for (final Chat c in chats)
        if (c.isMyTurn(_uid) && c.lastMessageAt != null) c.lastMessageAt!,
    ];
    notifyListeners();
  }

  /// Total de conversaciones donde te toca responder (sin filtro de edad).
  int get myTurnTotal => _myTurnWaiting.length;

  /// Nº de pendientes que cuentan para el límite suave: te toca responder Y han
  /// pasado al menos [maxAgeHours] horas desde el último mensaje (§2).
  int pendingCount(int maxAgeHours) =>
      countOlderThan(_myTurnWaiting, maxAgeHours);

  /// Lógica pura (testeable): cuántas fechas son al menos tan antiguas como
  /// [maxAgeHours] respecto a [now] (= now por defecto).
  static int countOlderThan(
    List<DateTime> waitingSince,
    int maxAgeHours, {
    DateTime? now,
  }) {
    final DateTime cutoff =
        (now ?? DateTime.now()).subtract(Duration(hours: maxAgeHours));
    return waitingSince.where((DateTime d) => !d.isAfter(cutoff)).length;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
