const test = require("node:test");
const assert = require("node:assert/strict");

const { monthlyGrantDecision, isGrantDue } = require("../lib/grants.js");

const DIA = 24 * 60 * 60 * 1000;
const AHORA = Date.UTC(2026, 8, 3, 12, 0, 0); // 3-sep-2026
const PERIODO = "202609";

// Packs por defecto del producto (grants.ts / flags): Free 1+0, Plus 5+1, Pro 15+4.
const PACK = {
  free: { attras: 1, boosts: 0 },
  plus: { attras: 5, boosts: 1 },
  pro: { attras: 15, boosts: 4 },
};

function decide(tier, walletData, nowMs = AHORA) {
  return monthlyGrantDecision({
    walletData,
    tier,
    ...PACK[tier],
    period: PERIODO,
    nowMs,
  });
}

/// Wallet tal y como lo deja un pack concedido hace [diasAtras] dias.
function wallet(tier, diasAtras, extra = {}) {
  return Object.assign(
    {
      lastMonthlyGrantAt: new Date(AHORA - diasAtras * DIA),
      monthlyGrantPeriod: PERIODO,
      monthlyGrantTier: tier,
      monthlyGrantAttras: PACK[tier].attras,
      monthlyGrantBoosts: PACK[tier].boosts,
    },
    extra
  );
}

test("primera vez: pack completo y ventana nueva", () => {
  const r = decide("plus", undefined);
  assert.equal(r.grant, true);
  assert.equal(r.attras, 5);
  assert.equal(r.boosts, 1);
  assert.equal(r.restartWindow, true);
});

// C27: el caso del informe. Free cobra su Attra el dia 1 y compra Plus el 3:
// antes no recibia NADA hasta el 2 del mes siguiente.
test("C27: Free -> Plus dentro de la ventana cobra la diferencia YA", () => {
  const w = wallet("free", 2);
  assert.equal(isGrantDue(w, PERIODO, AHORA, "plus"), true, "el prefiltro lo deja pasar");
  const r = decide("plus", w);
  assert.equal(r.grant, true);
  assert.equal(r.attras, 4, "5 del Plus menos el Attra Free ya cobrado");
  assert.equal(r.boosts, 1);
  assert.equal(r.restartWindow, false, "la ventana conserva su inicio");
  assert.equal(r.windowTier, "plus");
  assert.equal(r.windowAttras, 5);
});

test("C27: Plus -> Pro no cobra dos packs, solo la diferencia", () => {
  const r = decide("pro", wallet("plus", 5));
  assert.equal(r.attras, 10);
  assert.equal(r.boosts, 3);
});

test("mismo tier dentro de la ventana: nada (idempotencia de siempre)", () => {
  assert.equal(decide("plus", wallet("plus", 10)).grant, false);
  assert.equal(isGrantDue(wallet("plus", 10), PERIODO, AHORA, "plus"), false);
});

test("bajar y volver a subir en la misma ventana no cobra otra vez", () => {
  // Cobro Pro, bajo a Plus (no toca nada) y vuelvo a Pro.
  const w = wallet("pro", 3);
  assert.equal(decide("plus", w).grant, false);
  assert.equal(decide("pro", w).grant, false);
});

test("wallets anteriores al cambio (sin tier) no reciben un pack de regalo", () => {
  const legado = {
    lastMonthlyGrantAt: new Date(AHORA - 2 * DIA),
    monthlyGrantPeriod: PERIODO,
  };
  assert.equal(decide("pro", legado).grant, false);
  assert.equal(isGrantDue(legado, PERIODO, AHORA, "pro"), false);
});

test("ventana cumplida: pack completo del tier actual y ventana nueva", () => {
  const r = decide("pro", wallet("free", 31));
  assert.equal(r.grant, true);
  assert.equal(r.attras, 15);
  assert.equal(r.boosts, 4);
  assert.equal(r.restartWindow, true);
});

test("el prefiltro de Free sigue igual", () => {
  assert.equal(isGrantDue(undefined, PERIODO, AHORA), true);
  assert.equal(isGrantDue(wallet("free", 5), PERIODO, AHORA), false);
  assert.equal(isGrantDue(wallet("free", 31), PERIODO, AHORA), true);
  // Esquema antiguo por periodo natural: se respeta una vez.
  assert.equal(isGrantDue({ monthlyGrantPeriod: PERIODO }, PERIODO, AHORA), false);
});
