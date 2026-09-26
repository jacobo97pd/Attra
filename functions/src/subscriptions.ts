import { onCall, HttpsError } from "firebase-functions/v2/https";
import { DocumentSnapshot, FieldValue, Timestamp } from "firebase-admin/firestore";
import { createHash } from "node:crypto";
import { REGION, db } from "./firebase";
import { col, requireAuthUid, activeEntitlementTier } from "./common";
import {
  VerifiedStorePurchase,
  checkStorePurchase,
  readReceiptValidationConfig,
  storeSubscriptionKey,
  storeSubscriptionRef,
} from "./storeValidation";

/// Verificación de SUSCRIPCIONES compradas por IAP (Google Play / App Store).
///
/// ⚠️ El cliente NUNCA concede tier: lanza la compra, recibe el recibo de la
/// tienda y lo envía aquí. Esta función concede el plan en `userEntitlements`
/// (doc write:false para clientes) y es idempotente por compra.
///
/// El recibo se valida contra la tienda ANTES de conceder (ver
/// storeValidation.ts): en iOS, la firma del JWS de StoreKit 2 (siempre); en
/// Android, la Play Developer API (cuando el dueño le dé acceso a la cuenta de
/// servicio; hasta entonces, modo registro). Con la compra verificada, el
/// producto, la caducidad REAL y el id de transacción salen de la tienda, no
/// del cliente. Solo sin verificar (Android en modo 'log') se sigue calculando
/// una caducidad provisional según el periodo.

type Tier = "free" | "plus" | "premium" | "pro";
type Period = "monthly" | "yearly";
type Platform = "app_store" | "play_store";

/// Mapa producto → tier. Cubre:
///  - Productos de Play con PLANES BÁSICOS: `attra_plus` / `attra_pro` (el
///    periodo llega aparte, del plan básico elegido).
///  - IDs por periodo (estilo iOS): `attra_plus_monthly`, etc.
const PRODUCT_TIER: Record<string, Tier> = {
  attra_plus: "plus",
  attra_pro: "pro",
  attra_plus_monthly: "plus",
  attra_plus_yearly: "plus",
  attra_premium_monthly: "premium",
  attra_premium_yearly: "premium",
  attra_pro_monthly: "pro",
  attra_pro_yearly: "pro",
};

/// Orden de los planes: sirve para no DEGRADAR un tier vigente superior.
const TIER_RANK: Record<Tier, number> = {
  free: 0,
  plus: 1,
  premium: 2,
  pro: 3,
};

/// Deduce el periodo SOLO del productId.
///
/// Antes se aceptaba el campo `period` que enviaba el cliente cuando el id no
/// llevaba sufijo: un cliente modificado podía pedir 'yearly' habiendo pagado
/// un mes y llevarse un año de plan. Ahora, si el id no dice el periodo (planes
/// básicos de Play, p. ej. `attra_plus`), se concede el MÁS CORTO (mensual). Es
/// conservador a propósito: con la compra verificada la caducidad sale de la
/// tienda y este periodo ni se usa.
///
/// [stored] es el periodo que quedó guardado en el entitlement la primera vez
/// que se entregó ESE producto. Hace falta al restaurar: la app solo recuerda
/// el periodo elegido mientras dura la sesión, así que un anual de Play que se
/// reentregaba al arrancar llegaba sin periodo y recibía un mes.
export function periodFor(
  productId: string,
  requested: unknown,
  stored: Period | null = null
): Period {
  // El sufijo del id es la fuente FIABLE: no la puede tocar el cliente.
  if (productId.endsWith("_yearly")) return "yearly";
  if (productId.endsWith("_monthly")) return "monthly";
  // Planes basicos de Play: el ANUAL se vende bajo el id BASE (`attra_plus`),
  // asi que el id no dice el periodo y el unico dato disponible es el del
  // cliente. Ignorarlo daba 1 mes a quien pagaba 12 -- un dano MUCHO peor que
  // el fraude que evitaba, porque le pasa a usuarios legitimos y no hay forma
  // de recuperarlo hasta la siguiente renovacion.
  //
  // Es provisional y consciente: solo se llega aqui SIN verificar la compra
  // (Android en modo 'log'), y ahi un cliente modificado puede mentir igual
  // que puede autoconcederse un plan entero, asi que este campo no es el
  // eslabon debil.
  if (requested === "yearly" || requested === "monthly") return requested;
  return stored ?? "monthly";
}

function parsePeriod(value: unknown): Period | null {
  return value === "yearly" || value === "monthly" ? value : null;
}

function parsePlatform(value: unknown): Platform {
  if (value === "app_store" || value === "play_store") return value;
  throw new HttpsError(
    "invalid-argument",
    "platform debe ser 'app_store' o 'play_store'."
  );
}

function normalizeTier(value: unknown): Tier {
  const raw = (value ?? "free").toString();
  return raw === "plus" || raw === "premium" || raw === "pro" ? raw : "free";
}

/// Suma meses de CALENDARIO (no bloques fijos de días).
///
/// Antes se sumaban 31 y 366 días fijos, lo que regalaba entre 1 y 3 días de
/// plan en cada renovación (y casi una semana al año en los mensuales).
/// Se ajusta el día al último del mes destino para que 31-ene + 1 mes sea
/// 28/29-feb y no se desborde a marzo.
function addMonths(from: Date, months: number): Date {
  const day = from.getUTCDate();
  const d = new Date(from.getTime());
  d.setUTCDate(1);
  d.setUTCMonth(d.getUTCMonth() + months);
  const lastDayOfTargetMonth = new Date(
    Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0)
  ).getUTCDate();
  d.setUTCDate(Math.min(day, lastDayOfTargetMonth));
  return d;
}

function expiryFor(period: Period, from: Date): Date {
  return addMonths(from, period === "yearly" ? 12 : 1);
}

/// Margen de una renovacion SIN verificar sobre "un periodo desde hoy" (ver
/// [resolveGrant]). Una semana: de sobra para una primera entrega que se
/// retrasa unos dias, y lo maximo que gana quien encadena ids inventados.
export const UNVERIFIED_RENEWAL_SLACK_MS = 7 * 24 * 60 * 60 * 1000;

/// QUE CONCEDER ante un recibo. Funcion PURA para poder probarla: aqui es donde
/// se decidia mal quien tiene plan y quien no, y no habia un solo test.
///
/// Reglas, por orden:
///  - SUBIDA de plan: manda lo comprado (tier y caducidad). Coger la caducidad
///    mayor permitia comprar Plus ANUAL barato y luego Pro MENSUAL para quedarse
///    un ano de Pro por el precio de un mes.
///  - MISMO plan y MISMO producto todavia VIGENTE: es la MISMA suscripcion
///    reentregada (restaurar compras, reintento, recibo de iOS refrescado), no
///    una renovacion. NO se alarga nada. Sin esto, en iOS cada llamada traia un
///    recibo distinto -y por tanto una clave de compra distinta- y regalaba un
///    periodo: en produccion hay nueve apuntes de la misma suscripcion.
///  - MISMO plan pero caducado, o otro producto (mensual -> anual): es una
///    renovacion o una compra nueva. Se extiende y nunca se acorta.
///  - BAJADA: se conserva el plan alto vigente con SU caducidad. Alargar con una
///    compra mas barata regalaria el plan superior al precio del inferior.
///
/// [storeExpiresAtMs] es la caducidad REAL que da la tienda cuando la compra
/// esta verificada: con ella no hay que adivinar si una entrega es renovacion o
/// reentrega, manda la fecha (y nunca se acorta).
///
/// [newTransaction]: la clave de compra es un id ESTABLE de la tienda (no el
/// hash del recibo) y el ledger no la habia visto nunca. Sin verificar, es la
/// unica señal de que "mismo producto, aun vigente" es una RENOVACION: antes se
/// trataba como reentrega y la renovacion de Android se perdia (el plan caducaba
/// con el usuario pagando). Se extiende un periodo desde max(ahora, caducidad),
/// no desde ahora, para no comerse los dias que quedaban.
///
/// Pero con TOPE: como mucho un periodo desde hoy + [UNVERIFIED_RENEWAL_SLACK_MS].
/// Sin verificar, el id "nuevo" lo pone el cliente, y sin tope cada id
/// inventado sumaba otro periodo encima del anterior (dos llamadas = dos años
/// de Pro). Una renovacion real llega cuando el periodo pagado se acaba, asi
/// que nunca necesita mas que eso; el margen cubre el retraso entre la compra
/// y su primera entrega, que es lo que separa nuestra caducidad provisional
/// del ciclo real de Google.
///
/// [sandbox]: compra VERIFICADA de sandbox (App Review, TestFlight, testers de
/// Play). Alli la tienda acelera el reloj: un mensual caduca a los ~5 minutos y
/// un anual a la hora, y deja de renovar tras ~12 ciclos. Con la fecha de la
/// tienda tal cual, el revisor que compra ve Pro bloqueado minutos despues y
/// la app se rechaza. Para sandbox (y SOLO sandbox) la compra concede
/// max(fecha de la tienda, un periodo de calendario desde hoy), como antes de
/// verificar. Produccion sigue mandando la tienda sin retoques.
export function resolveGrant(input: {
  tier: Tier;
  productId: string;
  period: Period;
  nowMs: number;
  currentTier: Tier;
  currentProductId: string;
  currentExpiresAtMs: number | null;
  currentIsLifetime: boolean;
  storeExpiresAtMs?: number | null;
  newTransaction?: boolean;
  sandbox?: boolean;
}): { tier: Tier; expiresAtMs: number; extended: boolean; reason: string } {
  const {
    tier, productId, period, nowMs,
    currentTier, currentProductId, currentExpiresAtMs, currentIsLifetime,
  } = input;
  const storeExpiresAtMs = input.storeExpiresAtMs ?? null;

  const isUpgrade = TIER_RANK[tier] > TIER_RANK[currentTier];
  const isSameTier = TIER_RANK[tier] === TIER_RANK[currentTier];
  const calendarExpiresAtMs = expiryFor(period, new Date(nowMs)).getTime();
  const purchaseExpiresAtMs =
    storeExpiresAtMs === null
      ? calendarExpiresAtMs
      : input.sandbox === true
        ? Math.max(storeExpiresAtMs, calendarExpiresAtMs)
        : storeExpiresAtMs;

  if (isUpgrade) {
    return {
      tier,
      expiresAtMs: purchaseExpiresAtMs,
      extended: true,
      reason: "upgrade",
    };
  }

  if (isSameTier) {
    const vigente =
      currentIsLifetime ||
      (currentExpiresAtMs !== null && currentExpiresAtMs > nowMs);
    const mismaSuscripcion = vigente && currentProductId === productId;
    if (mismaSuscripcion && !currentIsLifetime && currentExpiresAtMs !== null) {
      if (storeExpiresAtMs !== null) {
        // Aqui va la fecha CRUDA de la tienda, tambien en sandbox: las
        // renovaciones aceleradas (cada ~5 min) y cada "restaurar compras"
        // son la misma suscripcion vigente, y con el suelo de calendario cada
        // una deslizaria el mes otra vez desde hoy.
        const expiresAtMs = Math.max(currentExpiresAtMs, storeExpiresAtMs);
        const extended = expiresAtMs > currentExpiresAtMs;
        return {
          tier,
          expiresAtMs,
          extended,
          reason: extended ? "renewal" : "same_subscription_redelivered",
        };
      }
      if (input.newTransaction === true) {
        const renovada = expiryFor(
          period,
          new Date(Math.max(nowMs, currentExpiresAtMs))
        ).getTime();
        const tope =
          expiryFor(period, new Date(nowMs)).getTime() +
          UNVERIFIED_RENEWAL_SLACK_MS;
        // Nunca acorta: si ya estaba en el tope, es una reentrega mas.
        const expiresAtMs = Math.max(
          currentExpiresAtMs,
          Math.min(renovada, tope)
        );
        const extended = expiresAtMs > currentExpiresAtMs;
        return {
          tier,
          expiresAtMs,
          extended,
          reason: extended ? "renewal" : "same_subscription_redelivered",
        };
      }
    }
    if (mismaSuscripcion) {
      return {
        tier,
        expiresAtMs: currentExpiresAtMs ?? purchaseExpiresAtMs,
        extended: false,
        reason: "same_subscription_redelivered",
      };
    }
    return {
      tier,
      expiresAtMs: Math.max(purchaseExpiresAtMs, currentExpiresAtMs ?? 0),
      extended: true,
      reason: vigente ? "same_tier_other_product" : "renewal",
    };
  }

  return {
    tier: currentTier,
    expiresAtMs: currentExpiresAtMs ?? purchaseExpiresAtMs,
    extended: false,
    reason: "downgrade_keeps_current",
  };
}

function sha256(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

/// La cuenta de Attra ya no existe: borrarla desde Ajustes elimina
/// `users/{uid}` (y luego la cuenta de Auth), o quedo marcada `isDeleted`.
///
/// Hace falta porque el enlace suscripcion -> cuenta (`storeSubscriptions`) es
/// para toda la vida de la suscripcion: si quien borra su cuenta y se crea otra
/// no pudiese reclamarla, Apple/Google le seguirian cobrando y la app le diria
/// "asociada a otra cuenta" en cada renovacion, sin salida. Una cuenta VIVA
/// sigue bloqueando: eso es lo que impide canjear la suscripcion de otro.
function isDeletedAccount(snap: DocumentSnapshot): boolean {
  return !snap.exists || snap.get("isDeleted") === true;
}

function millisFromDateLike(value: unknown): number | null {
  if (value instanceof Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "string" && value.length > 0) {
    const ms = Date.parse(value);
    return Number.isNaN(ms) ? null : ms;
  }
  return null;
}

/// Qué hacer con el entitlement ante lo que cuenta la TIENDA sin cliente de
/// por medio (notificaciones de App Store / RTDN de Play). Pura para tests.
///
///  - grant: la tienda dice que da acceso; se decide con [resolveGrant] y SU
///    caducidad (nunca acorta, respeta subidas/bajadas).
///  - revoke: reembolso o revocacion, SOLO si el plan vigente viene de ESA
///    suscripcion (otra compra posterior no se toca) y nunca un lifetime.
///  - ignore: todo lo demas (caducada sin mas: ya la corta activeEntitlementTier).
export function resolveStoreSync(input: {
  tier: Tier;
  productId: string;
  period: Period;
  nowMs: number;
  currentTier: Tier;
  currentProductId: string;
  currentExpiresAtMs: number | null;
  currentIsLifetime: boolean;
  currentSubscriptionKey: string;
  subscriptionKey: string;
  storeExpiresAtMs: number | null;
  entitled: boolean;
  revoked: boolean;
  allowRevocation: boolean;
  /// Notificacion de sandbox: mismo suelo de calendario que [resolveGrant].
  sandbox?: boolean;
}):
  | { action: "grant"; tier: Tier; expiresAtMs: number; reason: string }
  | { action: "revoke"; expiresAtMs: number; reason: string }
  | { action: "ignore"; reason: string } {
  if (input.revoked) {
    if (input.currentIsLifetime) return { action: "ignore", reason: "lifetime" };
    if (input.currentSubscriptionKey !== input.subscriptionKey) {
      return { action: "ignore", reason: "revoked_other_subscription" };
    }
    if (!input.allowRevocation) {
      return { action: "ignore", reason: "revocation_logged_only" };
    }
    return { action: "revoke", expiresAtMs: input.nowMs, reason: "revoked" };
  }
  if (!input.entitled || input.storeExpiresAtMs === null) {
    return { action: "ignore", reason: "not_entitled" };
  }
  const grant = resolveGrant({
    tier: input.tier,
    productId: input.productId,
    period: input.period,
    nowMs: input.nowMs,
    currentTier: input.currentTier,
    currentProductId: input.currentProductId,
    currentExpiresAtMs: input.currentExpiresAtMs,
    currentIsLifetime: input.currentIsLifetime,
    storeExpiresAtMs: input.storeExpiresAtMs,
    sandbox: input.sandbox === true,
  });
  if (!grant.extended) return { action: "ignore", reason: grant.reason };
  return {
    action: "grant",
    tier: grant.tier,
    expiresAtMs: grant.expiresAtMs,
    reason: grant.reason,
  };
}

/// Aplica al entitlement lo que dice la tienda por una notificacion de
/// servidor. Es lo que hace llegar las RENOVACIONES aunque el usuario no abra
/// la app: antes el plan caducaba en la fecha provisional con el usuario
/// pagando, porque la renovacion solo existia si el cliente reenviaba recibo.
export async function applyStoreSubscriptionUpdate(input: {
  purchase: VerifiedStorePurchase;
  source: string;
  allowRevocation: boolean;
}): Promise<{ applied: boolean; reason: string; uid?: string }> {
  const { purchase } = input;
  const tier = PRODUCT_TIER[purchase.productId];
  if (!tier) return { applied: false, reason: "unknown_product" };
  const subscriptionKey = storeSubscriptionKey(
    purchase.platform,
    purchase.originalTransactionId
  );
  const subRef = storeSubscriptionRef(
    purchase.platform,
    purchase.originalTransactionId
  );
  const linkedRef = purchase.linkedOriginalTransactionId
    ? storeSubscriptionRef(purchase.platform, purchase.linkedOriginalTransactionId)
    : null;
  const ledgerRef = db
    .collection("subscriptionLedger")
    .doc(sha256(`${purchase.platform}|${purchase.transactionId}`));

  return db.runTransaction(async (tx) => {
    const [subSnap, linkedSnap, ledgerSnap] = await Promise.all([
      tx.get(subRef),
      linkedRef ? tx.get(linkedRef) : Promise.resolve(null),
      tx.get(ledgerRef),
    ]);
    // Una suscripcion que sustituye a otra (cambio de plan en Play) trae token
    // NUEVO: se encuentra la cuenta por el anterior.
    const uid = (
      subSnap.get("uid") ??
      linkedSnap?.get("uid") ??
      ""
    ).toString();
    if (!uid) return { applied: false, reason: "unknown_subscription" };

    const entRef = col.entitlements.doc(uid);
    const [entSnap, ownerSnap] = await Promise.all([
      tx.get(entRef),
      tx.get(col.users.doc(uid)),
    ]);
    // La cuenta se borro: no se escribe nada a su nombre (seria recrear datos
    // de alguien que pidio borrarlos). Si se crea otra cuenta y restaura,
    // verifyPurchase le pasa la suscripcion y las siguientes notificaciones ya
    // van a la nueva.
    if (isDeletedAccount(ownerSnap)) {
      return { applied: false, reason: "owner_deleted", uid };
    }
    const entData = entSnap.exists ? entSnap.data() : undefined;
    const currentProductId = (entData?.productId ?? "").toString();
    const nowMs = Date.now();
    const decision = resolveStoreSync({
      tier,
      productId: purchase.productId,
      period:
        purchase.period ??
        periodFor(purchase.productId, null, parsePeriod(entData?.period)),
      nowMs,
      currentTier: normalizeTier(activeEntitlementTier(entData)),
      currentProductId,
      currentExpiresAtMs: millisFromDateLike(entData?.expiresAt),
      currentIsLifetime: entData?.isLifetime === true,
      currentSubscriptionKey: (entData?.storeSubscriptionKey ?? "").toString(),
      subscriptionKey,
      storeExpiresAtMs: purchase.expiresAtMs,
      entitled: purchase.entitled,
      revoked: purchase.revoked,
      allowRevocation: input.allowRevocation,
      sandbox: purchase.sandbox === true,
    });

    if (decision.action === "grant") {
      const entUpdate: Record<string, unknown> = {
        tier: decision.tier,
        isLifetime: entData?.isLifetime === true,
        expiresAt: Timestamp.fromMillis(decision.expiresAtMs),
        updatedAt: FieldValue.serverTimestamp(),
      };
      if (decision.tier === tier) {
        entUpdate.source = purchase.platform;
        entUpdate.productId = purchase.productId;
        entUpdate.storeVerified = true;
        entUpdate.storeSubscriptionKey = subscriptionKey;
        if (purchase.period) entUpdate.period = purchase.period;
      }
      tx.set(entRef, entUpdate, { merge: true });
    } else if (decision.action === "revoke") {
      tx.set(
        entRef,
        {
          expiresAt: Timestamp.fromMillis(decision.expiresAtMs),
          revokedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }

    // La renovacion queda apuntada a nombre de esa cuenta: si luego la app la
    // reentrega, es un duplicado y no otra compra.
    if (!ledgerSnap.exists) {
      tx.set(ledgerRef, {
        uid,
        productId: purchase.productId,
        tier,
        platform: purchase.platform,
        purchaseId: purchase.transactionId.slice(0, 160),
        verified: true,
        sandbox: purchase.sandbox,
        source: input.source,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    tx.set(
      subRef,
      {
        uid,
        platform: purchase.platform,
        productId: purchase.productId,
        tier,
        expiresAt:
          purchase.expiresAtMs !== null
            ? Timestamp.fromMillis(purchase.expiresAtMs)
            : null,
        revoked: purchase.revoked,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return { applied: decision.action !== "ignore", reason: decision.reason, uid };
  });
}

export const verifyPurchase = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const platform = parsePlatform(request.data?.platform);
  const clientProductId =
    typeof request.data?.productId === "string" ? request.data.productId : "";
  if (!PRODUCT_TIER[clientProductId]) {
    throw new HttpsError(
      "invalid-argument",
      `Producto desconocido: ${clientProductId}`
    );
  }
  const rawVerificationData =
    typeof request.data?.verificationData === "string"
      ? (request.data.verificationData as string)
      : "";
  if (!rawVerificationData.trim()) {
    throw new HttpsError("invalid-argument", "Falta el recibo de compra.");
  }
  const rawPurchaseId =
    typeof request.data?.purchaseId === "string"
      ? request.data.purchaseId.trim()
      : "";

  // Validacion contra la tienda ANTES de tocar nada. Si no pasa, no se escribe
  // ni el ledger ni el entitlement.
  const check = await checkStorePurchase({
    platform,
    kind: "subscription",
    productId: clientProductId,
    verificationData: rawVerificationData,
    config: await readReceiptValidationConfig(),
  });
  if (check.status === "rejected") {
    return {
      ok: false,
      permanent: check.permanent,
      reason: check.reason,
      message: check.message,
    };
  }
  const verified = check.status === "verified" ? check.purchase : null;
  // Con la compra verificada el producto es el que dice la TIENDA: el del
  // cliente solo servia para saber a que preguntar.
  const productId = verified?.productId ?? clientProductId;
  const tier = PRODUCT_TIER[productId];
  if (!tier) {
    console.warn(
      `[receipt] ${platform} de un producto que no es un plan: ${productId}`
    );
    return {
      ok: false,
      permanent: true,
      reason: "unknown_product",
      message: "Esta compra no corresponde a un plan de Attra.",
    };
  }

  // Clave de la compra. Verificada: el id de transaccion de la TIENDA (uno por
  // compra/renovacion), que un cliente no puede inventarse. Sin verificar
  // (Android en modo 'log'): el purchaseId y, si no hay, el hash del recibo
  // COMPLETO: antes se cogían los primeros 160 caracteres del recibo y en iOS
  // esa cabecera es idéntica entre compras distintas del mismo dispositivo,
  // así que compras legítimas se descartaban como duplicadas y el usuario
  // pagaba sin recibir el plan.
  const purchaseKey = verified
    ? verified.transactionId
    : rawPurchaseId || sha256(rawVerificationData);
  // Solo un id de la tienda cuenta como transaccion "nueva" para renovar: el
  // hash del recibo cambia en cada reenvio de iOS y regalaria un periodo cada
  // vez (los nueve apuntes de la misma suscripcion).
  const stableKey = verified !== null || rawPurchaseId.length > 0;
  const subRef = verified
    ? storeSubscriptionRef(platform, verified.originalTransactionId)
    : null;
  const subKey = verified
    ? storeSubscriptionKey(platform, verified.originalTransactionId)
    : null;

  const entRef = col.entitlements.doc(uid);
  // Ledger GLOBAL por compra (sin el uid en el id). Con el id anterior
  // (`{uid}_{purchaseId}`) el mismo recibo real podía canjearse en cuentas
  // ilimitadas: una compra daba Pro a todos los amigos del comprador. Ahora el
  // documento es único por compra y guarda dentro qué uid la canjeó.
  const ledgerRef = db
    .collection("subscriptionLedger")
    .doc(sha256(`${platform}|${purchaseKey}`));

  // Ledger ANTIGUO (`{uid}_{purchaseId}`). Sin consultarlo, todo suscriptor ya
  // existente que restaure crearia un doc nuevo y se llevaria un periodo extra
  // gratis: justo el agujero que este cambio cierra.
  // El esquema anterior acotaba el id a 160 caracteres; se replica igual para
  // encontrar el documento.
  const legacyLedgerRef = db
    .collection("subscriptionLedger")
    .doc(`${uid}_${purchaseKey.slice(0, 160)}`);

  return db.runTransaction(async (tx) => {
    const [ledgerSnap, legacySnap, entSnap, subSnap] = await Promise.all([
      tx.get(ledgerRef),
      tx.get(legacyLedgerRef),
      tx.get(entRef),
      subRef ? tx.get(subRef) : Promise.resolve(null),
    ]);
    const now = new Date();
    const ledgerOwner = ledgerSnap.exists
      ? (ledgerSnap.get("uid") ?? "").toString()
      : "";
    const subOwner = (subSnap?.get("uid") ?? "").toString();

    // Dueños AJENOS de la compra o de la suscripcion: solo bloquean si su
    // cuenta sigue existiendo (ver isDeletedAccount). Se leen aqui, antes de
    // cualquier escritura, como exige la transaccion.
    const ajenos = [...new Set([ledgerOwner, subOwner])].filter(
      (owner) => owner.length > 0 && owner !== uid
    );
    const ajenosSnaps = await Promise.all(
      ajenos.map((owner) => tx.get(col.users.doc(owner)))
    );
    const borrados = new Set(
      ajenos.filter((_, i) => isDeletedAccount(ajenosSnaps[i]))
    );

    // ¿Este recibo ya se había procesado? Antes esto devolvía aquí mismo, sin
    // tocar el entitlement: "idempotente" se implementó como "no hacer NADA".
    // El resultado es que restaurar compras no restauraba. Si el entitlement se
    // había perdido (reinstalar en otra cuenta, un reset, una escritura que se
    // quedó a medias), el usuario tenía la compra pagada y apuntada en el
    // ledger, la app decía "compras restauradas" y el plan seguía sin aparecer:
    // pagado y sin acceso, sin ningún error que lo delatara. Ahora un duplicado
    // RECONCILIA el entitlement y solo se salta el apunte del ledger.
    const yaProcesada =
      legacySnap.exists || (ledgerSnap.exists && ledgerOwner === uid);
    // La compra la canjeo una cuenta que ya se borro: pasa a esta. No es una
    // transaccion NUEVA (ya se concedio una vez), asi que no alarga nada.
    const reclamadaDe =
      ledgerSnap.exists && !yaProcesada && borrados.has(ledgerOwner)
        ? ledgerOwner
        : null;

    if (ledgerSnap.exists && !yaProcesada && reclamadaDe === null) {
      // Otra cuenta ya canjeó este recibo. NO se lanza excepcion: el cliente
      // solo finaliza la transaccion cuando la entrega va bien, asi que un
      // error aqui la dejaria reencolada en StoreKit para siempre, reintentando
      // en cada arranque y bloqueando compras posteriores. Y lo dispara gente
      // legitima: misma cuenta de tienda con otra cuenta de Attra tras
      // reinstalar, o compartir en familia. Se devuelve un fallo PERMANENTE
      // para que el cliente cierre la transaccion y avise al usuario.
      return {
        ok: false,
        permanent: true,
        reason: "claimed_by_other_account",
        message:
          "Esta compra ya está asociada a otra cuenta de Attra. Inicia sesión " +
          "con la cuenta que la realizó o escribe a soporte.",
      };
    }

    // La SUSCRIPCION ya es de otra cuenta. Cada renovacion trae un id de
    // transaccion nuevo, asi que el ledger por transaccion no lo veria y la
    // segunda cuenta se llevaria el plan en cada renovacion. Mismo trato que
    // arriba: fallo permanente, no excepcion. Salvo que esa cuenta ya no
    // exista: entonces la suscripcion pasa a quien la presenta (se reescribe
    // `storeSubscriptions` mas abajo con su uid).
    const suscripcionDe =
      subOwner && subOwner !== uid && borrados.has(subOwner) ? subOwner : null;
    if (subOwner && subOwner !== uid && suscripcionDe === null) {
      return {
        ok: false,
        permanent: true,
        reason: "claimed_by_other_account",
        message:
          "Esta compra ya está asociada a otra cuenta de Attra. Inicia sesión " +
          "con la cuenta que la realizó o escribe a soporte.",
      };
    }

    const entData = entSnap.exists ? entSnap.data() : undefined;
    // Tier VIGENTE (free si ya caducó) y caducidad actual.
    const currentTier = normalizeTier(activeEntitlementTier(entData));
    const currentExpiresAtMs = millisFromDateLike(entData?.expiresAt);
    const currentIsLifetime = entData?.isLifetime === true;

    const currentProductId = (entData?.productId ?? "").toString();
    // Periodo: el de la tienda si lo da (plan basico de Play); si no, sufijo,
    // lo que pida el cliente o lo que se guardo al comprar ESTE producto.
    const period =
      verified?.period ??
      periodFor(
        productId,
        request.data?.period,
        currentProductId === productId ? parsePeriod(entData?.period) : null
      );

    if (verified && !verified.entitled) {
      // Compra autentica que la tienda ya NO respalda: caducada, reembolsada o
      // sustituida por un cambio de plan. Antes cualquier recibo, por viejo que
      // fuese, abria un periodo nuevo desde hoy (restaurar una suscripcion de
      // hace un año daba otro mes). Se responde ok para que la app cierre la
      // transaccion: no hay nada que reintentar.
      return {
        ok: true,
        duplicate: yaProcesada,
        reason: "store_not_entitled",
        tier: currentTier,
        expiresAt:
          currentExpiresAtMs !== null
            ? new Date(currentExpiresAtMs).toISOString()
            : null,
      };
    }

    // Restaurar compras no puede degradar ni recortar, y reentregar la misma
    // suscripcion no puede regalar periodo. Toda esa decision vive en
    // resolveGrant, que es pura y esta cubierta por tests.
    const grant = resolveGrant({
      tier,
      productId,
      period,
      nowMs: now.getTime(),
      currentTier,
      currentProductId,
      currentExpiresAtMs,
      currentIsLifetime,
      storeExpiresAtMs: verified?.expiresAtMs ?? null,
      newTransaction: !ledgerSnap.exists && !legacySnap.exists && stableKey,
      // Solo una compra VERIFICADA como sandbox recibe el suelo de calendario;
      // sin verificar no hay fecha de la tienda que corregir.
      sandbox: verified?.sandbox === true,
    });
    if (reclamadaDe !== null || suscripcionDe !== null) {
      console.log(
        `[receipt] ${platform} de una cuenta borrada ` +
          `(${reclamadaDe ?? suscripcionDe}) pasa a ${uid}`
      );
    }
    const grantedTier = grant.tier;
    const grantedExpiresAt = new Date(grant.expiresAtMs);
    const isUpgradeOrSame = TIER_RANK[tier] >= TIER_RANK[currentTier];

    const entUpdate: Record<string, unknown> = {
      tier: grantedTier,
      // Un lifetime (admin/promo) tampoco puede perderse por una compra IAP.
      isLifetime: currentIsLifetime,
      expiresAt: Timestamp.fromDate(grantedExpiresAt),
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (isUpgradeOrSame) {
      // `source` debe ser un valor que el cliente sepa parsear: EntitlementSource
      // solo conoce 'app_store' | 'play_store' | 'admin' | 'promo'. Con el
      // antiguo `iap_${platform}` toda suscripción real quedaba como origen
      // desconocido (none) en la app.
      entUpdate.source = platform;
      entUpdate.productId = productId;
      // Campos NUEVOS (el resto del documento no cambia de forma): el periodo
      // para las restauraciones, si la tienda lo confirmo y de que suscripcion
      // viene, que es lo que permite a una notificacion de reembolso saber si
      // este plan es el suyo.
      entUpdate.period = period;
      entUpdate.storeVerified = verified !== null;
      if (subKey) entUpdate.storeSubscriptionKey = subKey;
    }
    // Se escribe SIEMPRE, tambien en un duplicado: es lo que hace que
    // "restaurar compras" restaure de verdad cuando el entitlement se perdio.
    tx.set(entRef, entUpdate, { merge: true });

    if (!yaProcesada) {
      tx.set(ledgerRef, {
        uid,
        productId,
        tier,
        grantedTier,
        period,
        platform,
        // Se guarda solo un prefijo acotado: el id real puede ser muy largo y
        // la unicidad ya la garantiza el id del documento (hash de la compra).
        purchaseId: purchaseKey.slice(0, 160),
        hasReceipt: true,
        verified: verified !== null,
        sandbox: verified?.sandbox ?? null,
        // Rastro de auditoria cuando la compra venia de una cuenta borrada.
        ...(reclamadaDe !== null ? { reclaimedFrom: reclamadaDe } : {}),
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    if (subRef && verified) {
      tx.set(
        subRef,
        {
          uid,
          platform,
          productId,
          tier,
          expiresAt:
            verified.expiresAtMs !== null
              ? Timestamp.fromMillis(verified.expiresAtMs)
              : null,
          revoked: verified.revoked,
          ...(suscripcionDe !== null ? { relinkedFrom: suscripcionDe } : {}),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }

    return {
      ok: true,
      duplicate: yaProcesada,
      reason: grant.reason,
      tier: grantedTier,
      expiresAt: grantedExpiresAt.toISOString(),
    };
  });
});
