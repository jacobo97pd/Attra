/**
 * Rango de edad en la ficha publica (functions/src/discovery.ts,
 * buildDiscoveryDoc) — C09.
 *
 * COMO SE EJECUTAN:
 *
 *   cd functions && npm run build && node --test test/discovery_age_prefs.test.js
 *
 * POR QUE: el onboarding obliga a elegir un rango de edad ("Personaliza a quien
 * te mostraremos") y se guardaba en preferences.preferredAgeMin/Max, pero la
 * ficha publica no lo llevaba: el feed no podia comprobar si TU edad cabia en
 * el rango del otro, y a quien busca 22-30 le salia gente de 58. El directo si
 * lo aplicaba en los dos sentidos (isLiveCompatible).
 */
const test = require("node:test");
const assert = require("node:assert/strict");

const { buildDiscoveryDoc } = require("../lib/discovery.js");

const AHORA = Date.UTC(2026, 8, 25, 12, 0, 0);

function usuario(preferences) {
  return {
    onboardingCompleted: true,
    profileCompleted: true,
    isBot: false,
    profile: { displayName: "Lucia", gender: "female", age: 22 },
    preferences,
  };
}

test("publica el rango de edad que busca", () => {
  const doc = buildDiscoveryDoc(
    "lucia",
    usuario({ interestedIn: ["male"], preferredAgeMin: 22, preferredAgeMax: 30 }),
    false,
    AHORA
  );
  assert.equal(doc.preferredAgeMin, 22);
  assert.equal(doc.preferredAgeMax, 30);
  // No se pierde nada de lo que ya se publicaba de `preferences`.
  assert.deepEqual(doc.interestedIn, ["male"]);
});

test("mismo recorte que el directo: nunca por debajo de 18, tope 80, min <= max", () => {
  const bajo = buildDiscoveryDoc(
    "a",
    usuario({ preferredAgeMin: 15, preferredAgeMax: 99 }),
    false,
    AHORA
  );
  assert.equal(bajo.preferredAgeMin, 18);
  assert.equal(bajo.preferredAgeMax, 80);

  const alReves = buildDiscoveryDoc(
    "b",
    usuario({ preferredAgeMin: 40, preferredAgeMax: 30 }),
    false,
    AHORA
  );
  assert.equal(alReves.preferredAgeMin, 40);
  assert.equal(alReves.preferredAgeMax, 40);

  const soloMin = buildDiscoveryDoc(
    "c",
    usuario({ preferredAgeMin: "25" }),
    false,
    AHORA
  );
  assert.equal(soloMin.preferredAgeMin, 25);
  assert.equal(soloMin.preferredAgeMax, 80);
});

test("sin rango guardado no se publica nada (el feed es permisivo)", () => {
  const doc = buildDiscoveryDoc("d", usuario({ interestedIn: [] }), false, AHORA);
  assert.equal("preferredAgeMin" in doc, false);
  assert.equal("preferredAgeMax" in doc, false);

  const sinPrefs = buildDiscoveryDoc("e", usuario(undefined), false, AHORA);
  assert.equal("preferredAgeMin" in sinPrefs, false);
});

test("no publica nada mas de `preferences` (radio ni filtros guardados)", () => {
  const doc = buildDiscoveryDoc(
    "f",
    usuario({
      preferredAgeMin: 25,
      preferredAgeMax: 35,
      maxDistanceKm: 30,
      feedFilters: { smoking: "never", dealbreakers: ["smoking"] },
    }),
    false,
    AHORA
  );
  assert.equal("maxDistanceKm" in doc, false);
  assert.equal("feedFilters" in doc, false);
});
