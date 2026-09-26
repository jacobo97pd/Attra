const test = require("node:test");
const assert = require("node:assert");

const {
  resolveGrant,
  resolveStoreSync,
  periodFor,
  UNVERIFIED_RENEWAL_SLACK_MS,
} = require("../lib/subscriptions.js");

const DIA = 24 * 60 * 60 * 1000;
const AHORA = Date.UTC(2026, 8, 18, 12, 0, 0); // 18-sep-2026

/// Base: alguien sin nada. Cada test cambia solo lo que le importa.
function caso(extra) {
  return Object.assign(
    {
      tier: "pro",
      productId: "attra_pro_monthly",
      period: "monthly",
      nowMs: AHORA,
      currentTier: "free",
      currentProductId: "",
      currentExpiresAtMs: null,
      currentIsLifetime: false,
    },
    extra
  );
}

test("primera compra concede el plan y un mes", () => {
  const r = resolveGrant(caso());
  assert.strictEqual(r.tier, "pro");
  assert.strictEqual(r.reason, "upgrade");
  assert.ok(r.expiresAtMs > AHORA + 27 * DIA);
  assert.ok(r.expiresAtMs < AHORA + 32 * DIA);
});

test("anual concede doce meses, no uno", () => {
  const r = resolveGrant(caso({ productId: "attra_pro_yearly", period: "yearly" }));
  assert.ok(r.expiresAtMs > AHORA + 360 * DIA);
});

// EL FALLO QUE SE VEIA EN PRODUCCION: en iOS el recibo cambia en cada llamada,
// asi que cada reintento o cada "restaurar compras" entraba como compra nueva y
// regalaba un periodo. Habia nueve apuntes de la misma suscripcion.
test("reentregar la MISMA suscripcion vigente no alarga nada", () => {
  const caduca = AHORA + 12 * DIA;
  const r = resolveGrant(
    caso({
      currentTier: "pro",
      currentProductId: "attra_pro_monthly",
      currentExpiresAtMs: caduca,
    })
  );
  assert.strictEqual(r.expiresAtMs, caduca, "no debe mover la caducidad");
  assert.strictEqual(r.extended, false);
  assert.strictEqual(r.reason, "same_subscription_redelivered");
});

test("la renovacion real (ya caducado) si extiende", () => {
  const r = resolveGrant(
    caso({
      currentTier: "pro",
      currentProductId: "attra_pro_monthly",
      currentExpiresAtMs: AHORA - 2 * DIA,
    })
  );
  assert.ok(r.expiresAtMs > AHORA + 27 * DIA);
  assert.strictEqual(r.extended, true);
  assert.strictEqual(r.reason, "renewal");
});

test("pasar de mensual a anual del mismo plan extiende", () => {
  const r = resolveGrant(
    caso({
      productId: "attra_pro_yearly",
      period: "yearly",
      currentTier: "pro",
      currentProductId: "attra_pro_monthly",
      currentExpiresAtMs: AHORA + 10 * DIA,
    })
  );
  assert.ok(r.expiresAtMs > AHORA + 360 * DIA);
  assert.strictEqual(r.reason, "same_tier_other_product");
});

test("subir de Plus a Pro manda lo comprado, no la fecha mas larga", () => {
  // Plus ANUAL barato + Pro MENSUAL no puede dar un ano de Pro.
  const r = resolveGrant(
    caso({
      tier: "pro",
      productId: "attra_pro_monthly",
      currentTier: "plus",
      currentProductId: "attra_plus_yearly",
      currentExpiresAtMs: AHORA + 300 * DIA,
    })
  );
  assert.strictEqual(r.tier, "pro");
  assert.ok(r.expiresAtMs < AHORA + 32 * DIA, "no hereda el ano del Plus");
});

test("restaurar un Plus viejo no degrada a quien tiene Pro", () => {
  const caduca = AHORA + 40 * DIA;
  const r = resolveGrant(
    caso({
      tier: "plus",
      productId: "attra_plus_monthly",
      currentTier: "pro",
      currentProductId: "attra_pro_monthly",
      currentExpiresAtMs: caduca,
    })
  );
  assert.strictEqual(r.tier, "pro");
  assert.strictEqual(r.expiresAtMs, caduca, "ni acorta ni alarga el Pro");
  assert.strictEqual(r.reason, "downgrade_keeps_current");
});

// El caso del usuario: pago hecho, apuntado en el ledger, pero el entitlement
// se perdio. Reconciliar tiene que devolverle el plan, no dejarlo en free.
test("con el entitlement perdido, el mismo recibo vuelve a conceder", () => {
  const r = resolveGrant(
    caso({
      currentTier: "free",
      currentProductId: "",
      currentExpiresAtMs: null,
    })
  );
  assert.strictEqual(r.tier, "pro");
  assert.ok(r.expiresAtMs > AHORA);
});

test("un lifetime no se pierde ni se acorta por una compra", () => {
  const r = resolveGrant(
    caso({
      tier: "plus",
      productId: "attra_plus_monthly",
      currentTier: "pro",
      currentProductId: "app_review_demo",
      currentExpiresAtMs: null,
      currentIsLifetime: true,
    })
  );
  assert.strictEqual(r.tier, "pro");
});

test("un lifetime del mismo tier tampoco se toca", () => {
  const r = resolveGrant(
    caso({
      tier: "pro",
      productId: "attra_pro_monthly",
      currentTier: "pro",
      currentProductId: "attra_pro_monthly",
      currentExpiresAtMs: null,
      currentIsLifetime: true,
    })
  );
  assert.strictEqual(r.tier, "pro");
  assert.strictEqual(r.extended, false);
});

test("nunca se devuelve una caducidad anterior a la vigente", () => {
  const combinaciones = [
    ["pro", "attra_pro_monthly", "pro", "attra_pro_monthly"],
    ["pro", "attra_pro_yearly", "pro", "attra_pro_monthly"],
    ["plus", "attra_plus_monthly", "pro", "attra_pro_monthly"],
    ["pro", "attra_pro_monthly", "plus", "attra_plus_monthly"],
  ];
  for (const [tier, productId, currentTier, currentProductId] of combinaciones) {
    const caduca = AHORA + 45 * DIA;
    const r = resolveGrant(
      caso({
        tier,
        productId,
        period: productId.endsWith("_yearly") ? "yearly" : "monthly",
        currentTier,
        currentProductId,
        currentExpiresAtMs: caduca,
      })
    );
    // Salvo la subida de plan, que manda lo comprado a proposito.
    const esSubida = r.reason === "upgrade";
    if (!esSubida) {
      assert.ok(
        r.expiresAtMs >= caduca,
        `${tier}/${productId} sobre ${currentTier}/${currentProductId} acorto la caducidad`
      );
    }
  }
});

// C12: la renovacion de Android llega SIN verificar (modo 'log') con un
// orderId nuevo (`GPA...N`) y el plan aun vigente. Antes se trataba como
// reentrega y el plan caducaba con el usuario pagando.
test("renovacion sin verificar: id de tienda NUEVO extiende desde la caducidad", () => {
  const caduca = AHORA + 3 * DIA;
  const r = resolveGrant(
    caso({
      currentTier: "pro",
      currentProductId: "attra_pro_monthly",
      currentExpiresAtMs: caduca,
      newTransaction: true,
    })
  );
  assert.strictEqual(r.reason, "renewal");
  assert.strictEqual(r.extended, true);
  // Un mes desde la caducidad, no desde hoy: no se come los 3 dias.
  assert.ok(r.expiresAtMs > caduca + 27 * DIA);
  assert.ok(r.expiresAtMs < caduca + 32 * DIA);
});

// Sin verificar, el id "nuevo" lo pone el cliente: sin tope, cada id inventado
// sumaba otro periodo (dos llamadas = dos años de Pro por el precio de nada).
test("renovacion sin verificar: como mucho un periodo desde hoy + margen", () => {
  const caduca = AHORA + 360 * DIA; // ya tenia casi un año por delante
  const r = resolveGrant(
    caso({
      productId: "attra_pro_yearly",
      period: "yearly",
      currentTier: "pro",
      currentProductId: "attra_pro_yearly",
      currentExpiresAtMs: caduca,
      newTransaction: true,
    })
  );
  assert.ok(r.expiresAtMs <= AHORA + 365 * DIA + UNVERIFIED_RENEWAL_SLACK_MS);
  assert.ok(r.expiresAtMs >= caduca, "nunca acorta");
  // Ya en el tope: otro id inventado no mueve nada.
  const otra = resolveGrant(
    caso({
      productId: "attra_pro_yearly",
      period: "yearly",
      currentTier: "pro",
      currentProductId: "attra_pro_yearly",
      currentExpiresAtMs: r.expiresAtMs,
      newTransaction: true,
    })
  );
  assert.strictEqual(otra.expiresAtMs, r.expiresAtMs);
  assert.strictEqual(otra.extended, false);
  assert.strictEqual(otra.reason, "same_subscription_redelivered");
});

test("el hash del recibo (sin id de tienda) sigue sin alargar la vigente", () => {
  const caduca = AHORA + 12 * DIA;
  const r = resolveGrant(
    caso({
      currentTier: "pro",
      currentProductId: "attra_pro_monthly",
      currentExpiresAtMs: caduca,
      newTransaction: false,
    })
  );
  assert.strictEqual(r.expiresAtMs, caduca);
  assert.strictEqual(r.reason, "same_subscription_redelivered");
});

test("con caducidad de la tienda: manda la tienda y nunca acorta", () => {
  const caduca = AHORA + 12 * DIA;
  const base = {
    currentTier: "pro",
    currentProductId: "attra_pro_monthly",
    currentExpiresAtMs: caduca,
  };
  const renovada = resolveGrant(caso({ ...base, storeExpiresAtMs: caduca + 30 * DIA }));
  assert.strictEqual(renovada.expiresAtMs, caduca + 30 * DIA);
  assert.strictEqual(renovada.reason, "renewal");
  const vieja = resolveGrant(caso({ ...base, storeExpiresAtMs: caduca - 5 * DIA }));
  assert.strictEqual(vieja.expiresAtMs, caduca);
  assert.strictEqual(vieja.extended, false);
  const subida = resolveGrant(
    caso({
      currentTier: "plus",
      currentProductId: "attra_plus_yearly",
      currentExpiresAtMs: AHORA + 300 * DIA,
      storeExpiresAtMs: AHORA + 30 * DIA,
    })
  );
  assert.strictEqual(subida.tier, "pro");
  assert.strictEqual(subida.expiresAtMs, AHORA + 30 * DIA);
});

// App Review compra en SANDBOX, donde Apple acelera el reloj: un mensual
// caduca a los ~5 minutos. Con la fecha tal cual, el revisor que acaba de
// pagar veia Pro bloqueado minutos despues.
test("sandbox: la compra concede un periodo de calendario aunque Apple diga 5 minutos", () => {
  const cincoMin = AHORA + 5 * 60 * 1000;
  const mensual = resolveGrant(caso({ storeExpiresAtMs: cincoMin, sandbox: true }));
  assert.strictEqual(mensual.reason, "upgrade");
  assert.ok(mensual.expiresAtMs > AHORA + 27 * DIA, "un mes, no 5 minutos");
  assert.ok(mensual.expiresAtMs < AHORA + 32 * DIA);
  // Anual en sandbox (~1 h): doce meses.
  const anual = resolveGrant(
    caso({
      productId: "attra_pro_yearly",
      period: "yearly",
      storeExpiresAtMs: AHORA + 60 * 60 * 1000,
      sandbox: true,
    })
  );
  assert.ok(anual.expiresAtMs > AHORA + 360 * DIA);
  // Si la tienda da una fecha MAS larga, manda la tienda.
  const larga = resolveGrant(
    caso({ storeExpiresAtMs: AHORA + 40 * DIA, sandbox: true })
  );
  assert.strictEqual(larga.expiresAtMs, AHORA + 40 * DIA);
});

test("produccion: la misma compra de 5 minutos NO recibe el suelo de calendario", () => {
  const cincoMin = AHORA + 5 * 60 * 1000;
  const r = resolveGrant(caso({ storeExpiresAtMs: cincoMin }));
  assert.strictEqual(r.expiresAtMs, cincoMin);
  const explicito = resolveGrant(caso({ storeExpiresAtMs: cincoMin, sandbox: false }));
  assert.strictEqual(explicito.expiresAtMs, cincoMin);
});

// Las renovaciones aceleradas de sandbox (una cada ~5 min) y cada "restaurar
// compras" son la MISMA suscripcion: no pueden deslizar el mes desde hoy.
test("sandbox: renovar o restaurar la misma suscripcion vigente no alarga el mes", () => {
  const mes = AHORA + 20 * DIA; // concedido hace ~10 dias
  const r = resolveGrant(
    caso({
      currentTier: "pro",
      currentProductId: "attra_pro_monthly",
      currentExpiresAtMs: mes,
      storeExpiresAtMs: AHORA + 5 * 60 * 1000,
      sandbox: true,
    })
  );
  assert.strictEqual(r.expiresAtMs, mes);
  assert.strictEqual(r.extended, false);
  assert.strictEqual(r.reason, "same_subscription_redelivered");
});

test("notificacion de sandbox: la compra nueva tambien recibe el mes", () => {
  const r = sync({
    currentTier: "free",
    currentProductId: "",
    currentExpiresAtMs: null,
    storeExpiresAtMs: AHORA + 5 * 60 * 1000,
    sandbox: true,
  });
  assert.strictEqual(r.action, "grant");
  assert.ok(r.expiresAtMs > AHORA + 27 * DIA);
  // En produccion, la fecha de la tienda tal cual.
  const prod = sync({
    currentTier: "free",
    currentProductId: "",
    currentExpiresAtMs: null,
    storeExpiresAtMs: AHORA + 5 * 60 * 1000,
  });
  assert.strictEqual(prod.expiresAtMs, AHORA + 5 * 60 * 1000);
});

test("periodo: el guardado al comprar sirve al restaurar un plan basico de Play", () => {
  assert.strictEqual(periodFor("attra_plus", undefined, "yearly"), "yearly");
  assert.strictEqual(periodFor("attra_plus", undefined, null), "monthly");
  assert.strictEqual(periodFor("attra_plus", "monthly", "yearly"), "monthly");
  assert.strictEqual(periodFor("attra_plus_monthly", "yearly", "yearly"), "monthly");
});

function sync(extra) {
  return resolveStoreSync(
    Object.assign(
      {
        tier: "pro",
        productId: "attra_pro_monthly",
        period: "monthly",
        nowMs: AHORA,
        currentTier: "pro",
        currentProductId: "attra_pro_monthly",
        currentExpiresAtMs: AHORA + 2 * DIA,
        currentIsLifetime: false,
        currentSubscriptionKey: "k1",
        subscriptionKey: "k1",
        storeExpiresAtMs: AHORA + 32 * DIA,
        entitled: true,
        revoked: false,
        allowRevocation: true,
      },
      extra
    )
  );
}

test("notificacion de renovacion: extiende a la fecha de la tienda", () => {
  const r = sync();
  assert.strictEqual(r.action, "grant");
  assert.strictEqual(r.expiresAtMs, AHORA + 32 * DIA);
  assert.strictEqual(sync({ storeExpiresAtMs: AHORA + DIA }).action, "ignore");
  assert.strictEqual(sync({ entitled: false }).action, "ignore");
});

test("reembolso: solo quita el plan si viene de ESA suscripcion", () => {
  const r = sync({ revoked: true, entitled: false });
  assert.strictEqual(r.action, "revoke");
  assert.strictEqual(r.expiresAtMs, AHORA);
  assert.strictEqual(
    sync({ revoked: true, currentSubscriptionKey: "otra" }).action,
    "ignore"
  );
  assert.strictEqual(sync({ revoked: true, currentIsLifetime: true }).action, "ignore");
  // Play en modo 'log': se registra pero no se quita.
  assert.strictEqual(sync({ revoked: true, allowRevocation: false }).action, "ignore");
});
