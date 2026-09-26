import { onCall, HttpsError } from "firebase-functions/v2/https";
import { createHash } from "node:crypto";
import { FieldValue, DocumentData } from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
import { col, requireAuthUid } from "./common";
import {
  StoreCheck,
  StorePlatform,
  checkStorePurchase,
  readReceiptValidationConfig,
} from "./storeValidation";

/// Consumibles comprables de Attra: ATTRAS, BOOSTS y SWIPES (likes extra).
/// Boosts/swipes viven en `users/{uid}.wallet.{boosts,swipes}`; los Attras, en
/// `attraWallets/{uid}.balance` (con espejo en `users/{uid}.attrasBalance`, que
/// es de donde los lee la app). Esta función los ABONA al saldo.
///
/// Antes era un PLACEHOLDER que abonaba sin recibo (`purchase_placeholder`):
/// cualquier cuenta se regalaba packs llamando a la callable con un
/// `purchaseId` distinto cada vez. Ahora SIEMPRE exige plataforma y recibo, lo
/// valida contra la tienda (ver storeValidation.ts) y la idempotencia va por el
/// id de transaccion de la TIENDA, no por lo que diga el cliente.

type ConsumableKind = "boost" | "swipe" | "attra";

interface ConsumableProduct {
  kind: ConsumableKind;
  amount: number;
}

/// Catálogo AUTORITATIVO producto → {tipo, cantidad}, igual que `PRODUCT_TIER`
/// en subscriptions.ts.
///
/// Antes la cantidad llegaba en `amount` desde el cliente y el servidor se la
/// creía (hasta 100 por llamada): cualquiera con la callable podía abonarse 100
/// Boosts sin pagar. Ahora la cantidad SIEMPRE sale de aquí y lo que mande el
/// cliente se ignora. Los ids/cantidades son exactamente los de
/// lib/src/features/monetization/domain/premium_product_catalog.dart.
const CONSUMABLE_PRODUCTS: Record<string, ConsumableProduct> = {
  attra_pack_3: { kind: "attra", amount: 3 },
  attra_pack_10: { kind: "attra", amount: 10 },
  attra_pack_50: { kind: "attra", amount: 50 },
  attra_boost_1: { kind: "boost", amount: 1 },
  attra_boost_5: { kind: "boost", amount: 5 },
  attra_swipes_25: { kind: "swipe", amount: 25 },
};

interface ResolvedProduct extends ConsumableProduct {
  productId: string;
}

/// Resuelve el producto comprado. Ruta principal: `productId` del catálogo.
///
/// Compatibilidad: el cliente actual (boost_service.dart) todavía manda
/// `kind`+`amount` sin `productId`, así que ese par se resuelve buscando el
/// producto del catálogo que lo tenga EXACTO. Sigue siendo lista blanca (un par
/// que no exista en el catálogo se rechaza), solo que la clave es (kind, amount)
/// en vez del id. Cuando el cliente mande `productId` esta rama sobra.
function resolveProduct(data: DocumentData | undefined): ResolvedProduct {
  const productId =
    typeof data?.productId === "string" ? data.productId.trim() : "";
  if (productId.length > 0) {
    const product = CONSUMABLE_PRODUCTS[productId];
    if (!product) {
      throw new HttpsError(
        "invalid-argument",
        `Producto desconocido: ${productId}`
      );
    }
    return { productId, ...product };
  }

  const kind = data?.kind;
  const amount = typeof data?.amount === "number" ? data.amount : Number(data?.amount);
  for (const [id, product] of Object.entries(CONSUMABLE_PRODUCTS)) {
    if (product.kind === kind && product.amount === amount) {
      return { productId: id, ...product };
    }
  }
  throw new HttpsError(
    "invalid-argument",
    "Producto no reconocido: manda 'productId' del catálogo."
  );
}

/// Identificador estable del canje SIN verificar: el hash del recibo (en Play,
/// el token de la compra), para que el mismo recibo produzca siempre la misma
/// clave. Con la compra verificada la clave es el id de la tienda (ver
/// resolveConsumableGrant).
function purchaseKeyFor(verificationData: string | null): string {
  if (verificationData) return createHash("sha256").update(verificationData).digest("hex");
  // Sin identificador no hay idempotencia posible: la misma compra podría
  // abonarse infinitas veces. Antes esto se permitía (ledger con id aleatorio).
  throw new HttpsError(
    "invalid-argument",
    "Falta el identificador de compra (purchaseId o recibo)."
  );
}

/// Id GLOBAL del canje (no lleva uid): así el mismo recibo no se puede canjear
/// desde varias cuentas.
function ledgerIdFor(purchaseKey: string): string {
  // Solo la compra: si la plataforma entrase en el id, el mismo pago entregado
  // por dos caminos (uno con platform, otro sin ella) generaria DOS documentos
  // y se abonaria dos veces, que es justo lo que este ledger evita.
  return createHash("sha256").update(purchaseKey).digest("hex");
}

function walletField(kind: ConsumableKind): "boosts" | "swipes" {
  return kind === "boost" ? "boosts" : "swipes";
}

/// Qué abonar según lo que dijo la tienda. Pura para poder probarla.
///
///  - rechazada: no se abona nada y se devuelve el motivo (con `permanent`
///    para que la app sepa si cerrar la transaccion).
///  - verificada: producto, cantidad e id de canje salen de la TIENDA. Un
///    recibo real de OTRO producto (una suscripcion, un pack mas barato) no
///    puede abonar el pack que pida el cliente.
///  - sin verificar (solo Android cuando Google no puede contestar): con el
///    producto del cliente y, como clave, el hash del TOKEN de Play, no el
///    purchaseId. El token es uno por compra y no cambia al pagarse; el
///    orderId que manda la app como purchaseId, si: mientras la compra esta
///    PENDIENTE de pago (efectivo, metodos lentos) Play no tiene orderId y la
///    app manda '', y al pagarse llega con 'GPA...'. Con el purchaseId de clave
///    eran dos compras distintas y el mismo pack se abonaba dos veces (una de
///    ellas antes de estar pagado).
export function resolveConsumableGrant(input: {
  check: StoreCheck;
  requested: ResolvedProduct;
  verificationData: string;
}):
  | {
      ok: true;
      product: ResolvedProduct;
      amount: number;
      purchaseKey: string;
      verified: boolean;
      sandbox: boolean | null;
    }
  | { ok: false; permanent: boolean; reason: string; message: string } {
  const { check, requested } = input;
  if (check.status === "rejected") {
    return {
      ok: false,
      permanent: check.permanent,
      reason: check.reason,
      message: check.message,
    };
  }
  if (check.status === "unverified") {
    return {
      ok: true,
      product: requested,
      amount: requested.amount,
      purchaseKey: purchaseKeyFor(input.verificationData),
      verified: false,
      sandbox: null,
    };
  }
  const purchase = check.purchase;
  const catalog = CONSUMABLE_PRODUCTS[purchase.productId];
  if (!catalog) {
    return {
      ok: false,
      permanent: true,
      reason: "unknown_product",
      message: "Esta compra no corresponde a un pack de Attra.",
    };
  }
  if (purchase.revoked || !purchase.entitled) {
    return {
      ok: false,
      permanent: true,
      reason: "revoked",
      message: "Esta compra fue reembolsada o cancelada.",
    };
  }
  return {
    ok: true,
    product: { productId: purchase.productId, ...catalog },
    amount: catalog.amount * Math.max(1, purchase.quantity),
    purchaseKey: purchase.transactionId,
    verified: true,
    sandbox: purchase.sandbox,
  };
}

/// Abona el consumible del producto comprado. Registra el canje en
/// `consumableLedger` (auditable) e IDEMPOTENTE por compra: el mismo recibo no
/// abona dos veces ni aunque lo reenvíe otra cuenta.
export const grantConsumable = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const requested = resolveProduct(request.data);
  const rawPurchaseId =
    typeof request.data?.purchaseId === "string" && request.data.purchaseId.trim()
      ? request.data.purchaseId.trim().slice(0, 120)
      : "";
  // Recibo de la tienda (IAP). Los dos caminos reales de la app
  // (purchase_delivery_router y la hoja de Boosts) mandan SIEMPRE plataforma y
  // recibo; sin ellos no hay nada que validar y antes se abonaba igual.
  const platform: StorePlatform | null =
    request.data?.platform === "app_store" || request.data?.platform === "play_store"
      ? (request.data.platform as StorePlatform)
      : null;
  const verificationData =
    typeof request.data?.verificationData === "string"
      ? (request.data.verificationData as string)
      : "";
  if (!platform || !verificationData.trim()) {
    throw new HttpsError("invalid-argument", "Falta el recibo de compra.");
  }

  const check = await checkStorePurchase({
    platform,
    kind: "consumable",
    productId: requested.productId,
    verificationData,
    config: await readReceiptValidationConfig(),
  });
  // El recibo se hashea ENTERO cuando hace falta usarlo de clave (sin
  // verificar y sin purchaseId). Truncarlo antes del hash reintroducia el bug
  // que subscriptions.ts documenta: en iOS la cabecera del recibo es identica
  // entre compras distintas del mismo dispositivo, asi que dos compras reales
  // colapsaban en la misma clave. Y aqui el dano es peor: el falso duplicado
  // responde ok, el cliente da la compra por entregada y la finaliza en la
  // tienda. Dinero cobrado, saldo no abonado, sin vuelta atras.
  const decision = resolveConsumableGrant({
    check,
    requested,
    verificationData,
  });
  if (!decision.ok) {
    return {
      ok: false,
      permanent: decision.permanent,
      reason: decision.reason,
      message: decision.message,
    };
  }
  const { productId, kind } = decision.product;
  const amount = decision.amount;
  const purchaseKey = decision.purchaseKey;
  const source = `iap_${platform}`;

  const userRef = col.users.doc(uid);
  const ledgerRef = db.collection("consumableLedger").doc(ledgerIdFor(purchaseKey));
  // Canjes anteriores al ledger global quedaron con id `${uid}_${purchaseId}`;
  // se siguen mirando para no reabonar una compra ya entregada.
  const legacyLedgerRef =
    rawPurchaseId.length > 0
      ? db.collection("consumableLedger").doc(`${uid}_${rawPurchaseId}`)
      : null;
  const attraWalletRef = col.wallets.doc(uid);
  const attraLedgerRef = col.ledger.doc();

  return db.runTransaction(async (tx) => {
    const [userSnap, ledgerSnap, legacySnap, attraWalletSnap] = await Promise.all([
      tx.get(userRef),
      tx.get(ledgerRef),
      legacyLedgerRef ? tx.get(legacyLedgerRef) : Promise.resolve(null),
      kind === "attra" ? tx.get(attraWalletRef) : Promise.resolve(null),
    ]);
    if (!userSnap.exists) {
      throw new HttpsError("failed-precondition", "No existe tu perfil.");
    }

    const userData = userSnap.data() ?? {};
    const wallet = (userData.wallet ?? {}) as Record<string, unknown>;
    // Saldo de Attras: la fuente transaccional es `attraWallets`; si el doc no
    // existe todavía partimos del espejo del usuario para no borrar saldo previo.
    const attraBase = attraWalletSnap?.exists
      ? Number(attraWalletSnap.data()?.balance ?? 0)
      : Number(userData.attrasBalance ?? 0);
    const currentBalance =
      kind === "attra" ? attraBase : Number(wallet[walletField(kind)] ?? 0);

    // Idempotencia: una misma compra no abona dos veces.
    if (ledgerSnap.exists || legacySnap?.exists) {
      const ownerUid = (ledgerSnap.data()?.uid ?? uid).toString();
      if (ledgerSnap.exists && ownerUid !== uid) {
        // NO se lanza excepcion: el cliente solo finaliza la transaccion
        // cuando la entrega va bien, y un error aqui la dejaria reencolada en
        // la tienda para siempre. Se devuelve un fallo PERMANENTE explicito
        // para que el cliente la cierre y avise. Ademas, inferir la
        // permanencia del CODIGO de error era peligroso: el SDK usa
        // 'not-found' cuando la funcion no esta desplegada y
        // 'permission-denied' ante problemas de App Check, y tratarlos como
        // definitivos cerraba compras legitimas sin entregar nada.
        return {
          ok: false,
          permanent: true,
          reason: "claimed_by_other_account",
          message: "Esa compra ya fue canjeada por otra cuenta.",
        };
      }
      return {
        ok: true,
        duplicate: true,
        productId,
        kind,
        amount: 0,
        balance: currentBalance,
      };
    }

    const now = FieldValue.serverTimestamp();
    const newBalance = currentBalance + amount;

    if (kind === "attra") {
      // Los Attras se gastan contra `attraWallets` (sendAttra), pero la app lee
      // `users.attrasBalance`: hay que escribir en los dos o el saldo comprado
      // no se ve (o no se puede gastar).
      tx.set(
        attraWalletRef,
        { balance: newBalance, updatedAt: now },
        { merge: true }
      );
      tx.set(
        userRef,
        { attrasBalance: newBalance, updatedAt: now },
        { merge: true }
      );
      tx.set(attraLedgerRef, {
        uid,
        type: "purchase",
        amount,
        balanceAfter: newBalance,
        productId,
        source,
        createdAt: now,
      });
    } else {
      // Incrementa el saldo anidado `wallet.boosts`/`wallet.swipes` (mismo campo
      // que consume activateBoost / sendLike). Un único write para no duplicar.
      tx.set(
        userRef,
        {
          wallet: {
            [walletField(kind)]: FieldValue.increment(amount),
          },
          updatedAt: now,
        },
        { merge: true }
      );
    }

    tx.set(ledgerRef, {
      uid,
      productId,
      kind,
      amount,
      purchaseId: rawPurchaseId || null,
      purchaseKey,
      platform,
      hasReceipt: true,
      verified: decision.verified,
      sandbox: decision.sandbox,
      type: "grant",
      source,
      createdAt: now,
    });

    return { ok: true, duplicate: false, productId, kind, amount, balance: newBalance };
  });
});
