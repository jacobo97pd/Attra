import { onDocumentCreated, onDocumentWritten } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { FieldValue, DocumentData, Timestamp } from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
import { col } from "./common";

/// Señales de ranking (BACKEND-AUTORITATIVO). Triggers AISLADOS que solo
/// ESCRIBEN en `rankingSignals/{uid}` a partir de eventos existentes (likes,
/// matches, mensajes, reportes, bloqueos, juegos). NO tocan la lógica crítica:
/// si un trigger falla, el flujo original sigue intacto.
///
/// El job nocturno deriva los 5 scores [0..1] que consume el cliente.

const DATABASE = "attra-database";
const signals = db.collection("rankingSignals");

/// Incrementa contadores en rankingSignals/{uid} (merge, idempotente por evento
/// gracias a que los triggers onCreate solo disparan una vez por doc).
async function bump(uid: string, patch: Record<string, unknown>): Promise<void> {
  if (!uid) return;
  try {
    await signals.doc(uid).set(
      { ...patch, recentActivityAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
  } catch (e) {
    console.error(`[ranking] bump ${uid} falló: ${(e as Error).message}`);
  }
}

/// Like → +outbound al emisor, +inbound al receptor.
export const rankingOnLike = onDocumentCreated(
  { document: "likes/{likeId}", database: DATABASE, region: REGION },
  async (event) => {
    const d = event.data?.data() as DocumentData | undefined;
    if (!d) return;
    const fromUid = (d.fromUid ?? "").toString();
    const toUid = (d.toUid ?? "").toString();
    await Promise.all([
      bump(fromUid, { outboundLikeCount: FieldValue.increment(1) }),
      bump(toUid, { inboundLikeCount: FieldValue.increment(1) }),
    ]);
  }
);

/// Match → +matchCount a ambos.
export const rankingOnMatch = onDocumentCreated(
  { document: "matches/{matchId}", database: DATABASE, region: REGION },
  async (event) => {
    const d = event.data?.data() as DocumentData | undefined;
    if (!d) return;
    const users: string[] = Array.isArray(d.users)
      ? (d.users as unknown[]).filter((u): u is string => typeof u === "string")
      : [];
    await Promise.all(
      users.map((u) => bump(u, { matchCount: FieldValue.increment(1) }))
    );
  }
);

/// Mensaje humano → +messageCount al emisor. Si lleva gameSessionId, cuenta como
/// participación en juego. Ignora sistema/contexto.
export const rankingOnMessage = onDocumentCreated(
  {
    document: "chats/{chatId}/messages/{messageId}",
    database: DATABASE,
    region: REGION,
  },
  async (event) => {
    const d = event.data?.data() as DocumentData | undefined;
    if (!d) return;
    const type = (d.type ?? "text").toString();
    if (["system", "like_context", "attra_context"].includes(type)) return;
    const senderId = (d.senderId ?? "").toString();
    if (!senderId || senderId === "system") return;
    const patch: Record<string, unknown> = {
      messageCount: FieldValue.increment(1),
    };
    if (typeof d.gameSessionId === "string" && d.gameSessionId) {
      patch.gameMessageCount = FieldValue.increment(1);
    }
    if (type === "date_proposal") {
      patch.dateProposedCount = FieldValue.increment(1);
    }
    await bump(senderId, patch);
  }
);

/// Reporte → +reportsCount al reportado (baja trustSafety en el job nocturno).
export const rankingOnReport = onDocumentCreated(
  { document: "reports/{reportId}", database: DATABASE, region: REGION },
  async (event) => {
    const d = event.data?.data() as DocumentData | undefined;
    if (!d) return;
    await bump((d.reportedUid ?? "").toString(), {
      reportsCount: FieldValue.increment(1),
    });
  }
);

/// Bloqueo → +blocksCount al bloqueado.
export const rankingOnBlock = onDocumentCreated(
  { document: "blocks/{blockId}", database: DATABASE, region: REGION },
  async (event) => {
    const d = event.data?.data() as DocumentData | undefined;
    if (!d) return;
    await bump((d.blockedUid ?? "").toString(), {
      blocksCount: FieldValue.increment(1),
    });
  }
);

/// Sesión de juego → al pasar a active cuenta "iniciado"; a completed,
/// "completado" (para gameCompletionRate). Idempotente por transición.
export const rankingOnGameSession = onDocumentWritten(
  {
    document: "chats/{chatId}/gameSessions/{sessionId}",
    database: DATABASE,
    region: REGION,
  },
  async (event) => {
    const before = event.data?.before.data() as DocumentData | undefined;
    const after = event.data?.after.data() as DocumentData | undefined;
    if (!after) return;
    const prev = (before?.status ?? "").toString();
    const cur = (after.status ?? "").toString();
    if (prev === cur) return;
    const participants = [after.creatorUserId, after.invitedUserId]
      .filter((u): u is string => typeof u === "string" && u.length > 0);
    if (cur === "active" && prev !== "active") {
      await Promise.all(
        participants.map((u) =>
          bump(u, { gameStartedCount: FieldValue.increment(1) })
        )
      );
    } else if (cur === "completed") {
      await Promise.all(
        participants.map((u) =>
          bump(u, { gameCompletedCount: FieldValue.increment(1) })
        )
      );
    }
  }
);

// --- Job nocturno: deriva los 5 scores [0..1] ---

function clamp01(v: number): number {
  return v < 0 ? 0 : v > 1 ? 1 : v;
}

/// profileQualityScore desde users/{uid} (completitud, NO belleza).
function profileQuality(user: DocumentData): number {
  const profile = (user.profile ?? {}) as DocumentData;
  const photos: unknown[] = Array.isArray(user.photos) ? user.photos : [];
  const prompts: unknown[] = Array.isArray(user.profilePrompts)
    ? user.profilePrompts
    : [];
  const bio = (profile.bio ?? "").toString();
  const verification = (user.verification ?? {}) as DocumentData;
  const verified =
    typeof verification.liveSelfiePublicPhotoUrl === "string" &&
    verification.liveSelfiePublicPhotoUrl.length > 0;
  const completion =
    typeof user.profileCompletionPercent === "number"
      ? user.profileCompletionPercent / 100
      : 0;

  const photoScore = (Math.min(photos.length, 4) / 4) * 0.4;
  const bioScore = (Math.min(bio.trim().length, 120) / 120) * 0.2;
  const promptScore = (Math.min(prompts.length, 3) / 3) * 0.2;
  const verifiedScore = verified ? 0.1 : 0;
  const completionScore = completion * 0.1;
  return clamp01(
    photoScore + bioScore + promptScore + verifiedScore + completionScore
  );
}

/// connectionScore: probabilidad de conversación real (ratios acotados).
function connection(s: DocumentData): number {
  const matches = Number(s.matchCount ?? 0);
  const messages = Number(s.messageCount ?? 0);
  const gameStarted = Number(s.gameStartedCount ?? 0);
  const gameDone = Number(s.gameCompletedCount ?? 0);
  const dates = Number(s.dateProposedCount ?? 0);
  // replyRate aproximado: mensajes por match (cap a ~6 mensajes = pleno).
  const replyRate = matches > 0 ? Math.min(messages / (matches * 6), 1) : 0.5;
  const gameRate = gameStarted > 0 ? Math.min(gameDone / gameStarted, 1) : 0.5;
  const dateRate = matches > 0 ? Math.min(dates / matches, 1) : 0;
  return clamp01(replyRate * 0.55 + gameRate * 0.25 + dateRate * 0.2);
}

/// trustSafetyScore: confiabilidad. Penaliza fuerte SOLO con señales claras.
function trustSafety(user: DocumentData, s: DocumentData): number {
  const verification = (user.verification ?? {}) as DocumentData;
  const verified =
    typeof verification.liveSelfiePublicPhotoUrl === "string" &&
    verification.liveSelfiePublicPhotoUrl.length > 0;
  const reports = Number(s.reportsCount ?? 0);
  const blocks = Number(s.blocksCount ?? 0);
  const inbound = Number(s.inboundLikeCount ?? 0);
  const outbound = Number(s.outboundLikeCount ?? 0);
  // "Muchos likes sin reciprocidad" (proxy de spam): outbound alto, inbound ~0.
  const spammy = outbound >= 100 && inbound === 0 ? 0.2 : 0;
  let score = 0.65 + (verified ? 0.15 : 0);
  score -= Math.min(reports, 5) * 0.08;
  score -= Math.min(blocks, 5) * 0.06;
  score -= spammy;
  return clamp01(score);
}

/// Recalcula los scores derivados de los usuarios con actividad reciente. Acota
/// el coste procesando un lote ordenado por actividad.
export const rankingNightly = onSchedule(
  { schedule: "every 24 hours", region: REGION },
  async () => {
    const NEW_USER_DAYS = 7;
    const BATCH = 800;
    const snap = await signals
      .orderBy("recentActivityAt", "desc")
      .limit(BATCH)
      .get();
    if (snap.empty) {
      console.log("[ranking] nightly: sin señales que recomputar");
      return;
    }
    let updated = 0;
    for (const doc of snap.docs) {
      const s = doc.data();
      const uid = doc.id;
      try {
        const userSnap = await col.users.doc(uid).get();
        const user = userSnap.data() ?? {};
        const pq = profileQuality(user);
        const conn = connection(s);
        const trust = trustSafety(user, s);

        // Cold start: usuarios creados hace < NEW_USER_DAYS.
        const createdAt = user.createdAt;
        let newUserBoostUntil: Timestamp | null = null;
        if (createdAt && typeof createdAt.toMillis === "function") {
          const ageMs = Date.now() - createdAt.toMillis();
          if (ageMs < NEW_USER_DAYS * 24 * 3600 * 1000) {
            const until = new Date(
              createdAt.toMillis() + NEW_USER_DAYS * 24 * 3600 * 1000
            );
            newUserBoostUntil = Timestamp.fromDate(until);
          }
        }

        await signals.doc(uid).set(
          {
            profileQualityScore: pq,
            connectionScore: conn,
            trustSafetyScore: trust,
            isNewUserBoostUntil: newUserBoostUntil,
            exposureCount24h: 0, // reset diario del cap
            lastComputedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        updated += 1;
      } catch (e) {
        console.error(`[ranking] nightly ${uid}: ${(e as Error).message}`);
      }
    }
    console.log(`[ranking] nightly: ${updated}/${snap.size} recomputados`);
  }
);
