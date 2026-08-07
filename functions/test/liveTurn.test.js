/**
 * Tests de la generacion de credenciales TURN efimeras (functions/src/liveTurn.ts).
 *
 * COMO SE EJECUTAN (el proyecto no tiene runner de JS: se usa el de Node 20+):
 *
 *   cd functions && npm run build && node --test test/liveTurn.test.js
 *
 * Se prueban contra la salida COMPILADA (`lib/`) a proposito: es exactamente el
 * codigo que se despliega, y asi el test no necesita ni transpilador ni
 * dependencias nuevas.
 *
 * QUE SE VERIFICA Y POR QUE: el HMAC y la caducidad son el contrato con coturn.
 * Si el username deja de ser "<expiry>:<uid>" o el digest deja de ser
 * base64(HMAC-SHA1) el rele rechaza TODAS las conexiones, y el sintoma en la
 * app es identico a no tener TURN: llamadas que se quedan "conectando". Es un
 * fallo que no se ve en pruebas de sobremesa, de ahi que se fije aqui. Nada de
 * esto necesita red ni Firebase.
 */
const { test } = require("node:test");
const assert = require("node:assert");
const { createHmac } = require("node:crypto");

const {
  buildTurnGrant,
  clampTurnTtlSeconds,
  parseTurnUrls,
  sanitizeTurnUid,
  turnCredential,
  turnUsername,
  LIVE_TURN_DEFAULT_TTL_SECONDS,
  LIVE_TURN_MIN_TTL_SECONDS,
  LIVE_TURN_MAX_TTL_SECONDS,
} = require("../lib/liveTurn.js");

const SECRET = "secreto-de-prueba-no-usado-en-produccion";
/** 2026-01-01T00:00:00Z, para que la caducidad sea comprobable a mano. */
const NOW_MS = 1767225600000;

test("username = '<caducidad_unix>:<uid>'", () => {
  assert.strictEqual(turnUsername("abc123", 1767232800), "1767232800:abc123");
});

test("credential = base64(HMAC-SHA1(username, secreto))", () => {
  const username = "1767232800:abc123";
  // Referencia calculada aparte con el mismo algoritmo que aplica coturn.
  const expected = createHmac("sha1", SECRET).update(username).digest("base64");
  assert.strictEqual(turnCredential(username, SECRET), expected);
  // base64 de un SHA-1 (20 bytes) -> 28 caracteres con un '=' de relleno.
  assert.strictEqual(expected.length, 28);
  assert.ok(expected.endsWith("="));
});

test("el HMAC depende del secreto: otro secreto, otra credencial", () => {
  const username = "1767232800:abc123";
  assert.notStrictEqual(
    turnCredential(username, SECRET),
    turnCredential(username, SECRET + "x")
  );
});

test("la caducidad sale de now + ttl y viaja dentro del username", () => {
  const grant = buildTurnGrant({
    uid: "abc123",
    secret: SECRET,
    urls: ["turn:turn.example.com:3478?transport=udp"],
    ttlSeconds: 3600,
    nowMs: NOW_MS,
  });

  const expiryUnix = NOW_MS / 1000 + 3600;
  assert.strictEqual(grant.username, `${expiryUnix}:abc123`);
  assert.strictEqual(grant.expiresAtMs, expiryUnix * 1000);
  assert.strictEqual(grant.ttlSeconds, 3600);
  // Y el par username/credential tiene que validar con el secreto: es lo que
  // hara coturn al autenticar.
  assert.strictEqual(
    grant.credential,
    createHmac("sha1", SECRET).update(grant.username).digest("base64")
  );
});

test("dos emisiones separadas en el tiempo dan credenciales distintas", () => {
  const first = buildTurnGrant({
    uid: "abc123",
    secret: SECRET,
    urls: ["turn:turn.example.com:3478"],
    nowMs: NOW_MS,
  });
  const second = buildTurnGrant({
    uid: "abc123",
    secret: SECRET,
    urls: ["turn:turn.example.com:3478"],
    nowMs: NOW_MS + 60_000,
  });
  assert.notStrictEqual(first.username, second.username);
  assert.notStrictEqual(first.credential, second.credential);
});

test("el TTL se recorta a [1 h, 4 h] y la basura cae al valor por defecto", () => {
  assert.strictEqual(clampTurnTtlSeconds(60), LIVE_TURN_MIN_TTL_SECONDS);
  assert.strictEqual(clampTurnTtlSeconds(999999), LIVE_TURN_MAX_TTL_SECONDS);
  assert.strictEqual(clampTurnTtlSeconds("7200"), 7200);
  assert.strictEqual(clampTurnTtlSeconds(undefined), LIVE_TURN_DEFAULT_TTL_SECONDS);
  assert.strictEqual(clampTurnTtlSeconds("no-es-un-numero"), LIVE_TURN_DEFAULT_TTL_SECONDS);
  assert.strictEqual(clampTurnTtlSeconds(-1), LIVE_TURN_DEFAULT_TTL_SECONDS);
});

test("un uid con ':' no puede romper el parseo de la caducidad", () => {
  // coturn parte por el PRIMER ':': si el uid colara uno, el resto se
  // desplazaria y el HMAC dejaria de validar.
  assert.strictEqual(sanitizeTurnUid("ab:cd"), "abcd");
  const grant = buildTurnGrant({
    uid: "ab:cd",
    secret: SECRET,
    urls: ["turn:turn.example.com:3478"],
    ttlSeconds: 3600,
    nowMs: NOW_MS,
  });
  assert.strictEqual(grant.username.split(":").length, 2);
});

test("solo se aceptan URLs turn:/turns:, sin duplicados", () => {
  const urls = parseTurnUrls(
    " turn:a.example.com:3478?transport=udp , turns:a.example.com:5349 ," +
      "stun:no.example.com:19302,turn:a.example.com:3478?transport=udp,,basura"
  );
  assert.deepStrictEqual(urls, [
    "turn:a.example.com:3478?transport=udp",
    "turns:a.example.com:5349",
  ]);
  assert.deepStrictEqual(parseTurnUrls(undefined), []);
  assert.deepStrictEqual(parseTurnUrls(""), []);
});
