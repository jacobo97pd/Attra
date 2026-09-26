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

  /// Desde `blocks` con `blockerUid == yo`: a quién he bloqueado yo y el par.
  factory BlockedNotificationFilter.fromBlocks(
      Iterable<Map<String, dynamic>> docs) {
    final Set<String> uids = <String>{};
    final Set<String> pairs = <String>{};
    for (final Map<String, dynamic> d in docs) {
      final Object? blocked = d['blockedUid'];
      final Object? matchId = d['matchId'];
      if (blocked is String && blocked.isNotEmpty) uids.add(blocked);
      if (matchId is String && matchId.isNotEmpty) pairs.add(matchId);
    }
    return BlockedNotificationFilter(blockedUids: uids, blockedPairIds: pairs);
  }

  /// Desde `matches` en `blocked` donde estoy ([docsById]: id del par → doc).
  ///
  /// Es la fuente que cubre también a quien ME bloqueó (su documento de
  /// `blocks` no se puede leer desde este lado), y aunque no hubiera match:
  /// applyBlock escribe `users` en matches/{par} en todo bloqueo. Antes se
  /// miraban los chats, pero el chat de un par sin match se crea sin `users`,
  /// así que el Attra de quien te bloqueaba antes de hacer match seguía en la
  /// bandeja con su nombre.
  factory BlockedNotificationFilter.fromBlockedPairs(
    String uid,
    Map<String, Map<String, dynamic>> docsById,
  ) {
    final Set<String> uids = <String>{};
    final Set<String> pairs = <String>{};
    docsById.forEach((String id, Map<String, dynamic> data) {
      if (id.isNotEmpty) pairs.add(id);
      final Object? users = data['users'];
      if (users is! List) return;
      for (final Object? u in users) {
        if (u is String && u.isNotEmpty && u != uid) uids.add(u);
      }
    });
    return BlockedNotificationFilter(blockedUids: uids, blockedPairIds: pairs);
  }

  /// Lo bloqueado por cualquiera de las dos fuentes.
  BlockedNotificationFilter union(BlockedNotificationFilter other) =>
      BlockedNotificationFilter(
        blockedUids: <String>{...blockedUids, ...other.blockedUids},
        blockedPairIds: <String>{...blockedPairIds, ...other.blockedPairIds},
      );

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
