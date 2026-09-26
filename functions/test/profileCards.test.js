/**
 * C02 / C10: ocultar el perfil, pausar la cuenta, no salir en recomendaciones o
 * el incognito de pago BORRABAN discovery/{uid}, la unica ficha publica de un
 * usuario real. Sus matches y a quien habia dado like veian "Alguien" sin foto
 * y "No se pudo cargar el perfil", y el incognito le escondia justo de las
 * personas a las que habia dado like. Ahora discovery es solo el listado del
 * feed y profileCards/{uid} la ficha por uid de todo usuario publicable.
 *
 * D06: la edad minima solo se comprobaba en el onboarding del cliente; el
 * backend publicaba a cualquiera, tambien a un menor.
 *
 *   cd functions && npm run build && node --test test/profileCards.test.js
 */
const { test, afterEach, mock } = require("node:test");
const assert = require("node:assert/strict");
const { Query, Timestamp } = require("firebase-admin/firestore");
const { installFakeFirestore } = require("./fakeFirestore.js");
const { db } = require("../lib/firebase.js");
const {
  backfillDiscovery,
  isDiscoverable,
  onUserWrittenSyncDiscovery,
  planPublication,
  publicDocsFor,
  runPublicationBackfill,
} = require("../lib/discovery.js");
const { ageFromBirthDateAt, cardBlocker } = require("../lib/profileCards.js");

afterEach(() => mock.restoreAll());

const AHORA = Date.UTC(2026, 8, 26, 12, 0, 0); // 26-sep-2026
const nacido = (y, m, d) => Timestamp.fromDate(new Date(Date.UTC(y, m - 1, d)));

/// Usuaria real, adulta y publicable. [extra] se mezcla encima.
function ana(extra = {}) {
  const base = {
    onboardingCompleted: true,
    profileCompleted: true,
    isBot: false,
    photoUrl: "https://example.test/ana.jpg",
    profile: {
      displayName: "Ana",
      gender: "female",
      bio: "Hola",
      birthDate: nacido(1995, 5, 20),
      currentCity: "Madrid",
      currentCountryName: "España",
      currentCountryIso2: "ES",
      // Rasgo sensible cedido SOLO para filtros: nunca en la ficha.
      religion: "catholic",
    },
    profileVisibility: {
      fields: { religion: { visibleInProfile: false, useForFilters: true } },
    },
    location: { latitude: 40.4168, longitude: -3.7038 },
    settings: {},
  };
  return {
    ...base,
    ...extra,
    profile: { ...base.profile, ...(extra.profile ?? {}) },
    settings: { ...base.settings, ...(extra.settings ?? {}) },
  };
}

const ENT_PLUS = { tier: "plus", expiresAt: Timestamp.fromMillis(Date.now() + 864e5) };

// ---------------------------------------------------------------------------
// D06: 18+ en servidor
// ---------------------------------------------------------------------------

test("D06: a minor by birth date is neither listed nor carded", () => {
  const menor = ana({ profile: { birthDate: nacido(2010, 3, 1) } });
  assert.equal(isDiscoverable(menor, false, AHORA), false);
  assert.deepEqual(planPublication(menor, false, AHORA), {
    card: false,
    listed: false,
    reason: "underage",
  });
});

test("D06: a declared adult age cannot hide an under-18 birth date", () => {
  const trampa = ana({ profile: { age: 25, birthDate: nacido(2010, 3, 1) } });
  assert.equal(isDiscoverable(trampa, false, AHORA), false);
  assert.equal(cardBlocker(trampa, AHORA), "underage");
});

test("D06: without a valid birth date nothing is published", () => {
  const sinFecha = ana();
  delete sinFecha.profile.birthDate;
  assert.equal(cardBlocker(sinFecha, AHORA), "no_birth_date");
  assert.equal(isDiscoverable(sinFecha, false, AHORA), false);
  // Fecha futura o basura: igual que sin fecha.
  assert.equal(
    cardBlocker(ana({ profile: { birthDate: nacido(2030, 1, 1) } }), AHORA),
    "no_birth_date"
  );
  assert.equal(
    cardBlocker(ana({ profile: { birthDate: "no es una fecha" } }), AHORA),
    "no_birth_date"
  );
});

test("D06: the 18th birthday is the boundary", () => {
  // Cumple 18 justo hoy (26-sep-2026): publicable.
  assert.equal(ageFromBirthDateAt(nacido(2008, 9, 26), AHORA), 18);
  assert.equal(isDiscoverable(ana({ profile: { birthDate: nacido(2008, 9, 26) } }), false, AHORA), true);
  // Los cumple manana: todavia no.
  assert.equal(ageFromBirthDateAt(nacido(2008, 9, 27), AHORA), 17);
  assert.equal(isDiscoverable(ana({ profile: { birthDate: nacido(2008, 9, 27) } }), false, AHORA), false);
  // Texto ISO (lo que escriben algunos scripts) tambien vale.
  assert.equal(cardBlocker(ana({ profile: { birthDate: "1990-01-01" } }), AHORA), null);
});

// ---------------------------------------------------------------------------
// C02 / C10: ocultarse del feed no borra la ficha
// ---------------------------------------------------------------------------

test("hiding, pausing, no recommendations and paid incognito keep the card", () => {
  const casos = [
    [ana({ settings: { "privacy.hideProfile": true } }), false, "hidden"],
    [ana({ settings: { "privacy.showInRecommendations": false } }), false, "not_recommended"],
    [ana({ settings: { "privacy.incognito": true } }), true, "incognito"],
  ];
  for (const [data, isPaid, reason] of casos) {
    assert.deepEqual(planPublication(data, isPaid, AHORA), { card: true, listed: false, reason }, reason);
    assert.equal(isDiscoverable(data, isPaid, AHORA), false, reason);
  }
  // Incognito sin plan no surte efecto: sigue en el feed.
  const gratis = ana({ settings: { "privacy.incognito": true } });
  assert.deepEqual(planPublication(gratis, false, AHORA), { card: true, listed: true, reason: null });
});

test("banned, deleted, bots and unfinished onboarding get no card at all", () => {
  assert.equal(planPublication(ana({ isBanned: true }), false, AHORA).card, false);
  assert.equal(planPublication(ana({ isDeleted: true }), false, AHORA).card, false);
  assert.equal(planPublication(ana({ isBot: true }), false, AHORA).card, false);
  assert.equal(planPublication(ana({ profileCompleted: false }), false, AHORA).card, false);
  assert.equal(planPublication(undefined, false, AHORA).card, false);
});

test("the card has the listing shape without geo or filter-only traits", () => {
  const { listing, card } = publicDocsFor("ana", ana(), false, AHORA);
  assert.ok(listing.geo, "el listado del feed sigue llevando geo aproximado");
  assert.equal(listing.filterTraits.religion, "catholic");
  assert.equal(card.displayName, "Ana");
  assert.equal(card.photoUrl, "https://example.test/ana.jpg");
  assert.equal(card.age, 31);
  assert.equal(card.currentCity, "Madrid");
  assert.equal(card.geo, undefined);
  assert.equal(card.filterTraits, undefined);
  assert.equal(card.religion, undefined);
});

test("a paid incognito card hides location and activity, as the setting promises", () => {
  const data = ana({ settings: { "privacy.incognito": true } });
  const { listing, card } = publicDocsFor("ana", data, true, AHORA);
  assert.equal(listing, null);
  assert.equal(card.displayName, "Ana");
  assert.equal(card.currentCity, "");
  assert.equal(card.currentCountryName, "");
  assert.equal(card.countryIso2, undefined);
  assert.equal(card.geo, undefined);
  assert.equal(card.showDistance, false);
  assert.equal(card.showActiveStatus, false);
  // Ocultarse sin incognito NO promete esconder la ciudad.
  const oculta = publicDocsFor("ana", ana({ settings: { "privacy.hideProfile": true } }), false, AHORA);
  assert.equal(oculta.card.currentCity, "Madrid");
});

// ---------------------------------------------------------------------------
// Trigger users/{uid} -> discovery + profileCards
// ---------------------------------------------------------------------------

function writtenEvent(uid, after) {
  return {
    params: { uid },
    data: { after: { exists: after !== undefined, data: () => after } },
  };
}

test("trigger: hiding the profile removes the listing but keeps the card", async () => {
  const { docs } = installFakeFirestore(mock, {
    "discovery/ana": { uid: "ana", displayName: "Ana" },
  });
  await onUserWrittenSyncDiscovery.run(
    writtenEvent("ana", ana({ settings: { "privacy.hideProfile": true } }))
  );
  assert.equal(docs.has("discovery/ana"), false);
  assert.equal(docs.get("profileCards/ana").displayName, "Ana");
  assert.equal(docs.get("profileCards/ana").geo, undefined);
});

test("trigger: a listed user gets both documents", async () => {
  const { docs } = installFakeFirestore(mock, {});
  await onUserWrittenSyncDiscovery.run(writtenEvent("ana", ana()));
  assert.equal(docs.get("discovery/ana").displayName, "Ana");
  assert.equal(docs.get("profileCards/ana").displayName, "Ana");
});

test("trigger: paid incognito keeps a card without location", async () => {
  const { docs } = installFakeFirestore(mock, {
    "discovery/ana": { uid: "ana" },
    "userEntitlements/ana": ENT_PLUS,
  });
  await onUserWrittenSyncDiscovery.run(
    writtenEvent("ana", ana({ settings: { "privacy.incognito": true } }))
  );
  assert.equal(docs.has("discovery/ana"), false);
  assert.equal(docs.get("profileCards/ana").displayName, "Ana");
  assert.equal(docs.get("profileCards/ana").currentCity, "");
});

test("trigger: a minor or a deleted user loses listing and card", async () => {
  const { docs } = installFakeFirestore(mock, {
    "discovery/nina": { uid: "nina" },
    "profileCards/nina": { uid: "nina" },
    "discovery/gone": { uid: "gone" },
    "profileCards/gone": { uid: "gone" },
  });
  await onUserWrittenSyncDiscovery.run(
    writtenEvent("nina", ana({ profile: { birthDate: nacido(2011, 1, 1) } }))
  );
  assert.equal(docs.has("discovery/nina"), false);
  assert.equal(docs.has("profileCards/nina"), false);

  await onUserWrittenSyncDiscovery.run(writtenEvent("gone", undefined));
  assert.equal(docs.has("discovery/gone"), false);
  assert.equal(docs.has("profileCards/gone"), false);
});

// ---------------------------------------------------------------------------
// Backfill (ensayo por defecto)
// ---------------------------------------------------------------------------

/// El fake comun no pagina por __name__ ni tiene getAll: se anaden aqui, solo
/// para este test, leyendo del mismo mapa de documentos.
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
    "users/a_listed": ana(),
    "users/b_hidden": ana({ settings: { "privacy.hideProfile": true } }),
    "users/c_incog": ana({ settings: { "privacy.incognito": true } }),
    "userEntitlements/c_incog": ENT_PLUS,
    "users/d_minor": ana({ profile: { birthDate: nacido(2012, 6, 1) } }),
    "users/e_bot": ana({ isBot: true }),
    // Ficha huerfana de antes: el menor no puede conservarla.
    "discovery/d_minor": { uid: "d_minor" },
  };
}

test("backfill dry run reads and counts without writing anything", async () => {
  const { docs, writes } = installFakeFirestore(mock, backfillWorld());
  installUserPaging(docs);
  const result = await runPublicationBackfill({ dryRun: true, pageSize: 2, nowMs: AHORA });
  assert.equal(writes.length, 0);
  assert.equal(docs.has("discovery/d_minor"), true);
  assert.deepEqual(result, {
    dryRun: true,
    processed: 5,
    published: 1,
    removed: 4,
    cardsPublished: 3,
    cardsRemoved: 2,
    reasons: { hidden: 1, incognito: 1, underage: 1, bot: 1 },
  });
});

test("backfill write mode publishes cards for hidden users and drops minors", async () => {
  const { docs } = installFakeFirestore(mock, backfillWorld());
  installUserPaging(docs);
  const result = await runPublicationBackfill({ dryRun: false, pageSize: 2, nowMs: AHORA });
  assert.equal(result.cardsPublished, 3);
  assert.equal(docs.has("discovery/a_listed"), true);
  assert.equal(docs.has("discovery/b_hidden"), false);
  assert.equal(docs.get("profileCards/b_hidden").displayName, "Ana");
  assert.equal(docs.get("profileCards/c_incog").currentCity, "");
  assert.equal(docs.has("discovery/d_minor"), false);
  assert.equal(docs.has("profileCards/d_minor"), false);
  assert.equal(docs.has("profileCards/e_bot"), false);
});

test("backfill callable: admins only, and a dry run unless told otherwise", async () => {
  const { docs, writes } = installFakeFirestore(mock, backfillWorld());
  installUserPaging(docs);
  await assert.rejects(
    backfillDiscovery.run({ auth: { uid: "cualquiera", token: {} }, data: {} }),
    (e) => e.code === "permission-denied"
  );
  const result = await backfillDiscovery.run({
    auth: { uid: "admin", token: { admin: true } },
    data: {},
  });
  assert.equal(result.dryRun, true);
  assert.equal(writes.length, 0);
});
