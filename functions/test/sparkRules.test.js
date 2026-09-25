/**
 * C31 (reglas): las sesiones de Attra Spark solo se escriben en un match
 * ACTIVO. applyBlock deja matches/{par} con `users` y status 'blocked' aunque
 * nunca hubiera match, y las reglas solo miraban la pertenencia: el BLOQUEADO
 * podia crear un reto (push a quien le bloqueo) o cerrar una sesion con texto
 * propio.
 *
 * Necesita el EMULADOR de Firestore; sin el, se salta (la suite normal
 * `node --test test/*.test.js` no depende de Java ni de la CLI). Desde la raiz:
 *
 *   firebase emulators:exec --only firestore --project demo-attra \
 *     "node --test functions/test/sparkRules.test.js"
 *
 * Habla con la API REST del emulador (sin SDK de cliente, que el proyecto no
 * tiene): carga firestore.rules del repo en attra-database (da igual con que
 * reglas arrancara el emulador), siembra como `owner` (se salta las reglas) y
 * escribe como usuario con un ID token sin firmar, que el emulador acepta.
 */
const { test, before, beforeEach } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const HOST = process.env.FIRESTORE_EMULATOR_HOST;
const PROJECT = process.env.GCLOUD_PROJECT || "demo-attra";
const DB = "attra-database";
const skip = HOST ? false : "sin FIRESTORE_EMULATOR_HOST (emulador apagado)";

const A = "uid_a";
const B = "uid_b";
const PAIR = `${A}_${B}`;
const DOCS = `http://${HOST}/v1/projects/${PROJECT}/databases/${DB}/documents`;

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

async function write(uid, docPath, data) {
  const res = await fetch(`${DOCS}/${docPath}`, {
    method: "PATCH",
    headers: {
      Authorization: `Bearer ${uid === "owner" ? "owner" : idToken(uid)}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ fields: fields(data) }),
  });
  return res.status;
}

const SESSION = `matches/${PAIR}/sparkSessions/icebreaker_v1`;
const waiting = { userAId: B, userBId: A, invitedBy: B, status: "waiting" };

async function seedMatch(status) {
  assert.equal(await write("owner", `matches/${PAIR}`, { users: [A, B], status }), 200);
}

before(async () => {
  if (skip) return;
  const rules = fs.readFileSync(
    path.join(__dirname, "..", "..", "firestore.rules"),
    "utf8"
  );
  // Endpoint POR BASE DE DATOS: el de proyecto (`projects/x:securityRules`)
  // contesta 200 pero no toca attra-database, y el test acabaria probando las
  // reglas con las que arranco el emulador en vez de las del repo.
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
});

test("a participant of an ACTIVE match can still create and play a session", { skip }, async () => {
  await seedMatch("active");
  assert.equal(await write(B, SESSION, waiting), 200);
  assert.equal(
    await write(A, SESSION, { ...waiting, status: "active", currentRound: 1 }),
    200
  );
});

test("the blocked person cannot create a challenge on the blocked pair", { skip }, async () => {
  await seedMatch("blocked");
  assert.equal(await write(B, SESSION, waiting), 403);
});

test("unmatched and closed pairs cannot create sessions either", { skip }, async () => {
  for (const status of ["unmatched", "closed", "deleted"]) {
    await seedMatch(status);
    assert.equal(await write(B, SESSION, waiting), 403, status);
  }
});

test("a running session freezes once the pair is blocked", { skip }, async () => {
  await seedMatch("active");
  assert.equal(await write(B, SESSION, waiting), 200);
  await seedMatch("blocked");
  assert.equal(
    await write(B, SESSION, {
      ...waiting,
      status: "completed",
      summary: { chatLine: "texto inyectado" },
    }),
    403
  );
});

test("a session cannot be born completed or carrying a summary", { skip }, async () => {
  await seedMatch("active");
  assert.equal(await write(B, SESSION, { ...waiting, status: "completed" }), 403);
  assert.equal(
    await write(B, SESSION, { ...waiting, summary: { chatLine: "x" } }),
    403
  );
});

test("outsiders still cannot write, even on an active match", { skip }, async () => {
  await seedMatch("active");
  assert.equal(
    await write("uid_c", SESSION, { ...waiting, userAId: "uid_c" }),
    403
  );
});
