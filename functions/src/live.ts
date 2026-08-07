/// FEED EN VIVO — backend autoritativo del vídeo 1:1 con desconocidos.
///
/// PORQUE ASI: el vídeo va peer-to-peer (el servidor NUNCA lo ve), así que todo
/// lo que decide quién habla con quién, cuánto dura y quién queda bloqueado se
/// resuelve aquí con Admin SDK. El cliente solo:
///   - pide entrar/salir de la cola y pedir pareja (callables de este fichero),
///   - escribe SU documento de señalización WebRTC (reglas de Firestore),
///   - manda fotogramas del vídeo REMOTO a `reviewLiveFrame` (liveModeration.ts).
///
/// Reparto de ficheros del vivo:
///   - live.ts (aquí): cola, emparejamiento, sesión, veredictos y barrido.
///   - liveModeration.ts: SafeSearch, strikes y bloqueos. Este fichero NO
///     duplica nada de eso: importa `assertLiveNotBlocked`, `liveCol` y
///     `noteLiveModerationCoverage`.
///
/// Y reutiliza lo que ya existía en el proyecto:
///   - `pairId`/`directedId` (ids.ts) para ids deterministas,
///   - `writeMatchAndChat` (match.ts) para crear match+chat igual que el resto,
///   - `col`/`requireAuthUid` (common.ts), `createReport` (safety.ts),
///   - los MISMOS filtros duros del feed (FeedFilter/IntentCompatibility del
///     cliente), reimplantados aquí porque son Dart y no se pueden importar.
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { DocumentData, FieldValue, Timestamp } from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
import { directedId, pairId } from "./ids";
import { writeMatchAndChat } from "./match";
import { createReport } from "./safety";
import {
  col,
  isUserContactable,
  requireAuthUid,
  requireStringArg,
  senderPrioritySnapshot,
} from "./common";
import {
  LIVE_SESSION_MAX_MS,
  assertLiveNotBlocked,
  strikeStatusFromData,
  liveCol,
  noteLiveModerationCoverage,
} from "./liveModeration";

// ── Constantes propias del emparejamiento ───────────────────────────────────
// (LIVE_SESSION_MAX_MS, LIVE_SAMPLE_MS, LIVE_STRIKE_BLOCK_MS y LIVE_MAX_STRIKES
//  viven en liveModeration.ts: una sola fuente de verdad para el contrato.)

/// Tiempo máximo en 'ringing' (negociando WebRTC). Si en 60 s no hay conexión
/// se cierra: si no, un fallo de red deja a los dos "emparejados" para siempre
/// y ninguno de los dos puede volver a la cola.
const LIVE_RING_TIMEOUT_MS = 60 * 1000;
/// Una entrada de cola sin señales de vida (el cliente dejó de pedir pareja) se
/// considera abandonada: la app se cerró o el usuario se fue.
const LIVE_QUEUE_STALE_MS = 3 * 60 * 1000;
/// A partir de aquí una entrada 'paired' se revisa (y se borra si su sesión ya
/// no está viva). Es corto a propósito: mientras la entrada siga 'paired' el
/// usuario no puede volver a emparejarse.
const LIVE_PAIRED_REVIEW_MS = 30 * 1000;
/// Margen absoluto: pasada la duración máxima + 2 min, la entrada 'paired' se
/// borra pase lo que pase (su sesión no puede seguir viva).
const LIVE_PAIRED_STALE_MS = LIVE_SESSION_MAX_MS + 2 * 60 * 1000;
/// Tras hablar con alguien no se le vuelve a emparejar en 24 h aunque nadie
/// diera veredicto (si dieron 'pass' ya lo impide el dislike).
const LIVE_REPAIR_COOLDOWN_MS = 24 * 60 * 60 * 1000;
/// Ventana para votar después de que la sesión termine (la pantalla de
/// veredicto aparece al colgar; pasado este tiempo el veredicto ya no cuenta).
const LIVE_VERDICT_GRACE_MS = 10 * 60 * 1000;
/// Cuántas entradas de cola se leen por intento de emparejamiento.
const LIVE_CANDIDATE_SCAN = 40;
/// Cuántos candidatos se comprueban a fondo (bloqueos/match/dislikes/sesión).
const LIVE_CANDIDATE_CHECK = 5;
/// `lastSeenAt` solo se refresca cada 20 s: escribirlo en cada sondeo dispara
/// contención con la transacción de emparejamiento del otro lado.
const LIVE_SEEN_REFRESH_MS = 20 * 1000;

/// Subcolecciones de `liveSessions/{id}`. 'moderation' es el estado por
/// llamante de liveModeration.ts (contador de fotogramas para el rate limit):
/// se nombra aquí porque al REUTILIZAR un sessionId (es determinista, pairId)
/// hay que borrar el estado de la sesión anterior. Si se dejara, un contador
/// de fotogramas agotado dejaría la nueva sesión SIN moderación.
const SUB_SIGNALS = "signals";
const SUB_VERDICTS = "verdicts";
const SUB_MODERATION = "moderation";

type LiveVerdict = "like" | "pass";
type LiveEndReason =
  | "left"
  | "timeout"
  | "reported"
  | "moderation"
  | "matched";

// ── Utilidades de lectura tolerante ─────────────────────────────────────────
function asMap(value: unknown): DocumentData {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as DocumentData)
    : {};
}

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asStringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((v): v is string => typeof v === "string")
    .map((v) => v.trim())
    .filter((v) => v.length > 0);
}

function asInt(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  if (typeof value === "string") {
    const parsed = Number.parseInt(value, 10);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function millisOf(value: unknown): number | null {
  if (value instanceof Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (value && typeof value === "object" && "toMillis" in value) {
    const maybe = value as { toMillis?: unknown };
    if (typeof maybe.toMillis === "function") {
      const ms = maybe.toMillis();
      return typeof ms === "number" ? ms : null;
    }
  }
  if (typeof value === "string") {
    const ms = Date.parse(value);
    return Number.isNaN(ms) ? null : ms;
  }
  return null;
}

function ageFromBirthDate(value: unknown): number | null {
  const ms = millisOf(value);
  if (ms === null) return null;
  const birthDate = new Date(ms);
  const now = new Date();
  let age = now.getUTCFullYear() - birthDate.getUTCFullYear();
  const passed =
    now.getUTCMonth() > birthDate.getUTCMonth() ||
    (now.getUTCMonth() === birthDate.getUTCMonth() &&
      now.getUTCDate() >= birthDate.getUTCDate());
  if (!passed) age -= 1;
  if (age < 0 || age > 120) return null;
  return age;
}

/// Espejo EXACTO de `FeedFilter.canonCountry` (Dart). Se duplica porque el
/// filtro del feed vive en el cliente y no se puede importar desde TypeScript;
/// si allí se añade un alias, hay que añadirlo aquí o dos personas del mismo
/// país dejarán de verse en el vivo.
const COUNTRY_ALIASES: Record<string, string> = {
  "españa": "es",
  espana: "es",
  spain: "es",
  italia: "it",
  italy: "it",
  francia: "fr",
  france: "fr",
  portugal: "pt",
  alemania: "de",
  germany: "de",
  deutschland: "de",
  "reino unido": "gb",
  "united kingdom": "gb",
  inglaterra: "gb",
  "estados unidos": "us",
  "united states": "us",
  usa: "us",
  "méxico": "mx",
  mexico: "mx",
  argentina: "ar",
  brasil: "br",
  brazil: "br",
  "países bajos": "nl",
  "paises bajos": "nl",
  netherlands: "nl",
  "bélgica": "be",
  belgica: "be",
  belgium: "be",
  irlanda: "ie",
  ireland: "ie",
};

function canonCountry(raw: unknown): string {
  const s = asString(raw).toLowerCase();
  if (s.length === 0) return "";
  return COUNTRY_ALIASES[s] ?? s;
}

/// Espejo de `IntentMode.channels` (Dart). `groups` no participa en el feed de
/// personas → tampoco en el vivo (su superficie son los grupos).
function intentChannels(mode: string): Set<string> {
  switch (mode) {
    case "friends":
      return new Set(["friends"]);
    case "both":
      return new Set(["dating", "friends"]);
    case "groups":
      return new Set<string>();
    default:
      return new Set(["dating"]);
  }
}

function normalizeIntent(value: unknown): string {
  const raw = asString(value).toLowerCase();
  if (raw === "friends" || raw === "both" || raw === "groups") return raw;
  return "dating"; // usuarios antiguos sin campo = citas, como en el feed
}

// ── Criterios de emparejamiento ─────────────────────────────────────────────
interface LiveCriteria {
  uid: string;
  gender: string;
  interestedIn: string[];
  countryName: string;
  countryKey: string;
  intentMode: string;
  minAge: number;
  maxAge: number;
  age: number | null;
}

const AGE_FLOOR = 18;
const AGE_CEIL = 80;

/// Lee los criterios del PERFIL REAL (users/{uid}), nunca de lo que mande el
/// cliente: si el cliente pudiera declarar su género/edad/país, cualquiera se
/// colaría en colas donde no debería estar.
async function loadCriteria(uid: string): Promise<LiveCriteria> {
  const snap = await col.users.doc(uid).get();
  if (!isUserContactable(snap)) {
    throw new HttpsError(
      "failed-precondition",
      "Tu cuenta no puede usar el directo ahora mismo."
    );
  }
  const data = snap.data() ?? {};
  const profile = asMap(data.profile);
  const prefs = asMap(data.preferences);

  const minRaw = asInt(prefs.preferredAgeMin) ?? AGE_FLOOR;
  const maxRaw = asInt(prefs.preferredAgeMax) ?? AGE_CEIL;
  // Nunca por debajo de 18: el rango es una preferencia, no una puerta para
  // emparejar con menores.
  const minAge = Math.max(AGE_FLOOR, Math.min(minRaw, AGE_CEIL));
  const maxAge = Math.max(minAge, Math.min(maxRaw, AGE_CEIL));

  const countryName = asString(profile.currentCountryName);
  const criteria: LiveCriteria = {
    uid,
    gender: asString(profile.gender),
    interestedIn: asStringList(prefs.interestedIn),
    countryName,
    countryKey: canonCountry(countryName),
    intentMode: normalizeIntent(profile.intentMode),
    minAge,
    maxAge,
    age:
      asInt(profile.age) ??
      asInt(data.age) ??
      ageFromBirthDate(profile.birthDate ?? data.birthDate),
  };

  // Un perfil solo-`groups` no participa en el feed de personas ni en el vivo.
  if (intentChannels(criteria.intentMode).size === 0) {
    throw new HttpsError(
      "failed-precondition",
      "Tu modo actual (grupos) no participa en el directo."
    );
  }
  return criteria;
}

function criteriaFromQueueDoc(uid: string, data: DocumentData): LiveCriteria {
  const countryName = asString(data.countryName);
  return {
    uid,
    gender: asString(data.gender),
    interestedIn: asStringList(data.interestedIn),
    countryName,
    countryKey: asString(data.countryKey) || canonCountry(countryName),
    intentMode: normalizeIntent(data.intentMode),
    minAge: asInt(data.minAge) ?? AGE_FLOOR,
    maxAge: asInt(data.maxAge) ?? AGE_CEIL,
    age: asInt(data.age),
  };
}

/// Payload de la entrada de cola. `countryKey` y `age` NO están en el contrato
/// pero son necesarios: sin la clave canónica no se puede filtrar por país en
/// la consulta y sin la edad no se puede aplicar el rango del OTRO lado.
function queueDocFrom(c: LiveCriteria): DocumentData {
  const now = FieldValue.serverTimestamp();
  return {
    uid: c.uid,
    gender: c.gender,
    interestedIn: c.interestedIn,
    countryName: c.countryName,
    countryKey: c.countryKey,
    age: c.age,
    intentMode: c.intentMode,
    minAge: c.minAge,
    maxAge: c.maxAge,
    joinedAt: now,
    lastSeenAt: now,
    status: "waiting",
    pairedSessionId: null,
    pairedWith: null,
    pairedAt: null,
  };
}

/// MISMOS filtros duros que el feed (`FeedFilter.apply`):
///   1. intención: tiene que haber solape de canal (dating/friends),
///   2. país: nunca de otro país (permisivo si falta el dato en un lado),
///   3. género: solo cuando el solape es de DATING (en amistad da igual),
///   4. edad: el rango preferido de CADA uno debe incluir al otro.
/// Permisivo cuando falta el dato, igual que el feed: preferimos emparejar de
/// más que dejar la cola vacía por perfiles incompletos.
export function isLiveCompatible(a: LiveCriteria, b: LiveCriteria): boolean {
  if (a.uid === b.uid) return false;

  const chA = intentChannels(a.intentMode);
  const chB = intentChannels(b.intentMode);
  const shared = [...chA].filter((c) => chB.has(c));
  if (shared.length === 0) return false;

  if (
    a.countryKey.length > 0 &&
    b.countryKey.length > 0 &&
    a.countryKey !== b.countryKey
  ) {
    return false;
  }

  if (shared.includes("dating")) {
    const aWantsB =
      a.interestedIn.length === 0 ||
      b.gender.length === 0 ||
      a.interestedIn.includes(b.gender);
    const bWantsA =
      b.interestedIn.length === 0 ||
      a.gender.length === 0 ||
      b.interestedIn.includes(a.gender);
    if (!aWantsB || !bWantsA) return false;
  }

  if (b.age !== null && (b.age < a.minAge || b.age > a.maxAge)) return false;
  if (a.age !== null && (a.age < b.minAge || a.age > b.maxAge)) return false;

  return true;
}

// ── Cierre de sesión (único camino, para no dejar estado a medias) ──────────
interface CloseResult {
  closed: boolean;
  users: string[];
}

/// Cierra una sesión y limpia las entradas de cola que la referencian.
///
/// Transaccional: dos cierres simultáneos (colgar + barrido) no pueden dejar el
/// documento a medias, y solo se borra la entrada de cola que apunta a ESTA
/// sesión (si el usuario ya se volvió a encolar, su entrada NUEVA se respeta).
async function closeLiveSession(params: {
  sessionId: string;
  endedBy: string;
  endReason: LiveEndReason;
}): Promise<CloseResult> {
  const sessionRef = liveCol.sessions.doc(params.sessionId);
  const result = await db.runTransaction<CloseResult>(async (tx) => {
    const snap = await tx.get(sessionRef);
    if (!snap.exists) return { closed: false, users: [] };
    const data = snap.data() ?? {};
    const users = asStringList(data.users);
    if (asString(data.status) === "ended") return { closed: false, users };

    const queueSnaps = await Promise.all(
      users.map((u) => tx.get(liveCol.queue.doc(u)))
    );

    const now = FieldValue.serverTimestamp();
    tx.update(sessionRef, {
      status: "ended",
      endedAt: now,
      endedBy: params.endedBy,
      endReason: params.endReason,
      updatedAt: now,
    });
    for (const qs of queueSnaps) {
      if (qs.exists && asString(qs.data()?.pairedSessionId) === params.sessionId) {
        tx.delete(qs.ref);
      }
    }
    return { closed: true, users };
  });

  if (result.closed) {
    // Contrato de moderación: anotar (NO cortar) a quien no envió fotogramas.
    // Es telemetría de seguridad y nunca puede tumbar el cierre, por eso va
    // fuera de la transacción y ya captura sus propios errores.
    await noteLiveModerationCoverage(params.sessionId);
  }
  return result;
}

// ── 1. joinLiveQueue ────────────────────────────────────────────────────────
export const joinLiveQueue = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  // Puerta de entrada: un sancionado no vuelve a la cola por mucho que su
  // cliente lo pida (el chequeo del cliente es cortesía, esto es la defensa).
  await assertLiveNotBlocked(uid);

  // Si ya está en una sesión viva, NO se le vuelve a encolar: si no, podría
  // acabar emparejado con un tercero mientras sigue hablando con el primero
  // (y el cierre de aquella sesión le borraría la entrada nueva).
  const queueRef = liveCol.queue.doc(uid);
  const currentSnap = await queueRef.get();
  if (currentSnap.exists && asString(currentSnap.data()?.status) === "paired") {
    const sessionId = asString(currentSnap.data()?.pairedSessionId);
    const sessionSnap = sessionId
      ? await liveCol.sessions.doc(sessionId).get()
      : null;
    if (sessionSnap?.exists && asString(sessionSnap.data()?.status) !== "ended") {
      const data = sessionSnap.data() ?? {};
      return {
        status: "paired",
        sessionId,
        peerUid: asStringList(data.users).find((u) => u !== uid) ?? "",
        isCaller: asString(data.userA) === uid,
      };
    }
  }

  const criteria = await loadCriteria(uid);
  await queueRef.set(queueDocFrom(criteria), { merge: false });

  return { status: "waiting" };
});

// ── 2. leaveLiveQueue ───────────────────────────────────────────────────────
export const leaveLiveQueue = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  await liveCol.queue.doc(uid).delete().catch(() => undefined);
  return { ok: true };
});

// ── 3. findLiveMatch ────────────────────────────────────────────────────────
interface PairAttempt {
  ok: boolean;
  /// 'self_gone' = mi entrada desapareció o ya está emparejada;
  /// 'taken' = el candidato lo cogió otro; 'busy' = ya hay sesión viva.
  reason?: "self_gone" | "taken" | "busy";
}

export const findLiveMatch = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  await assertLiveNotBlocked(uid);

  const myQueueRef = liveCol.queue.doc(uid);
  let mySnap = await myQueueRef.get();

  // Si mi entrada ya está emparejada, devuelvo la sesión (el cliente puede
  // haber perdido la respuesta anterior): idempotencia del sondeo.
  if (mySnap.exists && asString(mySnap.data()?.status) === "paired") {
    const sessionId = asString(mySnap.data()?.pairedSessionId);
    const sessionSnap = sessionId
      ? await liveCol.sessions.doc(sessionId).get()
      : null;
    if (sessionSnap?.exists && asString(sessionSnap.data()?.status) !== "ended") {
      const data = sessionSnap.data() ?? {};
      return {
        paired: true,
        sessionId,
        peerUid: asStringList(data.users).find((u) => u !== uid) ?? "",
        // El caller (quien crea la oferta WebRTC) es SIEMPRE userA: así los dos
        // clientes deciden el rol sin negociar y no hay "glare".
        isCaller: asString(data.userA) === uid,
        status: asString(data.status),
      };
    }
    // La sesión ya no vale (colgada, vencida o cortada por moderación): se
    // limpia la entrada y se vuelve a la cola.
    await myQueueRef.delete().catch(() => undefined);
    mySnap = await myQueueRef.get();
  }

  // Re-alta automática: el barrido puede haber borrado una entrada antigua
  // mientras el usuario seguía en la pantalla. Es preferible re-encolar a
  // devolver un error que el cliente tendría que traducir a "vuelve a entrar".
  let criteria: LiveCriteria;
  if (!mySnap.exists) {
    criteria = await loadCriteria(uid);
    await myQueueRef.set(queueDocFrom(criteria), { merge: false });
  } else {
    criteria = criteriaFromQueueDoc(uid, mySnap.data() ?? {});
    const lastSeenMs = millisOf(mySnap.data()?.lastSeenAt);
    if (lastSeenMs === null || Date.now() - lastSeenMs > LIVE_SEEN_REFRESH_MS) {
      // Señal de vida para el barrido de colas abandonadas. Se refresca con
      // cuentagotas: escribirlo en cada sondeo provocaría contención con la
      // transacción de emparejamiento del otro usuario.
      await myQueueRef.update({ lastSeenAt: FieldValue.serverTimestamp() });
    }
  }

  // Candidatos: FIFO (el que lleva más esperando primero). Con país conocido se
  // filtra en la consulta y se completa con los que no declararon país (el feed
  // es permisivo cuando falta el dato en un lado).
  const staleCutoffMs = Date.now() - LIVE_QUEUE_STALE_MS;
  const baseQuery = liveCol.queue
    .where("status", "==", "waiting")
    .orderBy("joinedAt", "asc")
    .limit(LIVE_CANDIDATE_SCAN);
  const queries =
    criteria.countryKey.length > 0
      ? [
          baseQuery.where("countryKey", "==", criteria.countryKey),
          baseQuery.where("countryKey", "==", ""),
        ]
      : [baseQuery];
  const snaps = await Promise.all(queries.map((q) => q.get()));

  const seen = new Set<string>([uid]);
  const candidates: LiveCriteria[] = [];
  for (const snap of snaps) {
    for (const doc of snap.docs) {
      if (seen.has(doc.id)) continue;
      seen.add(doc.id);
      const data = doc.data();
      // Entradas zombis: el cliente dejó de sondear. No se emparejan (nadie
      // contestaría) y el barrido las borrará.
      const seenMs = millisOf(data.lastSeenAt) ?? millisOf(data.joinedAt);
      if (seenMs !== null && seenMs < staleCutoffMs) continue;
      const other = criteriaFromQueueDoc(doc.id, data);
      if (isLiveCompatible(criteria, other)) candidates.push(other);
    }
  }
  if (candidates.length === 0) {
    return { paired: false, waiting: true, reason: "no_candidates" };
  }

  // Comprobaciones caras (bloqueos, match activo, descartes previos y sesión
  // reciente) solo para los primeros candidatos, en una única lectura por lote.
  const shortlist = candidates.slice(0, LIVE_CANDIDATE_CHECK);
  const refs = shortlist.flatMap((c) => [
    col.blocks.doc(directedId(uid, c.uid)),
    col.blocks.doc(directedId(c.uid, uid)),
    col.matches.doc(pairId(uid, c.uid)),
    col.dislikes.doc(directedId(uid, c.uid)),
    col.dislikes.doc(directedId(c.uid, uid)),
    liveCol.sessions.doc(pairId(uid, c.uid)),
    // Sancion del CANDIDATO. `assertLiveNotBlocked` solo mira a quien llama,
    // asi que sin esto un sancionado que siguiera encolado (le cayo la sancion
    // estando ya en cola) podia ser emparejado por un tercero: la puerta cierra
    // por dentro pero no por fuera. Y la sancion que mas importa aqui es
    // justamente la de desnudos.
    liveCol.strikes.doc(c.uid),
  ]);
  const docs = await db.getAll(...refs);

  const viable: string[] = [];
  const nowMs = Date.now();
  for (let i = 0; i < shortlist.length; i++) {
    const [blockAB, blockBA, match, dislikeAB, dislikeBA, session, strikes] =
      docs.slice(i * 7, i * 7 + 7);
    // Ni con quien tiene el vivo sancionado (permanente o temporal vigente).
    if (strikeStatusFromData(strikes.exists ? strikes.data() : undefined, nowMs).blocked) {
      continue;
    }
    // NUNCA con alguien bloqueado en ninguno de los dos sentidos.
    if (blockAB.exists || blockBA.exists) continue;
    // Ni con quien ya hay match activo (para eso está el chat).
    if (match.exists && (match.data()?.status ?? "active") === "active") continue;
    // Ni con quien ya se descartó (en el vivo o en el feed): el 'pass' del vivo
    // y el corte por moderación escriben dislike precisamente para eso.
    if (dislikeAB.exists || dislikeBA.exists) continue;
    if (session.exists) {
      const sdata = session.data() ?? {};
      if (asString(sdata.status) !== "ended") continue;
      const endedMs = millisOf(sdata.endedAt) ?? millisOf(sdata.updatedAt) ?? 0;
      if (Date.now() - endedMs < LIVE_REPAIR_COOLDOWN_MS) continue;
    }
    viable.push(shortlist[i].uid);
  }
  if (viable.length === 0) {
    return { paired: false, waiting: true, reason: "no_candidates" };
  }

  for (const otherUid of viable) {
    const attempt = await tryPair(uid, otherUid);
    if (attempt.ok) {
      const sessionId = pairId(uid, otherUid);
      const userA = uid <= otherUid ? uid : otherUid;
      return {
        paired: true,
        sessionId,
        peerUid: otherUid,
        isCaller: userA === uid,
        status: "ringing",
      };
    }
    // Mi propia entrada ya no está disponible (otro me emparejó primero):
    // no tiene sentido seguir probando candidatos.
    if (attempt.reason === "self_gone") break;
  }

  return { paired: false, waiting: true, reason: "race_lost" };
});

/// Emparejamiento ATÓMICO. La transacción lee las DOS entradas de cola y la
/// sesión: Firestore aborta y reintenta si alguna cambió entre la lectura y el
/// commit, así que dos usuarios NO pueden emparejarse a la vez con el mismo
/// tercero (el segundo verá esa entrada en 'paired' y pasará al siguiente).
async function tryPair(uid: string, otherUid: string): Promise<PairAttempt> {
  const sessionId = pairId(uid, otherUid);
  const sessionRef = liveCol.sessions.doc(sessionId);
  const myRef = liveCol.queue.doc(uid);
  const otherRef = liveCol.queue.doc(otherUid);
  const userA = uid <= otherUid ? uid : otherUid;
  const userB = uid <= otherUid ? otherUid : uid;

  return db.runTransaction<PairAttempt>(async (tx) => {
    const [mySnap, otherSnap, sessionSnap] = await Promise.all([
      tx.get(myRef),
      tx.get(otherRef),
      tx.get(sessionRef),
    ]);
    if (!mySnap.exists || asString(mySnap.data()?.status) !== "waiting") {
      return { ok: false, reason: "self_gone" };
    }
    if (!otherSnap.exists || asString(otherSnap.data()?.status) !== "waiting") {
      return { ok: false, reason: "taken" };
    }
    if (sessionSnap.exists && asString(sessionSnap.data()?.status) !== "ended") {
      return { ok: false, reason: "busy" };
    }

    const now = FieldValue.serverTimestamp();
    // El id de sesión es determinista (pairId), así que una sesión ANTIGUA
    // entre los mismos dos deja subcolecciones vivas. Se borran aquí porque:
    //  - un veredicto viejo crearía un match nada más empezar la sesión nueva,
    //  - una oferta SDP caduca rompería la negociación WebRTC,
    //  - y sobre todo: el contador de fotogramas de `moderation/{uid}` agotado
    //    dejaría la sesión nueva SIN moderación (rate limit ya consumido).
    for (const u of [userA, userB]) {
      tx.delete(sessionRef.collection(SUB_VERDICTS).doc(u));
      tx.delete(sessionRef.collection(SUB_SIGNALS).doc(u));
      tx.delete(sessionRef.collection(SUB_MODERATION).doc(u));
    }
    tx.set(sessionRef, {
      sessionId,
      users: [userA, userB],
      userA,
      userB,
      status: "ringing",
      startedAt: null,
      endsAt: null,
      endedAt: null,
      endedBy: null,
      endReason: null,
      moderationCoverage: {},
      moderationCoverageSuspicious: false,
      createdBy: uid,
      createdAt: now,
      updatedAt: now,
    });
    for (const ref of [myRef, otherRef]) {
      tx.update(ref, {
        status: "paired",
        pairedSessionId: sessionId,
        pairedWith: ref.id === uid ? otherUid : uid,
        pairedAt: now,
      });
    }
    return { ok: true };
  });
}

// ── 3.b startLiveSession — arranca el cronómetro en SERVIDOR ────────────────
/// El límite de 3 minutos no puede depender del reloj del cliente. Cuando el
/// vídeo ya fluye, cualquiera de los dos llama aquí y el servidor fija
/// startedAt/endsAt UNA sola vez (idempotente): el segundo en llamar recibe el
/// mismo endsAt y ambos cuentan lo mismo.
export const startLiveSession = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const sessionId = requireStringArg(request.data?.sessionId, "sessionId");
  const sessionRef = liveCol.sessions.doc(sessionId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(sessionRef);
    if (!snap.exists) throw new HttpsError("not-found", "La sesion no existe.");
    const data = snap.data() ?? {};
    if (!asStringList(data.users).includes(uid)) {
      throw new HttpsError("permission-denied", "No perteneces a esta sesion.");
    }
    const status = asString(data.status);
    if (status === "ended") {
      throw new HttpsError("failed-precondition", "La sesion ya termino.");
    }
    const existingEndsAt = millisOf(data.endsAt);
    if (status === "active" && existingEndsAt !== null) {
      return { sessionId, endsAt: new Date(existingEndsAt).toISOString() };
    }
    const endsAt = Timestamp.fromMillis(Date.now() + LIVE_SESSION_MAX_MS);
    tx.update(sessionRef, {
      status: "active",
      startedAt: FieldValue.serverTimestamp(),
      endsAt,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { sessionId, endsAt: endsAt.toDate().toISOString() };
  });
});

// ── 4. submitLiveVerdict ────────────────────────────────────────────────────
interface VerdictResult {
  outcome: "matched" | "liked" | "passed" | "ignored";
  matchId?: string;
  chatId?: string;
}

export const submitLiveVerdict = onCall(
  { region: REGION },
  async (request): Promise<VerdictResult> => {
    const uid = requireAuthUid(request.auth);
    const sessionId = requireStringArg(request.data?.sessionId, "sessionId");
    const raw = asString(request.data?.verdict).toLowerCase();
    if (raw !== "like" && raw !== "pass") {
      throw new HttpsError("invalid-argument", "Veredicto no valido.");
    }
    const verdict: LiveVerdict = raw;

    const sessionRef = liveCol.sessions.doc(sessionId);
    const myVerdictRef = sessionRef.collection(SUB_VERDICTS).doc(uid);

    return db.runTransaction<VerdictResult>(async (tx) => {
      const sessionSnap = await tx.get(sessionRef);
      if (!sessionSnap.exists) {
        throw new HttpsError("not-found", "La sesion no existe.");
      }
      const sessionData = sessionSnap.data() ?? {};
      const users = asStringList(sessionData.users);
      if (!users.includes(uid)) {
        throw new HttpsError("permission-denied", "No perteneces a esta sesion.");
      }
      const peerUid = users.find((u) => u !== uid) ?? "";
      if (!peerUid) {
        throw new HttpsError("failed-precondition", "Sesion incompleta.");
      }

      const endReason = asString(sessionData.endReason);
      // Una sesión cortada por moderación o denuncia NO puede acabar en match:
      // el veredicto se ignora aunque el cliente lo mande.
      if (endReason === "moderation" || endReason === "reported") {
        return { outcome: "ignored" };
      }
      const endedAtMs = millisOf(sessionData.endedAt);
      if (endedAtMs !== null && Date.now() - endedAtMs > LIVE_VERDICT_GRACE_MS) {
        return { outcome: "ignored" };
      }

      const peerVerdictRef = sessionRef.collection(SUB_VERDICTS).doc(peerUid);
      const [
        myVerdictSnap,
        peerVerdictSnap,
        blockAB,
        blockBA,
        matchSnap,
        entSnap,
        peerEntSnap,
        peerLikeSnap,
        myQueueSnap,
        peerQueueSnap,
      ] = await Promise.all([
        tx.get(myVerdictRef),
        tx.get(peerVerdictRef),
        tx.get(col.blocks.doc(directedId(uid, peerUid))),
        tx.get(col.blocks.doc(directedId(peerUid, uid))),
        tx.get(col.matches.doc(pairId(uid, peerUid))),
        tx.get(col.entitlements.doc(uid)),
        tx.get(col.entitlements.doc(peerUid)),
        tx.get(col.likes.doc(directedId(peerUid, uid))),
        tx.get(liveCol.queue.doc(uid)),
        tx.get(liveCol.queue.doc(peerUid)),
      ]);

      // Un bloqueo posterior a la sesión manda sobre cualquier veredicto.
      if (blockAB.exists || blockBA.exists) {
        return { outcome: "ignored" };
      }

      // Primer veredicto gana: no se puede cambiar el voto (evita rehacer el
      // dislike una y otra vez o forzar el match a posteriori).
      const already = myVerdictSnap.exists
        ? asString(myVerdictSnap.data()?.verdict)
        : "";
      const effective: LiveVerdict =
        already === "like" || already === "pass"
          ? (already as LiveVerdict)
          : verdict;
      if (!myVerdictSnap.exists) {
        tx.set(myVerdictRef, {
          uid,
          verdict: effective,
          decidedAt: FieldValue.serverTimestamp(),
        });
      }

      const now = FieldValue.serverTimestamp();

      if (effective === "pass") {
        // 'pass' = descarte: escribe dislike para no volver a verle ni en el
        // feed normal ni en el vivo (findLiveMatch mira dislikes).
        tx.set(
          col.dislikes.doc(directedId(uid, peerUid)),
          { fromUid: uid, toUid: peerUid, source: "live", createdAt: now },
          { merge: true }
        );
        // Si el otro ya había mostrado interés desde el vivo, su like queda
        // cancelado (igual que passProfile hace en la bandeja de likes).
        if (
          peerLikeSnap.exists &&
          asString(peerLikeSnap.data()?.status) === "active" &&
          asString(peerLikeSnap.data()?.targetType) === "live"
        ) {
          tx.set(
            col.likes.doc(directedId(peerUid, uid)),
            {
              status: "cancelled",
              cancelledAt: now,
              cancelledBy: uid,
              cancelReason: "passed_in_live",
            },
            { merge: true }
          );
        }
        return { outcome: "passed" };
      }

      // 'like': se escribe un like REAL (mismo modelo que sendLike) para que la
      // bandeja "te han dado like" y las reglas (fromUid/toUid) funcionen igual.
      tx.set(
        col.likes.doc(directedId(uid, peerUid)),
        {
          fromUid: uid,
          toUid: peerUid,
          type: "like",
          status: "active",
          ...senderPrioritySnapshot(entSnap.data(), "like"),
          targetType: "live",
          relatedSessionId: sessionId,
          targetPhotoId: null,
          targetPhotoUrlSnapshot: null,
          commentText: null,
          commentStatus: "none",
          commentModerationStatus: "approved",
          createdAt: now,
        },
        { merge: true }
      );
      tx.delete(col.dislikes.doc(directedId(uid, peerUid)));

      const peerVerdict = peerVerdictSnap.exists
        ? asString(peerVerdictSnap.data()?.verdict)
        : "";
      if (peerVerdict !== "like") {
        return { outcome: "liked" };
      }

      if (matchSnap.exists && (matchSnap.data()?.status ?? "active") === "active") {
        return { outcome: "matched", matchId: matchSnap.id, chatId: matchSnap.id };
      }

      // El veredicto del otro pudo escribirse por reglas (sin pasar por esta
      // callable), así que su like puede no existir todavía: se materializa
      // aquí para que el match no quede con un like "fantasma" sin fromUid
      // (las reglas de `likes` filtran por fromUid/toUid: sin ellos, nadie
      // podría leer su propia bandeja).
      if (!peerLikeSnap.exists) {
        tx.set(
          col.likes.doc(directedId(peerUid, uid)),
          {
            fromUid: peerUid,
            toUid: uid,
            type: "like",
            status: "active",
            ...senderPrioritySnapshot(peerEntSnap.data(), "like"),
            targetType: "live",
            relatedSessionId: sessionId,
            targetPhotoId: null,
            targetPhotoUrlSnapshot: null,
            commentText: null,
            commentStatus: "none",
            commentModerationStatus: "approved",
            createdAt: now,
          },
          { merge: true }
        );
      }

      // MISMO camino que el resto de la app: ids deterministas y chat creado
      // igual. No se duplica nada de la lógica de match.
      const refs = writeMatchAndChat(tx, {
        uidA: uid,
        uidB: peerUid,
        createdBy: uid,
        action: "like",
        hasAttra: false,
        attraSenderUid: null,
        origin: {
          originLikeId: directedId(uid, peerUid),
          originTargetType: "profile",
        },
      });

      if (asString(sessionData.status) !== "ended") {
        tx.update(sessionRef, {
          status: "ended",
          endedAt: now,
          endedBy: uid,
          endReason: "matched",
          updatedAt: now,
        });
      } else {
        tx.update(sessionRef, { endReason: "matched", updatedAt: now });
      }
      // Y se liberan las entradas de cola de ESTA sesión: mientras sigan
      // 'paired' ninguno de los dos puede volver a emparejarse. (El barrido
      // también lo haría, pero un minuto de espera se nota en la pantalla.)
      for (const qs of [myQueueSnap, peerQueueSnap]) {
        if (qs.exists && asString(qs.data()?.pairedSessionId) === sessionId) {
          tx.delete(qs.ref);
        }
      }

      return { outcome: "matched", matchId: refs.matchId, chatId: refs.chatId };
    });
  }
);

// ── 5. endLiveSession ───────────────────────────────────────────────────────
export const endLiveSession = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const sessionId = requireStringArg(request.data?.sessionId, "sessionId");
  const rawReason = asString(request.data?.reason).toLowerCase();
  // Del cliente solo se aceptan estos dos motivos: 'timeout', 'moderation' y
  // 'matched' los pone el servidor y no puede fabricarlos quien cuelga.
  const reason: LiveEndReason = rawReason === "reported" ? "reported" : "left";

  const snap = await liveCol.sessions.doc(sessionId).get();
  if (!snap.exists) throw new HttpsError("not-found", "La sesion no existe.");
  const users = asStringList(snap.data()?.users);
  if (!users.includes(uid)) {
    throw new HttpsError("permission-denied", "No perteneces a esta sesion.");
  }

  const result = await closeLiveSession({
    sessionId,
    endedBy: uid,
    endReason: reason,
  });

  if (reason === "reported") {
    const reportedUid = users.find((u) => u !== uid) ?? "";
    if (reportedUid) {
      // MISMA cola de moderación que reportUser (colección `reports`): no se
      // crea un flujo paralelo.
      await createReport({
        reporterUid: uid,
        reportedUid,
        reason: asString(request.data?.reportReason) || "live_video",
        details: asString(request.data?.details),
        matchId: null,
        chatId: null,
        messageId: sessionId,
      });
      // Denunciar implica no volver a verse: dislike en ambos sentidos, misma
      // colección e ids que passProfile.
      const now = FieldValue.serverTimestamp();
      const batch = db.batch();
      for (const [from, to] of [
        [uid, reportedUid],
        [reportedUid, uid],
      ]) {
        batch.set(
          col.dislikes.doc(directedId(from, to)),
          { fromUid: from, toUid: to, source: "live_report", createdAt: now },
          { merge: true }
        );
      }
      await batch.commit();
    }
  }

  return { ok: true, closed: result.closed };
});

// ── 6. Barrido por vencimiento ──────────────────────────────────────────────
/// Cierra sesiones vencidas y limpia la cola. EXPORTADO en index.ts: sin eso el
/// barrido no se despliega y las sesiones se quedan 'active' para siempre (ya
/// ha pasado en este proyecto con sweepChatGames).
export const sweepLiveSessions = onSchedule(
  { schedule: "every 1 minutes", region: REGION },
  async () => {
    const now = Date.now();

    // a) Sesiones activas pasadas de LIVE_SESSION_MAX_MS (endsAt lo fija el
    //    servidor en startLiveSession, no el cliente).
    const expired = await liveCol.sessions
      .where("status", "==", "active")
      .where("endsAt", "<", Timestamp.fromMillis(now))
      .limit(200)
      .get();
    for (const doc of expired.docs) {
      await closeLiveSession({
        sessionId: doc.id,
        endedBy: "system",
        endReason: "timeout",
      });
    }

    // b) Sesiones que nunca llegaron a conectar (WebRTC fallido): si no, las dos
    //    entradas de cola se quedan 'paired' y ninguno vuelve a emparejarse.
    const ringing = await liveCol.sessions
      .where("status", "==", "ringing")
      .where("createdAt", "<", Timestamp.fromMillis(now - LIVE_RING_TIMEOUT_MS))
      .limit(200)
      .get();
    for (const doc of ringing.docs) {
      await closeLiveSession({
        sessionId: doc.id,
        endedBy: "system",
        endReason: "timeout",
      });
    }

    // c) Entradas de cola abandonadas (el cliente dejó de dar señales de vida).
    const stale = await liveCol.queue
      .where("status", "==", "waiting")
      .where("lastSeenAt", "<", Timestamp.fromMillis(now - LIVE_QUEUE_STALE_MS))
      .limit(300)
      .get();
    for (const doc of stale.docs) {
      await doc.ref.delete().catch(() => undefined);
    }

    // d) Entradas 'paired' huérfanas: su sesión ya terminó (p. ej. corte por
    //    moderación, que cierra la sesión pero no toca la cola) o lleva
    //    demasiado tiempo. Mientras sigan 'paired' el usuario NO puede volver a
    //    emparejarse, así que esto es lo que le devuelve al vivo.
    const paired = await liveCol.queue
      .where("status", "==", "paired")
      .where("pairedAt", "<", Timestamp.fromMillis(now - LIVE_PAIRED_REVIEW_MS))
      .limit(300)
      .get();
    let orphans = 0;
    for (const doc of paired.docs) {
      const pairedAtMs = millisOf(doc.data().pairedAt) ?? 0;
      const tooOld = now - pairedAtMs > LIVE_PAIRED_STALE_MS;
      let dead = tooOld;
      if (!dead) {
        const sessionId = asString(doc.data().pairedSessionId);
        if (!sessionId) {
          dead = true;
        } else {
          const s = await liveCol.sessions.doc(sessionId).get();
          dead = !s.exists || asString(s.data()?.status) === "ended";
        }
      }
      if (dead) {
        orphans += 1;
        await doc.ref.delete().catch(() => undefined);
      }
    }

    console.log(
      `[live] barrido: ${expired.size} vencidas, ${ringing.size} sin conectar, ` +
        `${stale.size} colas abandonadas, ${orphans} colas huerfanas`
    );
  }
);
