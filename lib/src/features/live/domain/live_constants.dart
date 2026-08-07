/// Constantes del contrato del FEED EN VIVO.
///
/// PORQUÉ están aquí y no repartidas por la UI: cliente y backend comparten
/// exactamente estos valores (`functions/src/live.ts`). Si divergen, el
/// cliente creería que la sesión sigue viva cuando el servidor ya la cerró (o
/// al revés), y el vídeo 1:1 con un desconocido seguiría abierto. Un único
/// sitio = una única verdad.
library;

/// Duración MÁXIMA de una sesión de vídeo (3 minutos).
const int kLiveSessionMaxMs = 3 * 60 * 1000;

/// Cada cuánto el cliente captura un fotograma del vídeo REMOTO para moderar.
const int kLiveSampleMs = 5000;

/// Duración del bloqueo temporal del vivo tras el 2.º strike (24 h).
const int kLiveStrikeBlockMs = 24 * 60 * 60 * 1000;

/// Número de strikes que provoca el bloqueo permanente del vivo.
const int kLiveMaxStrikes = 3;

/// Espejo tipado de las constantes del contrato.
///
/// Se exponen además como [Duration] porque el resto del cliente razona en
/// duraciones (timers, countdowns) y así evitamos conversiones a mano —que es
/// donde se cuelan los ceros de más— en cada pantalla.
class LiveConstants {
  const LiveConstants._();

  /// LIVE_SESSION_MAX_MS
  static const int sessionMaxMs = kLiveSessionMaxMs;

  /// LIVE_SAMPLE_MS
  static const int sampleMs = kLiveSampleMs;

  /// LIVE_STRIKE_BLOCK_MS
  static const int strikeBlockMs = kLiveStrikeBlockMs;

  /// LIVE_MAX_STRIKES
  static const int maxStrikes = kLiveMaxStrikes;

  /// Tope duro de la sesión: al vencer se cierra y se pide veredicto.
  static const Duration sessionMax = Duration(milliseconds: sessionMaxMs);

  /// Cadencia de muestreo de fotogramas remotos para SafeSearch.
  static const Duration sampleInterval = Duration(milliseconds: sampleMs);

  /// Bloqueo temporal del vivo (2.º strike).
  static const Duration strikeBlock = Duration(milliseconds: strikeBlockMs);

  /// Nº de fotogramas que cabe esperar en una sesión completa.
  ///
  /// El backend lo usa para detectar clientes que NO moderan (sospechosos):
  /// si alguien no envía NINGÚN fotograma en toda la sesión se anota, porque
  /// moderamos el flujo AJENO y silenciarlo es justo lo que haría un cliente
  /// modificado.
  static int expectedSamples(Duration elapsed) =>
      elapsed.inMilliseconds ~/ sampleMs;
}

/// Nombres EXACTOS de las colecciones del vivo en Firestore (attra-database).
///
/// Centralizados para que capa de datos, reglas y tests no se desincronicen
/// por una errata: un nombre mal escrito aquí no falla en compilación, falla
/// en producción con la cámara abierta.
class LiveCollections {
  const LiveCollections._();

  /// `liveQueue/{uid}` — cola de espera. Solo escribe el backend.
  static const String queue = 'liveQueue';

  /// `liveSessions/{sessionId}` — sessionId = pairId(uidA, uidB).
  static const String sessions = 'liveSessions';

  /// `liveSessions/{sessionId}/signals/{uid}` — señalización WebRTC.
  static const String signals = 'signals';

  /// `liveSessions/{sessionId}/verdicts/{uid}` — veredicto de cada uno.
  static const String verdicts = 'verdicts';

  /// `liveStrikes/{uid}` — sanciones de moderación del vivo.
  static const String strikes = 'liveStrikes';
}
