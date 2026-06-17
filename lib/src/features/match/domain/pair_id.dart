/// IDs deterministas para el sistema de match/chat.
///
/// La clave de robustez del diseno: como los ids se derivan de los uids, las
/// operaciones son idempotentes y NUNCA se crean matches/chats duplicados,
/// aunque dos clientes disparen a la vez.
library;

/// ID simetrico para una relacion entre dos usuarios (match y chat comparten
/// id). Ordena los uids para que `pairId(a, b) == pairId(b, a)`.
String pairId(String a, String b) {
  return a.compareTo(b) <= 0 ? '${a}_$b' : '${b}_$a';
}

/// ID direccional para un like/dislike (de quien hacia quien). Permite que un
/// mismo emisor no duplique su intencion sobre el mismo receptor.
String directedId(String fromUid, String toUid) => '${fromUid}_$toUid';
