import '../../chat/domain/chat.dart';
import '../../chat/domain/chat_message.dart';

/// Estado de "turno" de una conversación, **derivado** de los campos que el
/// backend ya escribe en `chats/{chatId}` (`status`, `lastMessageSenderId`,
/// `lastMessageType`, `lastMessageAt`). No requiere campos nuevos ni migración:
/// es la base de la bandeja "Tu turno" (Attra Clear, sección 1).
class TurnInfo {
  const TurnInfo({this.waitingForUid, this.waitingSince});

  /// Uid de quien debe responder. `null` = nadie está esperando (conversación
  /// sin mensajes reales, cerrada, bloqueada o eliminada).
  final String? waitingForUid;

  /// Momento desde el que se espera respuesta (= `lastMessageAt` del último
  /// mensaje real). `null` si no hay espera.
  final DateTime? waitingSince;

  /// Nadie debe responder (no cuenta como pendiente ni como ghosting).
  static const TurnInfo none = TurnInfo();

  bool get hasPendingTurn => waitingForUid != null;

  /// True si le toca responder a [uid] (es SU turno).
  bool isWaitingOn(String uid) => waitingForUid != null && waitingForUid == uid;

  /// Cuánto lleva esperando respuesta respecto a [now]. `null` si no hay espera.
  Duration? waitedFor(DateTime now) =>
      waitingSince == null ? null : now.difference(waitingSince!);
}

/// Deriva el [TurnInfo] de un [Chat] para el usuario [currentUid].
///
/// Reglas (Attra Clear §1):
/// * Solo conversaciones **activas** cuentan. `closed`/`blocked`/`deleted` →
///   nadie espera (no es ghosting).
/// * El último mensaje debe ser **real** (no `system` ni contexto de apertura).
/// * Si lo envió el OTRO → te toca a TI. Si lo enviaste TÚ → le toca al otro.
extension ConversationTurnX on Chat {
  TurnInfo turnFor(String currentUid) {
    if (status != ChatStatus.active) return TurnInfo.none;

    final String? lastSender = lastMessageSenderId;
    if (lastSender == null || lastSender.isEmpty || lastMessageAt == null) {
      return TurnInfo.none;
    }

    // Mensajes de sistema / contexto de apertura (like/attra) no abren turno.
    final MessageType? t = lastMessageType;
    if (t == MessageType.system || (t?.isContext ?? false)) {
      return TurnInfo.none;
    }

    final String other = otherUid(currentUid);
    if (other.isEmpty) return TurnInfo.none;

    final String waitingForUid = lastSender == currentUid ? other : currentUid;
    return TurnInfo(waitingForUid: waitingForUid, waitingSince: lastMessageAt);
  }

  /// Atajo: ¿es mi turno de responder en este chat?
  bool isMyTurn(String currentUid) => turnFor(currentUid).isWaitingOn(currentUid);
}

/// Formato humano de la espera para la UI ("hace 18 h", "hace 2 días").
/// Conciso y sin librerías externas; en español.
String formatWaiting(Duration d) {
  if (d.isNegative || d.inMinutes < 1) return 'ahora mismo';
  if (d.inMinutes < 60) {
    final int m = d.inMinutes;
    return 'hace $m min';
  }
  if (d.inHours < 24) {
    final int h = d.inHours;
    return 'hace $h h';
  }
  final int days = d.inDays;
  return 'hace $days ${days == 1 ? 'día' : 'días'}';
}
