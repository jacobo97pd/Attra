import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
import { col, requireAuthUid } from "./common";

/// Verificación de SUSCRIPCIONES compradas por IAP (Google Play / App Store).
///
/// ⚠️ El cliente NUNCA concede tier: lanza la compra, recibe el recibo de la
/// tienda y lo envía aquí. Esta función concede el plan en `userEntitlements`
/// (doc write:false para clientes) y es idempotente por `purchaseId`.
///
/// TODO(validación real): antes de producción, validar `verificationData`
/// contra Google Play Developer API / App Store Server API ANTES de conceder, y
/// tomar de ahí la fecha real de expiración. Requiere credenciales de tienda
/// (service account de Google / clave de App Store). Hoy, si llega recibo se
/// confía en él y se calcula una expiración provisional según el periodo.

type Tier = "free" | "plus" | "premium" | "pro";
type Period = "monthly" | "yearly";

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

/// Deduce el periodo: del propio id si lo lleva, o del campo `period`.
function periodFor(productId: string, raw: unknown): Period {
  if (productId.endsWith("_yearly")) return "yearly";
  if (productId.endsWith("_monthly")) return "monthly";
  return raw === "yearly" ? "yearly" : "monthly";
}

function parsePlatform(value: unknown): "app_store" | "play_store" {
  if (value === "app_store" || value === "play_store") return value;
  throw new HttpsError(
    "invalid-argument",
    "platform debe ser 'app_store' o 'play_store'."
  );
}

function expiryFor(period: Period, from: Date): Date {
  const d = new Date(from);
  // Margen pequeño extra sobre el periodo nominal (provisional hasta validar el
  // recibo real). Mensual ≈ 31d, anual ≈ 366d.
  d.setUTCDate(d.getUTCDate() + (period === "yearly" ? 366 : 31));
  return d;
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
  const period = periodFor(productId, request.data?.period);
  const verificationData =
    typeof request.data?.verificationData === "string"
      ? (request.data.verificationData as string).slice(0, 12000)
      : null;
  if (!verificationData) {
    throw new HttpsError("invalid-argument", "Falta el recibo de compra.");
  }
  const purchaseId =
    typeof request.data?.purchaseId === "string" && request.data.purchaseId.trim()
      ? request.data.purchaseId.trim().slice(0, 160)
      : verificationData.slice(0, 160);

  const entRef = col.entitlements.doc(uid);
  const ledgerRef = db
    .collection("subscriptionLedger")
    .doc(`${uid}_${purchaseId}`);

  return db.runTransaction(async (tx) => {
    const ledgerSnap = await tx.get(ledgerRef);
    const now = new Date();
    const expiresAt = expiryFor(period, now);

    // Idempotencia: un mismo recibo no se procesa dos veces.
    if (ledgerSnap.exists) {
      return { ok: true, duplicate: true, tier };
    }

    tx.set(
      entRef,
      {
        tier,
        source: `iap_${platform}`,
        isLifetime: false,
        productId,
        expiresAt: Timestamp.fromDate(expiresAt),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    tx.set(ledgerRef, {
      uid,
      productId,
      tier,
      period,
      platform,
      purchaseId,
      hasReceipt: true,
      createdAt: FieldValue.serverTimestamp(),
    });

    return {
      ok: true,
      duplicate: false,
      tier,
      expiresAt: expiresAt.toISOString(),
    };
  });
});
