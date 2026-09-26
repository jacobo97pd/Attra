import { onRequest } from "firebase-functions/v2/https";
import { onMessagePublished } from "firebase-functions/v2/pubsub";
import { REGION } from "./firebase";
import {
  APPLE_BUNDLE_ID,
  parseAppleTransaction,
  verifyAppleSignedPayload,
} from "./storeApple";
import {
  PLAY_PACKAGE_NAME,
  fetchPlaySubscriptionRaw,
  parsePlaySubscriptionV2,
} from "./storeGoogle";
import {
  ReceiptValidationConfig,
  VerifiedStorePurchase,
  playSubscriptionToVerified,
  readReceiptValidationConfig,
} from "./storeValidation";
import { applyStoreSubscriptionUpdate } from "./subscriptions";

/// Notificaciones de servidor de las tiendas: RENOVACIONES, reembolsos y
/// revocaciones que ocurren sin que el usuario abra la app.
///
/// QUE FALLABA: la caducidad del plan se calculaba al comprar y solo se movia
/// si la app volvia a mandar un recibo. Android no reentrega las renovaciones
/// por su cuenta y no habia ningun receptor de notificaciones, asi que al mes
/// el suscriptor pasaba a Free (tope de likes, sin rewind, sin viaje ni
/// incognito) mientras Google le seguia cobrando.
///
///  - App Store Server Notifications V2 (`appStoreNotifications`): el cuerpo es
///    un JWS firmado por Apple y se verifica igual que los recibos, sin
///    credenciales. Paso externo: poner la URL en App Store Connect.
///  - Play RTDN (`playRtdn`): llega por Pub/Sub y solo trae el token; el estado
///    hay que pedirselo a la Play Developer API, asi que depende del mismo
///    acceso en Play Console que la validacion de Android. Las revocaciones de
///    Play solo se aplican en modo 'enforce' (en 'log' se registran).

type Json = Record<string, unknown>;

function obj(value: unknown): Json {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Json)
    : {};
}

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export interface NotificationDeps {
  verifyAppleJws: (jws: string) => Json;
  fetchPlaySubscription: (token: string) => Promise<Json>;
  apply: typeof applyStoreSubscriptionUpdate;
  config: () => Promise<ReceiptValidationConfig>;
  nowMs: () => number;
}

export const defaultNotificationDeps: NotificationDeps = {
  verifyAppleJws: (jws) => verifyAppleSignedPayload(jws),
  fetchPlaySubscription: fetchPlaySubscriptionRaw,
  apply: applyStoreSubscriptionUpdate,
  config: readReceiptValidationConfig,
  nowMs: () => Date.now(),
};

/// Tipos de Apple que quitan el acceso pagado.
const APPLE_REVOKING_TYPES = new Set(["REFUND", "REVOKE"]);

/// Procesa el `signedPayload` de una App Store Server Notification V2.
/// Devuelve el codigo HTTP: 401 si la firma no es de Apple (Apple reintenta
/// ante cualquier no-2xx, y si el fallo fuese nuestro, p. ej. una raiz rotada,
/// asi no se pierden), 200 en todo lo demas aunque no haya nada que aplicar.
export async function handleAppStoreNotification(
  signedPayload: string,
  deps: NotificationDeps = defaultNotificationDeps
): Promise<{ status: number; result: string }> {
  let notification: Json;
  try {
    notification = deps.verifyAppleJws(signedPayload);
  } catch (error) {
    console.warn(
      `[storeNotifications] App Store: firma no valida: ${(error as Error).message}`
    );
    return { status: 401, result: "bad_signature" };
  }
  const type = text(notification.notificationType);
  const subtype = text(notification.subtype);
  const data = obj(notification.data);
  const bundleId = text(data.bundleId);
  if (bundleId && bundleId !== APPLE_BUNDLE_ID) {
    return { status: 200, result: "other_app" };
  }
  if (type === "TEST") {
    console.log("[storeNotifications] App Store: notificacion de prueba OK");
    return { status: 200, result: "test" };
  }
  const signedTransaction = text(data.signedTransactionInfo);
  if (!signedTransaction) return { status: 200, result: "no_transaction" };

  let transaction;
  let graceExpiresMs: number | null = null;
  try {
    transaction = parseAppleTransaction(deps.verifyAppleJws(signedTransaction));
    const signedRenewal = text(data.signedRenewalInfo);
    if (signedRenewal) {
      const renewal = deps.verifyAppleJws(signedRenewal);
      graceExpiresMs =
        typeof renewal.gracePeriodExpiresDate === "number"
          ? renewal.gracePeriodExpiresDate
          : null;
    }
  } catch (error) {
    // El sobre SI era de Apple: reintentar no lo va a arreglar.
    console.error(
      `[storeNotifications] App Store ${type}: transaccion ilegible: ` +
        (error as Error).message
    );
    return { status: 200, result: "bad_transaction" };
  }
  if (transaction.bundleId && transaction.bundleId !== APPLE_BUNDLE_ID) {
    return { status: 200, result: "other_app" };
  }
  const config = await deps.config();
  const sandbox = transaction.environment === "Sandbox";
  if (sandbox && !config.allowSandbox) {
    return { status: 200, result: "sandbox_ignored" };
  }

  const nowMs = deps.nowMs();
  const revoked =
    transaction.revocationDateMs !== null || APPLE_REVOKING_TYPES.has(type);
  // En periodo de gracia (fallo de cobro) Apple mantiene el acceso hasta
  // `gracePeriodExpiresDate`; si no se respeta, se corta antes que la tienda.
  const expiresAtMs =
    transaction.expiresDateMs !== null
      ? Math.max(transaction.expiresDateMs, graceExpiresMs ?? 0)
      : null;
  const purchase: VerifiedStorePurchase = {
    platform: "app_store",
    productId: transaction.productId,
    transactionId: transaction.transactionId,
    originalTransactionId: transaction.originalTransactionId,
    linkedOriginalTransactionId: null,
    expiresAtMs,
    entitled:
      !revoked &&
      !transaction.isUpgraded &&
      expiresAtMs !== null &&
      expiresAtMs > nowMs,
    revoked,
    sandbox,
    quantity: transaction.quantity,
    period: null,
  };
  const outcome = await deps.apply({
    purchase,
    source: `app_store_notification:${type}${subtype ? `/${subtype}` : ""}`,
    allowRevocation: true,
  });
  console.log(
    `[storeNotifications] App Store ${type}/${subtype} ` +
      `${transaction.productId} tx=${transaction.transactionId}: ` +
      `${outcome.applied ? "aplicado" : "sin cambios"} (${outcome.reason})`
  );
  return { status: 200, result: outcome.reason };
}

/// Codigos de `subscriptionNotification.notificationType` de Play.
const PLAY_SUBSCRIPTION_REVOKED = 12;

/// Procesa un mensaje de Play RTDN (ya decodificado de Pub/Sub). Nunca lanza:
/// un error aqui solo haria que Pub/Sub no reintente (la funcion no pide
/// reintentos) y se perderia el registro.
export async function handlePlayRtdn(
  message: Json,
  deps: NotificationDeps = defaultNotificationDeps
): Promise<string> {
  const packageName = text(message.packageName);
  if (packageName && packageName !== PLAY_PACKAGE_NAME) return "other_app";
  if (message.testNotification) {
    console.log("[storeNotifications] Play RTDN: notificacion de prueba OK");
    return "test";
  }
  const subscription = obj(message.subscriptionNotification);
  const voided = obj(message.voidedPurchaseNotification);
  let token = "";
  let revoked = false;
  let kind = "";
  if (text(subscription.purchaseToken)) {
    token = text(subscription.purchaseToken);
    revoked = subscription.notificationType === PLAY_SUBSCRIPTION_REVOKED;
    kind = `subscription:${String(subscription.notificationType)}`;
  } else if (text(voided.purchaseToken) && voided.productType === 1) {
    // Reembolso/anulacion de una SUSCRIPCION (productType 1).
    token = text(voided.purchaseToken);
    revoked = true;
    kind = "voided_subscription";
  } else {
    // Consumibles y demas: solo se registran.
    console.log(
      `[storeNotifications] Play RTDN sin accion: ${Object.keys(message).join(",")}`
    );
    return "ignored";
  }

  const config = await deps.config();
  let purchase: VerifiedStorePurchase;
  try {
    const sub = parsePlaySubscriptionV2(
      await deps.fetchPlaySubscription(token),
      token,
      deps.nowMs()
    );
    purchase = playSubscriptionToVerified(sub, revoked);
  } catch (error) {
    // Sin acceso a la Play Developer API (paso externo pendiente) no hay forma
    // de saber que ha pasado: se registra y la renovacion se recuperara cuando
    // la app la reentregue al arrancar.
    console.warn(
      `[storeNotifications] Play RTDN ${kind}: no se pudo consultar a Google: ` +
        (error as Error).message
    );
    return "store_unavailable";
  }
  if (purchase.sandbox && !config.allowSandbox) return "sandbox_ignored";
  const outcome = await deps.apply({
    purchase,
    source: `play_rtdn:${kind}`,
    // Quitar un plan por una notificacion de Play depende del acceso a la API
    // y de su configuracion: solo con 'enforce'. En 'log' queda escrito.
    allowRevocation: config.mode === "enforce",
  });
  console.log(
    `[storeNotifications] Play RTDN ${kind} ${purchase.productId}: ` +
      `${outcome.applied ? "aplicado" : "sin cambios"} (${outcome.reason})`
  );
  return outcome.reason;
}

/// URL a configurar en App Store Connect (Produccion y Sandbox):
///   https://europe-west1-attra-database.cloudfunctions.net/appStoreNotifications
export const appStoreNotifications = onRequest(
  { region: REGION },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }
    const signedPayload = text(obj(req.body).signedPayload);
    if (!signedPayload) {
      res.status(400).send("Falta signedPayload");
      return;
    }
    try {
      const { status, result } = await handleAppStoreNotification(signedPayload);
      res.status(status).send(result);
    } catch (error) {
      // Error nuestro (Firestore caido...): 500 para que Apple reintente.
      console.error(
        `[storeNotifications] App Store: error procesando: ${(error as Error).message}`
      );
      res.status(500).send("error");
    }
  }
);

/// Topic de Pub/Sub a configurar en Play Console (Monetizacion > RTDN):
///   projects/attra-database/topics/play-rtdn
export const playRtdn = onMessagePublished(
  { topic: "play-rtdn", region: REGION },
  async (event) => {
    let message: Json;
    try {
      message = obj(event.data.message.json);
    } catch (error) {
      console.warn(
        `[storeNotifications] Play RTDN ilegible: ${(error as Error).message}`
      );
      return;
    }
    try {
      await handlePlayRtdn(message);
    } catch (error) {
      console.error(
        `[storeNotifications] Play RTDN: error procesando: ${(error as Error).message}`
      );
    }
  }
);
