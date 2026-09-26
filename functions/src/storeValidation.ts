import { createHash } from "node:crypto";
import { db } from "./firebase";
import {
  APPLE_BUNDLE_ID,
  AppleJwsError,
  looksLikeJws,
  parseAppleTransaction,
  verifyAppleSignedPayload,
} from "./storeApple";
import {
  PlayApiError,
  PlaySubscriptionState,
  fetchPlayProductRaw,
  fetchPlaySubscriptionRaw,
  parsePlayProductPurchase,
  parsePlaySubscriptionV2,
  periodFromBasePlan,
} from "./storeGoogle";

/// Validacion de recibos de compra ANTES de conceder nada (planes y
/// consumibles).
///
/// QUE FALLABA: `verifyPurchase` y `grantConsumable` solo comprobaban que el
/// recibo fuese un texto no vacio. Cualquier cuenta podia llamar a la callable
/// con `verificationData: 'x'` y llevarse un año de Pro, o abonarse packs de
/// Attras/Boosts sin fin cambiando el `purchaseId`.
///
/// Hay dos tipos de comprobacion y no se tratan igual:
///  - VERIFICABLES SIEMPRE (no necesitan credenciales): que haya recibo, y en
///    iOS la firma del JWS de StoreKit 2 hasta la raiz de Apple. Se exigen
///    SIEMPRE, en cualquier modo.
///  - DEPENDIENTES DE CREDENCIALES: en Android, preguntar a la Play Developer
///    API (la cuenta de servicio necesita acceso en Play Console, paso externo
///    del dueño). Van detras de `config/featureFlags.receiptValidation`:
///      'log'     (por defecto) se intenta; si Google NO PUEDE contestar (sin
///                permiso, red, 5xx) se registra y se concede como antes.
///                Exigirlo sin el acceso configurado dejaria sin plan a todo
///                el que paga en Android.
///      'enforce' ademas, en SUSCRIPCIONES, sin respuesta de Google no se
///                concede nada. Los CONSUMIBLES siguen como en 'log' ante un
///                fallo de Google: Play ya los ha consumido antes de llegar
///                aqui (buyConsumable con autoConsume), y rechazarlos por una
///                caida de Google perderia el pack pagado para siempre. Eso
///                cambia cuando la app consuma DESPUES de validar.
///    En CUALQUIER modo, si Google contesta que el token no existe o no es de
///    ese producto (400/404/410) se rechaza: esa respuesta solo puede llegar
///    con las credenciales ya funcionando, y es justo el recibo inventado.
///    Antes 'log' lo concedia igual, y como la plataforma la elige quien llama,
///    cualquier cuenta (tambien desde iOS) se regalaba un plan con
///    `platform: 'play_store'` aunque Google ya dijese que era falso.
///
/// OJO, hueco que sigue abierto HASTA el paso externo 2: sin acceso a la API
/// Google contesta 401/403 y todo token de Play, inventado o no, pasa sin
/// verificar. Lo puede usar CUALQUIER cuenta, no solo las de Android, porque
/// la plataforma la manda el cliente. Es bloqueante para dar la validacion por
/// cerrada.
///
/// Sandbox: la revision de Apple compra con cuentas SANDBOX sobre la build de
/// produccion, asi que el sandbox se acepta (`receiptValidationAllowSandbox`
/// a false lo corta cuando ya no haga falta; OJO: TestFlight tambien compra en
/// sandbox).
///
/// PASOS EXTERNOS (solo el dueño; sin ellos todo sigue funcionando en 'log'):
///  1. Google Cloud (proyecto attra-database): habilitar "Google Play Android
///     Developer API".
///  2. Play Console > Usuarios y permisos > Invitar: la cuenta de servicio con
///     la que corren las Functions (gen2: `<numero-proyecto>-compute@
///     developer.gserviceaccount.com`), con acceso a la app y el permiso "Ver
///     datos financieros, pedidos y respuestas a encuestas de cancelacion".
///  3. Play RTDN: tras desplegar `playRtdn` existe el topic `play-rtdn`. Darle
///     el rol "Publicador de Pub/Sub" a
///     `google-play-developer-notifications@system.gserviceaccount.com` y
///     ponerlo en Play Console > Monetizacion > Configuracion:
///     `projects/attra-database/topics/play-rtdn` ("Enviar notificacion de
///     prueba" -> en logs "notificacion de prueba OK").
///  4. App Store Connect > la app > Informacion de la app > Notificaciones del
///     servidor: version 2, URL de produccion Y de sandbox =
///     https://europe-west1-attra-database.cloudfunctions.net/appStoreNotifications
///     (no hace falta clave .p8 ni issuer id: se verifica por firma).
///  5. Cuando en los logs de compras reales de Android salga
///     "[receipt] play_store verificado" (y no "SIN VERIFICAR"), poner
///     `config/featureFlags.receiptValidation = "enforce"`. Con el paso 2 hecho
///     los tokens inventados ya se rechazan tambien en 'log'; 'enforce' solo
///     añade no conceder SUSCRIPCIONES mientras Google no conteste (no afecta
///     a los consumibles, ver arriba), asi que es seguro activarlo.

export type StorePlatform = "app_store" | "play_store";
export type ReceiptValidationMode = "log" | "enforce";

export interface ReceiptValidationConfig {
  mode: ReceiptValidationMode;
  allowSandbox: boolean;
}

export const DEFAULT_RECEIPT_VALIDATION: ReceiptValidationConfig = {
  mode: "log",
  allowSandbox: true,
};

/// Lee el modo de `config/featureFlags`. Cualquier valor que no sea
/// exactamente 'enforce' es 'log': un typo en la consola no puede cortar las
/// compras de todo Android.
export function parseReceiptValidationConfig(
  flags: Record<string, unknown> | undefined
): ReceiptValidationConfig {
  const rawMode = flags?.receiptValidation ?? flags?.receipt_validation;
  const mode: ReceiptValidationMode =
    typeof rawMode === "string" && rawMode.trim().toLowerCase() === "enforce"
      ? "enforce"
      : "log";
  const rawSandbox =
    flags?.receiptValidationAllowSandbox ?? flags?.receipt_validation_allow_sandbox;
  return { mode, allowSandbox: rawSandbox !== false };
}

const CONFIG_TTL_MS = 60 * 1000;
let configCache: { value: ReceiptValidationConfig; at: number } | null = null;

/// Olvida la config cacheada (tests; y por si algun dia se quiere forzar la
/// relectura tras cambiar el modo sin esperar al minuto de cache).
export function clearReceiptValidationConfigCache(): void {
  configCache = null;
}

export async function readReceiptValidationConfig(): Promise<ReceiptValidationConfig> {
  const now = Date.now();
  if (configCache && now - configCache.at < CONFIG_TTL_MS) return configCache.value;
  try {
    const snap = await db.collection("config").doc("featureFlags").get();
    const value = parseReceiptValidationConfig(snap.data());
    configCache = { value, at: now };
    return value;
  } catch (error) {
    // Sin poder leer la config se usa el default, que sigue exigiendo todo lo
    // verificable: nunca se afloja por un fallo de lectura.
    console.warn(`[receipt] no se pudo leer la config: ${(error as Error).message}`);
    return DEFAULT_RECEIPT_VALIDATION;
  }
}

/// Compra CONFIRMADA por la tienda. Todo lo que decide que se concede
/// (producto, caducidad, id de transaccion) sale de aqui, no del cliente.
export interface VerifiedStorePurchase {
  platform: StorePlatform;
  productId: string;
  /// Una por compra/renovacion: es la clave de idempotencia del ledger.
  transactionId: string;
  /// Estable durante toda la suscripcion (originalTransactionId de Apple,
  /// purchaseToken de Play). Enlaza las notificaciones con la cuenta.
  originalTransactionId: string;
  /// Play: token anterior cuando la suscripcion sustituye a otra (cambio de
  /// plan, resuscripcion).
  linkedOriginalTransactionId: string | null;
  expiresAtMs: number | null;
  /// Suscripciones: la tienda dice que da acceso AHORA (no caducada, no
  /// reembolsada, no sustituida por un cambio de plan). Consumibles: siempre
  /// true salvo reembolso.
  entitled: boolean;
  revoked: boolean;
  sandbox: boolean;
  quantity: number;
  period: "monthly" | "yearly" | null;
}

export type StoreCheck =
  | { status: "verified"; purchase: VerifiedStorePurchase }
  /// Solo Play y solo cuando Google NO PUDO contestar: en modo 'log', o un
  /// consumible en cualquier modo.
  | { status: "unverified"; reason: string }
  | { status: "rejected"; permanent: boolean; reason: string; message: string };

export interface StoreDeps {
  verifyAppleJws: (jws: string) => Record<string, unknown>;
  fetchPlaySubscription: (token: string) => Promise<Record<string, unknown>>;
  fetchPlayProduct: (
    productId: string,
    token: string
  ) => Promise<Record<string, unknown>>;
  nowMs: () => number;
}

export const defaultStoreDeps: StoreDeps = {
  verifyAppleJws: (jws) => verifyAppleSignedPayload(jws),
  fetchPlaySubscription: fetchPlaySubscriptionRaw,
  fetchPlayProduct: fetchPlayProductRaw,
  nowMs: () => Date.now(),
};

/// Huella corta para los logs: nunca se escribe el recibo entero.
export function receiptFingerprint(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex").slice(0, 12);
}

function rejected(
  permanent: boolean,
  reason: string,
  message: string
): StoreCheck {
  return { status: "rejected", permanent, reason, message };
}

const MSG_NOT_VERIFIED =
  "No hemos podido verificar la compra con la tienda. Se volverá a intentar " +
  "automáticamente; no se te cobrará otra vez.";
const MSG_NOT_VALID = "Este recibo de compra no es válido.";

/// Comprueba la compra contra la tienda. NUNCA lanza por el recibo: devuelve
/// `rejected` con `permanent` para que el cliente sepa si cerrar la
/// transaccion.
///
/// `permanent: true` solo cuando es IMPOSIBLE que ese recibo llegue a valer
/// (de otra app, sin forma de JWS, cancelado). Un fallo de firma o de Google se
/// marca temporal a proposito: si el fallo fuese NUESTRO (una raiz rotada, un
/// permiso mal puesto), una compra real se quedaria abierta y se reintentaria
/// en vez de cerrarse sin entregar; y un recibo falso no gana nada con el
/// reintento.
export async function checkStorePurchase(
  input: {
    platform: StorePlatform;
    kind: "subscription" | "consumable";
    productId: string;
    verificationData: string;
    config: ReceiptValidationConfig;
  },
  deps: StoreDeps = defaultStoreDeps
): Promise<StoreCheck> {
  const data = input.verificationData.trim();
  const fp = receiptFingerprint(data);
  const nowMs = deps.nowMs();

  if (input.platform === "app_store") {
    // Todas las builds publicadas usan StoreKit 2, que manda SIEMPRE un JWS.
    // Otra cosa no la ha generado la App Store.
    if (!looksLikeJws(data)) {
      console.warn(`[receipt] app_store rechazado: no es JWS (${fp})`);
      return rejected(true, "receipt_malformed", MSG_NOT_VALID);
    }
    let tx;
    try {
      tx = parseAppleTransaction(deps.verifyAppleJws(data));
    } catch (error) {
      const code = error instanceof AppleJwsError ? error.code : "unknown";
      console.warn(
        `[receipt] app_store rechazado: ${code} ${(error as Error).message} (${fp})`
      );
      return code === "malformed"
        ? rejected(true, "receipt_malformed", MSG_NOT_VALID)
        : rejected(false, "receipt_unverified", MSG_NOT_VERIFIED);
    }
    if (tx.bundleId !== APPLE_BUNDLE_ID) {
      console.warn(`[receipt] app_store de otra app: ${tx.bundleId} (${fp})`);
      return rejected(true, "wrong_app", MSG_NOT_VALID);
    }
    const sandbox = tx.environment === "Sandbox";
    if (!sandbox && tx.environment !== "Production") {
      return rejected(true, "unsupported_environment", MSG_NOT_VALID);
    }
    if (sandbox && !input.config.allowSandbox) {
      return rejected(true, "sandbox_not_allowed", MSG_NOT_VALID);
    }
    const revoked = tx.revocationDateMs !== null;
    const entitled =
      input.kind === "subscription"
        ? !revoked &&
          !tx.isUpgraded &&
          tx.expiresDateMs !== null &&
          tx.expiresDateMs > nowMs
        : !revoked;
    console.log(
      `[receipt] app_store verificado ${tx.productId} tx=${tx.transactionId} ` +
        `env=${tx.environment} entitled=${entitled}`
    );
    return {
      status: "verified",
      purchase: {
        platform: "app_store",
        productId: tx.productId,
        transactionId: tx.transactionId,
        originalTransactionId: tx.originalTransactionId,
        linkedOriginalTransactionId: null,
        expiresAtMs: tx.expiresDateMs,
        entitled,
        revoked,
        sandbox,
        quantity: tx.quantity,
        period: null,
      },
    };
  }

  try {
    if (input.kind === "subscription") {
      const sub = parsePlaySubscriptionV2(
        await deps.fetchPlaySubscription(data),
        data,
        nowMs
      );
      if (sub.test && !input.config.allowSandbox) {
        return rejected(true, "sandbox_not_allowed", MSG_NOT_VALID);
      }
      console.log(
        `[receipt] play_store verificado ${sub.productId} order=${sub.orderId} ` +
          `state=${sub.state} entitled=${sub.entitled}`
      );
      return { status: "verified", purchase: playSubscriptionToVerified(sub) };
    }
    const product = parsePlayProductPurchase(
      await deps.fetchPlayProduct(input.productId, data),
      input.productId,
      data
    );
    if (product.purchaseState === 1) {
      return rejected(true, "purchase_canceled", "Esta compra está cancelada.");
    }
    if (product.purchaseState !== 0) {
      return rejected(
        false,
        "purchase_pending",
        "La compra todavía está pendiente de pago."
      );
    }
    if (product.test && !input.config.allowSandbox) {
      return rejected(true, "sandbox_not_allowed", MSG_NOT_VALID);
    }
    console.log(
      `[receipt] play_store verificado ${product.productId} order=${product.orderId}`
    );
    return {
      status: "verified",
      purchase: {
        platform: "play_store",
        productId: product.productId,
        transactionId: product.orderId,
        originalTransactionId: product.purchaseToken,
        linkedOriginalTransactionId: null,
        expiresAtMs: null,
        entitled: true,
        revoked: false,
        sandbox: product.test,
        quantity: product.quantity,
        period: null,
      },
    };
  } catch (error) {
    const kind = error instanceof PlayApiError ? error.kind : "unavailable";
    if (kind === "invalid") {
      // Google HA CONTESTADO (asi que las credenciales funcionan) y dice que el
      // token no existe o no es de este producto: es un recibo inventado, en
      // cualquier modo. Antes 'log' lo concedia igual y el ataque del informe
      // (`platform: 'play_store'`, token 'x') seguia dando Pro a cualquiera
      // aun con el acceso a la API ya configurado. Temporal a proposito, como
      // el resto de fallos de Google (ver arriba): una compra real mal
      // clasificada se reintenta en vez de cerrarse sin entregar.
      console.warn(
        `[receipt] play_store rechazado: receipt_invalid ` +
          `${(error as Error).message} (${fp})`
      );
      return rejected(false, "receipt_invalid", MSG_NOT_VERIFIED);
    }
    // Google no pudo contestar (sin permiso en Play Console, red, 429/5xx).
    // Eso no dice nada de si la compra es buena.
    if (input.config.mode === "enforce" && input.kind === "subscription") {
      console.warn(
        `[receipt] play_store rechazado (enforce): store_unavailable ` +
          `${(error as Error).message} (${fp})`
      );
      return rejected(false, "store_unavailable", MSG_NOT_VERIFIED);
    }
    // Modo 'log' (o un consumible): se concede como antes y queda registrado.
    // Un consumible NO se rechaza ni en 'enforce': Play ya lo consumio antes de
    // llegar aqui, no lo vuelve a devolver al restaurar, y la entrega
    // pendiente solo vive en la memoria de la app. Rechazarlo por una caida de
    // Google seria perder el pack pagado al cerrar la app.
    console.warn(
      `[receipt] play_store SIN VERIFICAR (${input.config.mode}, ${input.kind}): ` +
        `store_unavailable ${(error as Error).message} (${fp})`
    );
    return { status: "unverified", reason: "store_unavailable" };
  }
}

/// Suscripcion de Play (respuesta de Google) en el formato comun.
export function playSubscriptionToVerified(
  sub: PlaySubscriptionState,
  revoked = false
): VerifiedStorePurchase {
  return {
    platform: "play_store",
    productId: sub.productId,
    transactionId: sub.orderId,
    originalTransactionId: sub.purchaseToken,
    linkedOriginalTransactionId: sub.linkedPurchaseToken,
    expiresAtMs: sub.expiresAtMs,
    entitled: sub.entitled && !revoked,
    revoked,
    sandbox: sub.test,
    quantity: 1,
    period: periodFromBasePlan(sub.basePlanId),
  };
}

/// Documento que enlaza una suscripcion de la tienda (su id ESTABLE) con la
/// cuenta de Attra. Lo necesitan las notificaciones de servidor, que no traen
/// uid; y cierra que otra cuenta canjee las renovaciones de una suscripcion
/// ajena (cada renovacion trae un id de transaccion nuevo, el ledger por
/// transaccion no lo veria).
export function storeSubscriptionKey(
  platform: StorePlatform,
  originalTransactionId: string
): string {
  return createHash("sha256")
    .update(`${platform}|${originalTransactionId}`, "utf8")
    .digest("hex");
}

export function storeSubscriptionRef(
  platform: StorePlatform,
  originalTransactionId: string
) {
  return db
    .collection("storeSubscriptions")
    .doc(storeSubscriptionKey(platform, originalTransactionId));
}
