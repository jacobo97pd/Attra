import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { createHash } from "node:crypto";
import { REGION, db } from "./firebase";
import { col, requireAuthUid, activeEntitlementTier } from "./common";

/// Verificación de SUSCRIPCIONES compradas por IAP (Google Play / App Store).
///
/// ⚠️ El cliente NUNCA concede tier: lanza la compra, recibe el recibo de la
/// tienda y lo envía aquí. Esta función concede el plan en `userEntitlements`
/// (doc write:false para clientes) y es idempotente por compra.
///
/// TODO(validación real): antes de producción, validar `verificationData`
/// contra Google Play Developer API / App Store Server API ANTES de conceder, y
/// tomar de ahí la fecha real de expiración. Requiere credenciales de tienda
/// (service account de Google / clave de App Store). Hoy, si llega recibo se
/// confía en él y se calcula una expiración provisional según el periodo.

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
/// conservador a propósito: la renovación real la confirmará la validación
/// server-side del recibo (ver TODO de arriba), no la palabra del cliente.
function periodFor(productId: string, requested: unknown): Period {
  // El sufijo del id es la fuente FIABLE: no la puede tocar el cliente.
  if (productId.endsWith("_yearly")) return "yearly";
  if (productId.endsWith("_monthly")) return "monthly";
  // Planes basicos de Play: el ANUAL se vende bajo el id BASE (`attra_plus`),
  // asi que el id no dice el periodo y el unico dato disponible es el del
  // cliente. Ignorarlo daba 1 mes a quien pagaba 12 -- un dano MUCHO peor que
  // el fraude que evitaba, porque le pasa a usuarios legitimos y no hay forma
  // de recuperarlo hasta la siguiente renovacion.
  //
  // Es provisional y consciente: mientras no exista validacion del recibo
  // contra la tienda (ver TODO de arriba), un cliente modificado puede mentir
  // aqui igual que puede autoconcederse un plan entero, asi que este campo no
  // es el eslabon debil.
  return requested === "yearly" ? "yearly" : "monthly";
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

function sha256(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
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

export const verifyPurchase = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const platform = parsePlatform(request.data?.platform);
  const productId =
    typeof request.data?.productId === "string" ? request.data.productId : "";
  const tier = PRODUCT_TIER[productId];
  if (!tier) {
    throw new HttpsError("invalid-argument", `Producto desconocido: ${productId}`);
  }
  // El periodo se deriva del producto: el cliente ya no decide cuánto dura.
  const period = periodFor(productId, request.data?.period);
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

  // Clave de la compra. Cuando no hay purchaseId (iOS a menudo no lo trae) se
  // usa el hash del recibo COMPLETO: antes se cogían los primeros 160
  // caracteres del recibo y en iOS esa cabecera es idéntica entre compras
  // distintas del mismo dispositivo, así que compras legítimas se descartaban
  // como duplicadas y el usuario pagaba sin recibir el plan.
  const purchaseKey = rawPurchaseId || sha256(rawVerificationData);

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
    const [ledgerSnap, legacySnap, entSnap] = await Promise.all([
      tx.get(ledgerRef),
      tx.get(legacyLedgerRef),
      tx.get(entRef),
    ]);
    const now = new Date();

    // Ya procesada con el esquema viejo: idempotente igualmente.
    if (legacySnap.exists) {
      return { ok: true, duplicate: true, tier };
    }

    if (ledgerSnap.exists) {
      const ownerUid = (ledgerSnap.get("uid") ?? "").toString();
      // Misma cuenta: idempotente (reintentos, restaurar compras) → no se
      // vuelve a conceder ni a alargar nada.
      if (ownerUid === uid) {
        return { ok: true, duplicate: true, tier };
      }
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

    const entData = entSnap.exists ? entSnap.data() : undefined;
    // Tier VIGENTE (free si ya caducó) y caducidad actual.
    const currentTier = normalizeTier(activeEntitlementTier(entData));
    const currentExpiresAtMs = millisFromDateLike(entData?.expiresAt);
    const currentIsLifetime = entData?.isLifetime === true;

    // Restaurar compras no puede degradar ni recortar:
    //  - Antes se escribía siempre el tier del producto restaurado, así que
    //    alguien con Pro que restauraba un Plus antiguo se quedaba en Plus.
    //  - Y siempre se escribía una caducidad contada desde HOY, que además de
    //    regalar periodo podía ACORTAR una suscripción vigente más larga.
    const isUpgrade = TIER_RANK[tier] > TIER_RANK[currentTier];
    const isSameTier = TIER_RANK[tier] === TIER_RANK[currentTier];
    const isUpgradeOrSame = isUpgrade || isSameTier;
    const grantedTier: Tier = isUpgradeOrSame ? tier : currentTier;

    const purchaseExpiresAtMs = expiryFor(period, now).getTime();
    // Si la compra es de un tier INFERIOR al vigente se conserva el tier alto
    // con SU caducidad: alargar la fecha con una compra más barata regalaría
    // el plan superior al precio del inferior. Nunca se acorta lo ya concedido.
    // SUBIDA de plan: manda la caducidad de LO COMPRADO. Coger la mayor
    // permitia comprar Plus ANUAL (barato) y luego Pro MENSUAL para quedarse un
    // ano de Pro por el precio de un mes.
    // MISMO plan: se extiende (renovacion/restauracion) y nunca se acorta.
    // BAJADA: se conserva el plan alto vigente con SU caducidad.
    const grantedExpiresAtMs = isUpgrade
      ? purchaseExpiresAtMs
      : isSameTier
          ? Math.max(purchaseExpiresAtMs, currentExpiresAtMs ?? 0)
          : (currentExpiresAtMs ?? purchaseExpiresAtMs);
    const grantedExpiresAt = new Date(grantedExpiresAtMs);

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
    }
    tx.set(entRef, entUpdate, { merge: true });

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
      createdAt: FieldValue.serverTimestamp(),
    });

    return {
      ok: true,
      duplicate: false,
      tier: grantedTier,
      expiresAt: grantedExpiresAt.toISOString(),
    };
  });
});
