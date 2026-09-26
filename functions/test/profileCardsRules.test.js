/**
 * C02 / C10 (reglas): profileCards/{uid} es la ficha por uid de quien NO sale
 * en el feed (perfil oculto, cuenta pausada, sin recomendaciones, incognito).
 * La leen el dueno, su match ACTIVO y las personas a las que el dueno dio like
 * (lo que promete el incognito: "Solo te ven las personas a las que tu has
 * dado like"). Nadie mas, nadie la escribe y no se puede listar.
 *
 * Necesita el EMULADOR de Firestore; sin el, se salta (la suite normal
 * `node --test test/*.test.js` no depende de Java ni de la CLI). Desde la raiz:
 *
 *   firebase emulators:exec --only firestore --project demo-attra \
 *     "node --test functions/test/profileCardsRules.test.js"
 *
 * Mismo mecanismo que sparkRules.test.js: API REST del emulador, reglas del
 * repo cargadas en attra-database, siembra como `owner` y lectura con un ID
 * token sin firmar.
 */
const { test, before, beforeEach } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const HOST = process.env.FIRESTORE_EMULATOR_HOST;
const PROJECT = process.env.GCLOUD_PROJECT || "demo-attra";
const DB = "attra-database";
const skip = HOST ? false : "sin FIRESTORE_EMULATOR_HOST (emulador apagado)";
const DOCS = `http://${HOST}/v1/projects/${PROJECT}/databases/${DB}/documents`;

// uid_a < uid_b: el match del par es matches/uid_a_uid_b (pairId).
const A = "uid_a"; // dueno de la ficha oculta (incognito)
const B = "uid_b";
const C = "uid_c";

function idToken(uid) {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const now = Math.floor(Date.now() / 1000);
  return `${b64({ alg: "none", typ: "JWT" })}.${b64({
    iss: `https://securetoken.google.com/${PROJECT}`,
    aud: PROJECT,
    sub: uid,
    user_id: uid,
    iat: now,
    exp: now + 3600,
    auth_time: now,
    firebase: { sign_in_provider: "custom", identities: {} },
  })}.`;
}

function encode(value) {
  if (value === null) return { nullValue: null };
  if (typeof value === "string") return { stringValue: value };
  if (typeof value === "number") return { integerValue: String(value) };
  if (typeof value === "boolean") return { booleanValue: value };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(encode) } };
  return { mapValue: { fields: fields(value) } };
}
function fields(obj) {
  return Object.fromEntries(Object.entries(obj).map(([k, v]) => [k, encode(v)]));
}

const auth = (uid) => ({
  Authorization: `Bearer ${uid === "owner" ? "owner" : idToken(uid)}`,
});

async function write(uid, docPath, data) {
  const res = await fetch(`${DOCS}/${docPath}`, {
    method: "PATCH",
    headers: { ...auth(uid), "Content-Type": "application/json" },
    body: JSON.stringify({ fields: fields(data) }),
  });
  return res.status;
}

async function read(uid, docPath) {
  const res = await fetch(`${DOCS}/${docPath}`, { headers: auth(uid) });
  return res.status;
}

async function seed(docPath, data) {
  assert.equal(await write("owner", docPath, data), 200, docPath);
}

const card = (uid) => ({ uid, displayName: `Perfil ${uid}`, photoUrl: "x" });

before(async () => {
  if (skip) return;
  const rules = fs.readFileSync(
    path.join(__dirname, "..", "..", "firestore.rules"),
    "utf8"
  );
  const res = await fetch(
    `http://${HOST}/emulator/v1/projects/${PROJECT}/databases/${DB}:securityRules`,
    {
      method: "PUT",
      body: JSON.stringify({
        rules: { files: [{ name: "firestore.rules", content: rules }] },
      }),
    }
  );
  assert.equal(res.status, 200, await res.text());
});

beforeEach(async () => {
  if (skip) return;
  await fetch(
    `http://${HOST}/emulator/v1/projects/${PROJECT}/databases/${DB}/documents`,
    { method: "DELETE" }
  );
  await seed(`profileCards/${A}`, card(A));
  await seed(`profileCards/${B}`, card(B));
});

test("the owner reads their own card", { skip }, async () => {
  assert.equal(await read(A, `profileCards/${A}`), 200);
});

test("incognito: whoever A liked can see A and answer the like", { skip }, async () => {
  await seed(`likes/${A}_${B}`, { fromUid: A, toUid: B, status: "active" });
  assert.equal(await read(B, `profileCards/${A}`), 200);
});

test("liking someone does not unlock their hidden card", { skip }, async () => {
  // C da like a A (a mano, conociendo su uid): A no le ha dado like a C.
  await seed(`likes/${C}_${A}`, { fromUid: C, toUid: A, status: "active" });
  assert.equal(await read(C, `profileCards/${A}`), 403);
  // Un desconocido sin relacion tampoco.
  assert.equal(await read(C, `profileCards/${B}`), 403);
});

test("a cancelled like (passed or rewound) no longer grants access", { skip }, async () => {
  await seed(`likes/${A}_${B}`, {
    fromUid: A,
    toUid: B,
    status: "cancelled",
    cancelReason: "passed_by_recipient",
  });
  assert.equal(await read(B, `profileCards/${A}`), 403);
});

test("an active match sees each other, whatever the uid order", { skip }, async () => {
  await seed(`matches/${A}_${B}`, { users: [A, B], status: "active" });
  assert.equal(await read(B, `profileCards/${A}`), 200); // lector > dueno
  assert.equal(await read(A, `profileCards/${B}`), 200); // lector < dueno
});

test("blocked, unmatched, closed or deleted pairs lose access even with likes left", { skip }, async () => {
  await seed(`likes/${A}_${B}`, { fromUid: A, toUid: B, status: "active" });
  for (const status of ["blocked", "unmatched", "closed", "deleted"]) {
    await seed(`matches/${A}_${B}`, { users: [A, B], status });
    assert.equal(await read(B, `profileCards/${A}`), 403, status);
    assert.equal(await read(A, `profileCards/${B}`), 403, status);
  }
});

test("nobody writes cards and the collection cannot be listed", { skip }, async () => {
  await seed(`matches/${A}_${B}`, { users: [A, B], status: "active" });
  assert.equal(await write(A, `profileCards/${A}`, card(A)), 403);
  assert.equal(await write(B, `profileCards/${A}`, card(A)), 403);
  assert.equal(await read(A, "profileCards"), 403);
});

test("signed-out requests are denied", { skip }, async () => {
  const res = await fetch(`${DOCS}/profileCards/${A}`);
  assert.equal(res.status, 403);
});
