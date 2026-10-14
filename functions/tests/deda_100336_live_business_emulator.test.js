"use strict";
// Genuine Firestore Emulator transaction tests. NEVER run against production.
const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");
const {readPlaceEngagement, setPlaceEngagement} =
  require("../deda_place_engagement.js");
const {setPlaceTheme} = require("../deda_place_branding.js");

const host = process.env.FIRESTORE_EMULATOR_HOST || "";
assert.match(host, /^(localhost|127\.0\.0\.1):[0-9]+$/,
    "SAFE_STOP: refusing real Firestore connections");
const projectId = "demo-deda-heartbeat-rules";
admin.initializeApp({projectId});
const db = admin.firestore();
const id = "approved_place_100336";

test.before(async () => {
  const initial = {
    published: true, ownerUid: "uid1", accountKey: "account-1",
    name: "ماركت", status: "approved", latitude: 33.1,
    longitude: 44.1, isAvailableNow: true, themeIndex: 4,
  };
  await db.collection("published_places").doc(id).set(initial);
  for (const [uid, key] of [
    ["uid1", "account-1"], ["uid1-rotated", "account-1"],
    ["uid2", "account-2"],
  ]) {
    await db.collection("users").doc(uid).set({accountKey: key});
    await db.collection("deda_sessions").doc(uid).set({accountKey: key});
  }
});

test.after(async () => {
  await admin.app().delete();
});

test("two genuine accounts + rotated UID: exactly two follows, no duplicate", async () => {
  const [one, second] = await Promise.all([
    setPlaceEngagement(db, {placeId: id, uid: "uid1", kind: "follow", active: true}),
    setPlaceEngagement(db, {placeId: id, uid: "uid2", kind: "follow", active: true}),
  ]);
  assert.ok(one.followers >= 1 && second.followers >= 1);
  const rotated = await setPlaceEngagement(db, {
    placeId: id, uid: "uid1-rotated", kind: "follow", active: true,
  });
  assert.equal(rotated.followers, 2);
  const twice = await setPlaceEngagement(db, {
    placeId: id, uid: "uid1", kind: "follow", active: true,
  });
  assert.equal(twice.followers, 2);
  const like = await setPlaceEngagement(db, {
    placeId: id, uid: "uid1", kind: "like", active: true,
  });
  assert.equal(like.followers, 2);
  assert.equal(like.likes, 1);
  const seenBySecond = await readPlaceEngagement(db, {
    placeId: id, uid: "uid2",
  });
  assert.equal(seenBySecond.followers, 2);
  assert.equal(seenBySecond.following, true);
  assert.equal(seenBySecond.liked, false);
  const reverse = await setPlaceEngagement(db, {
    placeId: id, uid: "uid1-rotated", kind: "follow", active: false,
  });
  assert.equal(reverse.followers, 1);
  const afterRead = await readPlaceEngagement(db, {placeId: id, uid: "uid1"});
  assert.equal(afterRead.following, false);
  assert.equal(afterRead.likes, 1);
});

test("only current verified owner changes place theme 0..13, no other fields", async () => {
  const ref = db.collection("published_places").doc(id);
  const before = (await ref.get()).data();
  for (let themeIndex = 0; themeIndex < 14; themeIndex++) {
    const result = await setPlaceTheme(db, {uid: "uid1", placeId: id, themeIndex});
    assert.equal(result.themeIndex, themeIndex);
    assert.equal((await ref.get()).get("themeIndex"), themeIndex);
  }
  await assert.rejects(
      () => setPlaceTheme(db, {uid: "uid2", placeId: id, themeIndex: 4}),
      /published-owner-place-required/);
  await assert.rejects(
      () => setPlaceTheme(db, {uid: "uid1", placeId: id, themeIndex: 14}),
      /invalid-place-theme/);
  const after = (await ref.get()).data();
  assert.deepEqual({...after, themeIndex: before.themeIndex}, before);
});
