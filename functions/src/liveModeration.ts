/// MODERACION DEL FEED EN VIVO (video 1:1 con desconocidos).
///
/// PORQUE ESTE FICHERO EXISTE Y COMO FUNCIONA
/// -----------------------------------------------------------------------
/// El video va PEER-TO-PEER (WebRTC): el servidor NO lo ve NUNCA. No hay
/// forma de que el backend inspeccione el stream, asi que la deteccion tiene
/// que nacer en el cliente. La decision de diseno clave es:
///
///   CADA CLIENTE MODERA EL FLUJO QUE **RECIBE**, NO EL QUE EMITE.
///
/// Si cada uno moderase su propio video, bastaria un cliente modificado (APK
/// parcheado) para desactivar la moderacion: el infractor simplemente no
/// enviaria fotogramas y nadie le denunciaria. Al moderar el flujo AJENO, el
/// infractor no puede impedir que su contraparte le denuncie: tendria que
/// controlar el movil de la victima, no el suyo.
///
/// El servidor sigue siendo la AUTORIDAD: recibe el fotograma, lo pasa por
/// Cloud Vision SafeSearch, y es el unico que escribe strikes y cierra
/// sesiones. El cliente nunca decide la sancion.
///
/// FICHERO HERMANO EN EL CLIENTE:
///   lib/src/features/live/domain/live_strikes.dart  (misma escalera)
///   lib/src/features/live/domain/live_constants.dart (mismas constantes)
/// Si tocas la politica aqui, tocala alli. Divergir = sancionar distinto en
/// cliente y servidor, que es peor que no sancionar.

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue, Timestamp, DocumentData } from "firebase-admin/firestore";
import { GoogleAuth } from "google-auth-library";
import { createHash } from "node:crypto";
import { REGION, db } from "./firebase";
import { col, requireAuthUid, requireStringArg } from "./common";
import { directedId } from "./ids";
import { createReport } from "./safety";

// ---------------------------------------------------------------------------
// CONSTANTES DEL CONTRATO
// Mismos nombres y valores en cliente (live_constants.dart) y backend.
// ---------------------------------------------------------------------------

/// Duracion MAXIMA de una sesion de video (3 min). Al vencer se cierra y se
/// pide veredicto.
export const LIVE_SESSION_MAX_MS = 3 * 60 * 1000;

/// Cada cuanto el cliente captura un fotograma del video REMOTO y lo manda a
/// `reviewLiveFrame`.
export const LIVE_SAMPLE_MS = 5000;

/// Bloqueo temporal del vivo tras el 2.o strike (24 h).
export const LIVE_STRIKE_BLOCK_MS = 24 * 60 * 60 * 1000;

/// Numero de strikes que provoca el bloqueo PERMANENTE del vivo.
export const LIVE_MAX_STRIKES = 3;

// ---------------------------------------------------------------------------
// LIMITES ANTI-ABUSO (no son parte del contrato con el cliente, son defensa)
// ---------------------------------------------------------------------------

/// Tamano maximo del fotograma YA DECODIFICADO. Un JPEG de 640x480 al 70% de
/// calidad pesa ~50 KB; 512 KB deja margen de sobra para HD sin permitir que
/// alguien nos suba video entero disfrazado de "fotograma".
export const LIVE_FRAME_MAX_BYTES = 512 * 1024;

/// Por debajo de esto no hay imagen que analizar (pixel transparente, basura).
/// Aceptarlo gastaria cuota de Vision para nada.
export const LIVE_FRAME_MIN_BYTES = 512;

/// Intervalo minimo entre fotogramas del MISMO llamante en la MISMA sesion.
/// El cliente muestrea cada 5 s; 2 s deja margen para jitter/reintentos y aun
/// asi impide inundar la API de Vision (que se paga por peticion).
export const LIVE_FRAME_MIN_INTERVAL_MS = 2000;

/// Tope duro de fotogramas por sesion y llamante. Una sesion completa da
/// 180s/5s = 36 muestras; 60 cubre reintentos y corta cualquier bucle.
export const LIVE_MAX_FRAMES_PER_SESSION = 60;

/// Margen de gracia sobre el tope de sesion para aceptar fotogramas tardios
/// (un POST en vuelo cuando la sesion vence). Fuera de esta ventana el
/// fotograma se rechaza: evita que alguien "reviva" una sesion cerrada para
/// fabricar strikes contra otra persona.
const LIVE_FRAME_GRACE_MS = 15 * 1000;

/// Reporter sintetico cuando la sancion la origina el sistema y no hay un
/// humano detras al que atribuir el reporte. `createReport` exige que
/// reporter != reportado, y un uid reservado nunca colisiona con uno real.
const LIVE_SYSTEM_REPORTER_UID = "system:live-moderation";

/// Motivo con el que entran los reportes automaticos en la cola de moderacion
/// (MISMA coleccion `reports` que `reportUser`; no duplicamos flujo).
const LIVE_REPORT_REASON = "live_video_sexual_content";

// ---------------------------------------------------------------------------
// COLECCIONES DEL VIVO
// Centralizadas aqui para no escribir strings sueltos. Los nombres son los del
// contrato y coinciden con `LiveCollections` del cliente.
// ---------------------------------------------------------------------------
export const liveCol = {
  queue: db.collection("liveQueue"),
  sessions: db.collection("liveSessions"),
  strikes: db.collection("liveStrikes"),
};

/// Subcoleccion de estado de moderacion POR LLAMANTE dentro de una sesion:
/// `liveSessions/{sessionId}/moderation/{callerUid}`.
/// Sirve para dos cosas: rate limit (contador transaccional) y cobertura
/// (saber quien NO esta moderando, ver `noteLiveModerationCoverage`).
const MODERATION_STATE_SUB = "moderation";

/// Auditoria de eventos relevantes: `liveSessions/{id}/moderationEvents/{auto}`.
/// NO se guarda la imagen (seria almacenar contenido potencialmente ilegal y
/// datos biometricos): solo el hash del fotograma y el veredicto de SafeSearch.
const MODERATION_EVENTS_SUB = "moderationEvents";

// ---------------------------------------------------------------------------
// 1) LOGICA PURA: interpretar la respuesta de SafeSearch
// Sin red, sin Firestore, sin auth -> testeable en aislamiento.
// ---------------------------------------------------------------------------

/// Escala de SafeSearch. `UNKNOWN` significa que Vision NO pudo decidir, no
/// que sea seguro: por eso vale 0 y se trata aparte (ver `interpretSafeSearch`).
const LIKELIHOOD_RANK: Record<string, number> = {
  UNKNOWN: 0,
  VERY_UNLIKELY: 1,
  UNLIKELY: 2,
  POSSIBLE: 3,
  LIKELY: 4,
  VERY_LIKELY: 5,
};

/// Umbral del contrato: `adult` o `racy` en LIKELY o VERY_LIKELY -> strike.
export const LIVE_SAFESEARCH_THRESHOLD = LIKELIHOOD_RANK.LIKELY;

/// Rango numerico de una likelihood. Valores desconocidos -> 0 (UNKNOWN).
export function likelihoodRank(value: unknown): number {
  const raw = (value ?? "").toString().trim().toUpperCase();
  return LIKELIHOOD_RANK[raw] ?? 0;
}

export type LiveFrameOutcome =
  /// Analizado y limpio.
  | "clean"
  /// Analizado y por encima del umbral -> strike.
  | "violation"
  /// NO se pudo analizar (Vision caida, API sin habilitar, respuesta rara).
  /// FAIL-CLOSED: se corta la sesion, pero NO se sanciona (ver abajo).
  | "unreviewable";

export interface LiveFrameDecision {
  outcome: LiveFrameOutcome;
  /// ¿Se incrementa `liveStrikes/{targetUid}.count`?
  strike: boolean;
  /// ¿Se cierra la sesion AHORA para ambos?
  endSession: boolean;
  /// Etiqueta para logs/auditoria y para el `reasons[]` del doc de strikes.
  reason: string;
  /// Likelihoods crudas (para la cola de moderacion humana).
  adult: string;
  racy: string;
  violence: string;
}

/// Interpreta el cuerpo JSON de `images:annotate` y decide si hay strike.
///
/// LOGICA PURA A PROPOSITO: es el corazon de la moderacion y es lo unico que
/// se puede testear sin credenciales ni red. Acepta `unknown` porque la
/// respuesta viene de fuera; `null`/`undefined` significa "la llamada fallo".
///
/// POLITICA ANTE FALLOS -> **FALLAR CERRANDO**:
///   - Si Vision NO esta habilitada en el proyecto, devuelve 403, se cae, o
///     manda algo que no sabemos leer, NO damos el fotograma por bueno.
///     Devolvemos `unreviewable` y el llamante CORTA la sesion.
///   - Pero NO ponemos strike: sancionar a alguien por una averia NUESTRA
///     seria injusto y ademas contaminaria la cola de moderacion humana.
///   Resumen: ante la duda se corta el video, no se castiga a la persona.
///   Lo que NUNCA hacemos es dejar pasar contenido sin revisar en silencio.
export function interpretSafeSearch(payload: unknown): LiveFrameDecision {
  const unreviewable = (reason: string): LiveFrameDecision => ({
    outcome: "unreviewable",
    strike: false,
    // Fail-closed: sin revision no hay video. El usuario ve "no hemos podido
    // verificar el contenido" y la sesion muere.
    endSession: true,
    reason,
    adult: "UNKNOWN",
    racy: "UNKNOWN",
    violence: "UNKNOWN",
  });

  if (payload === null || payload === undefined) {
    return unreviewable("vision_unavailable");
  }
  if (typeof payload !== "object") {
    return unreviewable("vision_malformed");
  }

  const responses = (payload as { responses?: unknown }).responses;
  if (!Array.isArray(responses) || responses.length === 0) {
    return unreviewable("vision_malformed");
  }
  const first = responses[0];
  if (!first || typeof first !== "object") {
    return unreviewable("vision_malformed");
  }

  // Vision devuelve 200 con un `error` por peticion cuando la imagen no se
  // pudo decodificar o falta permiso. Tambien es "sin revisar".
  const perRequestError = (first as { error?: unknown }).error;
  if (perRequestError && typeof perRequestError === "object") {
    return unreviewable("vision_request_error");
  }

  const annotation = (first as { safeSearchAnnotation?: unknown })
    .safeSearchAnnotation;
  if (!annotation || typeof annotation !== "object") {
    return unreviewable("vision_no_annotation");
  }

  const a = annotation as Record<string, unknown>;
  const adult = (a.adult ?? "UNKNOWN").toString().toUpperCase();
  const racy = (a.racy ?? "UNKNOWN").toString().toUpperCase();
  const violence = (a.violence ?? "UNKNOWN").toString().toUpperCase();

  const adultRank = likelihoodRank(adult);
  const racyRank = likelihoodRank(racy);

  // Si Vision no supo decidir NI adult NI racy, no hemos revisado nada.
  // Tratarlo como "limpio" seria exactamente el agujero que queremos evitar.
  if (adultRank === 0 && racyRank === 0) {
    return unreviewable("vision_unknown_verdict");
  }

  if (adultRank >= LIVE_SAFESEARCH_THRESHOLD || racyRank >= LIVE_SAFESEARCH_THRESHOLD) {
    return {
      outcome: "violation",
      strike: true,
      // El corte por moderacion es INMEDIATO para ambos (contrato).
      endSession: true,
      reason: adultRank >= racyRank ? "safesearch_adult" : "safesearch_racy",
      adult,
      racy,
      violence,
    };
  }

  return {
    outcome: "clean",
    strike: false,
    endSession: false,
    reason: "clean",
    adult,
    racy,
    violence,
  };
}

// ---------------------------------------------------------------------------
// 2) LOGICA PURA: escalera de sanciones
// Espejo EXACTO de LiveStrikePolicy.evaluate (live_strikes.dart).
// ---------------------------------------------------------------------------

export type LiveStrikeAction =
  | "none"
  | "warn_and_end"
  | "temporary_block"
  | "permanent_block";

export interface LiveStrikeDecision {
  action: LiveStrikeAction;
  /// Desde el PRIMER strike se corta la sesion, no solo se avisa.
  endSession: boolean;
  /// Fin del bloqueo temporal en epoch ms (null si no aplica).
  blockedUntilMs: number | null;
  permanentlyBlocked: boolean;
  /// Al 3.er strike entra en la MISMA cola que `reportUser`.
  reportToModeration: boolean;
}

/// Evalua el recuento TOTAL (acumulado, no incremental) de strikes.
///
/// Un `count` <= 0 nunca sanciona: un dato corrupto no puede castigar a nadie.
/// A partir de LIVE_MAX_STRIKES la sancion es permanente y no hay escalera mas
/// alla (un 4.o strike no "reinicia" nada).
export function evaluateLiveStrike(
  count: number,
  nowMs: number
): LiveStrikeDecision {
  if (!Number.isFinite(count) || count <= 0) {
    return {
      action: "none",
      endSession: false,
      blockedUntilMs: null,
      permanentlyBlocked: false,
      reportToModeration: false,
    };
  }

  if (count >= LIVE_MAX_STRIKES) {
    // Permanente SIN `blockedUntil` a proposito: una fecha de fin invitaria a
    // esperar a que caducara. El permanente solo lo levanta moderacion humana.
    return {
      action: "permanent_block",
      endSession: true,
      blockedUntilMs: null,
      permanentlyBlocked: true,
      reportToModeration: true,
    };
  }

  if (count === 1) {
    return {
      action: "warn_and_end",
      endSession: true,
      blockedUntilMs: null,
      permanentlyBlocked: false,
      reportToModeration: false,
    };
  }

  // count == 2 (y cualquier intermedio si algun dia sube LIVE_MAX_STRIKES).
  return {
    action: "temporary_block",
    endSession: true,
    blockedUntilMs: nowMs + LIVE_STRIKE_BLOCK_MS,
    permanentlyBlocked: false,
    reportToModeration: false,
  };
}

// ---------------------------------------------------------------------------
// 3) ESTADO DE SANCIONES (lectura) — util para el emparejador
// ---------------------------------------------------------------------------

export interface LiveStrikeStatus {
  count: number;
  blockedUntilMs: number | null;
  permanentlyBlocked: boolean;
  /// ¿Vetado del vivo AHORA? El bloqueo de 24 h CADUCA solo; los strikes no se
  /// borran, la sancion si vence.
  blocked: boolean;
}

function asInt(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value)) return Math.trunc(value);
  if (typeof value === "string") {
    const n = Number.parseInt(value.trim(), 10);
    return Number.isFinite(n) ? n : 0;
  }
  return 0;
}

function millisFromTimestampLike(value: unknown): number | null {
  if (!value) return null;
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "object" && value !== null) {
    const maybe = value as { toMillis?: unknown };
    if (typeof maybe.toMillis === "function") {
      const ms = (maybe.toMillis as () => unknown)();
      return typeof ms === "number" ? ms : null;
    }
  }
  return null;
}

export function strikeStatusFromData(
  data: DocumentData | undefined,
  nowMs: number
): LiveStrikeStatus {
  const permanentlyBlocked = data?.permanentlyBlocked === true;
  const blockedUntilMs = millisFromTimestampLike(data?.blockedUntil);
  return {
    count: asInt(data?.count),
    blockedUntilMs,
    permanentlyBlocked,
    blocked:
      permanentlyBlocked ||
      (blockedUntilMs !== null && nowMs < blockedUntilMs),
  };
}

/// Lee `liveStrikes/{uid}`. Documento inexistente = expediente limpio.
export async function readLiveStrikeStatus(
  uid: string,
  nowMs = Date.now()
): Promise<LiveStrikeStatus> {
  const snap = await liveCol.strikes.doc(uid).get();
  return strikeStatusFromData(snap.exists ? snap.data() : undefined, nowMs);
}

/// Puerta de entrada al vivo. La debe llamar el emparejador ANTES de meter a
/// nadie en `liveQueue`: un sancionado no puede volver a la cola por mucho que
/// su cliente lo pida (el chequeo del cliente es cortesia, esto es la defensa).
export async function assertLiveNotBlocked(uid: string): Promise<void> {
  const status = await readLiveStrikeStatus(uid);
  if (!status.blocked) return;
  if (status.permanentlyBlocked) {
    throw new HttpsError(
      "permission-denied",
      "Tu acceso al video en vivo esta bloqueado de forma permanente."
    );
  }
  throw new HttpsError(
    "permission-denied",
    "Tu acceso al video en vivo esta bloqueado temporalmente."
  );
}

// ---------------------------------------------------------------------------
// 4) applyLiveStrike — aplica la sancion de forma transaccional
// ---------------------------------------------------------------------------

export interface LiveStrikeOutcome extends LiveStrikeDecision {
  /// Recuento resultante tras el incremento.
  count: number;
  /// Id del reporte automatico creado (solo al 3.er strike).
  reportId: string | null;
}

/// Incrementa `liveStrikes/{uid}` y aplica la escalera del contrato:
///   1 -> aviso + corte de sesion
///   2 -> bloqueo del vivo 24 h
///   3 -> bloqueo permanente + reporte automatico a moderacion
///
/// TRANSACCIONAL porque dos fotogramas casi simultaneos (uno por cada
/// participante, o reintentos) podrian leer el mismo `count` y pisarse: sin
/// transaccion, dos infracciones contarian como una y la escalera se saltaria
/// un peldano.
export async function applyLiveStrike(params: {
  uid: string;
  reason: string;
  sessionId?: string | null;
  /// Quien detecto la infraccion (el OTRO participante). Se usa como reporter
  /// del reporte automatico para que moderacion sepa de donde sale.
  detectedByUid?: string | null;
}): Promise<LiveStrikeOutcome> {
  const { uid, reason } = params;
  const nowMs = Date.now();
  const ref = liveCol.strikes.doc(uid);

  const decision = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const prev = snap.exists ? snap.data() : undefined;
    const count = asInt(prev?.count) + 1;
    const d = evaluateLiveStrike(count, nowMs);

    // Historial acotado: interesa el motivo de las ultimas infracciones para
    // la revision humana, no un array que crezca sin limite.
    const prevReasons: string[] = Array.isArray(prev?.reasons)
      ? (prev?.reasons as unknown[]).map((r) => (r ?? "").toString())
      : [];
    const reasons = [...prevReasons, reason].slice(-20);

    // Un bloqueo permanente NUNCA se degrada a temporal: si ya lo estaba, sigue.
    const permanentlyBlocked =
      d.permanentlyBlocked || prev?.permanentlyBlocked === true;

    tx.set(
      ref,
      {
        uid,
        count,
        reasons,
        lastAt: FieldValue.serverTimestamp(),
        // En el permanente dejamos `blockedUntil` a null a proposito (ver
        // evaluateLiveStrike): no debe existir fecha de caducidad.
        blockedUntil: permanentlyBlocked
          ? null
          : d.blockedUntilMs !== null
            ? Timestamp.fromMillis(d.blockedUntilMs)
            : (prev?.blockedUntil ?? null),
        permanentlyBlocked,
        lastSessionId: params.sessionId ?? null,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return { ...d, count, permanentlyBlocked };
  });

  // Fuera de la transaccion: sacarle de la cola si queda bloqueado. Defensivo
  // (no deberia estar en cola durante una sesion), pero barato y evita que el
  // emparejador le asigne otra victima en el mismo segundo.
  if (decision.permanentlyBlocked || decision.blockedUntilMs !== null) {
    await liveCol.queue
      .doc(uid)
      .delete()
      .catch((e: unknown) => {
        console.error(`[live] no se pudo sacar de la cola a ${uid}: ${e}`);
      });
  }

  let reportId: string | null = null;
  if (decision.reportToModeration) {
    // Reutiliza la MISMA cola que `reportUser` (coleccion `reports`). No se
    // crea una cola paralela: moderacion humana mira un solo sitio.
    // El reporte automatico lo firma SIEMPRE el sistema, nunca la persona que
    // estaba al otro lado. La regla de `reports` concede lectura al
    // `reporterUid`, asi que atribuirselo a la victima le abriria el expediente
    // del infractor: su uid, cuantos strikes lleva y por que. Es un dato de
    // moderacion de un tercero. Quien lo detecto queda en el texto para el
    // equipo humano, que lee con Admin SDK y no pasa por las reglas.
    const detectedBy =
      params.detectedByUid && params.detectedByUid !== uid
        ? params.detectedByUid
        : null;
    try {
      reportId = await createReport({
        reporterUid: LIVE_SYSTEM_REPORTER_UID,
        reportedUid: uid,
        reason: LIVE_REPORT_REASON,
        details:
          `Bloqueo permanente automatico del video en vivo tras ` +
          `${decision.count} strikes. Ultimo motivo: ${reason}. ` +
          `Sesion: ${params.sessionId ?? "desconocida"}.` +
          (detectedBy ? ` Detectado en sesion con: ${detectedBy}.` : ""),
        matchId: null,
        chatId: null,
        messageId: null,
      });
    } catch (e) {
      // El bloqueo YA esta escrito. Si el reporte falla, el usuario sigue
      // bloqueado: nunca deshacemos la sancion por un fallo de la cola.
      console.error(`[live] fallo al crear reporte automatico de ${uid}: ${e}`);
    }
  }

  return { ...decision, reportId };
}

// ---------------------------------------------------------------------------
// 5) Cierre de sesion por moderacion
// ---------------------------------------------------------------------------

/// Cierra la sesion para AMBOS de forma inmediata.
///
/// `blockPair` decide si ademas se escribe DISLIKE MUTUO Y PERMANENTE. Se usa
/// la MISMA coleccion `dislikes` y los MISMOS ids deterministas que
/// `passProfile`; no se inventa nada nuevo.
///
/// Solo se bloquea ante una INFRACCION REAL: si alguien te ha ensenado
/// contenido sexual, lo ultimo que puede pasar es que el feed os vuelva a
/// emparejar. Pero cuando el corte viene de que NO PUDIMOS revisar (Vision
/// caida, API sin habilitar), la averia es NUESTRA: bloquear ahi condena a dos
/// personas legitimas a no volver a verse jamas, y el dislike es permanente y
/// silencioso, asi que ninguna de las dos sabria nunca por que. Se corta el
/// video, que para eso es fail-closed, y ahi acaba el castigo.
export async function endLiveSessionForModeration(params: {
  sessionId: string;
  users: string[];
  endedBy: string;
  reason: string;
  blockPair: boolean;
}): Promise<void> {
  const now = FieldValue.serverTimestamp();
  const batch = db.batch();

  batch.set(
    liveCol.sessions.doc(params.sessionId),
    {
      status: "ended",
      endedAt: now,
      endedBy: params.endedBy,
      // `endReason` del contrato. La UI lo lee para explicar el corte.
      endReason: "moderation",
      moderationReason: params.reason,
      updatedAt: now,
    },
    { merge: true }
  );

  const users = params.users.filter((u) => typeof u === "string" && u.length > 0);
  if (params.blockPair && users.length === 2) {
    const [a, b] = users;
    for (const [from, to] of [
      [a, b],
      [b, a],
    ]) {
      batch.set(
        col.dislikes.doc(directedId(from, to)),
        {
          fromUid: from,
          toUid: to,
          source: "live_moderation",
          createdAt: now,
        },
        { merge: true }
      );
    }
  }

  await batch.commit();
}

// ---------------------------------------------------------------------------
// 6) Cobertura de moderacion: quien NO esta moderando
// ---------------------------------------------------------------------------

/// Anota (NO corta) si algun participante no envio fotogramas.
///
/// Contrato: "un cliente que NO envia fotogramas durante toda la sesion es
/// sospechoso: el backend lo anota, no corta". PORQUE no cortamos: una red
/// mala, una camara tapada o un movil viejo producen el mismo sintoma que un
/// cliente parcheado, y castigar a la victima de una mala conexion seria peor
/// que el problema. Lo dejamos escrito para que se pueda auditar y, si el
/// patron se repite en un usuario, moderacion humana lo vea.
///
/// La debe llamar el codigo que CIERRA la sesion (live.ts), sea por salida,
/// timeout o veredicto.
export async function noteLiveModerationCoverage(
  sessionId: string
): Promise<void> {
  try {
    const sessionRef = liveCol.sessions.doc(sessionId);
    const [sessionSnap, stateSnap] = await Promise.all([
      sessionRef.get(),
      sessionRef.collection(MODERATION_STATE_SUB).get(),
    ]);
    if (!sessionSnap.exists) return;
    const data = sessionSnap.data() ?? {};
    const users: string[] = Array.isArray(data.users) ? data.users : [];
    if (users.length === 0) return;

    const startedAtMs =
      millisFromTimestampLike(data.startedAt) ??
      millisFromTimestampLike(data.createdAt);
    const endedAtMs = millisFromTimestampLike(data.endedAt) ?? Date.now();
    // Sin `startedAt` no hubo video: no hay nada que reprochar.
    if (startedAtMs === null) return;
    const elapsedMs = Math.max(0, Math.min(endedAtMs - startedAtMs, LIVE_SESSION_MAX_MS));
    const expected = Math.floor(elapsedMs / LIVE_SAMPLE_MS);

    const framesByUid: Record<string, number> = {};
    for (const doc of stateSnap.docs) {
      framesByUid[doc.id] = asInt(doc.data()?.frames);
    }

    const coverage: Record<string, unknown> = {};
    let anySuspicious = false;
    for (const uid of users) {
      const frames = framesByUid[uid] ?? 0;
      // Sospechoso solo si CABIA enviar fotogramas (>=2 esperados, o sea la
      // sesion duro al menos ~10 s) y no llego ninguno. Con menos margen
      // marcariamos como sospechosa cualquier sesion que se corta enseguida.
      const suspicious = expected >= 2 && frames === 0;
      if (suspicious) anySuspicious = true;
      coverage[uid] = { frames, expected, suspicious };
    }

    if (anySuspicious) {
      console.warn(
        `[live] cobertura de moderacion incompleta en ${sessionId}: ` +
          JSON.stringify(coverage)
      );
    }

    await sessionRef.set(
      {
        moderationCoverage: coverage,
        moderationCoverageSuspicious: anySuspicious,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  } catch (e) {
    // Nunca puede tumbar el cierre de la sesion: es telemetria de seguridad,
    // no una precondicion.
    console.error(`[live] noteLiveModerationCoverage(${sessionId}): ${e}`);
  }
}

// ---------------------------------------------------------------------------
// 7) Cloud Vision SafeSearch
// ---------------------------------------------------------------------------

/// Credenciales POR DEFECTO de la funcion (Application Default Credentials):
/// el service account de Cloud Run/Functions. No hay API key en el codigo ni
/// en el cliente; una key en el APK seria una key robada.
const visionAuth = new GoogleAuth({
  scopes: ["https://www.googleapis.com/auth/cloud-platform"],
});

const VISION_ENDPOINT = "https://vision.googleapis.com/v1/images:annotate";

/// Timeout de la llamada a Vision. Si tarda mas, la sesion ya habria avanzado
/// varios fotogramas: preferimos fallar (y cerrar) a acumular peticiones.
const VISION_TIMEOUT_MS = 8000;

/// Llama a SafeSearch. Devuelve el JSON crudo, o `null` si NO se pudo revisar
/// (red, 403 por API deshabilitada, permisos, timeout...). El `null` lo
/// interpreta `interpretSafeSearch` como fail-closed.
async function annotateFrame(contentBase64: string): Promise<unknown | null> {
  try {
    const token = await visionAuth.getAccessToken();
    if (!token) {
      console.error("[Vision] sin access token (ADC no disponible)");
      return null;
    }
    const res = await fetch(VISION_ENDPOINT, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        requests: [
          {
            image: { content: contentBase64 },
            features: [{ type: "SAFE_SEARCH_DETECTION" }],
          },
        ],
      }),
      signal: AbortSignal.timeout(VISION_TIMEOUT_MS),
    });
    if (!res.ok) {
      // Causa mas comun: `vision.googleapis.com` sin habilitar en el proyecto
      // (403 SERVICE_DISABLED) o el service account sin permiso. Se ve en los
      // logs de la funcion; mientras tanto la politica fail-closed corta las
      // sesiones, que es justo lo que queremos que se note.
      const body = await res.text().catch(() => "");
      console.error(
        `[Vision] safeSearch HTTP ${res.status}: ${body.slice(0, 300)}`
      );
      return null;
    }
    return await res.json();
  } catch (e) {
    console.error(`[Vision] safeSearch error: ${(e as Error).message}`);
    return null;
  }
}

// ---------------------------------------------------------------------------
// 8) reviewLiveFrame (callable)
// ---------------------------------------------------------------------------

/// Quita el prefijo `data:image/jpeg;base64,` si el cliente lo manda, y todo
/// el whitespace (algunos encoders parten en lineas de 76 chars).
function normalizeBase64(raw: string): string {
  const comma = raw.indexOf(",");
  const body = raw.startsWith("data:") && comma > 0 ? raw.slice(comma + 1) : raw;
  return body.replace(/\s+/g, "");
}

const BASE64_RE = /^[A-Za-z0-9+/]+={0,2}$/;

/// Bytes reales que representa una cadena base64 (sin decodificarla: para
/// rechazar por tamano ANTES de gastar memoria en el Buffer).
function base64ByteLength(b64: string): number {
  const padding = b64.endsWith("==") ? 2 : b64.endsWith("=") ? 1 : 0;
  return Math.floor((b64.length * 3) / 4) - padding;
}

/// `reviewLiveFrame`: el cliente manda un fotograma del video REMOTO.
///
/// Recuerda: `targetUid` es SIEMPRE el otro participante, nunca uno mismo.
/// Quien llama esta denunciando lo que VE, no lo que emite.
export const reviewLiveFrame = onCall(
  {
    region: REGION,
    // Un fotograma base64 de hasta 512 KB + overhead. El default de 256MiB no
    // da problema, pero la subida si necesita margen de payload.
    memory: "512MiB",
    timeoutSeconds: 30,
    // Es la funcion mas llamada de la app con diferencia: un fotograma cada 5 s
    // POR PARTICIPANTE. Con 20 sesiones en vivo son 8 llamadas/segundo, y con
    // el maxInstances global la moderacion se encolaria. Y encolarse aqui no es
    // lentitud: la politica es fallar cerrando, asi que un atasco corta
    // sesiones legitimas a mansalva.
    // 40 y no mas: cada instancia declarada consume cuota de CPU de la region
    // (CpuAllocPerProjectRegion), y pedir 100 aqui dejaba sin desplegar a esta
    // misma funcion. Con el vivo en dark launch no hay trafico todavia; cuando
    // se encienda, este es el numero que hay que revisar primero.
    maxInstances: 40,
  },
  async (request) => {
    const callerUid = requireAuthUid(request.auth);
    const sessionId = requireStringArg(request.data?.sessionId, "sessionId");
    const targetUid = requireStringArg(request.data?.targetUid, "targetUid");
    const rawImage = request.data?.imageBase64;

    if (callerUid === targetUid) {
      // Nadie se denuncia a si mismo: seria la via trivial para que un cliente
      // parcheado "gastase" strikes ajenos o falsease su propio expediente.
      throw new HttpsError("invalid-argument", "Parametro invalido.");
    }
    if (typeof rawImage !== "string" || rawImage.length === 0) {
      throw new HttpsError("invalid-argument", "Falta el parametro 'imageBase64'.");
    }

    const contentBase64 = normalizeBase64(rawImage);
    const bytes = base64ByteLength(contentBase64);
    if (bytes > LIVE_FRAME_MAX_BYTES) {
      throw new HttpsError("invalid-argument", "El fotograma es demasiado grande.");
    }
    if (bytes < LIVE_FRAME_MIN_BYTES) {
      throw new HttpsError("invalid-argument", "El fotograma no es valido.");
    }
    if (!BASE64_RE.test(contentBase64)) {
      // No mandamos basura a Vision: cada peticion se paga.
      throw new HttpsError("invalid-argument", "El fotograma no es valido.");
    }

    // --- Autorizacion: solo participantes de ESTA sesion -------------------
    const sessionRef = liveCol.sessions.doc(sessionId);
    const sessionSnap = await sessionRef.get();
    if (!sessionSnap.exists) {
      throw new HttpsError("not-found", "La sesion no existe.");
    }
    const session = sessionSnap.data() ?? {};
    const users: string[] = Array.isArray(session.users) ? session.users : [];
    if (!users.includes(callerUid)) {
      throw new HttpsError("permission-denied", "No perteneces a esta sesion.");
    }
    if (!users.includes(targetUid)) {
      // Blindaje del contrato: no se puede denunciar a alguien de OTRA sesion.
      // Sin esto, un cliente modificado podria fabricar strikes contra
      // cualquier uid de la app mandando porno con su nombre.
      throw new HttpsError("permission-denied", "El objetivo no esta en esta sesion.");
    }

    const status = (session.status ?? "").toString();
    if (status === "ended") {
      // Sesion cerrada: no se aceptan fotogramas tardios que puedan sancionar
      // a alguien por algo que ya no esta ocurriendo.
      return { ok: true, outcome: "ignored", reason: "session_ended" };
    }

    // Ventana temporal: solo fotogramas de una sesion en curso (o recien
    // vencida, por los POST en vuelo).
    const startedAtMs =
      millisFromTimestampLike(session.startedAt) ??
      millisFromTimestampLike(session.createdAt);
    const nowMs = Date.now();
    if (
      startedAtMs !== null &&
      nowMs > startedAtMs + LIVE_SESSION_MAX_MS + LIVE_FRAME_GRACE_MS
    ) {
      return { ok: true, outcome: "ignored", reason: "session_expired" };
    }

    // --- Rate limit por llamante y sesion ----------------------------------
    // Transaccional: dos peticiones simultaneas del mismo cliente no pueden
    // colarse las dos leyendo el mismo contador.
    const stateRef = sessionRef.collection(MODERATION_STATE_SUB).doc(callerUid);
    const allowed = await db.runTransaction(async (tx) => {
      const snap = await tx.get(stateRef);
      const data = snap.exists ? snap.data() : undefined;
      const frames = asInt(data?.frames);
      const lastAtMs = millisFromTimestampLike(data?.lastFrameAt);

      if (frames >= LIVE_MAX_FRAMES_PER_SESSION) return false;
      if (lastAtMs !== null && nowMs - lastAtMs < LIVE_FRAME_MIN_INTERVAL_MS) {
        return false;
      }

      tx.set(
        stateRef,
        {
          uid: callerUid,
          targetUid,
          frames: frames + 1,
          // Timestamp del servidor: el reloj del movil no manda aqui.
          lastFrameAt: FieldValue.serverTimestamp(),
          firstFrameAt: snap.exists
            ? (data?.firstFrameAt ?? FieldValue.serverTimestamp())
            : FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      return true;
    });

    if (!allowed) {
      // No es un error del usuario: su cliente va demasiado rapido. Se
      // responde 'throttled' y NO se gasta cuota de Vision.
      throw new HttpsError(
        "resource-exhausted",
        "Demasiados fotogramas; reduce la frecuencia."
      );
    }

    // --- Analisis ----------------------------------------------------------
    const raw = await annotateFrame(contentBase64);
    const decision = interpretSafeSearch(raw);

    // Hash del fotograma para trazabilidad SIN almacenar la imagen: guardar el
    // contenido seria conservar material potencialmente ilegal y ademas dato
    // biometrico (RGPD). El hash basta para correlacionar repeticiones.
    const frameHash = createHash("sha256")
      .update(contentBase64)
      .digest("hex")
      .slice(0, 32);

    if (decision.outcome !== "clean") {
      // Auditoria solo de lo relevante: escribir los ~36 fotogramas limpios de
      // cada sesion multiplicaria las escrituras sin aportar nada.
      await sessionRef
        .collection(MODERATION_EVENTS_SUB)
        .add({
          sessionId,
          reporterUid: callerUid,
          targetUid,
          outcome: decision.outcome,
          reason: decision.reason,
          adult: decision.adult,
          racy: decision.racy,
          violence: decision.violence,
          frameHash,
          frameBytes: bytes,
          createdAt: FieldValue.serverTimestamp(),
        })
        .catch((e: unknown) => {
          console.error(`[live] auditoria de moderacion fallida: ${e}`);
        });
    }

    if (decision.outcome === "clean") {
      return { ok: true, outcome: "clean", strike: false, endSession: false };
    }

    if (decision.outcome === "unreviewable") {
      // FAIL-CLOSED: no hemos podido revisar -> se corta el video, pero NADIE
      // recibe strike. Ver `interpretSafeSearch` para el razonamiento.
      await endLiveSessionForModeration({
        sessionId,
        users,
        endedBy: "system",
        reason: decision.reason,
        // Averia nuestra: se corta, pero no se bloquea a la pareja.
        blockPair: false,
      });
      return {
        ok: true,
        outcome: "unreviewable",
        strike: false,
        endSession: true,
        reason: decision.reason,
      };
    }

    // --- Infraccion: strike + corte inmediato para ambos -------------------
    const outcome = await applyLiveStrike({
      uid: targetUid,
      reason: decision.reason,
      sessionId,
      detectedByUid: callerUid,
    });

    await endLiveSessionForModeration({
      sessionId,
      users,
      endedBy: "system",
      reason: decision.reason,
      // Infraccion confirmada: aqui SI se bloquea la pareja.
      blockPair: true,
    });

    // Lo que devolvemos al DENUNCIANTE es deliberadamente escueto: saber el
    // recuento de strikes del otro es informacion sobre un tercero. Solo se le
    // dice que la sesion se ha cortado.
    return {
      ok: true,
      outcome: "violation",
      strike: true,
      endSession: true,
      reason: decision.reason,
      // Auditoria interna: no se expone `count` ni `reportId` al cliente.
      action: outcome.action === "none" ? "none" : "sanctioned",
    };
  }
);

// ---------------------------------------------------------------------------
// 9) getLiveStrikeStatus (callable) — el usuario puede ver SU expediente
// ---------------------------------------------------------------------------

/// Devuelve el estado de sanciones del PROPIO llamante (nunca el de otro).
/// La UI lo usa para explicar por que no puede entrar al vivo. No es la
/// defensa: la defensa es `assertLiveNotBlocked` en el emparejador.
export const getLiveStrikeStatus = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const status = await readLiveStrikeStatus(uid);
  return {
    count: status.count,
    blocked: status.blocked,
    permanentlyBlocked: status.permanentlyBlocked,
    blockedUntilMs: status.blockedUntilMs,
    maxStrikes: LIVE_MAX_STRIKES,
  };
});
