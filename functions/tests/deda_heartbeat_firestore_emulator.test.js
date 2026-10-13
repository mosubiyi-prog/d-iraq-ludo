"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {
  initializeTestEnvironment, assertFails, assertSucceeds,
} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc, updateDoc, serverTimestamp} =
  require("firebase/firestore");

const projectId = "demo-deda-heartbeat-rules";
let environment;
const placeId = "approved_place_01";
const ownerKey = "9647700000001";

test.before(async () => {
  // This test must NEVER connect to production. Require an explicit emulator.
  assert.match(process.env.FIRESTORE_EMULATOR_HOST || "",
      /^(127\.0\.0\.1|localhost):[0-9]+$/);
  environment = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: "127.0.0.1", port: 8080,
      rules: fs.readFileSync("firestore.rules", "utf8"),
    },
  });
  await environment.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await Promise.all([
      setDoc(doc(db, "users", "u-owner"), {accountKey: ownerKey}),
      setDoc(doc(db, "deda_sessions", "u-owner"), {accountKey: ownerKey}),
      setDoc(doc(db, "users", "u-other"), {accountKey: "9647700000002"}),
      setDoc(doc(db, "deda_sessions", "u-other"), {accountKey: "9647700000002"}),
      setDoc(doc(db, "published_places", placeId), {
        ownerUid: "u-owner", accountKey: ownerKey, published: true,
        status: "approved", themeIndex: 4, isAvailableNow: false,
      }),
      setDoc(doc(db, "owner_place_notifications",
          "heartbeat_approval_approved_place_01"), {
        type: "approved", accountKey: ownerKey, ownerUid: "u-owner",
        createdAt: new Date(),
      }),
      setDoc(doc(db, "deda_place_engagement_totals", placeId),
          {followers: 10, likes: 3}),
      setDoc(doc(db, "deda_place_engagement", placeId, "users", "actor-hash"),
          {following: true, liked: true}),
    ]);
  });
});
test.after(async () => {
  if (environment) await environment.cleanup();
});

test("owner can read/mark own approval bell; another account cannot", async () => {
  const owner=environment.authenticatedContext("u-owner").firestore();
  const other=environment.authenticatedContext("u-other").firestore();
  const path=["owner_place_notifications", "heartbeat_approval_approved_place_01"];
  await assertSucceeds(getDoc(doc(owner, ...path)));
  await assertFails(getDoc(doc(other, ...path)));
  await assertSucceeds(updateDoc(doc(owner, ...path), {readAt: serverTimestamp()}));
  await assertFails(updateDoc(doc(other, ...path), {readAt: serverTimestamp()}));
});
test("clients cannot spoof an approved notice", async () => {
  const owner=environment.authenticatedContext("u-owner").firestore();
  await assertFails(setDoc(doc(owner, "owner_place_notifications", "fake-approval"),{
    type:"approved", ownerUid:"u-owner", accountKey:ownerKey,
  }));
});
test("no client can forge following totals or another person's reactions", async () => {
  for (const uid of ["u-owner", "u-other"]) {
    const user=environment.authenticatedContext(uid).firestore();
    await assertFails(getDoc(doc(user, "deda_place_engagement_totals", placeId)));
    await assertFails(setDoc(doc(user, "deda_place_engagement_totals", placeId),
        {followers: 2000000,likes:9999999}));
    await assertFails(setDoc(
        doc(user, "deda_place_engagement", placeId, "users", "actor-hash"),
        {following:false,liked:false}));
  }
});
test("public colour cannot be overwritten through direct client Firestore writes", async () => {
  const owner=environment.authenticatedContext("u-owner").firestore();
  await assertFails(updateDoc(doc(owner, "published_places", placeId),
      {themeIndex: 13, updatedAt: serverTimestamp()}));
});

test("actual Firestore transactions survive concurrent follow/like without duplicates", async () => {
  // Explicit emulator-only guard protects against writing any live account.
  assert.match(process.env.FIRESTORE_EMULATOR_HOST || "",
      /^(127\\.0\\.0\\.1|localhost):[0-9]+$/);
  const {initializeApp, deleteApp} = require("firebase-admin/app");
  const {getFirestore} = require("firebase-admin/firestore");
  const {setPlaceEngagement, readPlaceEngagement} =
      require("../deda_place_engagement.js");
  const racePlace="race_place_01";
  const ids=["race-user-1","race-user-2","race-user-3"];
  await environment.withSecurityRulesDisabled(async (ctx) => {
    const db=ctx.firestore();
    const writes=[
      setDoc(doc(db,"published_places",racePlace),{
        published:true,status:"approved",hiddenByManager:false,
      }),
    ];
    for(let i=0;i<ids.length;i++) {
      const key="96477000001"+String(i);
      writes.push(setDoc(doc(db,"deda_sessions",ids[i]),{accountKey:key}));
      writes.push(setDoc(doc(db,"users",ids[i]),{accountKey:key}));
    }
    await Promise.all(writes);
  });
  const app=initializeApp({projectId},"heartbeat-emulator-count-test");
  try {
    const db=getFirestore(app);
    await Promise.all(ids.map(uid=>setPlaceEngagement(db,{
      placeId:racePlace,uid,kind:"follow",active:true,
    })));
    const count=await readPlaceEngagement(db,{placeId:racePlace,uid:ids[0]});
    assert.equal(count.followers,3);
    assert.equal(count.following,true);
    await Promise.all([
      setPlaceEngagement(db,{placeId:racePlace,uid:ids[0],kind:"follow",active:true}),
      setPlaceEngagement(db,{placeId:racePlace,uid:ids[1],kind:"like",active:true}),
      setPlaceEngagement(db,{placeId:racePlace,uid:ids[2],kind:"like",active:true}),
    ]);
    const again=await readPlaceEngagement(db,{placeId:racePlace,uid:ids[1]});
    assert.equal(again.followers,3);
    assert.equal(again.likes,2);
    assert.equal(again.following,true);
    assert.equal(again.liked,true);
  } finally {
    await deleteApp(app);
  }
});
