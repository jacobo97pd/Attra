/**
 * Barrido horario de viajes/planes y backfill de publicacion: UN documento
 * raro no puede tumbar la pasada de todos.
 *
 *   cd functions && npm run build && node --test test/discovery_sweep.test.js
 *
 * QUE FALLABA: un `settings.travel.until` escrito a mano fuera del rango de
 * Timestamp hacia lanzar a `Timestamp.fromMillis` dentro de `syncOne`. En
 * `sweepTravelModes` no habia guarda por usuario: no se confirmaba el lote de
 * apagados de esa pagina, se saltaban las paginas siguientes y la pasada de
 * planes caducados no llegaba a correr (nadie volvia a casa ni perdia el
 * incognito de pago), y asi cada hora. `runPublicationBackfill` se paraba en
 * ese usuario y la migracion de profileCards/18+ quedaba a medias.
 */
const { test, afterEach, mock } = require("node:test");
const assert = require("node:assert/strict");
const { Query, Timestamp } = require("firebase-admin/firestore");
const { installFakeFirestore } = require("./fakeFirestore.js");
const { db } = require("../lib/firebase.js");
const { runPublicationBackfill, runTravelSweep } = require("../lib/discovery.js");

afterEach(() => mock.restoreAll());

const HORA = 60 * 60 * 1000;
const DIA = 24 * HORA;
const AHORA = Date.now();
const nacido = (y, m, d) => Timestamp.fromDate(new Date(Date.UTC(y, m - 1, d)));

function usuaria(extra = {}) {
  const base = {
    onboardingCompleted: true,
    profileCompleted: true,
    isBot: false,
    photoUrl: "https://example.test/a.jpg",
    profile: {
      displayName: "Ana",
      gender: "female",
      birthDate: nacido(1995, 5, 20),
      currentCity: "Madrid",
      currentCountryName: "España",
      currentCountryIso2: "ES",
    },
    location: { latitude: 40.4168, longitude: -3.7038 },
    settings: {},
  };
  return { ...base, ...extra };
}

/// Documento que hace LANZAR a la construccion de la ficha (el getter se
/// evalua al leer el nombre publico), sea cual sea la causa real.
function rompeFicha(extra = {}) {
  const data = usuaria(extra);
  data.profile = {
    birthDate: nacido(1995, 5, 20),
    get displayName() {
      throw new Error("documento raro");
    },
  };
  return data;
}

function viaje(extra = {}) {
  return {
    active: true,
    iso2: "ES",
    city: "Cadiz",
    country: "Spain",
    untilAt: Timestamp.fromMillis(AHORA + 10 * DIA),
    ...extra,
  };
}

const PRO = { tier: "pro", isLifetime: true };

/// El fake comun no tiene getAll fuera de transacciones.
function installGetAll() {
  mock.method(db, "getAll", async (...refs) => Promise.all(refs.map((r) => r.get())));
}

test("barrido: un usuario que hace lanzar a syncOne no para la pasada", async () => {
  const { docs, writes } = installFakeFirestore(mock, {
    // Primero en orden de __name__: antes su throw se llevaba por delante el
    // apagado de b_caducado y toda la pasada de planes.
    "users/a_roto": rompeFicha({ settings: { travel: viaje() } }),
    "userEntitlements/a_roto": PRO,
    "users/b_caducado": usuaria({
      settings: { travel: viaje({ untilAt: Timestamp.fromMillis(AHORA - DIA) }) },
    }),
    // Plan que caduco hace una hora con el incognito puesto.
    "users/c_plan": usuaria({ settings: { "privacy.incognito": true } }),
    "userEntitlements/c_plan": {
      tier: "plus",
      expiresAt: Timestamp.fromMillis(AHORA - HORA),
    },
  });
  installGetAll();

  const result = await runTravelSweep(AHORA);

  assert.deepEqual(result, { deactivated: 1, resynced: 1, failed: 1 });
  const apagado = writes.find((w) => w.op === "update" && w.path === "users/b_caducado");
  assert.ok(apagado, "el lote de apagados de la pagina se confirma");
  assert.equal(apagado.value["settings.travel.active"], false);
  assert.equal(apagado.value["settings.travel.until"], null);
  // La pasada de planes caducados corre: sin plan, el incognito deja de valer.
  assert.equal(docs.has("discovery/c_plan"), true);
  assert.equal(docs.has("discovery/a_roto"), false);
});

test("barrido: un `until` fuera de rango se apaga en vez de lanzar", async () => {
  const { writes } = installFakeFirestore(mock, {
    "users/raro": usuaria({
      settings: { travel: viaje({ untilAt: null, until: "+010000-01-01T00:00:00Z" }) },
    }),
    "userEntitlements/raro": PRO,
  });
  installGetAll();

  const result = await runTravelSweep(AHORA);

  assert.deepEqual(result, { deactivated: 1, resynced: 0, failed: 0 });
  const apagado = writes.find((w) => w.op === "update" && w.path === "users/raro");
  assert.equal(apagado.value["settings.travel.until"], null, "la fecha rara no se queda");
});

/// El fake comun no pagina `users` por __name__ directamente sobre la
/// coleccion (el backfill no filtra): se anade aqui, como en profileCards.test.js.
function installUserPaging(docs) {
  const snapOf = (path) => {
    const value = docs.get(path);
    return {
      id: path.split("/").pop(),
      ref: db.doc(path),
      exists: value !== undefined,
      data: () => (value === undefined ? undefined : { ...value }),
    };
  };
  const pager = (collPath, lim, after) => ({
    limit: (n) => pager(collPath, n, after),
    startAfter: (id) => pager(collPath, lim, id),
    get: async () => {
      let ids = [...docs.keys()]
        .filter((p) => p.startsWith(`${collPath}/`) && p.split("/").length === 2)
        .map((p) => p.split("/")[1])
        .sort();
      if (after) ids = ids.filter((id) => id > after);
      if (lim !== null) ids = ids.slice(0, lim);
      const found = ids.map((id) => snapOf(`${collPath}/${id}`));
      return { empty: found.length === 0, size: found.length, docs: found };
    },
  });
  mock.method(Query.prototype, "orderBy", function () {
    return pager(this.path, null, null);
  });
  mock.method(db, "getAll", async (...refs) => refs.map((r) => snapOf(r.path)));
}

function backfillWorld() {
  return {
    "users/a_roto": rompeFicha(),
    // Viajero de pago con una fecha imposible: antes lanzaba aqui.
    "users/b_fecha": usuaria({
      settings: { travel: viaje({ untilAt: null, until: "+100000-01-01T00:00:00Z" }) },
    }),
    "userEntitlements/b_fecha": PRO,
    "users/c_normal": usuaria(),
  };
}

test("backfill: un documento que no se puede construir se cuenta y se salta", async () => {
  const { docs, writes } = installFakeFirestore(mock, backfillWorld());
  installUserPaging(docs);

  const ensayo = await runPublicationBackfill({ dryRun: true, pageSize: 2, nowMs: AHORA });
  assert.equal(writes.length, 0);
  assert.equal(ensayo.processed, 3, "el ensayo recorre a todos en vez de lanzar");
  assert.equal(ensayo.reasons.error, 1);

  const result = await runPublicationBackfill({ dryRun: false, pageSize: 2, nowMs: AHORA });
  assert.equal(result.processed, 3);
  assert.equal(result.reasons.error, 1);
  assert.equal(result.published, 2);
  // Del roto no se escribe ni se borra nada.
  assert.equal(writes.some((w) => w.path.endsWith("/a_roto")), false);
  // La fecha imposible cuenta como viaje caducado: se publica en casa.
  assert.equal(docs.get("discovery/b_fecha").traveling, false);
  assert.equal(docs.get("discovery/b_fecha").currentCity, "Madrid");
  assert.equal(docs.has("profileCards/c_normal"), true);
});
