import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import {
  FieldValue,
  DocumentData,
  DocumentSnapshot,
  QueryDocumentSnapshot,
} from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
import { activeEntitlementTier, col, requireAuthUid } from "./common";

/// Pack mensual incluido en cada plan: Attras Y Boosts.
///
/// Backend-autoritativo: el cliente nunca acredita saldo. Un job programado
/// concede lo incluido al wallet de cada usuario segun su tier ACTIVO.
/// Idempotente: el wallet guarda la fecha de la ultima concesion y no se vuelve
/// a conceder hasta que pase la ventana, asi que reejecutar el job no duplica.
///
/// QUE FALLABA (1): el pack solo daba Attras. `PremiumFeature.monthlyBoost` se
/// anunciaba en el paywall pero NADIE concedia Boosts nunca: el saldo de
/// `users.wallet.boosts` solo subia comprando. Ahora el grant tambien acredita
/// Boosts, que es lo que hace real la promesa de "N Boosts al mes".
///
/// QUE FALLABA (2): `isPaidActive` cortaba antes de tiempo y Free recibia 0.
/// Free es el escalon donde se decide la conversion, asi que ahora tambien
/// entra en el barrido y recibe 1 Attra al mes (ver `sweepFreeUsers` para el
/// coste y como se acota).

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

/// Acotado del barrido de usuarios Free (ver `sweepFreeUsers`).
const FREE_SCAN_PAGE_SIZE = 300;
/// Solo usuarios que han entrado en los ultimos 30 dias. Un usuario dormido no
/// necesita su Attra mensual: lo recibira el dia que vuelva (el job corre a
/// diario y la ventana es de 31 dias, asi que como mucho espera 24 h).
const FREE_SCAN_MAX_INACTIVITY_MS = 30 * 24 * 60 * 60 * 1000;
/// Tope duro de usuarios por ejecucion. Protege el timeout de la funcion y la
/// factura de lecturas: el barrido va de MAS reciente a MENOS, asi que si algun
/// dia se corta, los que se quedan fuera son los menos activos y entran al dia
/// siguiente (o el dia que vuelvan a abrir la app, que los pone los primeros).
const FREE_SCAN_MAX_USERS = 18000;

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

/// Lee un entero de `config/featureFlags` aceptando las dos variantes de nombre
/// (snake_case y camelCase), igual que hace el parser del cliente.
function flagInt(
  flags: DocumentData,
  snakeKey: string,
  camelKey: string,
  fallback: number
): number {
  const raw = flags[snakeKey] ?? flags[camelKey];
  if (typeof raw === "number" && Number.isFinite(raw)) return Math.floor(raw);
  if (typeof raw === "string") {
    const parsed = parseInt(raw, 10);
    if (Number.isFinite(parsed)) return parsed;
  }
  return fallback;
}

/// Attras incluidos segun tier, leidos de config/featureFlags (mismos campos
/// que consume el cliente), con los defaults del producto.
function monthlyAttrasForTier(tier: string, flags: DocumentData): number {
  if (flags.attrasEnabled === false) return 0;
  switch (tier) {
    case "plus":
      return flagInt(flags, "plus_monthly_attras", "plusMonthlyAttras", 5);
    case "premium":
      return flagInt(flags, "premium_monthly_attras", "premiumMonthlyAttras", 10);
    case "pro":
      return flagInt(flags, "pro_monthly_attras", "proMonthlyAttras", 15);
    case "free":
      // El gancho de conversion: Free prueba el producto de verdad una vez al
      // mes. Antes recibia 0 y nunca llegaba a ver para que sirve un Attra.
      return flagInt(flags, "free_monthly_attras", "freeMonthlyAttras", 1);
    default:
      return 0;
  }
}

/// Boosts incluidos segun tier. Con el Superboost a 3 Boosts (ver boosts.ts) el
/// saldo es una sola moneda: Pro recibe 4 = un Superboost + un Boost, o cuatro
/// Boosts cortos, como prefiera.
function monthlyBoostsForTier(tier: string, flags: DocumentData): number {
  switch (tier) {
    case "plus":
      return flagInt(flags, "plus_monthly_boosts", "plusMonthlyBoosts", 1);
    case "premium":
      return flagInt(flags, "premium_monthly_boosts", "premiumMonthlyBoosts", 2);
    case "pro":
      return flagInt(flags, "pro_monthly_boosts", "proMonthlyBoosts", 4);
    case "free":
      return flagInt(flags, "free_monthly_boosts", "freeMonthlyBoosts", 0);
    default:
      return 0;
  }
}

/// True si al wallet le toca pack (no hay concesion previa o ya paso la
/// ventana). Se usa como PREFILTRO fuera de transaccion para no abrir una
/// transaccion (2 lecturas + bloqueo) por cada usuario que no toca.
function isGrantDue(
  walletData: DocumentData | undefined,
  period: string,
  now: number
): boolean {
  const lastGrantMs = millisFromDateLike(walletData?.lastMonthlyGrantAt);
  if (lastGrantMs !== null) return now - lastGrantMs >= GRANT_WINDOW_MS;
  // Wallets anteriores a la ventana solo tienen `monthlyGrantPeriod`: se
  // respeta una vez para no regalar un pack extra en la migracion.
  return (walletData?.monthlyGrantPeriod ?? "") !== period;
}

interface GrantResult {
  attras: number;
  boosts: number;
}

const NO_GRANT: GrantResult = { attras: 0, boosts: 0 };

/// Concede (idempotente) el pack mensual a un usuario ya resuelto a un tier
/// ACTIVO. Devuelve lo acreditado (ceros si aun no toca o el tier no incluye
/// nada).
async function grantOne(
  uid: string,
  tier: string,
  flags: DocumentData,
  period: string
): Promise<GrantResult> {
  const attras = monthlyAttrasForTier(tier, flags);
  const boosts = monthlyBoostsForTier(tier, flags);
  if (attras <= 0 && boosts <= 0) return NO_GRANT;

  const walletRef = col.wallets.doc(uid);
  const userRef = col.users.doc(uid);
  const ledgerRef = col.ledger.doc();
  return db.runTransaction(async (tx): Promise<GrantResult> => {
    const [wallet, userSnap] = await Promise.all([
      tx.get(walletRef),
      tx.get(userRef),
    ]);
    const walletData = wallet.data();
    const now = Date.now();

    // Idempotencia por ventana (revalidada DENTRO de la transaccion: el
    // prefiltro de fuera puede estar desfasado si dos ejecuciones se solapan).
    if (!isGrantDue(walletData, period, now)) return NO_GRANT;

    // La app lee el saldo de `users/{uid}.attrasBalance` y sendAttra lo gasta
    // desde `attraWallets/{uid}.balance`: el pack se acreditaba solo en el
    // wallet, asi que el usuario nunca lo veia. Ahora se escriben los dos. Si el
    // wallet aun no existe se parte del espejo del usuario para no borrar saldo
    // que ya tuviera.
    const base = wallet.exists
      ? Number(walletData?.balance ?? 0)
      : Number(userSnap.data()?.attrasBalance ?? 0);
    const newBalance = base + attras;
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
    // lo creamos a medias: el saldo de Attras sigue vivo en el wallet. Los
    // Boosts SI se perderian en ese caso (viven solo en `users`), pero un
    // entitlement sin doc de usuario es una cuenta rota, no un caso real.
    if (userSnap.exists) {
      tx.set(
        userRef,
        {
          attrasBalance: newBalance,
          // Los Boosts se acreditan con increment para respetar el saldo previo
          // (comprado o sobrante del mes anterior): NUNCA se pisa.
          ...(boosts > 0
            ? {
                wallet: {
                  boosts: FieldValue.increment(boosts),
                  boostsUpdatedAt: serverNow,
                },
              }
            : {}),
          updatedAt: serverNow,
        },
        { merge: true }
      );
    }
    tx.set(ledgerRef, {
      uid,
      type: "monthly_grant",
      tier,
      amount: attras,
      boosts,
      balanceAfter: newBalance,
      period,
      createdAt: serverNow,
    });
    return { attras, boosts };
  });
}

interface SweepTotals {
  granted: number;
  attras: number;
  boosts: number;
}

function addGrant(totals: SweepTotals, result: GrantResult): void {
  if (result.attras <= 0 && result.boosts <= 0) return;
  totals.granted += 1;
  totals.attras += result.attras;
  totals.boosts += result.boosts;
}

/// Pasada 1: entitlements de pago. Devuelve ademas el conjunto de uids con plan
/// de pago ACTIVO, para que la pasada de Free no los vuelva a tocar (si un Pro
/// cobrase el pack de Free se quemaria su ventana con 1 Attra en vez de 15).
async function sweepPaidUsers(
  flags: DocumentData,
  period: string,
  totals: SweepTotals
): Promise<Set<string>> {
  const paidActiveUids = new Set<string>();
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
      // `activeEntitlementTier` devuelve "free" si el plan caduco: ese usuario
      // NO se marca como de pago y lo recoge la pasada de Free, que es lo
      // correcto (ya no paga, pero sigue mereciendo su Attra gratis).
      const tier = activeEntitlementTier(doc.data());
      if (tier === "free") continue;
      paidActiveUids.add(doc.id);
      addGrant(totals, await grantOne(doc.id, tier, flags, period));
    }
    if (snap.size < pageSize) break;
  }
  return paidActiveUids;
}

/// Pasada 2: usuarios Free activos.
///
/// COSTE: es la parte cara, porque Free es la inmensa mayoria de la base. Se
/// acota en tres sitios para que no se dispare:
///   1. Solo usuarios con `lastLoginAt` en los ultimos 30 dias (la consulta ya
///      filtra en Firestore: los dormidos no se leen ni se pagan).
///   2. Prefiltro del wallet en lote (`getAll`) antes de abrir transaccion: la
///      ventana es de 31 dias, asi que ~97% de los usuarios de cada ejecucion
///      NO tocan y se descartan con 2 lecturas (usuario + wallet) en vez de 4
///      (usuario + wallet + las 2 de la transaccion).
///   3. Tope duro de FREE_SCAN_MAX_USERS por ejecucion.
/// Con 18.000 usuarios activos: ~36.000 lecturas/dia (~1,1 M/mes ≈ 0,65 $/mes
/// a 0,06 $/100k). Con la pasada de pago aparte, sigue siendo calderilla frente
/// a lo que aporta el gancho de conversion.
async function sweepFreeUsers(
  flags: DocumentData,
  period: string,
  totals: SweepTotals,
  paidActiveUids: Set<string>
): Promise<{ scanned: number; truncated: boolean }> {
  const now = Date.now();
  const since = new Date(now - FREE_SCAN_MAX_INACTIVITY_MS);
  let cursor: QueryDocumentSnapshot<DocumentData> | null = null;
  let scanned = 0;

  // eslint-disable-next-line no-constant-condition
  while (true) {
    if (scanned >= FREE_SCAN_MAX_USERS) return { scanned, truncated: true };
    // Orden descendente por `lastLoginAt`: primero los mas activos. Como
    // `lastLoginAt` solo avanza, un usuario que entra a mitad del barrido salta
    // por delante del cursor y, como mucho, se queda para la ejecucion de
    // manana; nunca se pierde el pack. Los usuarios sin `lastLoginAt` (cuentas
    // que nunca han entrado) quedan fuera del filtro a proposito.
    let q = col.users
      .where("lastLoginAt", ">=", since)
      .orderBy("lastLoginAt", "desc")
      .limit(FREE_SCAN_PAGE_SIZE);
    if (cursor) q = q.startAfter(cursor);
    const snap = await q.get();
    if (snap.empty) break;
    cursor = snap.docs[snap.docs.length - 1];

    const candidates = snap.docs.filter((doc) => {
      const data = doc.data();
      // Cuentas baneadas o borradas no reciben nada.
      if (data.isBanned === true || data.isDeleted === true) return false;
      return !paidActiveUids.has(doc.id);
    });
    scanned += snap.size;
    if (candidates.length === 0) {
      if (snap.size < FREE_SCAN_PAGE_SIZE) break;
      continue;
    }

    // Prefiltro en lote: una sola ronda de lecturas para saber a quien le toca.
    const walletSnaps: DocumentSnapshot<DocumentData>[] = await db.getAll(
      ...candidates.map((doc) => col.wallets.doc(doc.id))
    );
    for (let i = 0; i < candidates.length; i++) {
      if (!isGrantDue(walletSnaps[i]?.data(), period, now)) continue;
      addGrant(totals, await grantOne(candidates[i].id, "free", flags, period));
    }

    if (snap.size < FREE_SCAN_PAGE_SIZE) break;
  }
  return { scanned, truncated: false };
}

/// Recorre a quien le toca y concede el pack mensual. Compartido por el job
/// programado y el disparador manual (testing/backfill de periodo).
async function runMonthlyGrant(): Promise<{
  period: string;
  granted: number;
  credited: number;
  creditedBoosts: number;
  freeScanned: number;
  freeTruncated: boolean;
}> {
  const period = currentPeriod();
  const cfgSnap = await db.collection("config").doc("featureFlags").get();
  const flags = cfgSnap.data() ?? {};

  const totals: SweepTotals = { granted: 0, attras: 0, boosts: 0 };
  const paidActiveUids = await sweepPaidUsers(flags, period, totals);
  const free = await sweepFreeUsers(flags, period, totals, paidActiveUids);

  return {
    period,
    granted: totals.granted,
    credited: totals.attras,
    creditedBoosts: totals.boosts,
    freeScanned: free.scanned,
    freeTruncated: free.truncated,
  };
}

/// Job diario: concede el pack mensual a quien le toque. Se ejecuta a diario
/// (no mensual) para que un alta nueva reciba su pack en <24h sin depender de la
/// fecha exacta de renovacion; la ventana de idempotencia evita duplicar.
///
/// `timeoutSeconds`/`memory`: con el default (60 s, 256 MiB) el barrido de Free
/// no cabia ni de lejos. `region` fijada a la de la base de datos: sin ella la
/// funcion se desplegaba en us-central1 y cada lectura cruzaba el Atlantico.
export const grantMonthlyAttras = onSchedule(
  {
    schedule: "every 24 hours",
    region: REGION,
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const result = await runMonthlyGrant();
    console.log(
      `[grantMonthlyAttras] period=${result.period} granted=${result.granted} ` +
        `attras=${result.credited} boosts=${result.creditedBoosts} ` +
        `freeScanned=${result.freeScanned} freeTruncated=${result.freeTruncated}`
    );
    if (result.freeTruncated) {
      console.warn(
        `[grantMonthlyAttras] barrido Free cortado en ${FREE_SCAN_MAX_USERS} ` +
          "usuarios: sube el tope o pasa a un reparto por lotes."
      );
    }
  }
);

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
// El timeout tambien se sube aqui: desde que Free entra en el barrido, este
// callable hace el mismo trabajo largo que el job.
export const runMonthlyAttraGrant = onCall(
  { region: REGION, timeoutSeconds: 540, memory: "512MiB" },
  async (request) => {
    const uid = requireAuthUid(request.auth);
    if (request.auth?.token?.admin !== true) {
      throw new HttpsError("permission-denied", "Solo administradores.");
    }
    console.log(`[runMonthlyAttraGrant] disparo manual por uid=${uid}`);
    return runMonthlyGrant();
  }
);
