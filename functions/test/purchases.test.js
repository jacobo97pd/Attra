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
        // Produccion: la fecha exacta de Apple (sandbox recibe un suelo de
        // calendario, ver el test de App Review).
        environment: "Production",
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
      "users/u1": { name: "dueña" }, // la cuenta que la compro sigue viva
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

// Quien borra su cuenta y se crea otra seguia pagando a Apple/Google, pero el
// enlace suscripcion -> cuenta era para siempre: "asociada a otra cuenta" en
// cada renovacion y sin forma de recuperar el plan.
test("cuenta borrada: su suscripcion (y la compra ya canjeada) pasa a la cuenta nueva", async () => {
  const key = storeSubscriptionKey("app_store", "orig-1");
  const expires = Date.now() + 20 * DIA;
  const ledgerId = sha256("app_store|tx-1");
  for (const vieja of [
    {}, // `users/u-vieja` ya no existe (borrado desde Ajustes)
    { "users/u-vieja": { isDeleted: true } },
  ]) {
    const mem = installMemoryDb({
      docs: {
        ...vieja,
        "users/u-nueva": { name: "yo otra vez" },
        [`storeSubscriptions/${key}`]: { uid: "u-vieja" },
        [`subscriptionLedger/${ledgerId}`]: { uid: "u-vieja", productId: "attra_pro_monthly" },
      },
    });
    const r = await call(verifyPurchase, "u-nueva", {
      platform: "app_store",
      productId: "attra_pro_monthly",
      verificationData: signJws(
        appleTransaction({
          environment: "Production",
          transactionId: "tx-1",
          originalTransactionId: "orig-1",
          expiresDate: expires,
        })
      ),
    });
    assert.equal(r.ok, true, JSON.stringify(r));
    assert.equal(r.duplicate, false);
    const ent = mem.get("userEntitlements/u-nueva");
    assert.equal(ent.tier, "pro");
    assert.equal(ent.expiresAt.toMillis(), expires, "la fecha de Apple, sin periodo extra");
    const sub = mem.get(`storeSubscriptions/${key}`);
    assert.equal(sub.uid, "u-nueva", "las notificaciones ya van a la cuenta nueva");
    assert.equal(sub.relinkedFrom, "u-vieja");
    const apunte = mem.get(`subscriptionLedger/${ledgerId}`);
    assert.equal(apunte.uid, "u-nueva");
    assert.equal(apunte.reclaimedFrom, "u-vieja");
  }
});

test("compra de una cuenta borrada sin verificar (Play en 'log'): pasa, pero no alarga", async () => {
  const caduca = Date.now() + 10 * DIA;
  const mem = installMemoryDb({
    docs: {
      "users/u-nueva": {},
      "userEntitlements/u-nueva": {
        tier: "plus",
        productId: "attra_plus",
        period: "monthly",
        expiresAt: new Date(caduca).toISOString(),
      },
      [`subscriptionLedger/${sha256("play_store|GPA.1..0")}`]: { uid: "u-vieja" },
    },
  });
  const r = await call(verifyPurchase, "u-nueva", {
    platform: "play_store",
    productId: "attra_plus",
    verificationData: "token",
    purchaseId: "GPA.1..0",
  });
  assert.equal(r.ok, true);
  assert.equal(r.reason, "same_subscription_redelivered", "ya se concedio una vez");
  assert.equal(Date.parse(r.expiresAt), caduca);
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
  // Clave: el TOKEN de Play (uno por compra), no el purchaseId del cliente.
  assert.equal(mem.get(`consumableLedger/${sha256(sha256("token"))}`).verified, false);
});

// Pago PENDIENTE (efectivo, metodos lentos): Play no tiene orderId y la app
// manda purchaseId ''. Al pagarse llega con 'GPA...' y el MISMO token. Con el
// purchaseId de clave eran dos compras y el pack se abonaba dos veces.
test("Android pendiente y luego pagado (mismo token): el pack se abona UNA vez", async () => {
  const mem = installMemoryDb({ docs: { "users/u1": { attrasBalance: 0 } } });
  const pedir = (purchaseId) =>
    call(grantConsumable, "u1", {
      productId: "attra_pack_10",
      purchaseId,
      platform: "play_store",
      verificationData: "token-T",
    });
  const pendiente = await pedir("");
  assert.equal(pendiente.ok, true);
  const pagada = await pedir("GPA.1111-2222-3333-44444");
  assert.equal(pagada.duplicate, true);
  assert.equal(mem.get("users/u1").attrasBalance, 10, "antes: 20 por un solo pack");
});

// C01 en Play: la plataforma la elige quien llama, asi que esto lo podia hacer
// cualquier cuenta (tambien desde iOS). En 'log' se concedia aunque Google ya
// hubiese contestado que el token no existe.
test("C01: token inventado con Google contestando 404 no concede nada, tampoco en 'log'", async () => {
  const mem = installMemoryDb({ docs: { "users/u1": { attrasBalance: 0 } } });
  const noExiste = async () => {
    throw new PlayApiError("invalid", 404, "no existe");
  };
  mock.method(defaultStoreDeps, "fetchPlaySubscription", noExiste);
  mock.method(defaultStoreDeps, "fetchPlayProduct", noExiste);

  const plan = await call(verifyPurchase, "u1", {
    platform: "play_store",
    productId: "attra_pro_yearly",
    verificationData: "x",
    purchaseId: "fake1",
  });
  assert.equal(plan.ok, false);
  assert.equal(plan.reason, "receipt_invalid");
  assert.equal(mem.get("userEntitlements/u1"), undefined);

  for (const purchaseId of ["r1", "r2", "r3"]) {
    const pack = await call(grantConsumable, "u1", {
      productId: "attra_pack_50",
      purchaseId,
      platform: "play_store",
      verificationData: `token-${purchaseId}`,
    });
    assert.equal(pack.ok, false);
  }
  assert.equal(mem.get("users/u1").attrasBalance, 0);
});

// Mientras Google no pueda contestar (sin acceso a la API) el token no se puede
// comprobar, pero encadenar ids inventados ya no suma un periodo por llamada.
test("Play sin verificar: ids inventados en cadena no apilan periodos", async () => {
  const mem = installMemoryDb();
  const pedir = (purchaseId) =>
    call(verifyPurchase, "u1", {
      platform: "play_store",
      productId: "attra_pro_yearly",
      verificationData: "x",
      purchaseId,
    });
  const primera = await pedir("fake1");
  assert.equal(primera.ok, true);
  const unAno = Date.parse(primera.expiresAt);
  await pedir("fake2");
  await pedir("fake3");
  const final = mem.get("userEntitlements/u1").expiresAt.toMillis();
  assert.ok(
    final <= unAno + 8 * DIA,
    `antes: un año mas por llamada (${new Date(final).toISOString()})`
  );
});

// 'enforce' no puede perder packs pagados: Play ya los consumio antes de
// llegar al backend, asi que una caida de Google no puede rechazarlos.
test("'enforce' con Google caido: la suscripcion espera, el consumible se abona", async () => {
  const mem = installMemoryDb({
    docs: { "users/u1": { attrasBalance: 0 } },
    flags: { receiptValidation: "enforce" },
  });
  const plan = await call(verifyPurchase, "u1", {
    platform: "play_store",
    productId: "attra_plus",
    verificationData: "token-plan",
    purchaseId: "GPA.5",
  });
  assert.equal(plan.ok, false);
  assert.equal(plan.permanent, false, "se reintenta: no se ha consumido nada");
  const pack = await call(grantConsumable, "u1", {
    productId: "attra_pack_10",
    purchaseId: "GPA.6",
    platform: "play_store",
    verificationData: "token-pack",
  });
  assert.equal(pack.ok, true);
  assert.equal(mem.get("users/u1").attrasBalance, 10);
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

// Sandbox acelera el reloj: el mensual caduca a los ~5 minutos. El revisor que
// paga no puede ver Pro bloqueado al volver de otra pantalla.
test("App Review: un mensual de sandbox que Apple da por 5 minutos dura un mes", async () => {
  const mem = installMemoryDb();
  const cincoMin = Date.now() + 5 * 60 * 1000;
  const r = await call(verifyPurchase, "reviewer", {
    platform: "app_store",
    productId: "attra_pro_monthly",
    verificationData: signJws(
      appleTransaction({
        environment: "Sandbox",
        transactionId: "tx-review-5m",
        originalTransactionId: "orig-review-5m",
        expiresDate: cincoMin,
      })
    ),
  });
  assert.equal(r.ok, true);
  const ent = mem.get("userEntitlements/reviewer");
  assert.equal(ent.tier, "pro");
  assert.ok(ent.expiresAt.toMillis() > Date.now() + 27 * DIA, "un mes, no 5 minutos");
  // La siguiente renovacion acelerada (otra transaccion, +5 min) no mueve el mes.
  const mes = ent.expiresAt.toMillis();
  const renov = await call(verifyPurchase, "reviewer", {
    platform: "app_store",
    productId: "attra_pro_monthly",
    verificationData: signJws(
      appleTransaction({
        environment: "Sandbox",
        transactionId: "tx-review-5m-2",
        originalTransactionId: "orig-review-5m",
        expiresDate: cincoMin + 5 * 60 * 1000,
      })
    ),
  });
  assert.equal(renov.ok, true);
  assert.equal(renov.reason, "same_subscription_redelivered");
  assert.equal(mem.get("userEntitlements/reviewer").expiresAt.toMillis(), mes);
});

test("produccion: la caducidad sigue siendo exactamente la de Apple", async () => {
  const mem = installMemoryDb();
  const cincoMin = Date.now() + 5 * 60 * 1000;
  const r = await call(verifyPurchase, "u1", {
    platform: "app_store",
    productId: "attra_pro_monthly",
    verificationData: signJws(
      appleTransaction({
        environment: "Production",
        transactionId: "tx-prod-5m",
        originalTransactionId: "orig-prod-5m",
        expiresDate: cincoMin,
      })
    ),
  });
  assert.equal(r.ok, true);
  assert.equal(mem.get("userEntitlements/u1").expiresAt.toMillis(), cincoMin);
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
    verificationData: "jws",
  });
  assert.equal(out.ok, false);
  assert.equal(out.permanent, true);
});
