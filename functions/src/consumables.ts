import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
import { col, requireAuthUid } from "./common";

/// Consumibles comprables de Attra: BOOSTS y SWIPES (likes extra). Viven en
/// `users/{uid}.wallet.{boosts,swipes}`. Esta función los ABONA al saldo.
///
/// ⚠️ PLACEHOLDER DE COMPRA: hoy abona directamente (MVP / pruebas). Antes de
/// producción debe ENVOLVERSE con validación de recibo IAP (App Store / Google
/// Play) o pasarela de pago: el cliente compra, valida el recibo en el backend,
/// y SOLO entonces se llama a esta concesión. No exponer el abono libre en prod.

type ConsumableKind = "boost" | "swipe";

/// Topes de cordura por llamada (evita abusos accidentales).
const MAX_PER_GRANT = 100;

function parseKind(value: unknown): ConsumableKind {
  if (value === "boost" || value === "swipe") return value;
  throw new HttpsError("invalid-argument", "kind debe ser 'boost' o 'swipe'.");
}

function parseAmount(value: unknown): number {
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(n) || n <= 0 || n > MAX_PER_GRANT) {
    throw new HttpsError("invalid-argument", `amount debe ser 1..${MAX_PER_GRANT}.`);
  }
  return Math.floor(n);
}

/// Abona [amount] consumibles de [kind] al saldo del usuario. Registra el
/// movimiento en `consumableLedger` (auditable). Idempotente por `purchaseId`
/// si se aporta (no duplica un mismo recibo de compra).
export const grantConsumable = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const kind = parseKind(request.data?.kind);
  const amount = parseAmount(request.data?.amount);
  const purchaseId =
    typeof request.data?.purchaseId === "string" && request.data.purchaseId.trim()
      ? request.data.purchaseId.trim().slice(0, 120)
      : null;
  // Recibo de la tienda (IAP). En la app real llega siempre; el placeholder de
  // pruebas puede no traerlo.
  const platform =
    request.data?.platform === "app_store" || request.data?.platform === "play_store"
      ? (request.data.platform as string)
      : null;
  const verificationData =
    typeof request.data?.verificationData === "string"
      ? (request.data.verificationData as string).slice(0, 8000)
      : null;

  // TODO(IAP server validation): cuando haya recibo (platform+verificationData),
  // validarlo contra Google Play Developer API / App Store Server API ANTES de
  // conceder. Requiere credenciales de tienda (service account / shared secret).
  // Hoy: si llega recibo confiamos en él (idempotente por purchaseId); si no,
  // es la concesión placeholder de pruebas.
  const source = platform ? `iap_${platform}` : "purchase_placeholder";

  const userRef = col.users.doc(uid);
  const ledgerRef = purchaseId
    ? db.collection("consumableLedger").doc(`${uid}_${purchaseId}`)
    : db.collection("consumableLedger").doc();

  return db.runTransaction(async (tx) => {
    const [userSnap, ledgerSnap] = await Promise.all([
      tx.get(userRef),
      tx.get(ledgerRef),
    ]);
    if (!userSnap.exists) {
      throw new HttpsError("failed-precondition", "No existe tu perfil.");
    }
    // Idempotencia: un mismo recibo de compra no abona dos veces.
    if (purchaseId && ledgerSnap.exists) {
      const wallet = (userSnap.data()?.wallet ?? {}) as Record<string, unknown>;
      return {
        ok: true,
        duplicate: true,
        kind,
        balance: Number(wallet[kind === "boost" ? "boosts" : "swipes"] ?? 0),
      };
    }

    const now = FieldValue.serverTimestamp();
    // Incrementa el saldo anidado `wallet.boosts`/`wallet.swipes` (mismo campo
    // que consume activateBoost / sendLike). Un único write para no duplicar.
    tx.set(
      userRef,
      {
        wallet: {
          [kind === "boost" ? "boosts" : "swipes"]: FieldValue.increment(amount),
        },
        updatedAt: now,
      },
      { merge: true }
    );

    tx.set(ledgerRef, {
      uid,
      kind,
      amount,
      purchaseId,
      platform,
      hasReceipt: verificationData != null,
      type: "grant",
      source,
      createdAt: now,
    });

    const wallet = (userSnap.data()?.wallet ?? {}) as Record<string, unknown>;
    const prev = Number(wallet[kind === "boost" ? "boosts" : "swipes"] ?? 0);
    return { ok: true, duplicate: false, kind, balance: prev + amount };
  });
});
