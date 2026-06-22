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

interface PlanSpec {
  tier: Tier;
  period: Period;
}

/// Mapa producto → plan. Única fuente de verdad en backend (debe coincidir con
/// premium_product_catalog.dart del cliente).
const PRODUCTS: Record<string, PlanSpec> = {
  attra_plus_monthly: { tier: "plus", period: "monthly" },
  attra_plus_yearly: { tier: "plus", period: "yearly" },
  attra_premium_monthly: { tier: "premium", period: "monthly" },
  attra_premium_yearly: { tier: "premium", period: "yearly" },
  attra_pro_monthly: { tier: "pro", period: "monthly" },
  attra_pro_yearly: { tier: "pro", period: "yearly" },
};

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
  const spec = PRODUCTS[productId];
  if (!spec) {
    throw new HttpsError("invalid-argument", `Producto desconocido: ${productId}`);
  }
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
    const expiresAt = expiryFor(spec.period, now);

    // Idempotencia: un mismo recibo no se procesa dos veces.
    if (ledgerSnap.exists) {
      return { ok: true, duplicate: true, tier: spec.tier };
    }

    tx.set(
      entRef,
      {
        tier: spec.tier,
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
      tier: spec.tier,
      period: spec.period,
      platform,
      purchaseId,
      hasReceipt: true,
      createdAt: FieldValue.serverTimestamp(),
    });

    return {
      ok: true,
      duplicate: false,
      tier: spec.tier,
      expiresAt: expiresAt.toISOString(),
    };
  });
});
