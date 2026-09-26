const { test, afterEach, beforeEach, mock } = require("node:test");
const assert = require("node:assert/strict");
const { createHash } = require("node:crypto");

const { verifyPurchase } = require("../lib/subscriptions.js");
const { grantConsumable, resolveConsumableGrant } = require("../lib/consumables.js");
const {
  defaultStoreDeps,
  clearReceiptValidationConfigCache,
  storeSubscriptionKey,
} = require("../lib/storeValidation.js");
const { verifyAppleSignedPayload } = require("../lib/storeApple.js");
const { PlayApiError } = require("../lib/storeGoogle.js");
const { installMemoryDb } = require("./helpers/memoryDb.js");
const { TEST_ROOT_DER, signJws, appleTransaction } = require("./helpers/storekit.js");

const DIA = 24 * 60 * 60 * 1000;
const sha256 = (s) => createHash("sha256").update(s, "utf8").digest("hex");

beforeEach(() => {
  clearReceiptValidationConfigCache();
  // La verificacion de Apple es la REAL; solo cambia el ancla de confianza por
  // la raiz de test (ningun test puede firmar con la clave de Apple).
  mock.method(defaultStoreDeps, "verifyAppleJws", (jws) =>
    verifyAppleSignedPayload(jws, { trustedRootsDer: [TEST_ROOT_DER] })
  );
  // Nunca se sale a Google desde un test: sin mock explicito, "sin acceso".
  mock.method(defaultStoreDeps, "fetchPlaySubscription", async () => {
    throw new PlayApiError("unavailable", 403, "sin acceso en test");
  });
  mock.method(defaultStoreDeps, "fetchPlayProduct", async () => {
    throw new PlayApiError("unavailable", 403, "sin acceso en test");
  });
});
afterEach(() => mock.restoreAll());

const call = (fn, uid, data) => fn.run({ auth: { uid }, data });

// ---------------------------------------------------------------------------
// C01 (a): verifyPurchase ya no concede un plan por un recibo inventado.
// ---------------------------------------------------------------------------

test("C01: iOS con recibo inventado ('x') no concede Pro, ni en modo log", async () => {
  const mem = installMemoryDb();
  const r = await call(verifyPurchase, "u1", {
    platform: "app_store",
    productId: "attra_pro_yearly",
    verificationData: "x",
    purchaseId: "fake1",
  });
  assert.equal(r.ok, false);
  assert.equal(r.permanent, true);
  assert.equal(mem.get("userEntitlements/u1"), undefined);
  assert.equal(mem.transactions(), 0, "no se toca Firestore sin recibo valido");
});

test("C01: Android con token inventado en 'enforce' no concede nada", async () => {
  const mem = installMemoryDb({ flags: { receiptValidation: "enforce" } });
  mock.method(defaultStoreDeps, "fetchPlaySubscription", async () => {
    throw new PlayApiError("invalid", 404, "no existe");
  });
  const r = await call(verifyPurchase, "u1", {
    platform: "play_store",
    productId: "attra_pro_yearly",
    verificationData: "x",
    purchaseId: "fake1",
  });
  assert.equal(r.ok, false);
  assert.equal(mem.get("userEntitlements/u1"), undefined);
});

test("iOS verificado: se concede lo que dice Apple, no lo que pide el cliente", async () => {
  const mem = installMemoryDb();
  const expires = Date.now() + 20 * DIA;
  const r = await call(verifyPurchase, "u1", {
    platform: "app_store",
    productId: "attra_pro_yearly", // el cliente pide un año de Pro...
    purchaseId: "fake1",
    verificationData: signJws(
      appleTransaction({
        productId: "attra_plus_monthly", // ...pero pago un mes de Plus
        transactionId: "tx-1",
        originalTransactionId: "orig-1",
        expiresDate: expires,
      })
    ),
  });
  assert.equal(r.ok, true);
  const ent = mem.get("userEntitlements/u1");
  assert.equal(ent.tier, "plus");
  assert.equal(ent.productId, "attra_plus_monthly");
  assert.equal(ent.expiresAt.toMillis(), expires);
  assert.equal(ent.storeVerified, true);
  assert.equal(ent.storeSubscriptionKey, storeSubscriptionKey("app_store", "orig-1"));
  // El ledger va por el id de transaccion de APPLE, no por el purchaseId.
  assert.ok(mem.get(`subscriptionLedger/${sha256("app_store|tx-1")}`));
  assert.equal(mem.get(`subscriptionLedger/${sha256("app_store|fake1")}`), undefined);
  const sub = mem.get(`storeSubscriptions/${storeSubscriptionKey("app_store", "orig-1")}`);
  assert.equal(sub.uid, "u1");
});

// C12 (iOS): la renovacion (transaccion nueva, mismo producto) llegaba con el
// plan aun vigente y se trataba como reentrega: el plan caducaba igual.
test("C12: renovacion de iOS con el plan vigente extiende hasta la fecha de Apple", async () => {
  const actual = Date.now() + 2 * DIA;
  const renovada = Date.now() + 32 * DIA;
  const mem = installMemoryDb({
    docs: {
      "userEntitlements/u1": {
        tier: "plus",
        productId: "attra_plus_monthly",
        expiresAt: new Date(actual).toISOString(),
        storeSubscriptionKey: storeSubscriptionKey("app_store", "orig-1"),
      },
      [`storeSubscriptions/${storeSubscriptionKey("app_store", "orig-1")}`]: { uid: "u1" },
    },
  });
  const r = await call(verifyPurchase, "u1", {
    platform: "app_store",
    productId: "attra_plus_monthly",
    purchaseId: "tx-2",
    verificationData: signJws(
      appleTransaction({
        productId: "attra_plus_monthly",
        transactionId: "tx-2",
        originalTransactionId: "orig-1",
        expiresDate: renovada,
      })
    ),
  });
  assert.equal(r.ok, true);
  assert.equal(r.reason, "renewal");
  assert.equal(mem.get("userEntitlements/u1").expiresAt.toMillis(), renovada);
});

test("iOS: restaurar una suscripcion ya caducada no abre otro periodo", async () => {
  const mem = installMemoryDb();
  const r = await call(verifyPurchase, "u1", {
    platform: "app_store",
    productId: "attra_pro_monthly",
    verificationData: signJws(appleTransaction({ expiresDate: Date.now() - 5 * DIA })),
  });
  assert.equal(r.ok, true);
  assert.equal(r.reason, "store_not_entitled");
  assert.equal(mem.get("userEntitlements/u1"), undefined);
});

test("las renovaciones de una suscripcion ajena no se canjean en otra cuenta", async () => {
  const mem = installMemoryDb({
    docs: {
      [`storeSubscriptions/${storeSubscriptionKey("app_store", "orig-1")}`]: { uid: "u1" },
    },
  });
  const r = await call(verifyPurchase, "u2", {
    platform: "app_store",
    productId: "attra_pro_monthly",
    verificationData: signJws(
      appleTransaction({ transactionId: "tx-nueva", originalTransactionId: "orig-1" })
    ),
  });
  assert.equal(r.ok, false);
  assert.equal(r.reason, "claimed_by_other_account");
  assert.equal(mem.get("userEntitlements/u2"), undefined);
});

// ---------------------------------------------------------------------------
// C01 (b): grantConsumable ya no abona sin recibo ni repite con otro purchaseId.
// ---------------------------------------------------------------------------

test("C01: grantConsumable sin recibo se rechaza (antes: 'purchase_placeholder')", async () => {
  const mem = installMemoryDb({ docs: { "users/u1": { attrasBalance: 0 } } });
  await assert.rejects(
    call(grantConsumable, "u1", { productId: "attra_pack_50", purchaseId: "r1" }),
    (error) => error.code === "invalid-argument"
  );
  await assert.rejects(
    call(grantConsumable, "u1", {
      productId: "attra_pack_50",
      purchaseId: "r1",
      verificationData: "x",
    }),
    (error) => error.code === "invalid-argument",
    "sin plataforma tampoco"
  );
  assert.equal(mem.get("users/u1").attrasBalance, 0);
});

test("C01: grantConsumable con recibo inventado de iOS no abona", async () => {
  const mem = installMemoryDb({ docs: { "users/u1": { attrasBalance: 0 } } });
  const r = await call(grantConsumable, "u1", {
    productId: "attra_pack_50",
    purchaseId: "r1",
    platform: "app_store",
    verificationData: "x",
  });
  assert.equal(r.ok, false);
  assert.equal(mem.get("users/u1").attrasBalance, 0);
});

test("C01: el mismo recibo con purchaseId r1, r2, r3 abona UNA vez y el pack real", async () => {
  const mem = installMemoryDb({ docs: { "users/u1": { attrasBalance: 0 } } });
  const jws = signJws(
    appleTransaction({
      productId: "attra_pack_3",
      type: "Consumable",
      transactionId: "tx-pack",
      expiresDate: undefined,
    })
  );
  const pedir = (purchaseId) =>
    call(grantConsumable, "u1", {
      productId: "attra_pack_50", // el cliente pide el grande
      purchaseId,
      platform: "app_store",
      verificationData: jws,
    });
  const primera = await pedir("r1");
  assert.equal(primera.ok, true);
  assert.equal(primera.amount, 3, "abona el pack que se pago, no el pedido");
  const segunda = await pedir("r2");
  const tercera = await pedir("r3");
  assert.equal(segunda.duplicate, true);
  assert.equal(tercera.duplicate, true);
  assert.equal(mem.get("users/u1").attrasBalance, 3);
  assert.ok(mem.get(`consumableLedger/${sha256("tx-pack")}`));
});

test("Android en modo log sin acceso a Google: abona como antes y queda marcado", async () => {
  const mem = installMemoryDb({ docs: { "users/u1": { attrasBalance: 0 } } });
  const r = await call(grantConsumable, "u1", {
    productId: "attra_pack_10",
    purchaseId: "GPA.1",
    platform: "play_store",
    verificationData: "token",
  });
  assert.equal(r.ok, true);
  assert.equal(mem.get(`consumableLedger/${sha256("GPA.1")}`).verified, false);
});

test("Android verificado por Google: la clave es el orderId de Google, no el purchaseId", async () => {
  const mem = installMemoryDb({ docs: { "users/u1": { attrasBalance: 0 } } });
  mock.method(defaultStoreDeps, "fetchPlayProduct", async (productId, token) => {
    assert.equal(productId, "attra_pack_10");
    assert.equal(token, "token-real");
    return { purchaseState: 0, orderId: "GPA.3333-4444-5555-66666", quantity: 1 };
  });
  const pedir = (purchaseId) =>
    call(grantConsumable, "u1", {
      productId: "attra_pack_10",
      purchaseId,
      platform: "play_store",
      verificationData: "token-real",
    });
  const primera = await pedir("r1");
  assert.equal(primera.ok, true);
  assert.equal(primera.amount, 10);
  const repetida = await pedir("r2");
  assert.equal(repetida.duplicate, true, "cambiar el purchaseId no vuelve a abonar");
  assert.equal(mem.get("users/u1").attrasBalance, 10);
  const apunte = mem.get(`consumableLedger/${sha256("GPA.3333-4444-5555-66666")}`);
  assert.equal(apunte.verified, true);
});

// App Review compra con cuentas SANDBOX sobre la build de produccion: si eso
// dejase de conceder el plan, la app se rechaza en revision.
test("App Review (sandbox de Apple) recibe su plan y queda marcado como sandbox", async () => {
  const mem = installMemoryDb();
  const r = await call(verifyPurchase, "reviewer", {
    platform: "app_store",
    productId: "attra_pro_monthly",
    verificationData: signJws(
      appleTransaction({
        environment: "Sandbox",
        transactionId: "tx-review",
        originalTransactionId: "orig-review",
      })
    ),
  });
  assert.equal(r.ok, true);
  assert.equal(mem.get("userEntitlements/reviewer").tier, "pro");
  assert.equal(mem.get(`subscriptionLedger/${sha256("app_store|tx-review")}`).sandbox, true);
});

test("resolveConsumableGrant: un recibo de suscripcion no abona un pack", () => {
  const out = resolveConsumableGrant({
    check: {
      status: "verified",
      purchase: {
        platform: "app_store",
        productId: "attra_pro_monthly",
        transactionId: "t",
        originalTransactionId: "t",
        linkedOriginalTransactionId: null,
        expiresAtMs: null,
        entitled: true,
        revoked: false,
        sandbox: true,
        quantity: 1,
        period: null,
      },
    },
    requested: { productId: "attra_pack_50", kind: "attra", amount: 50 },
    rawPurchaseId: "x",
    verificationData: "jws",
  });
  assert.equal(out.ok, false);
  assert.equal(out.permanent, true);
});
