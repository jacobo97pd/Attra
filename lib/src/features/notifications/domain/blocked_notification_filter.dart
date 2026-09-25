import 'app_notification.dart';

/// Esconde de la bandeja lo que viene de alguien bloqueado. Puro/testeable.
///
/// El backend borra estas notificaciones al bloquear, pero las anteriores a
/// ese arreglo (y las que se crucen con el bloqueo) seguían diciendo "X te ha
/// escrito" o "¡Nuevo match con X!" con nombre y vista previa, y al tocarlas
/// llevaban a un chat que ya no existe para ti. El bloqueo promete que no
/// volveréis a veros en la app.
///
/// Se identifica a la otra persona por lo que el backend guarda en `data`:
/// `fromUid` (likes y Attras), `matchId` (match, Spark) o `chatId` (mensajes).
/// `matchId` y `chatId` son el mismo id de pareja que el chat bloqueado.
class BlockedNotificationFilter {
  const BlockedNotificationFilter({
    this.blockedUids = const <String>{},
    this.blockedPairIds = const <String>{},
  });

  /// Personas bloqueadas (en cualquier sentido que el cliente pueda ver).
  final Set<String> blockedUids;

  /// Ids de pareja (match/chat) en estado bloqueado.
  final Set<String> blockedPairIds;

  static const BlockedNotificationFilter none = BlockedNotificationFilter();

  bool hides(AppNotification n) {
    String field(String key) => (n.data[key] ?? '').toString().trim();
    final String fromUid = field('fromUid');
    final String matchId = field('matchId');
    final String chatId = field('chatId');
    return (fromUid.isNotEmpty && blockedUids.contains(fromUid)) ||
        (matchId.isNotEmpty && blockedPairIds.contains(matchId)) ||
        (chatId.isNotEmpty && blockedPairIds.contains(chatId));
  }

  List<AppNotification> apply(Iterable<AppNotification> items) =>
      items.where((AppNotification n) => !hides(n)).toList(growable: false);
}
