const test = require("node:test");
const assert = require("node:assert/strict");

const {
  checkStorePurchase,
  parseReceiptValidationConfig,
  DEFAULT_RECEIPT_VALIDATION,
} = require("../lib/storeValidation.js");
const { verifyAppleSignedPayload } = require("../lib/storeApple.js");
const {
  PlayApiError,
  classifyPlayHttpStatus,
  parsePlaySubscriptionV2,
  parsePlayProductPurchase,
  periodFromBasePlan,
} = require("../lib/storeGoogle.js");
const { TEST_ROOT_DER, signJws, appleTransaction } = require("./helpers/storekit.js");

const DIA = 24 * 60 * 60 * 1000;
const LOG = { mode: "log", allowSandbox: true };
const ENFORCE = { mode: "enforce", allowSandbox: true };

/// Dependencias de test: la verificacion de Apple es la REAL (con la raiz de
/// test); Google se simula.
function deps(extra = {}) {
  return Object.assign(
    {
      verifyAppleJws: (jws) =>
        verifyAppleSignedPayload(jws, { trustedRootsDer: [TEST_ROOT_DER] }),
      fetchPlaySubscription: async () => {
        throw new PlayApiError("unavailable", 403, "sin acceso");
      },
      fetchPlayProduct: async () => {
        throw new PlayApiError("unavailable", 403, "sin acceso");
      },
      nowMs: () => Date.now(),
    },
    extra
  );
}

function check(input, extraDeps) {
  return checkStorePurchase(
    Object.assign(
      {
        platform: "app_store",
        kind: "subscription",
        productId: "attra_pro_yearly",
        verificationData: "x",
        config: LOG,
      },
      input
    ),
    deps(extraDeps)
  );
}

test("config: por defecto 'log' con sandbox; solo 'enforce' exacto endurece", () => {
  assert.deepEqual(parseReceiptValidationConfig(undefined), DEFAULT_RECEIPT_VALIDATION);
  assert.deepEqual(parseReceiptValidationConfig({}), { mode: "log", allowSandbox: true });
  assert.equal(parseReceiptValidationConfig({ receiptValidation: "enforce" }).mode, "enforce");
  assert.equal(parseReceiptValidationConfig({ receipt_validation: " ENFORCE " }).mode, "enforce");
  assert.equal(parseReceiptValidationConfig({ receiptValidation: "enforced" }).mode, "log");
  assert.equal(
    parseReceiptValidationConfig({ receiptValidationAllowSandbox: false }).allowSandbox,
    false
  );
});

// C01 (a): el ataque del informe, en iOS. Da igual el modo: la firma del JWS
// no necesita credenciales y se exige SIEMPRE.
test("iOS: un recibo inventado se rechaza en modo log (sin credenciales)", async () => {
  const r = await check({ verificationData: "x" });
  assert.equal(r.status, "rejected");
  assert.equal(r.permanent, true);
});

test("iOS: un JWS que no firma Apple se rechaza (temporal: por si fuese nuestro)", async () => {
  const r = await check({ verificationData: signJws(appleTransaction(), { chain: "rogue" }) });
  assert.equal(r.status, "rejected");
  assert.equal(r.reason, "receipt_unverified");
  assert.equal(r.permanent, false);
});

test("iOS: producto, caducidad e id salen del JWS, no del cliente", async () => {
  const expires = Date.now() + 20 * DIA;
  const r = await check({
    productId: "attra_pro_yearly", // lo que dice el cliente
    verificationData: signJws(
      appleTransaction({
        productId: "attra_plus_monthly",
        transactionId: "tx-real",
        originalTransactionId: "orig-1",
        expiresDate: expires,
      })
    ),
  });
  assert.equal(r.status, "verified");
  assert.equal(r.purchase.productId, "attra_plus_monthly");
  assert.equal(r.purchase.transactionId, "tx-real");
  assert.equal(r.purchase.originalTransactionId, "orig-1");
  assert.equal(r.purchase.expiresAtMs, expires);
  assert.equal(r.purchase.entitled, true);
});

test("iOS: el SANDBOX de App Review se acepta; se puede cortar por flag", async () => {
  const jws = signJws(appleTransaction({ environment: "Sandbox" }));
  const ok = await check({ verificationData: jws });
  assert.equal(ok.status, "verified");
  assert.equal(ok.purchase.sandbox, true);
  const prod = await check({
    verificationData: signJws(appleTransaction({ environment: "Production" })),
  });
  assert.equal(prod.status, "verified");
  assert.equal(prod.purchase.sandbox, false);
  const off = await check({
    verificationData: jws,
    config: { mode: "log", allowSandbox: false },
  });
  assert.equal(off.status, "rejected");
  assert.equal(off.permanent, true);
  const xcode = await check({
    verificationData: signJws(appleTransaction({ environment: "Xcode" })),
  });
  assert.equal(xcode.status, "rejected");
});

test("iOS: un JWS autentico de OTRA app no concede nada", async () => {
  const r = await check({
    verificationData: signJws(appleTransaction({ bundleId: "com.otra.app" })),
  });
  assert.equal(r.status, "rejected");
  assert.equal(r.reason, "wrong_app");
  assert.equal(r.permanent, true);
});

test("iOS: suscripcion caducada o reembolsada se verifica pero no da acceso", async () => {
  const caducada = await check({
    verificationData: signJws(appleTransaction({ expiresDate: Date.now() - DIA })),
  });
  assert.equal(caducada.status, "verified");
  assert.equal(caducada.purchase.entitled, false);
  const reembolsada = await check({
    verificationData: signJws(appleTransaction({ revocationDate: Date.now() - 1000 })),
  });
  assert.equal(reembolsada.purchase.revoked, true);
  assert.equal(reembolsada.purchase.entitled, false);
});

test("Android sin acceso a la API: 'log' registra y deja pasar, 'enforce' rechaza", async () => {
  const input = { platform: "play_store", productId: "attra_plus", verificationData: "tok" };
  const log = await check({ ...input, config: LOG });
  assert.equal(log.status, "unverified");
  assert.equal(log.reason, "store_unavailable");
  const enforce = await check({ ...input, config: ENFORCE });
  assert.equal(enforce.status, "rejected");
  // Temporal: con 'enforce' mal configurado la compra queda sin cerrar y Google
  // la reembolsa sola a los 3 dias, en vez de cerrarse sin entregar.
  assert.equal(enforce.permanent, false);
});

// Antes 'log' concedia igual aunque Google contestase que el token no existe:
// el ataque de C01 con `platform: 'play_store'` seguia abierto a cualquier
// cuenta con el acceso a la API ya configurado.
test("Android con token inventado (404 de Google): se rechaza en 'log' y en 'enforce'", async () => {
  const noExiste = async () => {
    throw new PlayApiError(classifyPlayHttpStatus(404), 404, "no existe");
  };
  for (const config of [LOG, ENFORCE]) {
    for (const kind of ["subscription", "consumable"]) {
      const r = await check(
        {
          platform: "play_store",
          kind,
          productId: kind === "subscription" ? "attra_plus" : "attra_pack_10",
          verificationData: "fake",
          config,
        },
        { fetchPlaySubscription: noExiste, fetchPlayProduct: noExiste }
      );
      assert.equal(r.status, "rejected", `${config.mode}/${kind}`);
      assert.equal(r.reason, "receipt_invalid");
      assert.equal(r.permanent, false);
    }
  }
});

// Play ya consumio el pack antes de llegar al backend (autoConsume) y no lo
// devuelve al restaurar: rechazarlo por una caida de Google lo perderia.
test("Android consumible con Google caido: tampoco 'enforce' lo rechaza", async () => {
  const r = await check({
    platform: "play_store",
    kind: "consumable",
    productId: "attra_pack_10",
    verificationData: "tok",
    config: ENFORCE,
  });
  assert.equal(r.status, "unverified");
  assert.equal(r.reason, "store_unavailable");
});

test("Android verificado: caducidad y producto de Google (anual real, no el mes)", async () => {
  const expiry = new Date(Date.now() + 360 * DIA).toISOString();
  const r = await check(
    { platform: "play_store", productId: "attra_plus", verificationData: "tok-1", config: LOG },
    {
      fetchPlaySubscription: async (token) => {
        assert.equal(token, "tok-1");
        return {
          subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
          lineItems: [
            {
              productId: "attra_plus",
              expiryTime: expiry,
              latestSuccessfulOrderId: "GPA.1234-5678..0",
              offerDetails: { basePlanId: "plus-yearly" },
            },
          ],
        };
      },
    }
  );
  assert.equal(r.status, "verified");
  assert.equal(r.purchase.expiresAtMs, Date.parse(expiry));
  assert.equal(r.purchase.transactionId, "GPA.1234-5678..0");
  assert.equal(r.purchase.originalTransactionId, "tok-1");
  assert.equal(r.purchase.period, "yearly");
});

test("Android consumible: cancelado es definitivo, pendiente es temporal", async () => {
  const base = {
    platform: "play_store",
    kind: "consumable",
    productId: "attra_pack_10",
    verificationData: "tok",
  };
  const cancelado = await check(base, {
    fetchPlayProduct: async () => ({ purchaseState: 1, orderId: "GPA.1" }),
  });
  assert.equal(cancelado.status, "rejected");
  assert.equal(cancelado.permanent, true);
  const pendiente = await check(base, {
    fetchPlayProduct: async () => ({ purchaseState: 2, orderId: "GPA.1" }),
  });
  assert.equal(pendiente.permanent, false);
  const ok = await check(base, {
    fetchPlayProduct: async () => ({ purchaseState: 0, orderId: "GPA.9", quantity: 1 }),
  });
  assert.equal(ok.status, "verified");
  assert.equal(ok.purchase.transactionId, "GPA.9");
});

test("Play: estados que dan acceso y el lineItem que caduca mas tarde", () => {
  const now = Date.UTC(2026, 9, 1);
  const raw = (state) => ({
    subscriptionState: state,
    linkedPurchaseToken: "viejo",
    testPurchase: {},
    lineItems: [
      { productId: "attra_plus", expiryTime: new Date(now + DIA).toISOString() },
      { productId: "attra_pro", expiryTime: new Date(now + 20 * DIA).toISOString() },
    ],
  });
  const activa = parsePlaySubscriptionV2(raw("SUBSCRIPTION_STATE_ACTIVE"), "t", now);
  assert.equal(activa.productId, "attra_pro");
  assert.equal(activa.entitled, true);
  assert.equal(activa.linkedPurchaseToken, "viejo");
  assert.equal(activa.test, true);
  assert.equal(activa.orderId, `t|${now + 20 * DIA}`);
  assert.equal(parsePlaySubscriptionV2(raw("SUBSCRIPTION_STATE_CANCELED"), "t", now).entitled, true);
  assert.equal(parsePlaySubscriptionV2(raw("SUBSCRIPTION_STATE_ON_HOLD"), "t", now).entitled, false);
  assert.equal(parsePlaySubscriptionV2(raw("SUBSCRIPTION_STATE_EXPIRED"), "t", now).entitled, false);
});

test("Play: token de otro producto se rechaza; codigos HTTP bien clasificados", () => {
  assert.throws(
    () => parsePlayProductPurchase({ productId: "attra_pack_3", purchaseState: 0 }, "attra_pack_50", "t"),
    PlayApiError
  );
  assert.equal(classifyPlayHttpStatus(404), "invalid");
  assert.equal(classifyPlayHttpStatus(410), "invalid");
  assert.equal(classifyPlayHttpStatus(401), "unavailable");
  assert.equal(classifyPlayHttpStatus(403), "unavailable");
  assert.equal(classifyPlayHttpStatus(503), "unavailable");
  assert.equal(periodFromBasePlan("plus-monthly"), "monthly");
  assert.equal(periodFromBasePlan("anual"), "yearly");
  assert.equal(periodFromBasePlan(null), null);
});
