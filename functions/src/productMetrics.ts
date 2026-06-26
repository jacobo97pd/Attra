import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { FieldValue, DocumentData } from "firebase-admin/firestore";
import { REGION, db } from "./firebase";

/// MÉTRICAS DE PRODUCTO (Fase 13). Privadas/admin: el cliente NO las lee.
///
/// Estrategia barata y exacta: un trigger incrementa contadores por DÍA y por
/// VERSIÓN de ranking en `productMetrics/{YYYY-MM-DD}` (sin escaneos). El job
/// nocturno deriva las TASAS del día anterior con las mismas fórmulas que el
/// cliente (FunnelMetrics).

const DATABASE = "attra-database";
const metrics = db.collection("productMetrics");

function dayKey(d: Date): string {
  return d.toISOString().slice(0, 10); // YYYY-MM-DD (UTC)
}

/// Cada evento del embudo → +1 al contador del día y de la versión de ranking.
export const productMetricsOnEvent = onDocumentCreated(
  { document: "feedEvents/{eventId}", database: DATABASE, region: REGION },
  async (event) => {
    const d = event.data?.data() as DocumentData | undefined;
    if (!d) return;
    const name = (d.event ?? "").toString();
    if (!name) return;
    const version = (d.rankingVersion ?? "unknown").toString();
    const key = dayKey(new Date());
    try {
      await metrics.doc(key).set(
        {
          [`counts.${name}`]: FieldValue.increment(1),
          [`byVersion.${version}.${name}`]: FieldValue.increment(1),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    } catch (e) {
      console.error(`[metrics] incremento ${name} falló: ${(e as Error).message}`);
    }
  }
);

function ratio(num: number, den: number): number {
  if (den <= 0) return 0;
  const r = num / den;
  return r < 0 ? 0 : r > 1 ? 1 : r;
}

/// Tasas del día (mismas fórmulas que FunnelMetrics en el cliente).
function ratesFrom(c: Record<string, number>): Record<string, number> {
  const v = (k: string) => Number(c[k] ?? 0);
  const decisions = v("likeSent") + v("nopeSent") + v("attraSent");
  const likesPlusAttras = v("likeSent") + v("attraSent");
  return {
    likeRate: ratio(likesPlusAttras, decisions),
    matchRate: ratio(v("matchCreated"), likesPlusAttras),
    conversationStartRate: ratio(v("conversationStarted"), v("matchCreated")),
    replyRate: ratio(v("messageSent") - v("firstMessageSent"), v("firstMessageSent")),
    gameCompletionRate: ratio(v("gameCompleted"), v("gameStarted")),
    dateProposalRate: ratio(v("dateProposed"), v("matchCreated")),
    dateAcceptanceRate: ratio(v("dateAccepted"), v("dateProposed")),
  };
}

/// Cierra el día anterior: calcula y guarda las tasas en su doc.
export const productMetricsFinalize = onSchedule(
  { schedule: "every 24 hours", region: REGION },
  async () => {
    const yesterday = new Date(Date.now() - 24 * 3600 * 1000);
    const key = dayKey(yesterday);
    const snap = await metrics.doc(key).get();
    if (!snap.exists) {
      console.log(`[metrics] ${key}: sin eventos`);
      return;
    }
    const data = snap.data() ?? {};
    const counts = (data.counts ?? {}) as Record<string, number>;
    const rates = ratesFrom(counts);

    // Fairness: % de usuarios nuevos (creados ese día) con exposición mínima
    // (aparecieron como targetUid en algún evento). Acotado.
    let newUsers = 0;
    let withExposure = 0;
    try {
      const start = new Date(`${key}T00:00:00.000Z`);
      const end = new Date(start.getTime() + 24 * 3600 * 1000);
      const usersSnap = await db
        .collection("users")
        .where("createdAt", ">=", start)
        .where("createdAt", "<", end)
        .limit(1000)
        .get();
      newUsers = usersSnap.size;
      // Exposición: marca en rankingSignals (inbound>0 o messageCount>0).
      for (const u of usersSnap.docs) {
        const sig = await db.collection("rankingSignals").doc(u.id).get();
        const s = sig.data() ?? {};
        if (Number(s.inboundLikeCount ?? 0) > 0 || Number(s.matchCount ?? 0) > 0) {
          withExposure += 1;
        }
      }
    } catch (e) {
      console.error(`[metrics] fairness ${key}: ${(e as Error).message}`);
    }

    await metrics.doc(key).set(
      {
        rates: { ...rates, newUserMinExposureRate: ratio(withExposure, newUsers) },
        newUsers,
        newUsersWithExposure: withExposure,
        finalizedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    console.log(`[metrics] ${key}: tasas calculadas (likeRate=${rates.likeRate.toFixed(3)})`);
  }
);
