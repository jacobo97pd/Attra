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
const {
  BACKFILL_MAX_BATCH_WRITES,
  decideTravelSweepFor,
  publicDocsFor,
  runPublicationBackfill,
  runTravelSweep,
} = require("../lib/discovery.js");

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

/// Cuenta las escrituras de cada commit (el fake no tiene limite; Firestore
/// rechaza un batch de mas de 500).
function countCommits() {
  const fakeBatch = db.batch;
  const commits = [];
  mock.method(db, "batch", () => {
    const inner = fakeBatch.call(db);
    const paths = [];
    const wrapped = {
      set: (ref, ...rest) => (paths.push(ref.path), inner.set(ref, ...rest), wrapped),
      update: (ref, ...rest) => (paths.push(ref.path), inner.update(ref, ...rest), wrapped),
      delete: (ref) => (paths.push(ref.path), inner.delete(ref), wrapped),
      commit: async () => {
        commits.push(paths.slice());
        await inner.commit();
      },
    };
    return wrapped;
  });
  return commits;
}

// Cada usuario son DOS escrituras (discovery + profileCards). Con paginas de
// 300 el primer commit real llevaba 600: Firestore lo rechaza entero y la
// migracion no se hacia. El ensayo no lo veia porque nunca confirma.
test("backfill: ningun commit pasa de 500 escrituras", async () => {
  const mundo = {};
  for (let i = 0; i < 650; i++) {
    mundo[`users/u${String(i).padStart(4, "0")}`] = usuaria();
  }
  const { docs } = installFakeFirestore(mock, mundo);
  installUserPaging(docs);
  const commits = countCommits();

  // Pagina por defecto...
  const result = await runPublicationBackfill({ dryRun: false, nowMs: AHORA });
  assert.equal(result.processed, 650);
  assert.equal(result.cardsPublished, 650);
  assert.ok(commits.length > 1);
  for (const c of commits) {
    assert.ok(c.length <= BACKFILL_MAX_BATCH_WRITES, `commit de ${c.length}`);
    assert.ok(c.length < 500);
  }
  assert.equal(
    commits.reduce((n, c) => n + c.length, 0),
    1300,
    "no se pierde ninguna escritura al partir"
  );

  // ...y aunque alguien pida una pagina enorme.
  commits.length = 0;
  await runPublicationBackfill({ dryRun: false, pageSize: 1000, nowMs: AHORA });
  for (const c of commits) assert.ok(c.length <= BACKFILL_MAX_BATCH_WRITES);
  // Listado y ficha de cada usuario, siempre en el mismo commit.
  for (const c of commits) {
    const ids = new Set(c.map((path) => path.split("/")[1]));
    for (const id of ids) {
      assert.ok(c.includes(`discovery/${id}`) && c.includes(`profileCards/${id}`));
    }
  }

  // En ensayo, nada se confirma.
  commits.length = 0;
  await runPublicationBackfill({ dryRun: true, nowMs: AHORA });
  assert.equal(commits.length, 0);
});

// ---------------------------------------------------------------------------
// Coste del barrido: un viajero de pago que NO sale en el feed (oculto,
// pausado, sin recomendaciones, incognito) no tiene listado, solo ficha. Solo
// se miraba discovery, asi que se le republicaba en CADA pasada, para siempre.
// ---------------------------------------------------------------------------

/// Lo que hay publicado si el trigger ya hizo su trabajo.
function publicado(uid, data, isPaid) {
  const { listing, card } = publicDocsFor(uid, data, isPaid, AHORA);
  return { listing: listing ?? undefined, card: card ?? undefined };
}

test("decision: el viajero oculto con su ficha al dia no se toca", () => {
  const oculto = usuaria({
    settings: { "privacy.hideProfile": true, travel: viaje() },
  });
  const pub = publicado("o", oculto, true);
  assert.equal(pub.listing, undefined, "no sale en el feed");
  assert.equal(pub.card.traveling, true);
  assert.equal(decideTravelSweepFor("o", oculto, true, pub, AHORA), "none");
  // Sin ficha, o con la ficha desalineada con el plan: si hay que republicar.
  assert.equal(
    decideTravelSweepFor("o", oculto, true, { listing: undefined, card: undefined }, AHORA),
    "resync"
  );
  assert.equal(
    decideTravelSweepFor("o", oculto, false, pub, AHORA),
    "resync",
    "el plan caduco: la ficha ya no puede decir 'de viaje'"
  );
  // Un listado que ya no le toca tambien se corrige.
  assert.equal(
    decideTravelSweepFor("o", oculto, true, { listing: { traveling: true }, card: pub.card }, AHORA),
    "resync"
  );
});

test("decision: la ficha de incognito (traveling=false forzado) no se republica en bucle", () => {
  const incognito = usuaria({
    settings: { "privacy.incognito": true, travel: viaje() },
  });
  const pub = publicado("i", incognito, true);
  assert.equal(pub.listing, undefined);
  assert.equal(pub.card.traveling, false, "incognito no dice que viaja");
  assert.equal(decideTravelSweepFor("i", incognito, true, pub, AHORA), "none");
});

test("decision: sin ficha posible (sin fecha de nacimiento) no se borra cada hora", () => {
  const sinFecha = usuaria({ settings: { travel: viaje() } });
  sinFecha.profile = { ...sinFecha.profile, birthDate: null };
  assert.equal(
    decideTravelSweepFor("s", sinFecha, true, { listing: undefined, card: undefined }, AHORA),
    "none"
  );
});

test("decision: el viajero que sale en el feed se compara con su listado, como antes", () => {
  const visible = usuaria({ settings: { travel: viaje() } });
  const pub = publicado("v", visible, true);
  assert.equal(pub.listing.traveling, true);
  assert.equal(decideTravelSweepFor("v", visible, true, pub, AHORA), "none");
  assert.equal(
    decideTravelSweepFor("v", visible, true, { listing: { traveling: false }, card: pub.card }, AHORA),
    "resync"
  );
  // Caducado: se apaga, publique lo que publique.
  const caducado = usuaria({
    settings: { travel: viaje({ untilAt: Timestamp.fromMillis(AHORA - DIA) }) },
  });
  assert.equal(decideTravelSweepFor("v", caducado, true, pub, AHORA), "deactivate");
});

test("barrido: viajeros de pago fuera del feed y al dia -> cero escrituras", async () => {
  const oculto = usuaria({ settings: { "privacy.hideProfile": true, travel: viaje() } });
  const incognito = usuaria({ settings: { "privacy.incognito": true, travel: viaje() } });
  const pubO = publicado("oculto", oculto, true);
  const pubI = publicado("incognito", incognito, true);
  const { writes } = installFakeFirestore(mock, {
    "users/oculto": oculto,
    "userEntitlements/oculto": PRO,
    "profileCards/oculto": pubO.card,
    "users/incognito": incognito,
    "userEntitlements/incognito": PRO,
    "profileCards/incognito": pubI.card,
  });
  installGetAll();

  const result = await runTravelSweep(AHORA);

  assert.deepEqual(result, { deactivated: 0, resynced: 0, failed: 0 });
  assert.equal(writes.length, 0, "antes: 2 escrituras por usuario y hora");
});
