import { onCall, HttpsError } from "firebase-functions/v2/https";
import { createHash } from "node:crypto";
import { FieldValue, DocumentData } from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
import { col, requireAuthUid } from "./common";

/// Consumibles comprables de Attra: ATTRAS, BOOSTS y SWIPES (likes extra).
/// Boosts/swipes viven en `users/{uid}.wallet.{boosts,swipes}`; los Attras, en
/// `attraWallets/{uid}.balance` (con espejo en `users/{uid}.attrasBalance`, que
/// es de donde los lee la app). Esta función los ABONA al saldo.
///
/// ⚠️ PLACEHOLDER DE COMPRA: hoy abona directamente (MVP / pruebas). Antes de
/// producción debe ENVOLVERSE con validación de recibo IAP (App Store / Google
/// Play) o pasarela de pago: el cliente compra, valida el recibo en el backend,
/// y SOLO entonces se llama a esta concesión. No exponer el abono libre en prod.

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

/// Identificador estable del canje. Preferimos el id de transacción de la
/// tienda; si no llega, lo derivamos del recibo (sha256) para que el mismo
/// recibo produzca siempre la misma clave.
function purchaseKeyFor(
  purchaseId: string,
  verificationData: string | null
): string {
  if (purchaseId.length > 0) return purchaseId;
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

/// Abona el consumible del producto comprado. Registra el canje en
/// `consumableLedger` (auditable) e IDEMPOTENTE por compra: el mismo recibo no
/// abona dos veces ni aunque lo reenvíe otra cuenta.
export const grantConsumable = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const { productId, kind, amount } = resolveProduct(request.data);
  const rawPurchaseId =
    typeof request.data?.purchaseId === "string" && request.data.purchaseId.trim()
      ? request.data.purchaseId.trim().slice(0, 120)
      : "";
  // Recibo de la tienda (IAP). En la app real llega siempre; el placeholder de
  // pruebas puede no traerlo.
  const platform =
    request.data?.platform === "app_store" || request.data?.platform === "play_store"
      ? (request.data.platform as string)
      : null;
  const verificationData =
    typeof request.data?.verificationData === "string"
      ? (request.data.verificationData as string)
      : null;
  // El recibo se hashea ENTERO. Truncarlo antes del hash reintroducia el bug
  // que subscriptions.ts documenta: en iOS la cabecera del recibo es identica
  // entre compras distintas del mismo dispositivo, asi que dos compras reales
  // colapsaban en la misma clave. Y aqui el dano es peor: el falso duplicado
  // responde ok, el cliente da la compra por entregada y la finaliza en la
  // tienda. Dinero cobrado, saldo no abonado, sin vuelta atras.
  const purchaseKey = purchaseKeyFor(rawPurchaseId, verificationData);

  // TODO(IAP server validation): cuando haya recibo (platform+verificationData),
  // validarlo contra Google Play Developer API / App Store Server API ANTES de
  // conceder. Requiere credenciales de tienda (service account / shared secret).
  // Hoy: si llega recibo confiamos en él (idempotente por compra); si no,
  // es la concesión placeholder de pruebas.
  const source = platform ? `iap_${platform}` : "purchase_placeholder";

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
        throw new HttpsError(
          "permission-denied",
          "Esa compra ya fue canjeada por otra cuenta."
        );
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
      hasReceipt: verificationData != null,
      type: "grant",
      source,
      createdAt: now,
    });

    return { ok: true, duplicate: false, productId, kind, amount, balance: newBalance };
  });
});
