const { test, afterEach, mock } = require("node:test");
const assert = require("node:assert/strict");
const { col } = require("../lib/common.js");
const { applyBlock, createReport, unmatch } = require("../lib/safety.js");
const { onMatchCreated } = require("../lib/notifications.js");
const {
  countDistinctReport,
  rankingOnMatch,
  rankingOnReport,
} = require("../lib/ranking.js");
const { DocumentReference, Query } = require("firebase-admin/firestore");
const { installFakeFirestore } = require("./fakeFirestore.js");

afterEach(() => mock.restoreAll());

test("block before matching excludes both people and creates no fake likes", async () => {
  const { docs } = installFakeFirestore(mock);
  await applyBlock("z", "a");
  assert.deepEqual(docs.get("matches/a_z").users, ["a", "z"]);
  assert.equal(docs.get("matches/a_z").status, "blocked");
  assert.equal(docs.get("chats/a_z").status, "blocked");
  assert.equal(docs.get("blocks/z_a").blockedUid, "a");
  assert.equal(docs.has("likes/a_z"), false);
  assert.equal(docs.has("likes/z_a"), false);
});

test("blocking cancels both pending likes and preserves moderation evidence", async () => {
  const { docs } = installFakeFirestore(mock, {
    "likes/z_a": { status: "active", commentText: "evidence one" },
    "likes/a_z": { status: "active", commentText: "evidence two" },
    "matches/a_z": { status: "active", source: "like" },
    "chats/a_z": { status: "active", users: ["a", "z"] },
  });
  await applyBlock("z", "a");
  for (const path of ["likes/z_a", "likes/a_z"]) {
    assert.equal(docs.get(path).status, "cancelled");
    assert.equal(docs.get(path).cancelReason, "blocked");
  }
  assert.equal(docs.get("likes/z_a").commentText, "evidence one");
  assert.equal(docs.get("matches/a_z").source, "like");
  assert.deepEqual(docs.get("chats/a_z").users, ["a", "z"]);
  await applyBlock("z", "a");
  assert.equal(docs.get("matches/a_z").status, "blocked");
});

test("self blocking is rejected before a write", async () => {
  const { docs, writes } = installFakeFirestore(mock);
  await assert.rejects(applyBlock("a", "a"), { code: "invalid-argument" });
  assert.equal(docs.size, 0);
  assert.equal(writes.length, 0);
});

// C06/C15/C16 (parte backend): la «segunda vuelta» resta los descartados del
// conjunto excluido; un descarte que sobrevivia al bloqueo devolvia al
// bloqueado (o a quien te bloqueo) al feed.
test("blocking deletes the passes in BOTH directions", async () => {
  const { docs } = installFakeFirestore(mock, {
    "dislikes/z_a": { fromUid: "z", toUid: "a" },
    "dislikes/a_z": { fromUid: "a", toUid: "z", source: "live_report" },
    "dislikes/z_other": { fromUid: "z", toUid: "other" },
  });
  await applyBlock("z", "a");
  assert.equal(docs.has("dislikes/z_a"), false);
  assert.equal(docs.has("dislikes/a_z"), false);
  // Solo los del par: el resto de descartes no se toca.
  assert.equal(docs.has("dislikes/z_other"), true);
});

// C47: la campana de quien bloquea seguia enseñando "B te ha escrito" con el
// texto del mensaje. Se limpian las dos bandejas por las tres claves.
test("blocking removes the pair's notifications from both inboxes, and only those", async () => {
  const { docs } = installFakeFirestore(mock, {
    "notifications/z/items/msg": { kind: "new_message", data: { chatId: "a_z" } },
    "notifications/z/items/match": { kind: "new_match", data: { matchId: "a_z" } },
    "notifications/z/items/attra": { kind: "attra_received", data: { fromUid: "a" } },
    "notifications/z/items/spark": { kind: "spark_challenge", data: { matchId: "a_z" } },
    "notifications/z/items/keep": { kind: "new_message", data: { chatId: "b_z" } },
    "notifications/z/items/keepLike": { kind: "new_like", data: { fromUid: "b" } },
    "notifications/z/items/comeBack": { kind: "come_back", data: {} },
    "notifications/a/items/msg": { kind: "new_message", data: { chatId: "a_z" } },
    "notifications/a/items/like": { kind: "new_like", data: { fromUid: "z" } },
    "notifications/a/items/keep": { kind: "new_like", data: { fromUid: "c" } },
  });
  await applyBlock("z", "a");
  const left = [...docs.keys()].filter((p) => p.startsWith("notifications/")).sort();
  assert.deepEqual(left, [
    "notifications/a/items/keep",
    "notifications/z/items/comeBack",
    "notifications/z/items/keep",
    "notifications/z/items/keepLike",
  ]);
});

test("a failing inbox cleanup never undoes or fails the block", async () => {
  const { docs } = installFakeFirestore(mock);
  mock.method(Query.prototype, "where", () => {
    throw new Error("index missing");
  });
  const logged = mock.method(console, "error", () => {});
  await applyBlock("z", "a");
  assert.equal(docs.get("blocks/z_a").blockedUid, "a");
  assert.equal(docs.get("matches/a_z").status, "blocked");
  assert.equal(logged.mock.callCount(), 1);
});

// C07: tras un unmatch los likes seguian 'matched' y contaban como intencion
// viva para reabrir el match con un like hecho a mano.
test("unmatch closes match and chat and cancels both likes", async () => {
  const { docs } = installFakeFirestore(mock, {
    "matches/a_z": { status: "active", users: ["a", "z"] },
    "chats/a_z": { status: "active", users: ["a", "z"] },
    "likes/a_z": { status: "matched", fromUid: "a", toUid: "z" },
    "likes/z_a": { status: "matched", fromUid: "z", toUid: "a" },
  });
  const res = await unmatch.run({ auth: { uid: "a" }, data: { matchId: "a_z" } });
  assert.deepEqual(res, { ok: true });
  assert.equal(docs.get("matches/a_z").status, "unmatched");
  assert.equal(docs.get("chats/a_z").status, "closed");
  for (const path of ["likes/a_z", "likes/z_a"]) {
    assert.equal(docs.get(path).status, "cancelled");
    assert.equal(docs.get(path).cancelReason, "unmatched");
    assert.equal(docs.get(path).cancelledBy, "a");
  }
});

test("unmatch keeps an earlier cancellation reason", async () => {
  const { docs } = installFakeFirestore(mock, {
    "matches/a_z": { status: "active", users: ["a", "z"] },
    "likes/a_z": {
      status: "cancelled",
      cancelReason: "passed_by_recipient",
      cancelledBy: "z",
    },
  });
  await unmatch.run({ auth: { uid: "z" }, data: { matchId: "a_z" } });
  assert.equal(docs.get("likes/a_z").cancelReason, "passed_by_recipient");
  assert.equal(docs.get("likes/a_z").cancelledBy, "z");
});

test("unmatch never downgrades a block nor resurrects a deleted account's chat", async () => {
  for (const status of ["blocked", "deleted"]) {
    const { docs } = installFakeFirestore(mock, {
      "matches/a_z": { status, users: ["a", "z"] },
      "chats/a_z": { status },
    });
    await unmatch.run({ auth: { uid: "a" }, data: { matchId: "a_z" } });
    assert.equal(docs.get("matches/a_z").status, status);
    assert.equal(docs.get("chats/a_z").status, status);
    mock.restoreAll();
  }
});

test("only a participant can unmatch", async () => {
  const { writes } = installFakeFirestore(mock, {
    "matches/a_z": { status: "active", users: ["a", "z"] },
  });
  await assert.rejects(
    unmatch.run({ auth: { uid: "intruso" }, data: { matchId: "a_z" } }),
    { code: "permission-denied" }
  );
  assert.equal(writes.length, 0);
});

test("a report keeps the exact story and conversation for moderation", async () => {
  let saved;
  mock.method(col.reports, "doc", () => ({
    id: "report-test",
    set: async (data) => { saved = data; },
  }));
  const id = await createReport({
    reporterUid: "me", reportedUid: "other", reason: "inappropriate",
    storyId: "story-42", chatId: "me_other",
  });
  assert.equal(id, "report-test");
  assert.equal(saved.storyId, "story-42");
  assert.equal(saved.chatId, "me_other");
  assert.equal(saved.status, "pending");
});

// C46: se contaban documentos de reporte, no personas: una sola persona
// pulsando "Reportar" cinco veces hundia el trustSafety de otra en todos los
// feeds.
test("repeated reports from the same person count once; distinct people count each", async () => {
  const { docs, writes } = installFakeFirestore(mock);
  const report = (reporterUid) =>
    rankingOnReport.run({
      data: { data: () => ({ reporterUid, reportedUid: "victima" }) },
      params: { reportId: `r-${Math.random()}` },
    });
  for (let i = 0; i < 5; i++) await report("rencoroso");
  await report("otra");
  const increments = writes.filter(
    (w) => w.path === "rankingSignals/victima" && "reportsCount" in w.value
  );
  assert.equal(increments.length, 2);
  assert.ok(docs.has("rankingSignals/victima/reporters/rencoroso"));
  assert.ok(docs.has("rankingSignals/victima/reporters/otra"));
});

test("a report with no reporter, or a self report, never counts", async () => {
  const { writes } = installFakeFirestore(mock);
  assert.equal(await countDistinctReport("victima", ""), false);
  assert.equal(await countDistinctReport("victima", "victima"), false);
  assert.equal(await countDistinctReport("", "alguien"), false);
  assert.equal(writes.length, 0);
});

test("blocked pairs never produce match notifications or ranking increments", async () => {
  const read = mock.method(DocumentReference.prototype, "get", async () => ({
    exists: false,
    data: () => ({}),
  }));
  const write = mock.method(DocumentReference.prototype, "set", async () => {});
  const event = {
    data: { data: () => ({ status: "blocked", users: ["a", "z"] }) },
    params: { matchId: "a_z" },
  };
  await onMatchCreated.run(event);
  await rankingOnMatch.run(event);
  assert.equal(read.mock.callCount(), 0);
  assert.equal(write.mock.callCount(), 0);
});

test("active matches still increment ranking for both participants", async () => {
  const paths = [];
  mock.method(DocumentReference.prototype, "set", async function () {
    paths.push(this.path);
  });
  await rankingOnMatch.run({
    data: { data: () => ({ status: "active", users: ["a", "z"] }) },
    params: { matchId: "a_z" },
  });
  assert.deepEqual(paths.sort(), ["rankingSignals/a", "rankingSignals/z"]);
});
