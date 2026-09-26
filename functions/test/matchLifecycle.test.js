/**
 * Ciclo de vida del match: que un match cerrado siga cerrado.
 *
 *   cd functions && npm run build && node --test test/matchLifecycle.test.js
 *
 * Cubre los fallos de backend_safety sobre likes/Attras/cierre:
 *  - C07: tras un unmatch, un like o un Attra hecho a mano reabria el match y
 *    el chat que la otra persona habia cerrado (y cobraba el like/Attra).
 *  - C41: «Cerrar con elegancia» dejaba el match 'active' (pestaña Matches con
 *    un "Enviar mensaje" hacia un chat cerrado).
 *  - C40/C43: sendAttra leia el tier en crudo y un Plus caducado seguia
 *    comentando.
 *  - C39: "Le gustas a alguien" tambien para likes que ya nacian 'matched'.
 *  - Revision: tras un unmatch (o bloqueo, o cuenta borrada) la marcha atras
 *    dejaba "deshacer" el like que hizo match: borraba el doc y devolvia el
 *    like del dia y el Attra Swipe de pago.
 */
const { test, afterEach, mock } = require("node:test");
const assert = require("node:assert/strict");
const { installFakeFirestore } = require("./fakeFirestore.js");
const { sendLike } = require("../lib/likes.js");
const { sendAttra, attraCommentFields } = require("../lib/attras.js");
const { unmatch, applyBlock } = require("../lib/safety.js");
const { rewindFeedAction } = require("../lib/rewind.js");
const { cleanupDeletedAccount } = require("../lib/accountCleanup.js");
const { closeConversationGracefully } = require("../lib/chat.js");
const { replyToStory } = require("../lib/stories.js");
const { onLikeCreated } = require("../lib/notifications.js");
const { moderateComment } = require("../lib/moderation.js");

afterEach(() => mock.restoreAll());

const A = "uid_a";
const B = "uid_b";
const PAIR = `${A}_${B}`;
const DAY = 24 * 3600 * 1000;

/// A y B con match activo: likes 'matched', match y chat 'active'.
function matchedPair(extra = {}) {
  return {
    [`users/${A}`]: { profile: { displayName: "Ana" } },
    [`users/${B}`]: { profile: { displayName: "Bea" } },
    [`matches/${PAIR}`]: { status: "active", users: [A, B] },
    [`chats/${PAIR}`]: { status: "active", users: [A, B], matchId: PAIR },
    [`likes/${A}_${B}`]: { status: "matched", fromUid: A, toUid: B, type: "like" },
    [`likes/${B}_${A}`]: { status: "matched", fromUid: B, toUid: A, type: "like" },
    [`attraWallets/${B}`]: { balance: 3 },
    ...extra,
  };
}

const likeWrites = (writes, path) => writes.filter((w) => w.path === path);

test("C07: after an unmatch, a hand-made like cannot reopen the match", async () => {
  const { docs, writes } = installFakeFirestore(mock, matchedPair());
  await unmatch.run({ auth: { uid: A }, data: { matchId: PAIR } });
  const before = writes.length;

  const res = await sendLike.run({ auth: { uid: B }, data: { toUid: A } });

  assert.deepEqual(res, { outcome: "blocked" });
  assert.equal(docs.get(`matches/${PAIR}`).status, "unmatched");
  assert.equal(docs.get(`chats/${PAIR}`).status, "closed");
  // Nada escrito: ni like, ni consumo del cupo diario.
  assert.equal(writes.length, before);
});

test("C07: after an unmatch, an Attra cannot reopen the match nor charge", async () => {
  const { docs, writes } = installFakeFirestore(mock, matchedPair());
  await unmatch.run({ auth: { uid: A }, data: { matchId: PAIR } });
  const before = writes.length;

  const res = await sendAttra.run({ auth: { uid: B }, data: { toUid: A } });

  assert.deepEqual(res, { outcome: "blocked" });
  assert.equal(docs.get(`attraWallets/${B}`).balance, 3);
  assert.equal(docs.get(`chats/${PAIR}`).status, "closed");
  assert.equal(writes.length, before);
});

test("C07: even with the likes still 'matched' (old data), a closed match is terminal", async () => {
  // Datos de antes del arreglo: unmatch no cancelaba los likes.
  const { docs } = installFakeFirestore(
    mock,
    matchedPair({
      [`matches/${PAIR}`]: { status: "unmatched", users: [A, B] },
      [`chats/${PAIR}`]: { status: "closed", users: [A, B] },
    })
  );
  assert.deepEqual(
    await sendLike.run({ auth: { uid: B }, data: { toUid: A } }),
    { outcome: "blocked" }
  );
  assert.deepEqual(
    await sendAttra.run({ auth: { uid: B }, data: { toUid: A } }),
    { outcome: "blocked" }
  );
  assert.equal(docs.get(`matches/${PAIR}`).status, "unmatched");
  assert.equal(docs.get(`likes/${B}_${A}`).status, "matched");
});

test("an active match still answers 'matched' and a fresh mutual like still matches", async () => {
  installFakeFirestore(mock, matchedPair());
  assert.deepEqual(
    await sendLike.run({ auth: { uid: B }, data: { toUid: A } }),
    { outcome: "matched", matchId: PAIR, chatId: PAIR }
  );
  mock.restoreAll();

  // Sin match previo y con el like inverso pendiente: el match se crea.
  const { docs } = installFakeFirestore(mock, {
    [`users/${A}`]: {},
    [`users/${B}`]: {},
    [`likes/${A}_${B}`]: { status: "active", fromUid: A, toUid: B, type: "like" },
  });
  const res = await sendLike.run({ auth: { uid: B }, data: { toUid: A } });
  assert.equal(res.outcome, "matched");
  assert.equal(docs.get(`matches/${PAIR}`).status, "active");
  assert.equal(docs.get(`chats/${PAIR}`).status, "active");
});

test("C41: closing gracefully closes the match too, and it stays closed", async () => {
  const { docs } = installFakeFirestore(mock, matchedPair());
  await closeConversationGracefully.run({
    auth: { uid: A },
    data: { chatId: PAIR, reason: "no_connection", message: "Gracias, suerte" },
  });
  assert.equal(docs.get(`chats/${PAIR}`).status, "closed");
  assert.equal(docs.get(`matches/${PAIR}`).status, "closed");
  assert.equal(docs.get(`matches/${PAIR}`).closedByUserId, A);
  assert.equal(docs.get(`matches/${PAIR}`).journeyStatus, "archived");

  assert.deepEqual(
    await sendLike.run({ auth: { uid: B }, data: { toUid: A } }),
    { outcome: "blocked" }
  );
  assert.equal(docs.get(`matches/${PAIR}`).status, "closed");
});

test("C07 (stories): replying to a story of someone you unmatched is refused before any write", async () => {
  const { docs, writes } = installFakeFirestore(
    mock,
    matchedPair({
      [`stories/s1`]: { ownerUid: A, status: "active" },
    })
  );
  await unmatch.run({ auth: { uid: A }, data: { matchId: PAIR } });
  const before = writes.length;
  await assert.rejects(
    replyToStory.run({
      auth: { uid: B },
      data: { storyId: "s1", text: "hola", asAttra: true },
    }),
    { code: "permission-denied" }
  );
  assert.equal(writes.length, before);
  assert.equal(docs.get(`attraWallets/${B}`).balance, 3);
});

test("C40: the Attra comment gate uses the EFFECTIVE tier", () => {
  const mod = moderateComment("me encanta tu foto");
  const expired = { tier: "plus", expiresAt: new Date(Date.now() - DAY) };
  const valid = { tier: "plus", expiresAt: new Date(Date.now() + DAY) };
  const lifetime = { tier: "pro", isLifetime: true, expiresAt: new Date(0) };

  assert.deepEqual(attraCommentFields(expired, mod), { cmtStatus: "none", cmtText: null });
  assert.deepEqual(attraCommentFields(undefined, mod), { cmtStatus: "none", cmtText: null });
  assert.deepEqual(attraCommentFields({ tier: "legacy?" }, mod), {
    cmtStatus: "none",
    cmtText: null,
  });
  assert.deepEqual(attraCommentFields(valid, mod), {
    cmtStatus: "approved",
    cmtText: "me encanta tu foto",
  });
  assert.deepEqual(attraCommentFields(lifetime, mod), {
    cmtStatus: "approved",
    cmtText: "me encanta tu foto",
  });
});

test("C40: an expired Plus sending an Attra with a comment gets it dropped", async () => {
  const { docs } = installFakeFirestore(mock, {
    [`users/${A}`]: {},
    [`users/${B}`]: {},
    [`attraWallets/${B}`]: { balance: 2 },
    [`userEntitlements/${B}`]: {
      tier: "plus",
      expiresAt: new Date(Date.now() - DAY),
    },
  });
  const res = await sendAttra.run({
    auth: { uid: B },
    data: { toUid: A, commentText: "hola guapa" },
  });
  assert.equal(res.outcome, "liked");
  const like = docs.get(`likes/${B}_${A}`);
  assert.equal(like.type, "attra");
  assert.equal(like.commentText, null);
  assert.equal(like.commentStatus, "none");
  assert.equal(like.senderTier, "free");
});

// C39 ------------------------------------------------------------------------

function likeEvent(data) {
  return { data: { data: () => data }, params: { likeId: `${data.fromUid}_${data.toUid}` } };
}
const inbox = (docs, uid) =>
  [...docs.keys()].filter((p) => p.startsWith(`notifications/${uid}/items/`));

test("C39: a like that was born 'matched' does not send 'Le gustas a alguien'", async () => {
  const { docs } = installFakeFirestore(mock, { [`users/${A}`]: {}, [`users/${B}`]: {} });
  await onLikeCreated.run(likeEvent({ fromUid: B, toUid: A, status: "matched", type: "like" }));
  await onLikeCreated.run(likeEvent({ fromUid: B, toUid: A, status: "matched", type: "attra" }));
  assert.equal(inbox(docs, A).length, 0);
});

test("C39: a pending like (or a legacy one with no status) still notifies", async () => {
  const { docs } = installFakeFirestore(mock, { [`users/${A}`]: {}, [`users/${B}`]: {} });
  await onLikeCreated.run(likeEvent({ fromUid: B, toUid: A, status: "active", type: "like" }));
  await onLikeCreated.run(likeEvent({ fromUid: B, toUid: A, type: "like" }));
  const items = inbox(docs, A).map((p) => docs.get(p));
  assert.equal(items.length, 2);
  assert.ok(items.every((n) => n.kind === "new_like" && n.data.fromUid === B));
});

test("C47: a like that lands right after a block does not reappear in the bell", async () => {
  const { docs } = installFakeFirestore(mock, {
    [`users/${A}`]: {},
    [`users/${B}`]: {},
    [`blocks/${A}_${B}`]: { blockerUid: A, blockedUid: B },
  });
  await onLikeCreated.run(likeEvent({ fromUid: B, toUid: A, status: "active", type: "attra" }));
  assert.equal(inbox(docs, A).length, 0);
});

// Marcha atras sobre un par cerrado ------------------------------------------

const USAGE_DAY = "20260926";
const usagePath = `users/${A}/usage/likes_${USAGE_DAY}`;

/// A es Plus y su like a B se pago con un Attra Swipe y conto en el cupo de
/// hoy: lo que un rewind indebido devolveria.
function paidLike(extra = {}) {
  return {
    [`userEntitlements/${A}`]: { tier: "plus", expiresAt: new Date(Date.now() + DAY) },
    [usagePath]: { count: 5 },
    ...extra,
  };
}

const rewind = (uid, targetUid, action) =>
  rewindFeedAction.run({ auth: { uid }, data: { targetUid, action } });

test("C07/rewind: after an unmatch, the like that made the match cannot be undone nor refunded", async () => {
  const { docs, writes } = installFakeFirestore(
    mock,
    matchedPair(
      paidLike({
        [`likes/${A}_${B}`]: {
          status: "matched",
          fromUid: A,
          toUid: B,
          type: "like",
          consumedSwipe: true,
          usageKey: USAGE_DAY,
          commentText: "me encanta tu foto",
        },
      })
    )
  );
  await unmatch.run({ auth: { uid: A }, data: { matchId: PAIR } });
  assert.equal(docs.get(`likes/${A}_${B}`).cancelReason, "unmatched");
  const before = writes.length;

  await assert.rejects(rewind(A, B, "like"), { code: "failed-precondition" });

  // Ni se borra el like (ni su comentario) ni se devuelve nada.
  assert.equal(writes.length, before);
  assert.equal(docs.get(`likes/${A}_${B}`).commentText, "me encanta tu foto");
  assert.equal(docs.get(usagePath).count, 5);
  assert.equal(docs.get(`users/${A}`).wallet, undefined);
});

test("C07/rewind: a block or an account deletion also closes the rewind (like and pass)", async () => {
  // B bloquea a A despues de que A le diera like y le pasara: el pase no puede
  // "deshacerse" para devolverle a A la tarjeta de quien le bloqueo.
  const { docs, writes } = installFakeFirestore(
    mock,
    paidLike({
      [`users/${A}`]: {},
      [`users/${B}`]: {},
      [`likes/${A}_${B}`]: {
        status: "active",
        fromUid: A,
        toUid: B,
        type: "like",
        consumedSwipe: true,
        usageKey: USAGE_DAY,
      },
      [`dislikes/${A}_${B}`]: { fromUid: A, toUid: B },
    })
  );
  await applyBlock(B, A);
  const before = writes.length;
  await assert.rejects(rewind(A, B, "like"), { code: "failed-precondition" });
  await assert.rejects(rewind(A, B, "pass"), {
    code: "failed-precondition",
    // Mismo texto neutro: no delata el bloqueo.
    message: "Este gesto ya no se puede deshacer.",
  });
  assert.equal(writes.length, before);
  assert.equal(docs.get(usagePath).count, 5);
  mock.restoreAll();

  // Cuenta borrada con match: el match queda 'deleted' y sigue siendo terminal.
  const deleted = installFakeFirestore(
    mock,
    matchedPair(
      paidLike({
        [`likes/${A}_${B}`]: {
          status: "matched",
          fromUid: A,
          toUid: B,
          type: "like",
          consumedSwipe: true,
          usageKey: USAGE_DAY,
        },
      })
    )
  );
  await cleanupDeletedAccount(B);
  assert.equal(deleted.docs.get(`matches/${PAIR}`).status, "deleted");
  await assert.rejects(rewind(A, B, "like"), { code: "failed-precondition" });
  assert.ok(deleted.docs.has(`likes/${A}_${B}`));
  assert.equal(deleted.docs.get(usagePath).count, 5);
});

test("C07/rewind: a like cancelled by an account deletion without a match stays put", async () => {
  const { docs } = installFakeFirestore(
    mock,
    paidLike({
      [`likes/${A}_${B}`]: {
        status: "active",
        fromUid: A,
        toUid: B,
        type: "like",
        consumedSwipe: true,
        usageKey: USAGE_DAY,
      },
    })
  );
  await cleanupDeletedAccount(B);
  assert.equal(docs.get(`likes/${A}_${B}`).cancelReason, "account_deleted");
  assert.equal(docs.has(`matches/${PAIR}`), false);

  await assert.rejects(rewind(A, B, "like"), { code: "failed-precondition" });
  assert.ok(docs.has(`likes/${A}_${B}`));
  assert.equal(docs.get(usagePath).count, 5);
});

test("C07/rewind: a plain like with no match is still undone and refunded", async () => {
  const { docs, writes } = installFakeFirestore(
    mock,
    paidLike({
      [`users/${A}`]: {},
      [`likes/${A}_${B}`]: {
        status: "active",
        fromUid: A,
        toUid: B,
        type: "like",
        consumedSwipe: true,
        usageKey: USAGE_DAY,
      },
    })
  );
  assert.deepEqual(await rewind(A, B, "like"), { ok: true, rewound: true });
  assert.equal(docs.has(`likes/${A}_${B}`), false);
  assert.equal(docs.get(usagePath).count, 4);
  assert.ok(writes.some((w) => w.path === `users/${A}` && w.value.wallet));
});
