import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { FieldValue, DocumentData } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { REGION, db } from "./firebase";
import {
  col,
  existsBlockBetween,
  requireAuthUid,
  requireStringArg,
} from "./common";

// ─────────────────────────────────────────────────────────────────────────────
// Utilidades
// ─────────────────────────────────────────────────────────────────────────────

function millis(value: unknown): number | null {
  if (!value) return null;
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number") return value;
  if (typeof value === "string") {
    const ms = Date.parse(value);
    return Number.isNaN(ms) ? null : ms;
  }
  if (typeof value === "object" && "toMillis" in value) {
    const t = value as { toMillis?: () => number };
    if (typeof t.toMillis === "function") return t.toMillis();
  }
  return null;
}

async function antiGhostingFlag(key: string, fallback: boolean): Promise<boolean> {
  try {
    const snap = await db.collection("config").doc("featureFlags").get();
    const data = snap.data() ?? {};
    return typeof data[key] === "boolean" ? (data[key] as boolean) : fallback;
  } catch {
    return fallback;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// §5b — Push de "te toca responder" (24h / 48h) con cooldown y exclusiones
// ─────────────────────────────────────────────────────────────────────────────

const IGNORED_LAST_TYPES = [
  "system",
  "like_context",
  "attra_context",
  "closure",
];

export const sendPendingReplyNudges = onSchedule(
  { schedule: "every 6 hours", region: REGION },
  async () => {
    if (!(await antiGhostingFlag("anti_ghosting_nudges_enabled", false))) {
      console.log("[pendingReplyNudges] flag off; skip");
      return;
    }
    const now = Date.now();
    const cutoff24 = new Date(now - 24 * 3600 * 1000);

    // Chats activos cuyo último mensaje es de hace >= 24h. Requiere índice
    // compuesto (status ASC, lastMessageAt ASC) — ver firestore.indexes.json.
    const snap = await col.chats
      .where("status", "==", "active")
      .where("lastMessageAt", "<=", cutoff24)
      .limit(400)
      .get();

    let sent = 0;
    for (const doc of snap.docs) {
      const c = doc.data();
      const users: string[] = Array.isArray(c.users)
        ? (c.users as unknown[]).filter((u): u is string => typeof u === "string")
        : [];
      const lastSender = (c.lastMessageSenderId ?? "").toString();
      const lastType = (c.lastMessageType ?? "text").toString();
      if (users.length !== 2 || !lastSender) continue;
      if (IGNORED_LAST_TYPES.includes(lastType)) continue;

      const waitingUid = users.find((u) => u !== lastSender) ?? "";
      if (!waitingUid) continue;

      const lastMsgMs = millis(c.lastMessageAt) ?? now;
      const hours = (now - lastMsgMs) / 3600000;
      const tier = hours >= 48 ? "48h" : "24h";

      const ag = (c.antiGhosting ?? {}) as DocumentData;
      // No repetir el mismo nivel, ni mandar dos pushes en < 20h.
      if (ag.lastNudgePushTier === tier) continue;
      const lastPushMs = millis(ag.lastPushSentAt);
      if (lastPushMs && now - lastPushMs < 20 * 3600 * 1000) continue;

      // Exclusiones: bloqueo, usuario inválido, modo ocupado del que espera.
      const [waitSnap, blocked] = await Promise.all([
        col.users.doc(waitingUid).get(),
        existsBlockBetween(users[0], users[1]),
      ]);
      if (blocked) continue;
      const wd = waitSnap.data() ?? {};
      if (wd.isBanned === true || wd.isDeleted === true) continue;
      const settings = (wd.settings ?? {}) as DocumentData;
      if (settings["privacy.busyModeEnabled"] === true) {
        const until = millis(settings["privacy.busyModeUntil"]);
        if (until && until > now) continue; // en pausa: no molestar
      }

      // Marca el cooldown SIEMPRE (aunque no haya tokens) para no reevaluar.
      await doc.ref
        .set(
          {
            antiGhosting: {
              lastPushSentAt: FieldValue.serverTimestamp(),
              lastNudgePushTier: tier,
            },
          },
          { merge: true }
        )
        .catch(() => undefined);

      const tokens: string[] = Array.isArray(wd.fcmTokens)
        ? (wd.fcmTokens as unknown[]).filter(
            (t): t is string => typeof t === "string"
          )
        : [];
      if (tokens.length === 0) continue;

      const content =
        tier === "48h"
          ? {
              title: "¿Seguís hablando?",
              body: "Puedes responder o cerrar la conversación con elegancia.",
            }
          : {
              title: "Te toca responder",
              body: "Tienes una conversación esperando en Attra.",
            };

      await getMessaging()
        .sendEachForMulticast({
          tokens,
          notification: content,
          data: { route: "chats", kind: "anti_ghosting_nudge" },
          android: { priority: "high", notification: { color: "#FF4F68" } },
          apns: { payload: { aps: { sound: "default" } } },
        })
        .catch(() => undefined);
      sent++;
    }
    console.log(`[pendingReplyNudges] sent=${sent}`);
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// §6 — Follow-up post-cita: responder a "¿Cómo fue la cita?"
// ─────────────────────────────────────────────────────────────────────────────

const FOLLOWUP_ANSWERS = [
  "keep_talking",
  "no_connection",
  "prefer_end",
  "uncomfortable",
  "report",
];

/// Registra la respuesta al follow-up post-cita. NO cierra ni reporta por sí
/// mismo: el cliente encadena el cierre elegante o el reporte con sus flujos
/// existentes (que ya validan seguridad). Solo marca el estado.
export const answerDateFollowUp = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const chatId = requireStringArg(request.data?.chatId, "chatId");
  const answer = requireStringArg(request.data?.answer, "answer");
  if (!FOLLOWUP_ANSWERS.includes(answer)) {
    throw new HttpsError("invalid-argument", "Respuesta no válida.");
  }

  const chatRef = col.chats.doc(chatId);
  const snap = await chatRef.get();
  if (!snap.exists) throw new HttpsError("not-found", "El chat no existe.");
  const users: string[] = (snap.data()?.users ?? []) as string[];
  if (!users.includes(uid)) {
    throw new HttpsError("permission-denied", "No participas en este chat.");
  }

  await chatRef.set(
    {
      dateFollowUpStatus: "answered",
      dateFollowUpAnswer: answer,
      dateFollowUpAnsweredAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  return { ok: true };
});

// ─────────────────────────────────────────────────────────────────────────────
// §7 — Score interno de fiabilidad conversacional (NUNCA público)
// ─────────────────────────────────────────────────────────────────────────────

export interface ReliabilityStats {
  closedChatsRespectfullyCount: number;
  ghostedChatsCount: number;
  ghostedAfterDateCount: number;
  reportedByOthersCount: number;
  blockedByOthersCount: number;
  replyRate48h: number; // 0..1 (default 1)
}

export function readReliabilityStats(
  data: DocumentData | undefined
): ReliabilityStats {
  const s = (data?.connectionReliabilityStats ?? {}) as DocumentData;
  const num = (v: unknown, d = 0): number =>
    typeof v === "number" && Number.isFinite(v) ? v : d;
  return {
    closedChatsRespectfullyCount: num(s.closedChatsRespectfullyCount),
    ghostedChatsCount: num(s.ghostedChatsCount),
    ghostedAfterDateCount: num(s.ghostedAfterDateCount),
    reportedByOthersCount: num(s.reportedByOthersCount),
    blockedByOthersCount: num(s.blockedByOthersCount),
    replyRate48h: num(s.replyRate48h, 1),
  };
}

/// Score 0..100. Conservador: penaliza ghosting (especialmente tras cita) y
/// reportes; premia cierres respetuosos y buen ratio de respuesta. NUNCA se
/// penaliza por bloquear/reportar (eso es seguridad, no ghosting).
export function computeReliabilityScore(s: ReliabilityStats): number {
  let score = 100;
  score -= Math.min(40, s.ghostedChatsCount * 6);
  score -= Math.min(30, s.ghostedAfterDateCount * 15);
  score -= Math.min(20, s.reportedByOthersCount * 10);
  score -= Math.min(10, s.blockedByOthersCount * 3);
  score += Math.min(10, s.closedChatsRespectfullyCount * 2);
  // replyRate48h en [0,1]: (rate-1)*10 ∈ [-10,0] -> penaliza respuesta lenta.
  score += Math.round((Math.max(0, Math.min(1, s.replyRate48h)) - 1) * 10);
  return Math.max(0, Math.min(100, Math.round(score)));
}

/// §8 badge positivo: solo si responde y cierra con respeto, sin ghosting grave
/// ni reportes recientes. Nunca expone porcentajes ni rankings.
export function qualifiesForBadge(
  s: ReliabilityStats,
  score: number
): boolean {
  return (
    score >= 75 &&
    s.ghostedChatsCount <= 1 &&
    s.ghostedAfterDateCount === 0 &&
    s.reportedByOthersCount === 0 &&
    s.closedChatsRespectfullyCount >= 1
  );
}

export const recomputeReliabilityScores = onSchedule(
  { schedule: "every 24 hours", region: REGION },
  async () => {
    if (
      !(await antiGhostingFlag("anti_ghosting_reliability_score_enabled", false))
    ) {
      console.log("[reliability] flag off; skip");
      return;
    }
    const badgeOn = await antiGhostingFlag(
      "anti_ghosting_reliability_badge_enabled",
      false
    );
    // v1: lote acotado por ejecución (cap). Producción: cursorar por
    // connectionReliabilityStats.lastReliabilityScoreCalculatedAt.
    const snap = await col.users.limit(500).get();
    let updated = 0;
    for (const doc of snap.docs) {
      const data = doc.data();
      if (data.isBot === true || data.isDeleted === true) continue;
      const stats = readReliabilityStats(data);
      const score = computeReliabilityScore(stats);
      const badge = badgeOn && qualifiesForBadge(stats, score);
      await doc.ref
        .set(
          {
            connectionReliabilityScore: score,
            hasReliabilityBadge: badge,
            // merge anidado: solo toca la marca de tiempo, conserva contadores.
            connectionReliabilityStats: {
              lastReliabilityScoreCalculatedAt: FieldValue.serverTimestamp(),
            },
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        )
        .catch(() => undefined);
      updated++;
    }
    console.log(`[reliability] updated=${updated}`);
  }
);
