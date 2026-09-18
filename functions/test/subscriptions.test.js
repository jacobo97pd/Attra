const test = require("node:test");
const assert = require("node:assert");

const { resolveGrant } = require("../lib/subscriptions.js");

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
