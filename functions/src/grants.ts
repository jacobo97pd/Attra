import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue, DocumentData } from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
import { col, requireAuthUid } from "./common";

/// Pack mensual de Attras incluido en los planes de pago (Plus/Premium/Pro).
///
/// Backend-autoritativo: el cliente nunca acredita saldo. Un job programado
/// concede los Attras incluidos al wallet de cada usuario con plan de pago
/// ACTIVO. Idempotente: el wallet guarda la fecha de la ultima concesion y no
/// se vuelve a conceder hasta que pase la ventana, asi que reejecutar el job no
/// duplica.

const PAID_TIERS = ["plus", "premium", "pro"] as const;

/// Ventana minima entre packs. Antes la idempotencia usaba el mes natural en
/// UTC (`YYYYMM`): el job diario concedia el dia 31 y otra vez el dia 1, dos
/// packs en menos de 24h. Con una ventana desde la ultima concesion eso ya no
/// puede pasar; 30 dias mantiene ~12 packs/ano aunque el mes sea corto.
// Ventana entre packs. 30 dias exactos derivan: 365/30 = 12,17, asi que algunos
// anos se conceden 13 packs en vez de 12. Con 31 dias el desplazamiento juega a
// favor de la empresa (11,7 packs/ano como maximo) sin llegar nunca a saltarse
// un mes para el usuario, porque el barrido corre a diario.
const GRANT_WINDOW_MS = 31 * 24 * 60 * 60 * 1000;

/// Periodo natural en UTC (YYYYMM). Ya no gobierna la idempotencia (ver
/// GRANT_WINDOW_MS), se conserva como etiqueta del ledger y para respetar las
/// concesiones que quedaron marcadas con el esquema anterior.
function currentPeriod(date = new Date()): string {
  return date.toISOString().slice(0, 7).replace("-", "");
}

function millisFromDateLike(value: unknown): number | null {
  if (!value) return null;
  if (value instanceof Date) return value.getTime();
  if (typeof value === "object" && "toMillis" in value) {
    const maybeTimestamp = value as { toMillis?: unknown };
    if (typeof maybeTimestamp.toMillis === "function") {
      const ms = maybeTimestamp.toMillis();
      return typeof ms === "number" ? ms : null;
    }
  }
  if (typeof value === "string") {
    const ms = Date.parse(value);
    return Number.isNaN(ms) ? null : ms;
  }
  return null;
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
/// acreditados (0 si aun no toca o el plan no esta activo).
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
  const userRef = col.users.doc(uid);
  const ledgerRef = col.ledger.doc();
  return db.runTransaction(async (tx): Promise<number> => {
    const [wallet, userSnap] = await Promise.all([
      tx.get(walletRef),
      tx.get(userRef),
    ]);
    const walletData = wallet.data();
    const now = Date.now();

    const lastGrantMs = millisFromDateLike(walletData?.lastMonthlyGrantAt);
    if (lastGrantMs !== null && now - lastGrantMs < GRANT_WINDOW_MS) return 0;
    // Wallets anteriores a la ventana solo tienen `monthlyGrantPeriod`: se
    // respeta una vez para no regalar un pack extra en la migracion.
    if (lastGrantMs === null && (walletData?.monthlyGrantPeriod ?? "") === period) {
      return 0;
    }

    // La app lee el saldo de `users/{uid}.attrasBalance` y sendAttra lo gasta
    // desde `attraWallets/{uid}.balance`: el pack se acreditaba solo en el
    // wallet, asi que el usuario nunca lo veia. Ahora se escriben los dos. Si el
    // wallet aun no existe se parte del espejo del usuario para no borrar saldo
    // que ya tuviera.
    const base = wallet.exists
      ? Number(walletData?.balance ?? 0)
      : Number(userSnap.data()?.attrasBalance ?? 0);
    const newBalance = base + amount;
    const serverNow = FieldValue.serverTimestamp();
    tx.set(
      walletRef,
      {
        balance: newBalance,
        monthlyGrantPeriod: period,
        lastMonthlyGrantAt: serverNow,
        updatedAt: serverNow,
      },
      { merge: true }
    );
    // Espejo de solo-lectura para el cliente. Si el doc de usuario no existe no
    // lo creamos a medias: el saldo sigue vivo en el wallet.
    if (userSnap.exists) {
      tx.set(userRef, { attrasBalance: newBalance, updatedAt: serverNow }, { merge: true });
    }
    tx.set(ledgerRef, {
      uid,
      type: "monthly_grant",
      amount,
      balanceAfter: newBalance,
      period,
      createdAt: serverNow,
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

/// Job diario: concede el pack mensual a quien le toque. Se ejecuta a diario
/// (no mensual) para que un alta nueva reciba su pack en <24h sin depender de la
/// fecha exacta de renovacion; la ventana de idempotencia evita duplicar.
export const grantMonthlyAttras = onSchedule("every 24 hours", async () => {
  const result = await runMonthlyGrant();
  console.log(
    `[grantMonthlyAttras] period=${result.period} granted=${result.granted} credited=${result.credited}`
  );
});

/// Disparador manual (testing o tras cambiar los importes en
/// config/featureFlags).
///
/// Antes bastaba con estar autenticado: CUALQUIER usuario podia lanzar un
/// escaneo completo de `userEntitlements` (coste de lecturas + DoS trivial).
/// Se mantiene como callable en vez de convertirla en tarea programada porque
/// `grantMonthlyAttras` ya hace justo eso a diario y un segundo scheduler seria
/// trabajo duplicado; lo que aporta esta es el disparo bajo demanda, asi que se
/// restringe a admins (claim `admin` en el token, que solo se pone server-side).
// Sin `region` se desplegaba en us-central1 mientras la app llama a
// europe-west1 (lib/app.dart), asi que era inalcanzable: NOT_FOUND en vez de
// permission-denied.
export const runMonthlyAttraGrant = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  if (request.auth?.token?.admin !== true) {
    throw new HttpsError("permission-denied", "Solo administradores.");
  }
  console.log(`[runMonthlyAttraGrant] disparo manual por uid=${uid}`);
  return runMonthlyGrant();
});
