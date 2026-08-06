import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { FieldValue, Transaction, DocumentData } from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
import { col, requireAuthUid, requireStringArg } from "./common";

type BoostType = "boost_normal" | "superboost";
type BoostEvent =
  | "boostStarted"
  | "boostExtended"
  | "boostExpired"
  | "boostImpression"
  | "boostLikeReceived"
  | "boostMatchGenerated"
  | "boostSummaryViewed"
  | "boostActivationFailedNoBalance";

interface BoostSpec {
  durationMs: number;
  priorityBonus: number;
  impressionCap: number;
}

interface ActiveBoostClientData {
  boostId: string;
  userId: string;
  type: BoostType;
  status: "active";
  startedAt: string;
  expiresAt: string;
  priorityBonus: number;
  impressionCap: number;
  deliveredImpressions: number;
}

const BOOST_SPECS: Record<BoostType, BoostSpec> = {
  boost_normal: {
    durationMs: 30 * 60 * 1000,
    priorityBonus: 80,
    impressionCap: 500,
  },
  superboost: {
    durationMs: 24 * 60 * 60 * 1000,
    priorityBonus: 150,
    impressionCap: 5000,
  },
};

/// Coste en Boosts de cada tipo.
///
/// QUE FALLABA: el Superboost (24 h, prioridad +150, cap 5000 impresiones)
/// descontaba EXACTAMENTE lo mismo que el Boost de 30 min (prioridad +80, cap
/// 500): `increment(-1)` de `users.wallet.boosts`. El producto caro valia lo
/// mismo que el barato, asi que nadie tenia motivo para gastar un Boost normal
/// y el saldo mensual no se podia expresar en una sola unidad.
///
/// Ahora el Superboost cuesta 3 Boosts (flag `superboost_cost_boosts`), que es
/// lo que permite tener UNA sola moneda: el usuario decide si gasta su saldo en
/// un Superboost o en varios Boosts cortos.
const DEFAULT_SUPERBOOST_COST = 3;

const FLAGS_CACHE_TTL_MS = 5 * 60 * 1000;
let cachedSuperboostCost: { value: number; at: number } | null = null;

/// Lee el coste del Superboost de `config/featureFlags` aceptando las dos
/// variantes de nombre (snake_case y camelCase), igual que el resto de flags.
///
/// Se cachea en memoria del proceso (5 min) porque `activateBoost` esta en la
/// ruta caliente: sin cache seria una lectura extra de Firestore por cada
/// activacion solo para releer un numero que casi nunca cambia.
async function superboostCostBoosts(): Promise<number> {
  const now = Date.now();
  if (cachedSuperboostCost && now - cachedSuperboostCost.at < FLAGS_CACHE_TTL_MS) {
    return cachedSuperboostCost.value;
  }
  let value = DEFAULT_SUPERBOOST_COST;
  try {
    const snap = await db.collection("config").doc("featureFlags").get();
    const data = snap.data() ?? {};
    const raw = data.superboost_cost_boosts ?? data.superboostCostBoosts;
    const parsed = Math.floor(numericValue(raw, DEFAULT_SUPERBOOST_COST));
    // Un flag mal puesto a 0 (o negativo) regalaria Superboosts infinitos: se
    // ignora y se cobra el default. El minimo vendible es 1.
    if (Number.isFinite(parsed) && parsed >= 1) value = parsed;
  } catch {
    // Si `config/featureFlags` no se puede leer se cobra el default: nunca
    // gratis, que es el fallo seguro para el negocio.
    value = DEFAULT_SUPERBOOST_COST;
  }
  cachedSuperboostCost = { value, at: now };
  return value;
}

function boostCostFor(type: BoostType, superboostCost: number): number {
  return type === "superboost" ? superboostCost : 1;
}

function boostTypeFromValue(value: unknown, fallback: BoostType): BoostType {
  if (value === "boost_normal" || value === "superboost") return value;
  return fallback;
}

function requiredBoostType(value: unknown): BoostType {
  if (value == null || value === "") return "boost_normal";
  if (value === "boost_normal" || value === "superboost") return value;
  throw new HttpsError("invalid-argument", "Tipo de Boost invalido.");
}

function millisFromDateLike(value: unknown): number | null {
  if (!value) return null;
  if (value instanceof Date) return value.getTime();
  if (typeof value === "string") {
    const ms = Date.parse(value);
    return Number.isNaN(ms) ? null : ms;
  }
  if (typeof value === "object" && "toMillis" in value) {
    const maybeTimestamp = value as { toMillis?: unknown };
    if (typeof maybeTimestamp.toMillis === "function") {
      const ms = maybeTimestamp.toMillis();
      return typeof ms === "number" ? ms : null;
    }
  }
  return null;
}

function isoFromDateLike(value: unknown, fallback: Date): string {
  const ms = millisFromDateLike(value);
  return new Date(ms ?? fallback.getTime()).toISOString();
}

function numericValue(value: unknown, fallback = 0): number {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
  }
  return fallback;
}

function safeDocPart(value: string): string {
  return value.replace(/[^A-Za-z0-9_.-]/g, "_").slice(0, 80) || "event";
}

function activeBoostToClient(data: DocumentData): ActiveBoostClientData {
  const type = boostTypeFromValue(data.type, "boost_normal");
  return {
    boostId: (data.boostId ?? "").toString(),
    userId: (data.userId ?? "").toString(),
    type,
    status: "active",
    startedAt: isoFromDateLike(data.startedAt, new Date()),
    expiresAt: isoFromDateLike(data.expiresAt, new Date()),
    priorityBonus: numericValue(data.priorityBonus, BOOST_SPECS[type].priorityBonus),
    impressionCap: numericValue(data.impressionCap, BOOST_SPECS[type].impressionCap),
    deliveredImpressions: numericValue(data.deliveredImpressions),
  };
}

function isLiveActiveBoost(data: DocumentData | undefined, at = Date.now()): boolean {
  if (!data) return false;
  if ((data.status ?? "active") !== "active") return false;
  const boostId = (data.boostId ?? "").toString();
  if (boostId.length === 0) return false;
  const expiresAt = millisFromDateLike(data.expiresAt);
  return expiresAt !== null && expiresAt > at;
}

function logBoostEventTx(
  tx: Transaction,
  event: BoostEvent,
  uid: string,
  boostId: string | null,
  targetUid?: string,
  meta: Record<string, unknown> = {}
): void {
  tx.set(col.feedEvents.doc(), {
    event,
    uid,
    boostId,
    ...(targetUid ? { targetUid } : {}),
    ...meta,
    at: FieldValue.serverTimestamp(),
  });
}

async function logBoostEvent(
  event: BoostEvent,
  uid: string,
  boostId: string | null,
  targetUid?: string,
  meta: Record<string, unknown> = {}
): Promise<void> {
  await col.feedEvents.add({
    event,
    uid,
    boostId,
    ...(targetUid ? { targetUid } : {}),
    ...meta,
    at: FieldValue.serverTimestamp(),
  });
}

function expireActiveBoostTx(
  tx: Transaction,
  uid: string,
  activeData: DocumentData
): void {
  const boostId = (activeData.boostId ?? "").toString();
  if (boostId.length > 0) {
    tx.set(
      col.boostSessions.doc(boostId),
      {
        status: "expired",
        expiredAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    logBoostEventTx(tx, "boostExpired", uid, boostId);
  }
  tx.delete(col.activeBoosts.doc(uid));
}

async function expireActiveBoost(uid: string, activeData: DocumentData): Promise<void> {
  const boostId = (activeData.boostId ?? "").toString();
  const batch = db.batch();
  if (boostId.length > 0) {
    batch.set(
      col.boostSessions.doc(boostId),
      {
        status: "expired",
        expiredAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    batch.set(col.feedEvents.doc(), {
      event: "boostExpired",
      uid,
      boostId,
      at: FieldValue.serverTimestamp(),
    });
  }
  batch.delete(col.activeBoosts.doc(uid));
  await batch.commit();
}

export const activateBoost = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const requestedType = requiredBoostType(request.data?.type);
  const userRef = col.users.doc(uid);
  const activeRef = col.activeBoosts.doc(uid);
  // Fuera de la transaccion: es otro documento y no debe participar en el
  // bloqueo del cobro.
  const superboostCost = await superboostCostBoosts();
  const cost = boostCostFor(requestedType, superboostCost);

  return db.runTransaction(async (tx) => {
    const [userSnap, activeSnap] = await Promise.all([
      tx.get(userRef),
      tx.get(activeRef),
    ]);
    if (!userSnap.exists) {
      throw new HttpsError("failed-precondition", "No existe tu perfil.");
    }

    const wallet = userSnap.data()?.wallet;
    const boosts = numericValue(
      wallet && typeof wallet === "object"
        ? (wallet as DocumentData).boosts
        : undefined
    );
    // El saldo se comprueba ANTES de cualquier escritura (incluido el camino de
    // "extender un boost ya activo", que se resuelve mas abajo dentro de esta
    // misma transaccion): si no llega, no se cobra nada.
    if (boosts < cost) {
      logBoostEventTx(tx, "boostActivationFailedNoBalance", uid, null, undefined, {
        type: requestedType,
        requiredBoosts: cost,
        availableBoosts: boosts,
      });
      return {
        success: false,
        boostId: null,
        // `no_balance` se reserva para "no tienes NADA" porque el cliente ya lo
        // traduce a "compra un Boost". Tener saldo pero insuficiente para un
        // Superboost es otra situacion (basta con esperar/comprar 2 mas), asi
        // que necesita un motivo distinguible para poder explicarla.
        status: boosts <= 0 ? "no_balance" : "insufficient_balance",
        startedAt: null,
        expiresAt: null,
        remainingBoosts: boosts,
        requiredBoosts: cost,
      };
    }

    const nowDate = new Date();
    const nowMs = nowDate.getTime();
    const serverNow = FieldValue.serverTimestamp();
    const activeData = activeSnap.exists ? activeSnap.data() : undefined;
    const hasLiveBoost = !!activeData && isLiveActiveBoost(activeData, nowMs);

    // Con un boost vivo de OTRO tipo se cobraba 1 Boost del saldo y se aplicaba
    // la duracion/prioridad del que ya estaba corriendo, no la del pedido: el
    // usuario pagaba un Superboost (24h, prioridad 150) y recibia 30 min de
    // Boost normal. Como el saldo es el mismo para ambos tipos no hay forma de
    // "cambiar" de tipo sin regalar o quitar valor, asi que se rechaza SIN
    // cobrar (la transaccion aborta antes del cargo) y decide el usuario.
    if (hasLiveBoost) {
      // El fallback del tipo vivo NO puede ser el tipo pedido: con un doc sin
      // `type` (legacy) cualquier peticion "coincidia" y se acababa aplicando
      // la spec equivocada. Con fallback fijo, un doc raro solo puede
      // extenderse como Boost normal; pedir Superboost se rechaza sin cobrar.
      const liveType = boostTypeFromValue(activeData?.type, "boost_normal");
      if (liveType !== requestedType) {
        throw new HttpsError(
          "failed-precondition",
          liveType === "superboost"
            ? "Ya tienes un Superboost activo. Espera a que termine para activar un Boost."
            : "Ya tienes un Boost activo. Espera a que termine para activar un Superboost."
        );
      }
    }

    tx.update(userRef, {
      "wallet.boosts": FieldValue.increment(-cost),
      "wallet.boostsUpdatedAt": serverNow,
      updatedAt: serverNow,
    });

    if (activeData && !hasLiveBoost) {
      expireActiveBoostTx(tx, uid, activeData);
    }

    if (activeData && hasLiveBoost) {
      // Mismo tipo garantizado por la comprobacion de arriba: se aplica SIEMPRE
      // la spec del tipo PEDIDO (nunca la que hubiera guardada en el doc), asi
      // extender un Superboost suma 24h/prioridad 150 y extender un Boost suma
      // 30 min/prioridad 80, que es exactamente lo que el usuario ha pagado.
      const activeType = requestedType;
      const spec = BOOST_SPECS[activeType];
      const boostId = (activeData.boostId ?? "").toString();
      const activeExpiresMs = millisFromDateLike(activeData.expiresAt) ?? nowMs;
      const expiresAt = new Date(Math.max(activeExpiresMs, nowMs) + spec.durationMs);
      // Extender con el cap de impresiones agotado cobraba 1 Boost del saldo y
      // no daba NADA: el cap se reescribia con el mismo valor mientras
      // `deliveredImpressions` sigue siendo acumulado, asi que
      // `recordBoostImpression` continuaba devolviendo "cap_reached" durante
      // todo el tiempo extra. Se elige AMPLIAR el cap (increment) en vez de
      // rechazar el cobro: el usuario que paga siempre recibe una tanda entera
      // de impresiones nuevas, y sumar en vez de reiniciar el contador conserva
      // las metricas acumuladas de la sesion (resumen del Boost).
      const extendedCap = FieldValue.increment(spec.impressionCap);
      tx.set(
        col.boostSessions.doc(boostId),
        {
          status: "active",
          type: activeType,
          expiresAt,
          priorityBonus: spec.priorityBonus,
          impressionCap: extendedCap,
          // El consumo registrado tiene que ser el REAL (3 para el Superboost),
          // no siempre 1, o el resumen del Boost mentiria sobre lo gastado.
          consumedAmount: FieldValue.increment(cost),
          extendedCount: FieldValue.increment(1),
          updatedAt: serverNow,
        },
        { merge: true }
      );
      tx.set(
        activeRef,
        {
          userId: uid,
          boostId,
          type: activeType,
          status: "active",
          expiresAt,
          priorityBonus: spec.priorityBonus,
          impressionCap: extendedCap,
          updatedAt: serverNow,
        },
        { merge: true }
      );
      logBoostEventTx(tx, "boostExtended", uid, boostId, undefined, {
        type: activeType,
        expiresAt: expiresAt.toISOString(),
        addedImpressionCap: spec.impressionCap,
      });
      return {
        success: true,
        boostId,
        status: "active",
        startedAt: isoFromDateLike(activeData.startedAt, nowDate),
        expiresAt: expiresAt.toISOString(),
        remainingBoosts: boosts - cost,
        spentBoosts: cost,
      };
    }

    const spec = BOOST_SPECS[requestedType];
    const sessionRef = col.boostSessions.doc();
    const boostId = sessionRef.id;
    const expiresAt = new Date(nowMs + spec.durationMs);
    const sessionPayload = {
      boostId,
      userId: uid,
      type: requestedType,
      status: "active",
      source: "wallet",
      consumedAmount: cost,
      startedAt: nowDate,
      expiresAt,
      createdAt: serverNow,
      updatedAt: serverNow,
      priorityBonus: spec.priorityBonus,
      impressionCap: spec.impressionCap,
      deliveredImpressions: 0,
      profileOpens: 0,
      likesReceived: 0,
      matchesGenerated: 0,
      extendedCount: 0,
    };
    tx.set(sessionRef, sessionPayload);
    tx.set(activeRef, {
      userId: uid,
      boostId,
      type: requestedType,
      status: "active",
      startedAt: nowDate,
      expiresAt,
      priorityBonus: spec.priorityBonus,
      impressionCap: spec.impressionCap,
      deliveredImpressions: 0,
      updatedAt: serverNow,
    });
    logBoostEventTx(tx, "boostStarted", uid, boostId, undefined, {
      type: requestedType,
      expiresAt: expiresAt.toISOString(),
      spentBoosts: cost,
    });
    return {
      success: true,
      boostId,
      status: "active",
      startedAt: nowDate.toISOString(),
      expiresAt: expiresAt.toISOString(),
      remainingBoosts: boosts - cost,
      spentBoosts: cost,
    };
  });
});

export const getActiveBoostForUser = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const snap = await col.activeBoosts.doc(uid).get();
  const data = snap.data();
  if (!snap.exists || !data) return { activeBoost: null };
  if (!isLiveActiveBoost(data)) {
    await expireActiveBoost(uid, data);
    return { activeBoost: null };
  }
  return { activeBoost: activeBoostToClient(data) };
});

export const getBoostSummary = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const boostId = requireStringArg(request.data?.boostId, "boostId");
  const snap = await col.boostSessions.doc(boostId).get();
  if (!snap.exists) throw new HttpsError("not-found", "Boost no encontrado.");
  const data = snap.data() ?? {};
  if ((data.userId ?? "") !== uid) {
    throw new HttpsError("permission-denied", "No puedes ver este Boost.");
  }
  await logBoostEvent("boostSummaryViewed", uid, boostId).catch(() => undefined);
  return {
    boostId,
    userId: uid,
    type: boostTypeFromValue(data.type, "boost_normal"),
    status: (data.status ?? "expired").toString(),
    startedAt: isoFromDateLike(data.startedAt, new Date()),
    expiresAt: isoFromDateLike(data.expiresAt, new Date()),
    priorityBonus: numericValue(data.priorityBonus),
    impressionCap: numericValue(data.impressionCap),
    deliveredImpressions: numericValue(data.deliveredImpressions),
    profileOpens: numericValue(data.profileOpens),
    likesReceived: numericValue(data.likesReceived),
    matchesGenerated: numericValue(data.matchesGenerated),
    extendedCount: numericValue(data.extendedCount),
  };
});

export const recordBoostImpression = onCall({ region: REGION }, async (request) => {
  const viewerUid = requireAuthUid(request.auth);
  const boostedUid = requireStringArg(request.data?.boostedUid, "boostedUid");
  if (viewerUid === boostedUid) {
    return { recorded: false, reason: "self" };
  }
  const rawFeedEventId =
    typeof request.data?.feedEventId === "string" ? request.data.feedEventId : "feed";
  const feedEventId = safeDocPart(rawFeedEventId);
  const activeRef = col.activeBoosts.doc(boostedUid);

  return db.runTransaction(async (tx) => {
    const activeSnap = await tx.get(activeRef);
    const activeData = activeSnap.data();
    if (!activeSnap.exists || !activeData) {
      return { recorded: false, reason: "no_active_boost" };
    }
    if (!isLiveActiveBoost(activeData)) {
      expireActiveBoostTx(tx, boostedUid, activeData);
      return { recorded: false, reason: "expired" };
    }

    const boostId = (activeData.boostId ?? "").toString();
    const cap = numericValue(activeData.impressionCap);
    const delivered = numericValue(activeData.deliveredImpressions);
    if (cap > 0 && delivered >= cap) {
      return { recorded: false, reason: "cap_reached" };
    }

    const impressionRef = col.boostImpressions.doc(
      `${safeDocPart(boostId)}_${safeDocPart(viewerUid)}_${feedEventId}`
    );
    const impressionSnap = await tx.get(impressionRef);
    if (impressionSnap.exists) {
      return { recorded: false, reason: "duplicate" };
    }

    tx.set(impressionRef, {
      boostId,
      boostedUid,
      viewerUid,
      feedEventId,
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.set(
      activeRef,
      {
        deliveredImpressions: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    tx.set(
      col.boostSessions.doc(boostId),
      {
        deliveredImpressions: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    logBoostEventTx(tx, "boostImpression", boostedUid, boostId, viewerUid, {
      feedEventId,
    });
    return { recorded: true, deliveredImpressions: delivered + 1 };
  });
});

export const expireBoosts = onSchedule(
  { schedule: "every 10 minutes", region: REGION },
  async () => {
    const now = new Date();
    const snap = await col.activeBoosts
      .where("expiresAt", "<=", now)
      .limit(300)
      .get();
    if (snap.empty) {
      console.log("[expireBoosts] expired=0");
      return;
    }

    const batch = db.batch();
    let expired = 0;
    for (const doc of snap.docs) {
      const data = doc.data();
      const uid = (data.userId ?? doc.id).toString();
      const boostId = (data.boostId ?? "").toString();
      if (boostId.length > 0) {
        batch.set(
          col.boostSessions.doc(boostId),
          {
            status: "expired",
            expiredAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        batch.set(col.feedEvents.doc(), {
          event: "boostExpired",
          uid,
          boostId,
          at: FieldValue.serverTimestamp(),
        });
      }
      batch.delete(doc.ref);
      expired++;
    }
    await batch.commit();
    console.log(`[expireBoosts] expired=${expired}`);
  }
);

function recordBoostCounterForUser(
  tx: Transaction,
  userId: string,
  activeBoostData: DocumentData | undefined,
  counter: "likesReceived" | "matchesGenerated",
  event: "boostLikeReceived" | "boostMatchGenerated"
): void {
  if (!isLiveActiveBoost(activeBoostData)) return;
  const boostId = (activeBoostData?.boostId ?? "").toString();
  tx.set(
    col.activeBoosts.doc(userId),
    { [counter]: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() },
    { merge: true }
  );
  tx.set(
    col.boostSessions.doc(boostId),
    { [counter]: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() },
    { merge: true }
  );
  logBoostEventTx(tx, event, userId, boostId);
}

export function recordBoostLikeReceivedForUser(
  tx: Transaction,
  userId: string,
  activeBoostData: DocumentData | undefined
): void {
  recordBoostCounterForUser(
    tx,
    userId,
    activeBoostData,
    "likesReceived",
    "boostLikeReceived"
  );
}

export function recordBoostMatchGeneratedForUser(
  tx: Transaction,
  userId: string,
  activeBoostData: DocumentData | undefined
): void {
  recordBoostCounterForUser(
    tx,
    userId,
    activeBoostData,
    "matchesGenerated",
    "boostMatchGenerated"
  );
}
