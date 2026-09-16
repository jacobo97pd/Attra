const { test, afterEach, mock } = require("node:test");
const assert = require("node:assert/strict");
const { db } = require("../lib/firebase.js");
const { col } = require("../lib/common.js");
const { applyBlock, createReport } = require("../lib/safety.js");
const { onMatchCreated } = require("../lib/notifications.js");
const { rankingOnMatch } = require("../lib/ranking.js");
const { DocumentReference } = require("firebase-admin/firestore");

afterEach(() => mock.restoreAll());

function captureTransaction(existing = {}) {
  const docs = new Map(Object.entries(existing));
  mock.method(db, "runTransaction", async (fn) => {
    const tx = {
      getAll: async (...refs) => refs.map((ref) => ({
        ref,
        exists: docs.has(ref.path),
        data: () => docs.get(ref.path),
      })),
      set: (ref, value, options) => {
        docs.set(ref.path, options?.merge
          ? { ...docs.get(ref.path), ...value } : value);
        return tx;
      },
      update: (ref, value) => {
        assert.ok(docs.has(ref.path), "only update existing evidence");
        docs.set(ref.path, { ...docs.get(ref.path), ...value });
        return tx;
      },
    };
    return fn(tx);
  });
  return docs;
}

test("block before matching excludes both people and creates no fake likes", async () => {
  const docs = captureTransaction();
  await applyBlock("z", "a");
  assert.deepEqual(docs.get("matches/a_z").users, ["a", "z"]);
  assert.equal(docs.get("matches/a_z").status, "blocked");
  assert.equal(docs.get("chats/a_z").status, "blocked");
  assert.equal(docs.get("blocks/z_a").blockedUid, "a");
  assert.equal(docs.has("likes/a_z"), false);
  assert.equal(docs.has("likes/z_a"), false);
});

test("blocking cancels both pending likes and preserves moderation evidence", async () => {
  const docs = captureTransaction({
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
  const docs = captureTransaction();
  await assert.rejects(applyBlock("a", "a"), { code: "invalid-argument" });
  assert.equal(docs.size, 0);
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
