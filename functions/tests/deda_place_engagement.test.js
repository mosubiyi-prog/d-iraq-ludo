"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const engagement = require("../deda_place_engagement");

class FakeDoc {
  constructor(store, key) {
    this.store = store;
    this.key = key;
  }
  collection(name) {
    return new FakeCollection(this.store, this.key + "/" + name);
  }
  async get() {
    const item = this.store.get(this.key);
    return {
      exists: item !== undefined,
      data: () => item,
    };
  }
}
class FakeCollection {
  constructor(store, key) {
    this.store = store;
    this.key = key;
  }
  doc(name) {
    return new FakeDoc(this.store, this.key + "/" + name);
  }
}
class FakeDB {
  constructor() {
    this.store = new Map();
  }
  collection(name) {
    return new FakeCollection(this.store, name);
  }
  async runTransaction(work) {
    const writes = [];
    const result = await work({
      get: (ref) => ref.get(),
      set: (ref, data, opts) => {
        writes.push({ref, data, merge: opts?.merge === true});
      },
    });
    for (const w of writes) {
      const old = this.store.get(w.ref.key) || {};
      this.store.set(w.ref.key, w.merge ? {...old, ...w.data} : w.data);
    }
    return result;
  }
}

function seeded() {
  const db = new FakeDB();
  db.store.set("published_places/approved_place_01", {
    published: true, status: "approved",
  });
  db.store.set("deda_sessions/uid1", {accountKey: "9647000000001"});
  db.store.set("users/uid1", {accountKey: "9647000000001"});
  db.store.set("deda_sessions/uid2", {accountKey: "9647000000001"});
  db.store.set("users/uid2", {accountKey: "9647000000001"});
  return db;
}

test("idempotent follow, account-stable across UIDs, like is independent", async () => {
  const db = seeded();
  const args = {placeId: "approved_place_01", uid: "uid1"};
  let state = await engagement.setPlaceEngagement(db, {
    ...args, kind: "follow", active: true,
  });
  assert.deepEqual(state, {following: true, liked: false, followers: 1, likes: 0});

  state = await engagement.setPlaceEngagement(db, {
    placeId: args.placeId, uid: "uid2", kind: "follow", active: true,
  });
  assert.equal(state.followers, 1);
  state = await engagement.setPlaceEngagement(db, {
    ...args, kind: "like", active: true,
  });
  assert.equal(state.following, true);
  assert.equal(state.liked, true);
  assert.equal(state.followers, 1);
  assert.equal(state.likes, 1);

  state = await engagement.setPlaceEngagement(db, {
    ...args, kind: "follow", active: false,
  });
  assert.equal(state.followers, 0);
  assert.equal(state.likes, 1);
  assert.equal(state.liked, true);
});

test("session mismatch, unpublished place and malicious input are denied", async () => {
  const db = seeded();
  db.store.set("users/uid1", {accountKey: "a different account"});
  await assert.rejects(() => engagement.setPlaceEngagement(db, {
    placeId: "approved_place_01", uid: "uid1", kind: "like", active: true,
  }), /verified-session-required/);
  await assert.rejects(() => engagement.setPlaceEngagement(db, {
    placeId: "../bad-place", uid: "uid2", kind: "follow", active: true,
  }), /invalid-place-id/);
  db.store.set("published_places/approved_place_01", {published: false});
  await assert.rejects(() => engagement.readPlaceEngagement(db, {
    placeId: "approved_place_01", uid: "uid2",
  }), /place-not-published/);
});

test("count without personal data exposed", async () => {
  const db = seeded();
  const result = await engagement.readPlaceEngagement(db, {
    placeId: "approved_place_01", uid: "",
  });
  assert.deepEqual(result, {following: false, liked: false, followers: 0, likes: 0});
  assert.equal(Object.keys(result).includes("accountKey"), false);
});


// Heartbeat stage 1: regression tests only. FakeDB does not prove contention
// safety; a Firestore Emulator transaction test is required before LIVE.

test("unauthenticated writes and malformed reactions leave totals unchanged", async () => {
  const db = seeded();
  const before = [...db.store.entries()].map(([key, value]) => [key, {...value}]);
  for (const input of [
    {uid: "", kind: "follow", active: true},
    {uid: "not-a-verified-session", kind: "like", active: true},
    {uid: "uid1", kind: "boost", active: true},
    {uid: "uid1", kind: "follow", active: "true"},
  ]) {
    await assert.rejects(() => engagement.setPlaceEngagement(db, {
      placeId: "approved_place_01",
      ...input,
    }));
  }
  assert.deepEqual(
    [...db.store.entries()].map(([key, value]) => [key, {...value}]),
    before,
  );
});

test("hidden or deleted places never accept reads or reactions", async () => {
  for (const state of [
    {published: true, hiddenByManager: true},
    {published: true, deleted: true},
    {published: true, status: "deleted"},
    {published: false, status: "pending"},
  ]) {
    const db = seeded();
    db.store.set("published_places/approved_place_01", state);
    await assert.rejects(() => engagement.readPlaceEngagement(db, {
      placeId: "approved_place_01", uid: "uid1",
    }), /place-not-published/);
    await assert.rejects(() => engagement.setPlaceEngagement(db, {
      placeId: "approved_place_01", uid: "uid1",
      kind: "follow", active: true,
    }), /place-not-published/);
    assert.equal(db.store.has("deda_place_engagement_totals/approved_place_01"), false);
  }
});

test("multiple follow and unfollow retries do not inflate or underflow totals", async () => {
  const db = seeded();
  const args = {placeId: "approved_place_01", uid: "uid1", kind: "follow"};
  for (let i = 0; i < 4; i++) {
    const value = await engagement.setPlaceEngagement(db, {...args, active: true});
    assert.equal(value.followers, 1);
  }
  for (let i = 0; i < 4; i++) {
    const value = await engagement.setPlaceEngagement(db, {...args, active: false});
    assert.equal(value.followers, 0);
  }
  const fromAnonymousRead = await engagement.readPlaceEngagement(db, {
    placeId: "approved_place_01", uid: "",
  });
  assert.equal(fromAnonymousRead.followers, 0);
  assert.equal(fromAnonymousRead.following, false);
});

test("untrusted corrupt negative totals are never displayed as negative", async () => {
  const db = seeded();
  db.store.set("deda_place_engagement_totals/approved_place_01", {
    followers: -200, likes: "99999",
  });
  const summary = await engagement.readPlaceEngagement(db, {
    placeId: "approved_place_01", uid: "",
  });
  assert.equal(summary.followers, 0);
  assert.equal(summary.likes, 0);
});
