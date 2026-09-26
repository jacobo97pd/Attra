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
  MAX_TRAVEL_MS,
  buildDiscoveryDoc,
  decideTravelSweep,
  entitlementChanged,
  isDiscoverable,
  isPaidActive,
  publicDocsFor,
  resolveCountryIso2,
  travelCenter,
  travelExpired,
  travelUntilMs,
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
      // Mayor de edad: sin fecha valida no se publica (18+ en servidor, D06).
      birthDate: Timestamp.fromDate(new Date(Date.UTC(1995, 4, 20))),
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

test("manda la fecha MÁS TARDÍA entre untilAt y el ISO antiguo", () => {
  // Una versión antigua reactiva el viaje: solo renueva `until` y el
  // `untilAt` viejo se queda. Antes mandaba untilAt y el barrido apagaba un
  // viaje recién puesto.
  const reactivado = {
    until: new Date(AHORA + DIA).toISOString(),
    untilAt: Timestamp.fromMillis(AHORA - DIA),
  };
  assert.equal(travelExpired(reactivado, AHORA), false);
  assert.equal(travelUntilMs(reactivado), AHORA + DIA);
  assert.equal(
    travelExpired(
      { until: new Date(AHORA - 2 * DIA).toISOString(), untilAt: Timestamp.fromMillis(AHORA - DIA) },
      AHORA
    ),
    true,
    "las dos pasadas: caducado"
  );
  assert.equal(travelExpired({ until: new Date(AHORA + DIA).toISOString() }, AHORA), false);
  assert.equal(travelExpired({}, AHORA), false, "sin fecha: vigente");
  assert.equal(travelExpired({ until: null, untilAt: null }, AHORA), false);
});

test("un `until` escrito a mano fuera de rango no tumba nada: cuenta como caducado", () => {
  // settings no valida tipos: "+010000-..." es 1 ms más que el mayor
  // Timestamp y Timestamp.fromMillis LANZABA dentro del trigger, del barrido
  // horario y del backfill.
  for (const until of ["+010000-01-01T00:00:00Z", "+100000-01-01T00:00:00Z", 8.64e15]) {
    const travel = viajeACadiz({ until, untilAt: null });
    const ms = travelUntilMs(travel);
    assert.ok(ms <= 253402300799999, `recortado al rango de Timestamp: ${until}`);
    assert.equal(travelExpired(travel, AHORA), true, String(until));
    assert.equal(decideTravelSweep(travel, true, undefined, AHORA), "deactivate");
    assert.doesNotThrow(() => publicDocsFor("ana", madrileno(travel), true, AHORA));
    const doc = buildDiscoveryDoc("ana", madrileno(travel), true, AHORA);
    assert.equal(doc.traveling, false, "vuelve a casa");
    assert.equal(doc.travelUntil, undefined);
  }
  // Un fin creíble pero lejano (más de MAX_TRAVEL_MS) tampoco vale.
  const lejano = viajeACadiz({ untilAt: Timestamp.fromMillis(AHORA + MAX_TRAVEL_MS + DIA) });
  assert.equal(travelExpired(lejano, AHORA), true);
  // Los 30 días que escribe la app, sí.
  const normal = viajeACadiz({ untilAt: Timestamp.fromMillis(AHORA + 30 * DIA) });
  assert.equal(travelExpired(normal, AHORA), false);
});

test("un viaje a un PAÍS entero no hereda el centro de un viaje anterior", () => {
  // La demo de App Review: "España" sin ciudad sobre un documento que aún
  // tenía el centro de Cádiz. Se publicaba en Cádiz y el feed se medía desde allí.
  const travel = viajeACadiz({ city: "" });
  const doc = buildDiscoveryDoc("ana", madrileno(travel), true, AHORA);
  assert.equal(doc.traveling, true);
  assert.equal(doc.geo, undefined, "sin ciudad no hay centro");
  assert.equal(travelCenter(travel), null);
});

test("el centro solo vale para la ciudad (e ISO2) para la que se resolvió", () => {
  // Una versión antigua cambia el destino a Barcelona con un merge que no
  // toca lat/lng: el centro de Cádiz no puede publicarse como Barcelona.
  const cambiado = viajeACadiz({ city: "Barcelona", geoCity: "Cadiz", geoIso2: "ES" });
  assert.equal(travelCenter(cambiado), null);
  assert.equal(buildDiscoveryDoc("ana", madrileno(cambiado), true, AHORA).geo, undefined);
  // Misma ciudad con otra grafía (acentos, mayúsculas): vale.
  const mismo = viajeACadiz({ city: "Cádiz", geoCity: " cadiz ", geoIso2: "es" });
  assert.deepEqual(travelCenter(mismo), { lat: 36.5267, lng: -6.2891 });
  // Homónimo en otro país.
  assert.equal(
    travelCenter(viajeACadiz({ city: "Valencia", iso2: "VE", geoCity: "Valencia", geoIso2: "ES" })),
    null
  );
  // Centros de antes de geoCity/geoIso2: basta con que haya ciudad.
  assert.deepEqual(travelCenter(viajeACadiz()), { lat: 36.5267, lng: -6.2891 });
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
  // Las dos fechas pasadas (con la más tardía mandando, un `until` futuro
  // mantendría el viaje: es el caso de una versión antigua que lo reactivó).
  const caducado = viajeACadiz({
    until: new Date(AHORA - DIA).toISOString(),
    untilAt: Timestamp.fromMillis(AHORA - DIA),
  });
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

test("barrido: al apagar un viaje caducado se borran centro y fechas, no el destino", () => {
  // Contrato con el cliente (UserRepository.buildTravelPatch): apagado =
  // lat/lng/fechas null y geoSource 'none'; país, ciudad e ISO2 se conservan.
  // El `until` ISO también se borra: si se quedaba, reactivar el viaje desde
  // una versión antigua o con seed_review_demo.py --travel-spain lo dejaba
  // caducado de nuevo y el barrido lo volvía a apagar.
  const { travelDeactivationPatch } = require("../lib/discovery.js");
  const patch = travelDeactivationPatch();
  assert.equal(patch["settings.travel.active"], false);
  for (const cleared of ["until", "untilAt", "lat", "lng", "geoCity", "geoIso2"]) {
    assert.equal(patch[`settings.travel.${cleared}`], null, cleared);
  }
  assert.equal(patch["settings.travel.geoSource"], "none");
  for (const kept of ["country", "city", "iso2"]) {
    assert.equal(`settings.travel.${kept}` in patch, false, kept);
  }
  // Reactivado sobre ese parche (sin fecha): vigente, nunca caducado.
  const reactivado = { active: true, iso2: "ES", country: "España", city: "", until: null, untilAt: null };
  assert.equal(decideTravelSweep(reactivado, true, true, AHORA), "none");
});
