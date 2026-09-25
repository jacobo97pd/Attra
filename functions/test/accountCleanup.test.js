/**
 * C25: borrar la cuenta dejaba likes, matches y chats 'active' (tarjeta
 * fantasma "Alguien" en «Recibidos» y un chat que aceptaba mensajes hacia una
 * cuenta que ya no existe).
 *
 *   cd functions && npm run build && node --test test/accountCleanup.test.js
 */
const { test, afterEach, mock } = require("node:test");
const assert = require("node:assert/strict");
const { installFakeFirestore } = require("./fakeFirestore.js");
const {
  cleanupDeletedAccount,
  onUserDeletedCleanup,
} = require("../lib/accountCleanup.js");
const { sendMessage, sendDateProposal } = require("../lib/chat.js");

afterEach(() => mock.restoreAll());

const GONE = "uid_gone";

test("deleting an account retires its likes, matches and chats (and nothing else)", async () => {
  const { docs } = installFakeFirestore(mock, {
    // Likes que salen de la cuenta borrada y que le llegan.
    [`likes/${GONE}_y`]: { fromUid: GONE, toUid: "y", status: "active" },
    [`likes/${GONE}_z`]: { fromUid: GONE, toUid: "z", status: "matched" },
    [`likes/w_${GONE}`]: { fromUid: "w", toUid: GONE, status: "active" },
    [`likes/v_${GONE}`]: {
      fromUid: "v",
      toUid: GONE,
      status: "cancelled",
      cancelReason: "passed_by_recipient",
    },
    // Ajenos: no se tocan.
    ["likes/y_z"]: { fromUid: "y", toUid: "z", status: "active" },
    // Matches y chats: el activo se retira, el bloqueo se respeta.
    [`matches/${GONE}_z`]: { users: [GONE, "z"], status: "active" },
    [`chats/${GONE}_z`]: { users: [GONE, "z"], status: "active" },
    [`matches/${GONE}_u`]: { users: [GONE, "u"], status: "unmatched" },
    [`chats/${GONE}_u`]: { users: [GONE, "u"], status: "closed" },
    [`matches/b_${GONE}`]: { users: ["b", GONE], status: "blocked" },
    [`chats/b_${GONE}`]: { users: ["b", GONE], status: "blocked" },
    ["matches/y_z"]: { users: ["y", "z"], status: "active" },
    ["chats/y_z"]: { users: ["y", "z"], status: "active" },
  });

  await onUserDeletedCleanup.run({ params: { uid: GONE } });

  for (const path of [`likes/${GONE}_y`, `likes/${GONE}_z`, `likes/w_${GONE}`]) {
    assert.equal(docs.get(path).status, "cancelled", path);
    assert.equal(docs.get(path).cancelReason, "account_deleted", path);
  }
  assert.equal(docs.get(`likes/v_${GONE}`).cancelReason, "passed_by_recipient");
  assert.equal(docs.get("likes/y_z").status, "active");

  assert.equal(docs.get(`matches/${GONE}_z`).status, "deleted");
  assert.equal(docs.get(`matches/${GONE}_z`).deletedReason, "account_deleted");
  assert.equal(docs.get(`chats/${GONE}_z`).status, "deleted");
  assert.equal(docs.get(`matches/${GONE}_u`).status, "unmatched");
  assert.equal(docs.get(`chats/${GONE}_u`).status, "deleted");
  assert.equal(docs.get(`matches/b_${GONE}`).status, "blocked");
  assert.equal(docs.get(`chats/b_${GONE}`).status, "blocked");
  assert.equal(docs.get("matches/y_z").status, "active");
  assert.equal(docs.get("chats/y_z").status, "active");
  // Evidencia intacta: solo cambia el estado.
  assert.deepEqual(docs.get(`chats/${GONE}_z`).users, [GONE, "z"]);
});

test("cleanup pages through large inboxes and is idempotent", async () => {
  const initial = {};
  for (let i = 0; i < 650; i++) {
    const from = `fan${String(i).padStart(4, "0")}`;
    initial[`likes/${from}_${GONE}`] = { fromUid: from, toUid: GONE, status: "active" };
  }
  const { docs } = installFakeFirestore(mock, initial);

  const first = await cleanupDeletedAccount(GONE);
  assert.deepEqual(first, { likes: 650, matches: 0, chats: 0 });
  assert.ok([...docs.values()].every((d) => d.status === "cancelled"));

  const again = await cleanupDeletedAccount(GONE);
  assert.deepEqual(again, { likes: 0, matches: 0, chats: 0 });
});

// Defensa en el envio: datos viejos (cuentas borradas antes del trigger) o la
// ventana hasta que la limpieza termina.
function chatWith(receiverDoc, extra = {}) {
  return {
    "users/me": {},
    ...(receiverDoc ? { "users/other": receiverDoc } : {}),
    ["chats/me_other"]: { users: ["me", "other"], status: "active", matchId: "me_other" },
    ["matches/me_other"]: { users: ["me", "other"], status: "active" },
    ...extra,
  };
}
const messagesOf = (docs) =>
  [...docs.keys()].filter((p) => p.startsWith("chats/me_other/messages/"));

test("a chat whose other side deleted the account no longer accepts messages", async () => {
  const { docs } = installFakeFirestore(mock, chatWith(null));
  await assert.rejects(
    sendMessage.run({ auth: { uid: "me" }, data: { chatId: "me_other", text: "¿hola?" } }),
    { code: "failed-precondition" }
  );
  await assert.rejects(
    sendDateProposal.run({
      auth: { uid: "me" },
      data: {
        chatId: "me_other",
        proposedDate: "2026-10-01",
        proposedTime: "20:00",
        placeName: "Bar",
      },
    }),
    { code: "failed-precondition" }
  );
  assert.equal(messagesOf(docs).length, 0);
});

test("banned or soft-deleted receivers are not reachable either", async () => {
  for (const receiver of [{ isBanned: true }, { isDeleted: true }]) {
    const { docs } = installFakeFirestore(mock, chatWith(receiver));
    await assert.rejects(
      sendMessage.run({ auth: { uid: "me" }, data: { chatId: "me_other", text: "hola" } }),
      { code: "failed-precondition" }
    );
    assert.equal(messagesOf(docs).length, 0);
    mock.restoreAll();
  }
});

test("real users and seed profiles still receive messages", async () => {
  const real = installFakeFirestore(mock, chatWith({}));
  await sendMessage.run({ auth: { uid: "me" }, data: { chatId: "me_other", text: "hola" } });
  assert.equal(messagesOf(real.docs).length, 1);
  mock.restoreAll();

  // Los bots del feed no tienen users/{uid}, solo seed_profiles/{uid}.
  const seed = installFakeFirestore(mock, chatWith(null, { "seed_profiles/other": {} }));
  await sendMessage.run({ auth: { uid: "me" }, data: { chatId: "me_other", text: "hola" } });
  assert.equal(messagesOf(seed.docs).length, 1);
});
