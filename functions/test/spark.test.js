/**
 * C31: applyBlock deja matches/{par} con `users` y status 'blocked' aunque el
 * par nunca hiciera match. Spark solo miraba la pertenencia, asi que el
 * BLOQUEADO podia retar (push a quien le bloqueo) o publicar su propio texto
 * como mensaje de sistema en ese chat.
 *
 *   cd functions && npm run build && node --test test/spark.test.js
 *
 * La mitad de reglas (firestore.rules) la prueba sparkRules.test.js contra el
 * emulador.
 */
const { test, afterEach, mock } = require("node:test");
const assert = require("node:assert/strict");
const { installFakeFirestore } = require("./fakeFirestore.js");
const { completeSparkSession } = require("../lib/spark.js");
const { onSparkSessionCreated } = require("../lib/notifications.js");

afterEach(() => mock.restoreAll());

const A = "uid_a"; // quien bloquea
const B = "uid_b"; // bloqueado
const PAIR = `${A}_${B}`;
const SESSION = `matches/${PAIR}/sparkSessions/icebreaker_v1`;

function state({ match = "active", chat = "active", block = false, session = {} } = {}) {
  return {
    [`users/${A}`]: { profile: { displayName: "Ana" } },
    [`users/${B}`]: { profile: { displayName: "Bea" } },
    [`users/uid_c`]: { profile: { displayName: "Carla" } },
    [`matches/${PAIR}`]: { status: match, users: [A, B] },
    [`chats/${PAIR}`]: { status: chat, users: [A, B] },
    ...(block ? { [`blocks/${A}_${B}`]: { blockerUid: A, blockedUid: B } } : {}),
    [SESSION]: {
      userAId: B,
      userBId: A,
      status: "completed",
      summary: { chatLine: "texto inyectado" },
      ...session,
    },
  };
}

const complete = (uid) =>
  completeSparkSession.run({
    auth: { uid },
    data: { matchId: PAIR, sessionId: "icebreaker_v1" },
  });
const systemMessages = (docs) =>
  [...docs.keys()].filter((p) => p.startsWith(`chats/${PAIR}/messages/`));

test("the blocked person cannot post a Spark summary into the blocker's chat", async () => {
  const { docs } = installFakeFirestore(mock, state({ match: "blocked", chat: "blocked", block: true }));
  await assert.rejects(complete(B), { code: "failed-precondition" });
  assert.equal(systemMessages(docs).length, 0);
  assert.equal(docs.get(`chats/${PAIR}`).lastMessage, undefined);
});

test("unmatched, closed or deleted matches do not accept a Spark summary", async () => {
  for (const match of ["unmatched", "closed", "deleted"]) {
    const { docs } = installFakeFirestore(mock, state({ match }));
    await assert.rejects(complete(B), { code: "failed-precondition" }, match);
    assert.equal(systemMessages(docs).length, 0);
    mock.restoreAll();
  }
});

test("an old graceful close (chat closed, match still active) is respected", async () => {
  const { docs } = installFakeFirestore(mock, state({ chat: "closed" }));
  await assert.rejects(complete(A), { code: "failed-precondition" });
  assert.equal(systemMessages(docs).length, 0);
});

test("a block doc wins even if the match merge has not landed yet", async () => {
  const { docs } = installFakeFirestore(mock, state({ block: true }));
  await assert.rejects(complete(B), { code: "permission-denied" });
  assert.equal(systemMessages(docs).length, 0);
});

test("only a player of that session can publish it", async () => {
  const { docs } = installFakeFirestore(
    mock,
    state({ session: { userAId: "uid_c", userBId: A } })
  );
  await assert.rejects(complete(B), { code: "permission-denied" });
  assert.equal(systemMessages(docs).length, 0);
});

test("an active match still gets its Spark summary", async () => {
  const { docs } = installFakeFirestore(
    mock,
    state({ session: { summary: { chatLine: "Habéis coincidido en 3 de 5" } } })
  );
  assert.deepEqual(await complete(A), { ok: true });
  const msg = docs.get(`chats/${PAIR}/messages/spark_icebreaker_v1`);
  assert.equal(msg.type, "system");
  assert.equal(msg.text, "Habéis coincidido en 3 de 5");
  assert.equal(docs.get(`matches/${PAIR}`).journeyStatus, "game_completed");
});

// onSparkSessionCreated ------------------------------------------------------

const created = (data) =>
  onSparkSessionCreated.run({
    data: { data: () => data },
    params: { matchId: PAIR, sessionId: "icebreaker_v1" },
  });
const inbox = (docs, uid) =>
  [...docs.keys()]
    .filter((p) => p.startsWith(`notifications/${uid}/items/`))
    .map((p) => docs.get(p));

test("a challenge from the blocked person never reaches the blocker", async () => {
  const { docs } = installFakeFirestore(mock, state({ match: "blocked", block: true }));
  await created({ userAId: B, userBId: A, invitedBy: B, status: "waiting" });
  assert.equal(inbox(docs, A).length, 0);
});

test("a challenge on a non-active match, or with a block doc, is not notified", async () => {
  for (const s of [{ match: "unmatched" }, { match: "closed" }, { block: true }]) {
    const { docs } = installFakeFirestore(mock, state(s));
    await created({ userAId: B, userBId: A, status: "waiting" });
    assert.equal(inbox(docs, A).length, 0, JSON.stringify(s));
    mock.restoreAll();
  }
});

test("the challenge names userAId, never a spoofed invitedBy", async () => {
  const { docs } = installFakeFirestore(mock, state());
  await created({ userAId: B, userBId: A, invitedBy: "uid_c", status: "waiting" });
  const items = inbox(docs, A);
  assert.equal(items.length, 1);
  assert.equal(items[0].kind, "spark_challenge");
  assert.equal(items[0].title, "Bea te ha retado");
  assert.equal(items[0].data.matchId, PAIR);
});
