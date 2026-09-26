import { GoogleAuth } from "google-auth-library";

/// Validacion de compras de Google Play contra la Play Developer API.
///
/// A diferencia de iOS, en Android lo que manda la app (el `purchaseToken`) NO
/// lleva firma que se pueda comprobar aqui: la unica fuente de verdad es
/// preguntarle a Google. Eso necesita que la cuenta de servicio por defecto de
/// las Functions tenga acceso a la app en Play Console (paso EXTERNO del
/// dueño, ver "PASOS EXTERNOS" en storeValidation.ts). Mientras no lo tenga,
/// Google responde 401/403 y la validacion se queda en modo registro (ver
/// storeValidation.ts): no se puede exigir lo que todavia no se puede
/// comprobar sin dejar sin plan a quien SI ha pagado.

export const PLAY_PACKAGE_NAME =
  process.env.PLAY_PACKAGE_NAME?.trim() || "com.jpedrero.attra";

const PLAY_API =
  "https://androidpublisher.googleapis.com/androidpublisher/v3/applications";

const PLAY_TIMEOUT_MS = 10000;

const auth = new GoogleAuth({
  scopes: ["https://www.googleapis.com/auth/androidpublisher"],
});

/// `invalid`: Google dice que ese token no existe o no es de este producto.
/// `unavailable`: no se pudo preguntar (sin permiso en Play Console, red, 5xx).
/// La diferencia importa: lo segundo NO dice nada de si la compra es buena.
export type PlayApiErrorKind = "invalid" | "unavailable";

export class PlayApiError extends Error {
  constructor(
    readonly kind: PlayApiErrorKind,
    readonly status: number | null,
    message: string
  ) {
    super(message);
    this.name = "PlayApiError";
  }
}

/// 400/404/410 son respuestas de Google sobre EL TOKEN (no existe, caducado,
/// de otro producto). 401/403 son sobre NUESTRAS credenciales, y el resto
/// (429, 5xx) es la infraestructura: ninguna de esas dice que la compra sea
/// falsa.
export function classifyPlayHttpStatus(status: number): PlayApiErrorKind {
  return status === 400 || status === 404 || status === 410
    ? "invalid"
    : "unavailable";
}

async function playGet(path: string): Promise<Record<string, unknown>> {
  let token: string | null | undefined;
  try {
    const client = await auth.getClient();
    token = (await client.getAccessToken()).token;
  } catch (error) {
    throw new PlayApiError(
      "unavailable",
      null,
      `Sin credenciales para la Play Developer API: ${(error as Error).message}`
    );
  }
  const control = new AbortController();
  const corte = setTimeout(() => control.abort(), PLAY_TIMEOUT_MS);
  try {
    const res = await fetch(`${PLAY_API}/${path}`, {
      headers: { Authorization: `Bearer ${token ?? ""}` },
      signal: control.signal,
    });
    if (!res.ok) {
      throw new PlayApiError(
        classifyPlayHttpStatus(res.status),
        res.status,
        `Play Developer API HTTP ${res.status}`
      );
    }
    const body = await res.json();
    return body && typeof body === "object" ? (body as Record<string, unknown>) : {};
  } catch (error) {
    if (error instanceof PlayApiError) throw error;
    throw new PlayApiError(
      "unavailable",
      null,
      `Play Developer API sin respuesta: ${(error as Error).message}`
    );
  } finally {
    clearTimeout(corte);
  }
}

/// `purchases.subscriptionsv2.get`: estado REAL de una suscripcion.
export function fetchPlaySubscriptionRaw(
  purchaseToken: string
): Promise<Record<string, unknown>> {
  return playGet(
    `${encodeURIComponent(PLAY_PACKAGE_NAME)}/purchases/subscriptionsv2/tokens/` +
      encodeURIComponent(purchaseToken)
  );
}

/// `purchases.products.get`: compra de un producto de un solo uso (consumible).
export function fetchPlayProductRaw(
  productId: string,
  purchaseToken: string
): Promise<Record<string, unknown>> {
  return playGet(
    `${encodeURIComponent(PLAY_PACKAGE_NAME)}/purchases/products/` +
      `${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}`
  );
}

export interface PlaySubscriptionState {
  productId: string;
  /// Id de la RENOVACION concreta (`GPA.xxxx..N`): cambia en cada cobro, asi
  /// que es la clave del ledger. Sin orderId (compras de prueba) se usa el
  /// token + la caducidad, que tambien cambia en cada renovacion.
  orderId: string;
  purchaseToken: string;
  linkedPurchaseToken: string | null;
  expiresAtMs: number | null;
  /// ACTIVE / IN_GRACE_PERIOD / CANCELED (cancelada pero aun pagada) dan
  /// acceso; ON_HOLD, PAUSED, EXPIRED y los PENDING no.
  state: string;
  entitled: boolean;
  basePlanId: string | null;
  test: boolean;
}

const ENTITLED_STATES = new Set([
  "SUBSCRIPTION_STATE_ACTIVE",
  "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
  "SUBSCRIPTION_STATE_CANCELED",
]);

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

/// Traduce la respuesta de `subscriptionsv2.get` (pura, para tests). Con varios
/// `lineItems` se queda con el que caduca mas tarde: es el que da acceso.
export function parsePlaySubscriptionV2(
  raw: Record<string, unknown>,
  purchaseToken: string,
  nowMs: number
): PlaySubscriptionState {
  const items = Array.isArray(raw.lineItems) ? raw.lineItems : [];
  let best: Record<string, unknown> | null = null;
  let bestExpiry = -Infinity;
  for (const item of items) {
    if (!item || typeof item !== "object") continue;
    const entry = item as Record<string, unknown>;
    const expiry = Date.parse(text(entry.expiryTime));
    const comparable = Number.isNaN(expiry) ? -Infinity : expiry;
    if (best === null || comparable > bestExpiry) {
      best = entry;
      bestExpiry = comparable;
    }
  }
  const productId = text(best?.productId);
  if (!best || !productId) {
    throw new PlayApiError("invalid", null, "La suscripcion no trae producto.");
  }
  const expiresAtMs = Number.isFinite(bestExpiry) ? bestExpiry : null;
  const offer =
    best.offerDetails && typeof best.offerDetails === "object"
      ? (best.offerDetails as Record<string, unknown>)
      : {};
  const state = text(raw.subscriptionState);
  const orderId =
    text(best.latestSuccessfulOrderId) ||
    text(raw.latestOrderId) ||
    `${purchaseToken}|${expiresAtMs ?? "?"}`;
  return {
    productId,
    orderId,
    purchaseToken,
    linkedPurchaseToken: text(raw.linkedPurchaseToken) || null,
    expiresAtMs,
    state,
    entitled:
      ENTITLED_STATES.has(state) && expiresAtMs !== null && expiresAtMs > nowMs,
    basePlanId: text(offer.basePlanId) || null,
    test: raw.testPurchase != null,
  };
}

/// Periodo segun el plan basico (`attra-plus-yearly`, `anual`, `monthly`...).
/// Solo para el registro: la caducidad buena es la de Google, no esta.
export function periodFromBasePlan(
  basePlanId: string | null
): "monthly" | "yearly" | null {
  const id = (basePlanId ?? "").toLowerCase();
  if (!id) return null;
  if (/(year|annual|anual|12m|p1y)/.test(id)) return "yearly";
  if (/(month|mensual|1m|p1m)/.test(id)) return "monthly";
  return null;
}

export interface PlayProductPurchase {
  productId: string;
  orderId: string;
  purchaseToken: string;
  /// 0 comprado, 1 cancelado, 2 pendiente.
  purchaseState: number;
  quantity: number;
  test: boolean;
}

/// Traduce `purchases.products.get` (pura, para tests).
export function parsePlayProductPurchase(
  raw: Record<string, unknown>,
  requestedProductId: string,
  purchaseToken: string
): PlayProductPurchase {
  // `productId` solo viene en respuestas recientes. Si viene y NO es el pedido,
  // alguien esta pasando el token de otro producto.
  const reported = text(raw.productId);
  if (reported && reported !== requestedProductId) {
    throw new PlayApiError(
      "invalid",
      null,
      `El token es de ${reported}, no de ${requestedProductId}.`
    );
  }
  const state =
    typeof raw.purchaseState === "number" ? raw.purchaseState : Number.NaN;
  const quantity =
    typeof raw.quantity === "number" && raw.quantity >= 1
      ? Math.floor(raw.quantity)
      : 1;
  return {
    productId: requestedProductId,
    orderId: text(raw.orderId) || purchaseToken,
    purchaseToken,
    purchaseState: Number.isFinite(state) ? state : -1,
    quantity,
    // purchaseType 0 = compra de prueba (license testers).
    test: raw.purchaseType === 0,
  };
}
