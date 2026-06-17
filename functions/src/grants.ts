import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall } from "firebase-functions/v2/https";
import { FieldValue, DocumentData } from "firebase-admin/firestore";
import { db } from "./firebase";
import { col, requireAuthUid } from "./common";

/// Pack mensual de Attras incluido en los planes de pago (Plus/Premium/Pro).
///
/// Backend-autoritativo: el cliente nunca acredita saldo. Un job programado
/// concede, una vez por periodo natural (`YYYYMM`), los Attras incluidos al
/// wallet de cada usuario con plan de pago ACTIVO. Idempotente: el wallet
/// guarda `monthlyGrantPeriod`, asi que reejecutar el job no duplica.

const PAID_TIERS = ["plus", "premium", "pro"] as const;

/// Periodo natural en UTC (YYYYMM) para la idempotencia del grant.
function currentPeriod(date = new Date()): string {
  return date.toISOString().slice(0, 7).replace("-", "");
}

/// True si el entitlement es de pago y sigue activo (no caducado).
function isPaidActive(entData: DocumentData | undefined): boolean {
  if (!entData) return false;
  const tier = (entData.tier ?? "free").toString();
  if (!PAID_TIERS.includes(tier as (typeof PAID_TIERS)[number])) return false;
  if (entData.isLifetime === true) return true;
  const expiresAt = entData.expiresAt;
  if (expiresAt?.toMillis) return expiresAt.toMillis() >= Date.now();
  return true;
}

/// Attras incluidos segun tier, leidos de config/featureFlags (mismos campos
/// que consume el cliente), con los defaults del producto.
function monthlyAttrasForTier(tier: string, flags: DocumentData): number {
  if (flags.attrasEnabled === false) return 0;
  const n = (key: string, fallback: number): number => {
    const v = flags[key];
    if (typeof v === "number") return v;
    if (typeof v === "string") return parseInt(v, 10) || fallback;
    return fallback;
  };
  switch (tier) {
    case "plus":
      return n("plusMonthlyAttras", 3);
    case "premium":
      return n("premiumMonthlyAttras", 10);
    case "pro":
      return n("proMonthlyAttras", 15);
    default:
      return 0;
  }
}

/// Concede (idempotente) el pack mensual a un usuario. Devuelve los Attras
/// acreditados (0 si ya estaba concedido este periodo o el plan no esta activo).
async function grantOne(
  uid: string,
  entData: DocumentData | undefined,
  flags: DocumentData,
  period: string
): Promise<number> {
  if (!isPaidActive(entData)) return 0;
  const amount = monthlyAttrasForTier((entData?.tier ?? "free").toString(), flags);
  if (amount <= 0) return 0;

  const walletRef = col.wallets.doc(uid);
  const ledgerRef = col.ledger.doc();
  return db.runTransaction(async (tx): Promise<number> => {
    const wallet = await tx.get(walletRef);
    if ((wallet.data()?.monthlyGrantPeriod ?? "") === period) return 0;

    const balance = (wallet.data()?.balance ?? 0) as number;
    const newBalance = balance + amount;
    const now = FieldValue.serverTimestamp();
    tx.set(
      walletRef,
      { balance: newBalance, monthlyGrantPeriod: period, updatedAt: now },
      { merge: true }
    );
    tx.set(ledgerRef, {
      uid,
      type: "monthly_grant",
      amount,
      balanceAfter: newBalance,
      period,
      createdAt: now,
    });
    return amount;
  });
}

/// Recorre los entitlements de pago y concede el pack mensual. Compartido por
/// el job programado y el disparador manual (testing/backfill de periodo).
async function runMonthlyGrant(): Promise<{
  period: string;
  granted: number;
  credited: number;
}> {
  const period = currentPeriod();
  const cfgSnap = await db.collection("config").doc("featureFlags").get();
  const flags = cfgSnap.data() ?? {};

  let granted = 0;
  let credited = 0;
  let lastId: string | null = null;
  const pageSize = 300;

  // Paginacion por __name__ sobre los entitlements de pago.
  // eslint-disable-next-line no-constant-condition
  while (true) {
    let q = col.entitlements
      .where("tier", "in", PAID_TIERS as unknown as string[])
      .orderBy("__name__")
      .limit(pageSize);
    if (lastId) q = q.startAfter(lastId);
    const snap = await q.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      lastId = doc.id;
      const amount = await grantOne(doc.id, doc.data(), flags, period);
      if (amount > 0) {
        granted += 1;
        credited += amount;
      }
    }
    if (snap.size < pageSize) break;
  }

  return { period, granted, credited };
}

/// Job diario: concede el pack mensual a quien le toque este periodo. Se ejecuta
/// a diario (no mensual) para que un alta nueva reciba su pack en <24h sin
/// depender de la fecha exacta de renovacion; la idempotencia evita duplicar.
export const grantMonthlyAttras = onSchedule("every 24 hours", async () => {
  const result = await runMonthlyGrant();
  console.log(
    `[grantMonthlyAttras] period=${result.period} granted=${result.granted} credited=${result.credited}`
  );
});

/// Disparador manual (solo sesion valida) para forzar la concesion del periodo
/// actual: util en testing o tras cambiar los importes en config/featureFlags.
export const runMonthlyAttraGrant = onCall(async (request) => {
  requireAuthUid(request.auth);
  return runMonthlyGrant();
});
