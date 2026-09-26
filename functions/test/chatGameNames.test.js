/**
 * Nombres del veredicto del "Duelo de Quimica" (functions/src/chatGame.ts).
 *
 *   cd functions && npm run build && node --test test/chatGameNames.test.js
 *
 * QUE FALLABA: `resolveNames` solo miraba discovery y seed_profiles. Quien
 * esta oculto del feed (perfil oculto, cuenta pausada, incognito) no tiene
 * listado en discovery, asi que el resultado del duelo le llamaba "Alguien"
 * aunque su match le veia el nombre en el chat (el cliente ya caia a
 * profileCards). Ahora sigue el mismo orden que el cliente.
 */
const { test, afterEach, mock } = require("node:test");
const assert = require("node:assert/strict");
const { installFakeFirestore } = require("./fakeFirestore.js");
const { resolveNames } = require("../lib/chatGame.js");

afterEach(() => mock.restoreAll());

test("un match oculto del feed se nombra por su ficha de profileCards", async () => {
  installFakeFirestore(mock, {
    "discovery/ana": { displayName: "Ana" },
    // Oculta: sin listado, solo ficha por uid.
    "profileCards/bea": { displayName: " Bea " },
  });
  assert.deepEqual(await resolveNames({}, "ana", "bea"), { a: "Ana", b: "Bea" });
});

test("mismo orden que el cliente: discovery, seed_profiles y profileCards", async () => {
  installFakeFirestore(mock, {
    "discovery/ana": { displayName: "Ana (feed)" },
    "profileCards/ana": { displayName: "Ana (ficha)" },
    "seed_profiles/mock_t_ines": { displayName: "Ines" },
  });
  assert.deepEqual(await resolveNames({}, "ana", "mock_t_ines"), {
    a: "Ana (feed)",
    b: "Ines",
  });
});

test("sin ninguna ficha (o sin nombre) sigue siendo 'Alguien'", async () => {
  installFakeFirestore(mock, { "profileCards/sin_nombre": { displayName: "  " } });
  assert.deepEqual(await resolveNames({}, "nadie", "sin_nombre"), {
    a: "Alguien",
    b: "Alguien",
  });
});
