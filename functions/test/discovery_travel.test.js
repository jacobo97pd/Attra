/**
 * Tests de la ficha publica en modo viaje y del pais comparable
 * (functions/src/discovery.ts, travel.ts, places.ts y la clave de pais de
 * live.ts).
 *
 * COMO SE EJECUTAN:
 *
 *   cd functions && npm run build && node --test test/discovery_travel.test.js
 *
 * QUE SE VERIFICA Y POR QUE: quien estaba en Madrid y viajaba a Cadiz seguia
 * viendo (y siendo visto por) gente de Madrid. El viajero se publicaba sin
 * coordenadas (le veia toda Espana), el pais se comparaba por nombre en el
 * idioma de cada telefono y nada caducaba el viaje si no se volvia a escribir
 * el usuario.
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const { Timestamp } = require("firebase-admin/firestore");

const {
  buildDiscoveryDoc,
  decideTravelSweep,
  entitlementChanged,
  isDiscoverable,
  isPaidActive,
  resolveCountryIso2,
  travelExpired,
} = require("../lib/discovery.js");
const {
  iso2ForCountryName,
  normalizePlace,
  geoCacheKey,
} = require("../lib/travel.js");
const { parseLocality } = require("../lib/places.js");

const DIA = 24 * 60 * 60 * 1000;
const AHORA = Date.UTC(2026, 8, 25, 12, 0, 0); // 25-sep-2026

/// Usuario en MADRID (coordenadas reales) con un viaje a CADIZ: el caso del
/// que se quejo el usuario.
function madrileno(travel) {
  return {
    onboardingCompleted: true,
    profileCompleted: true,
    isBot: false,
    photoUrl: "https://example.test/a.jpg",
    profile: {
      displayName: "Ana",
      gender: "female",
      bio: "Hola",
      currentCity: "Madrid",
      currentCountryName: "España",
      currentCountryIso2: "ES",
    },
    location: { latitude: 40.4168, longitude: -3.7038 },
    settings: travel ? { travel } : {},
  };
}

function viajeACadiz(extra) {
  return Object.assign(
    {
      active: true,
      iso2: "ES",
      city: "Cadiz",
      country: "Spain",
      lat: 36.5267,
      lng: -6.2891,
      geoSource: "asset",
      until: new Date(AHORA + 20 * DIA).toISOString(),
      untilAt: Timestamp.fromMillis(AHORA + 20 * DIA),
    },
    extra
  );
}

test("viajando con plan: se publica en el CENTRO del destino, nunca en casa", () => {
  const doc = buildDiscoveryDoc("ana", madrileno(viajeACadiz()), true, AHORA);
  assert.equal(doc.traveling, true);
  assert.equal(doc.currentCity, "Cadiz");
  assert.equal(doc.countryIso2, "ES");
  assert.deepEqual(doc.geo, { lat: 36.53, lng: -6.29 });
  assert.notEqual(doc.geo.lat, 40.42, "las coordenadas de Madrid no salen");
  assert.equal(doc.travelUntil.toMillis(), AHORA + 20 * DIA);
});

test("viajando con ubicación aproximada: el centro se difumina igual", () => {
  const data = madrileno(viajeACadiz());
  data.settings["location.precision"] = "approximate";
  const doc = buildDiscoveryDoc("ana", data, true, AHORA);
  assert.deepEqual(doc.geo, { lat: 36.5, lng: -6.3 });
});

test("viaje caducado: vuelve a casa (ciudad, país y coordenadas reales)", () => {
  const travel = viajeACadiz({
    until: new Date(AHORA - DIA).toISOString(),
    untilAt: Timestamp.fromMillis(AHORA - DIA),
  });
  const doc = buildDiscoveryDoc("ana", madrileno(travel), true, AHORA);
  assert.equal(doc.traveling, false);
  assert.equal(doc.currentCity, "Madrid");
  assert.equal(doc.countryIso2, "ES");
  assert.deepEqual(doc.geo, { lat: 40.42, lng: -3.7 });
  assert.equal(doc.travelUntil, undefined);
});

test("sin plan de pago el viaje se ignora", () => {
  const doc = buildDiscoveryDoc("ana", madrileno(viajeACadiz()), false, AHORA);
  assert.equal(doc.traveling, false);
  assert.deepEqual(doc.geo, { lat: 40.42, lng: -3.7 });
});

test("centro fuera de rango: viajando SIN geo (nunca las reales)", () => {
  const travel = viajeACadiz({ lat: 136.5, lng: -6.29 });
  const doc = buildDiscoveryDoc("ana", madrileno(travel), true, AHORA);
  assert.equal(doc.traveling, true);
  assert.equal(doc.geo, undefined);
});

test("viaje antiguo sin coordenadas: sin geo y país de destino por nombre", () => {
  const travel = viajeACadiz({ lat: undefined, lng: undefined, iso2: "" });
  const doc = buildDiscoveryDoc("ana", madrileno(travel), true, AHORA);
  assert.equal(doc.geo, undefined);
  assert.equal(doc.countryIso2, "ES", "deducido de 'Spain'");
});

test("untilAt (Timestamp) manda sobre el ISO antiguo", () => {
  const travel = {
    until: new Date(AHORA + DIA).toISOString(),
    untilAt: Timestamp.fromMillis(AHORA - DIA),
  };
  assert.equal(travelExpired(travel, AHORA), true);
  assert.equal(travelExpired({ until: new Date(AHORA + DIA).toISOString() }, AHORA), false);
  assert.equal(travelExpired({}, AHORA), false, "sin fecha: vigente");
});

test("país comparable: geocodificador > onboarding > nombre en cualquier idioma", () => {
  assert.equal(
    resolveCountryIso2({ currentCountryIso2: "pt", currentCountryCode: "ES" }, {}, false),
    "PT"
  );
  assert.equal(resolveCountryIso2({ currentCountryCode: "es" }, {}, false), "ES");
  // Nombres que escribían teléfonos en catalán, alemán o francés.
  for (const name of ["Espanya", "Spanien", "Espagne", "España", "Spain"]) {
    assert.equal(resolveCountryIso2({ currentCountryName: name }, {}, false), "ES", name);
  }
  assert.equal(iso2ForCountryName("Grecia"), "GR");
  assert.equal(iso2ForCountryName("Suiza"), "CH");
  assert.equal(iso2ForCountryName("Narnia"), "");
  // Viajando manda el destino.
  assert.equal(
    resolveCountryIso2({ currentCountryIso2: "ES" }, { iso2: "jp" }, true),
    "JP"
  );
});

test("expulsados y cuentas borradas no son descubribles", () => {
  const base = madrileno(null);
  assert.equal(isDiscoverable(base, false), true);
  assert.equal(isDiscoverable({ ...base, isBanned: true }, false), false);
  assert.equal(isDiscoverable({ ...base, isDeleted: true }, false), false);
});

test("tipos raros de users/{uid} no llegan a la ficha pública", () => {
  const data = madrileno(null);
  data.profile.bio = 123;
  data.profile.gender = { raro: true };
  data.photos = ["x", { url: "https://example.test/b.jpg" }, null];
  const doc = buildDiscoveryDoc("ana", data, false, AHORA);
  assert.equal(doc.bio, "");
  assert.equal(doc.gender, "");
  assert.deepEqual(doc.photos, [{ url: "https://example.test/b.jpg" }]);
});

test("barrido: caducado se apaga; plan y ficha desalineados se republican", () => {
  const caducado = viajeACadiz({ untilAt: Timestamp.fromMillis(AHORA - DIA) });
  assert.equal(decideTravelSweep(caducado, true, true, AHORA), "deactivate");
  // El plan caducó pero la ficha sigue "de viaje".
  assert.equal(decideTravelSweep(viajeACadiz(), false, true, AHORA), "resync");
  // Volvió a pagar y la ficha sigue en casa.
  assert.equal(decideTravelSweep(viajeACadiz(), true, false, AHORA), "resync");
  // Sin ficha publicada y con plan: hay que publicarla.
  assert.equal(decideTravelSweep(viajeACadiz(), true, undefined, AHORA), "resync");
  // Todo en su sitio.
  assert.equal(decideTravelSweep(viajeACadiz(), true, true, AHORA), "none");
  assert.equal(decideTravelSweep(viajeACadiz(), false, false, AHORA), "none");
  assert.equal(decideTravelSweep({ active: false }, true, false, AHORA), "none");
});

test("cambio de plan que importa a la ficha", () => {
  const pro = { tier: "pro", expiresAt: Timestamp.fromMillis(AHORA + DIA) };
  const caducado = { tier: "pro", expiresAt: Timestamp.fromMillis(AHORA - DIA) };
  assert.equal(isPaidActive(pro, AHORA), true);
  assert.equal(isPaidActive(caducado, AHORA), false);
  assert.equal(entitlementChanged(undefined, pro, AHORA), true);
  assert.equal(entitlementChanged(caducado, pro, AHORA), true);
  assert.equal(entitlementChanged(pro, { ...pro, updatedAt: 1 }, AHORA), false);
});

test("normalización idéntica a la del cliente", () => {
  assert.equal(normalizePlace("  Cádiz "), "cadiz");
  assert.equal(normalizePlace("El Puerto de Santa María"), "el puerto de santa maria");
  assert.equal(geoCacheKey("ES", "Cádiz"), "ES_cadiz");
});

test("Places: solo se acepta una localidad con coordenadas válidas", () => {
  assert.deepEqual(
    parseLocality({
      places: [{ types: ["locality", "political"], location: { latitude: 36.53, longitude: -6.29 } }],
    }),
    { lat: 36.53, lng: -6.29 }
  );
  assert.equal(
    parseLocality({ places: [{ types: ["bar"], location: { latitude: 1, longitude: 2 } }] }),
    null
  );
  assert.equal(parseLocality({ places: [] }), null);
  assert.equal(parseLocality({}), null);
});

test("vivo: la clave de país es el ISO2 (catalán y alemán casan con España)", () => {
  const { liveCountryKey } = require("../lib/live.js");
  assert.equal(liveCountryKey({ currentCountryName: "España" }), "es");
  assert.equal(liveCountryKey({ currentCountryName: "Espanya" }), "es");
  assert.equal(
    liveCountryKey({ currentCountryName: "Spanien", currentCountryIso2: "ES" }),
    "es"
  );
  assert.equal(liveCountryKey({ currentCountryCode: "gr" }), "gr");
  // Nombre que no se reconoce: se compara tal cual, como antes.
  assert.equal(liveCountryKey({ currentCountryName: "Narnia" }), "narnia");
  assert.equal(liveCountryKey({}), "");
});

test("barrido: al apagar un viaje caducado se borra el centro, no el destino", () => {
  // Contrato con el cliente (UserRepository.buildTravelPatch): apagado =
  // lat/lng null y geoSource 'none'; país, ciudad e ISO2 se conservan.
  const { travelDeactivationPatch } = require("../lib/discovery.js");
  const patch = travelDeactivationPatch();
  assert.equal(patch["settings.travel.active"], false);
  assert.equal(patch["settings.travel.untilAt"], null);
  assert.equal(patch["settings.travel.lat"], null);
  assert.equal(patch["settings.travel.lng"], null);
  assert.equal(patch["settings.travel.geoSource"], "none");
  for (const kept of ["country", "city", "iso2", "until"]) {
    assert.equal(`settings.travel.${kept}` in patch, false, kept);
  }
});
