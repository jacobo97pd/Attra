const { test, afterEach, mock } = require("node:test");
const assert = require("node:assert/strict");

const {
  handleAppStoreNotification,
  handlePlayRtdn,
} = require("../lib/storeNotifications.js");
const { applyStoreSubscriptionUpdate } = require("../lib/subscriptions.js");
const { storeSubscriptionKey } = require("../lib/storeValidation.js");
const { verifyAppleSignedPayload } = require("../lib/storeApple.js");
const { PlayApiError } = require("../lib/storeGoogle.js");
const { installMemoryDb } = require("./helpers/memoryDb.js");
const { TEST_ROOT_DER, signJws, appleTransaction } = require("./helpers/storekit.js");

const DIA = 24 * 60 * 60 * 1000;

afterEach(() => mock.restoreAll());

/// Dependencias: la firma de Apple es la verificacion REAL con la raiz de
/// test; `apply` se captura para ver QUE se aplicaria.
function deps({ mode = "log", play } = {}) {
  const applied = [];
  return {
    applied,
    deps: {
      verifyAppleJws: (jws) =>
        verifyAppleSignedPayload(jws, { trustedRootsDer: [TEST_ROOT_DER] }),
      fetchPlaySubscription:
        play ??
        (async () => {
          throw new PlayApiError("unavailable", 403, "sin acceso");
        }),
      apply: async (input) => {
        applied.push(input);
        return { applied: true, reason: "ok" };
      },
      config: async () => ({ mode, allowSandbox: true }),
      nowMs: () => Date.now(),
    },
  };
}

function appleNotification(type, transaction, extra = {}) {
  return signJws({
    notificationType: type,
    notificationUUID: "n-1",
    version: "2.0",
    signedDate: Date.now(),
    data: Object.assign(
      {
        bundleId: "com.jpedrero.attra",
        environment: "Sandbox",
        signedTransactionInfo: signJws(transaction),
      },
      extra
    ),
  });
}

test("App Store: una notificacion que no firma Apple se rechaza con 401", async () => {
  const { deps: d, applied } = deps();
  const r = await handleAppStoreNotification(
    signJws({ notificationType: "DID_RENEW" }, { chain: "rogue" }),
    d
  );
  assert.equal(r.status, 401);
  assert.equal(applied.length, 0);
});

test("App Store DID_RENEW: aplica la caducidad NUEVA de Apple", async () => {
  const { deps: d, applied } = deps();
  const expires = Date.now() + 30 * DIA;
  const r = await handleAppStoreNotification(
    appleNotification(
      "DID_RENEW",
      appleTransaction({ transactionId: "tx-2", originalTransactionId: "orig-1", expiresDate: expires })
    ),
    d
  );
  assert.equal(r.status, 200);
  assert.equal(applied.length, 1);
  assert.equal(applied[0].purchase.expiresAtMs, expires);
  assert.equal(applied[0].purchase.originalTransactionId, "orig-1");
  assert.equal(applied[0].purchase.entitled, true);
});

test("App Store REFUND: marca revocada y permite quitar el plan", async () => {
  const { deps: d, applied } = deps();
  await handleAppStoreNotification(
    appleNotification("REFUND", appleTransaction({ revocationDate: Date.now() })),
    d
  );
  assert.equal(applied[0].purchase.revoked, true);
  assert.equal(applied[0].purchase.entitled, false);
  assert.equal(applied[0].allowRevocation, true);
});

test("App Store: en periodo de gracia se respeta la fecha de gracia", async () => {
  const { deps: d, applied } = deps();
  const grace = Date.now() + 10 * DIA;
  await handleAppStoreNotification(
    appleNotification(
      "DID_FAIL_TO_RENEW",
      appleTransaction({ expiresDate: Date.now() - DIA }),
      { signedRenewalInfo: signJws({ gracePeriodExpiresDate: grace, signedDate: Date.now() }) }
    ),
    d
  );
  assert.equal(applied[0].purchase.expiresAtMs, grace);
  assert.equal(applied[0].purchase.entitled, true);
});

test("App Store: otra app o notificacion de prueba no tocan nada", async () => {
  const { deps: d, applied } = deps();
  const otra = await handleAppStoreNotification(
    appleNotification("DID_RENEW", appleTransaction(), { bundleId: "com.otra.app" }),
    d
  );
  assert.equal(otra.result, "other_app");
  const prueba = await handleAppStoreNotification(
    signJws({ notificationType: "TEST", signedDate: Date.now(), data: {} }),
    d
  );
  assert.equal(prueba.result, "test");
  assert.equal(applied.length, 0);
});

const playSub = (state, expiryMs) => async () => ({
  subscriptionState: state,
  lineItems: [
    {
      productId: "attra_plus",
      expiryTime: new Date(expiryMs).toISOString(),
      latestSuccessfulOrderId: "GPA.1..3",
      offerDetails: { basePlanId: "monthly" },
    },
  ],
});

test("Play RTDN renovada: pregunta a Google y extiende", async () => {
  const expiry = Date.now() + 30 * DIA;
  const { deps: d, applied } = deps({ play: playSub("SUBSCRIPTION_STATE_ACTIVE", expiry) });
  await handlePlayRtdn(
    {
      packageName: "com.jpedrero.attra",
      subscriptionNotification: { notificationType: 2, purchaseToken: "tok", subscriptionId: "attra_plus" },
    },
    d
  );
  assert.equal(applied.length, 1);
  assert.equal(applied[0].purchase.expiresAtMs, expiry);
  assert.equal(applied[0].purchase.transactionId, "GPA.1..3");
  assert.equal(applied[0].purchase.originalTransactionId, "tok");
});

test("Play RTDN revocada: en 'log' solo se registra, en 'enforce' se aplica", async () => {
  const message = {
    packageName: "com.jpedrero.attra",
    subscriptionNotification: { notificationType: 12, purchaseToken: "tok" },
  };
  const play = playSub("SUBSCRIPTION_STATE_EXPIRED", Date.now());
  const log = deps({ mode: "log", play });
  await handlePlayRtdn(message, log.deps);
  assert.equal(log.applied[0].purchase.revoked, true);
  assert.equal(log.applied[0].allowRevocation, false);
  const enforce = deps({ mode: "enforce", play });
  await handlePlayRtdn(message, enforce.deps);
  assert.equal(enforce.applied[0].allowRevocation, true);
});

test("Play RTDN sin acceso a la API: no hace nada y no revienta", async () => {
  const { deps: d, applied } = deps();
  const r = await handlePlayRtdn(
    {
      packageName: "com.jpedrero.attra",
      subscriptionNotification: { notificationType: 2, purchaseToken: "tok" },
    },
    d
  );
  assert.equal(r, "store_unavailable");
  assert.equal(applied.length, 0);
  assert.equal(await handlePlayRtdn({ packageName: "com.otra" }, d), "other_app");
});

// De punta a punta contra Firestore en memoria: la notificacion encuentra la
// cuenta por la suscripcion y alarga su plan sin que la app intervenga.
test("applyStoreSubscriptionUpdate: renovacion por notificacion alarga el plan", async () => {
  const key = storeSubscriptionKey("app_store", "orig-1");
  const renovada = Date.now() + 31 * DIA;
  const mem = installMemoryDb({
    docs: {
      "users/u1": {},
      [`storeSubscriptions/${key}`]: { uid: "u1" },
      "userEntitlements/u1": {
        tier: "pro",
        productId: "attra_pro_monthly",
        expiresAt: new Date(Date.now() + DIA).toISOString(),
        storeSubscriptionKey: key,
      },
    },
  });
  const r = await applyStoreSubscriptionUpdate({
    purchase: {
      platform: "app_store",
      productId: "attra_pro_monthly",
      transactionId: "tx-2",
      originalTransactionId: "orig-1",
      linkedOriginalTransactionId: null,
      expiresAtMs: renovada,
      entitled: true,
      revoked: false,
      sandbox: true,
      quantity: 1,
      period: null,
    },
    source: "test",
    allowRevocation: true,
  });
  assert.equal(r.applied, true);
  assert.equal(r.uid, "u1");
  assert.equal(mem.get("userEntitlements/u1").expiresAt.toMillis(), renovada);
});

test("applyStoreSubscriptionUpdate: reembolso de otra suscripcion no quita el plan", async () => {
  const mem = installMemoryDb({
    docs: {
      "users/u1": {},
      [`storeSubscriptions/${storeSubscriptionKey("app_store", "vieja")}`]: { uid: "u1" },
      "userEntitlements/u1": {
        tier: "pro",
        productId: "attra_pro_monthly",
        expiresAt: new Date(Date.now() + 10 * DIA).toISOString(),
        storeSubscriptionKey: storeSubscriptionKey("app_store", "nueva"),
      },
    },
  });
  const r = await applyStoreSubscriptionUpdate({
    purchase: {
      platform: "app_store",
      productId: "attra_pro_monthly",
      transactionId: "tx-v",
      originalTransactionId: "vieja",
      linkedOriginalTransactionId: null,
      expiresAtMs: Date.now() - DIA,
      entitled: false,
      revoked: true,
      sandbox: true,
      quantity: 1,
      period: null,
    },
    source: "test",
    allowRevocation: true,
  });
  assert.equal(r.applied, false);
  assert.equal(r.reason, "revoked_other_subscription");
  assert.equal(typeof mem.get("userEntitlements/u1").expiresAt, "string", "sin tocar");
});

// La cuenta se borro (Ajustes borra `users/{uid}`) pero Apple sigue mandando
// renovaciones: no se recrean datos a nombre de quien pidio borrarlos.
test("applyStoreSubscriptionUpdate: a una cuenta borrada no se le escribe nada", async () => {
  const key = storeSubscriptionKey("app_store", "orig-1");
  const mem = installMemoryDb({
    docs: { [`storeSubscriptions/${key}`]: { uid: "u-borrada" } },
  });
  const r = await applyStoreSubscriptionUpdate({
    purchase: {
      platform: "app_store",
      productId: "attra_pro_monthly",
      transactionId: "tx-3",
      originalTransactionId: "orig-1",
      linkedOriginalTransactionId: null,
      expiresAtMs: Date.now() + 30 * DIA,
      entitled: true,
      revoked: false,
      sandbox: false,
      quantity: 1,
      period: null,
    },
    source: "test",
    allowRevocation: true,
  });
  assert.equal(r.applied, false);
  assert.equal(r.reason, "owner_deleted");
  assert.equal(mem.get("userEntitlements/u-borrada"), undefined);
  assert.deepEqual(mem.get(`storeSubscriptions/${key}`), { uid: "u-borrada" });
});
