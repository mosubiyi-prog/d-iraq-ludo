"use strict";
// Zero production access. All users/accountKeys and places in this file are synthetic.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {
  initializeTestEnvironment, assertFails, assertSucceeds,
} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc, updateDoc, runTransaction, deleteDoc} =
    require("firebase/firestore");

// Read only a known local emulator candidate, never a production endpoint.
const candidateRules = process.env.DEDA_SPARK_RULES_FILE ||
    "firestore.spark.qa.rules";
assert.ok([
  "firestore.spark.qa.rules",
  "firestore.spark.live-preview.rules",
].includes(candidateRules), "SAFE_STOP unknown rules file");
const projectId = "demo-deda-spark-100336";
const placeId = "test_approved_place_100336";
const accountA = "test-account-100336-001";
const accountB = "test-account-100336-002";
let environment;
function reactPath(key=accountA) {
  return ["deda_spark_reactions", placeId, "users", key];
}
function totalsPath() {return ["deda_spark_totals", placeId];}
function ownerDb(uid="owner-a") {
  return environment.authenticatedContext(uid).firestore();
}
async function react(db, kind, enabled, key=accountA) {
  // When concurrent actors update the same aggregate, a stale getAfter
  // security-rules evaluation can report permission-denied before conflict
  // detection. Retry a bounded whole transaction with fresh snapshots;
  // never edit counters without rechecking all rows.
  for (let attempt=0;attempt<4;attempt++) {
    try {
      return await runTransaction(db, async tx => {
    const totalRef=doc(db, ...totalsPath());
    const reactionRef=doc(db, ...reactPath(key));
    // All document reads MUST happen before any transaction writes.
    const [totalSnap, reactionSnap] = await Promise.all([
      tx.get(totalRef),tx.get(reactionRef),
    ]);
    const totals=totalSnap.exists()?totalSnap.data():{followers:0,likes:0};
    const previous=reactionSnap.exists()?reactionSnap.data():
      {following:false,liked:false};
    const field=kind==="follow"?"following":"liked";
    const numberField=kind==="follow"?"followers":"likes";
    if (previous[field]===enabled) return totals;
    const next={...previous,[field]:enabled};
    const counted={
      followers:totals.followers,
      likes:totals.likes,
    };
    counted[numberField]+=(enabled?1:-1);
    tx.set(reactionRef,next);
    tx.set(totalRef,counted);
    return counted;
      });
    } catch (error) {
      if (error.code!=="permission-denied" || attempt===3) throw error;
      await new Promise(resolve => setTimeout(resolve, 40*(attempt+1)));
    }
  }
  throw new Error("unreachable-transaction");
}

test.before(async () => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST || "",
      /^(127\.0\.0\.1|localhost):[0-9]+$/);
  environment=await initializeTestEnvironment({
    projectId,firestore:{
      host:"127.0.0.1",port:8080,
      rules:fs.readFileSync(candidateRules,"utf8"),
    },
  });
  await environment.withSecurityRulesDisabled(async ctx => {
    const db=ctx.firestore();
    for (const [uid,key] of [
      ["owner-a",accountA],["owner-a-rotated",accountA],["viewer-b",accountB],
    ]) {
      await setDoc(doc(db,"users",uid),{accountKey:key});
      await setDoc(doc(db,"deda_sessions",uid),{accountKey:key});
    }
    await setDoc(doc(db,"published_places",placeId),{
      name:"ماركت",published:true,status:"approved",ownerUid:"owner-a",
      accountKey:accountA,isAvailableNow:true,themeIndex:4,latitude:32.4,
      longitude:44.3,
    });
    await setDoc(doc(db,"published_places","test_hidden_place"),{
      published:true,status:"approved",hiddenByManager:true,ownerUid:"owner-a",
      accountKey:accountA,
    });
  });
});
test.after(async () => {
  if(environment)await environment.cleanup();
});

test("Spark cannot touch users, sessions, profile, PIN or administrative data",async () => {
  const db=ownerDb();
  const userBefore=(await getDoc(doc(db,"users","owner-a"))).data();
  const sessionBefore=(await getDoc(doc(db,"deda_sessions","owner-a"))).data();
  const placeBefore=(await getDoc(doc(db,"published_places",placeId))).data();
  await react(db,"follow",true);
  assert.deepEqual((await getDoc(doc(db,"users","owner-a"))).data(),userBefore);
  assert.deepEqual((await getDoc(doc(db,"deda_sessions","owner-a"))).data(),
      sessionBefore);
  assert.deepEqual((await getDoc(doc(db,"published_places",placeId))).data(),
      placeBefore);
});

test("same account UID-rotation is idempotent, second account independent",async () => {
  const a=ownerDb("owner-a"),rotated=ownerDb("owner-a-rotated");
  const b=ownerDb("viewer-b");
  assert.equal((await react(rotated,"follow",true,accountA)).followers,1);
  assert.equal((await react(b,"follow",true,accountB)).followers,2);
  assert.equal((await react(a,"like",true,accountA)).likes,1);
  assert.equal((await react(a,"follow",false,accountA)).followers,1);
  const all=(await getDoc(doc(b,...totalsPath()))).data();
  assert.deepEqual(all,{followers:1,likes:1});
  assert.equal((await getDoc(doc(a,...reactPath(accountA)))).data().liked,true);
  await assertFails(getDoc(doc(b,...reactPath(accountA))));
  await assertFails(getDoc(doc(a,...reactPath(accountB))));
});

test("spoofed totals and reaction-only changes are rejected",async () => {
  const a=ownerDb("owner-a"),b=ownerDb("viewer-b");
  await assertFails(updateDoc(doc(a,...totalsPath()),{followers:500000}));
  await assertFails(setDoc(doc(a,...totalsPath()),
      {followers:999999,likes:999999}));
  await assertFails(setDoc(doc(a,...reactPath(accountA)),
      {following:true,liked:true}));
  await assertFails(setDoc(doc(b,...reactPath(accountA)),
      {following:true,liked:true}));
  await assertFails(deleteDoc(doc(a,...reactPath(accountA))));
});

test("atomic counterfeit increment cannot follow a genuine account transition",async () => {
  const a=ownerDb("owner-a");
  await assertFails(runTransaction(a,async tx=>{
    const rowRef=doc(a,...reactPath(accountA));
    const totalsRef=doc(a,...totalsPath());
    const row=await tx.get(rowRef);
    const totals=await tx.get(totalsRef);
    assert.equal(row.exists(),true);
    tx.set(rowRef,{following:!row.data().following,liked:row.data().liked});
    tx.set(totalsRef,{
      followers:totals.data().followers+888888,
      likes:totals.data().likes,
    });
  }));
  assert.deepEqual((await getDoc(doc(a,...totalsPath()))).data(),
      {followers:1,likes:1});
});

test("concurrent authentic actions are atomic and rotated UID cannot double count",async () => {
  const a=ownerDb("owner-a"),rotated=ownerDb("owner-a-rotated");
  const b=ownerDb("viewer-b");
  await Promise.all([
    react(a,"follow",true,accountA),
    react(b,"like",true,accountB),
  ]);
  let totals=(await getDoc(doc(a,...totalsPath()))).data();
  assert.deepEqual(totals,{followers:2,likes:2});
  await Promise.all([
    react(a,"follow",false,accountA),
    react(rotated,"follow",false,accountA),
  ]);
  totals=(await getDoc(doc(a,...totalsPath()))).data();
  assert.deepEqual(totals,{followers:1,likes:2});
  assert.equal((await getDoc(doc(a,...reactPath(accountA)))).data().following,false);
});

test("palette 0..13 owner only, no changes to name, GPS, requests or presence",async () => {
  const a=ownerDb("owner-a"),b=ownerDb("viewer-b");
  const ref=doc(a,"published_places",placeId);
  const before=(await getDoc(ref)).data();
  for(let color=0;color<14;color++) {
    await assertSucceeds(updateDoc(ref,{themeIndex:color}));
    assert.equal((await getDoc(ref)).data().themeIndex,color);
  }
  await assertFails(updateDoc(doc(b,"published_places",placeId),{themeIndex:0}));
  for(const invalid of [-1,14,1.5,"3"]) {
    await assertFails(updateDoc(ref,{themeIndex:invalid}));
  }
  await assertFails(updateDoc(ref,{name:"fake",themeIndex:1}));
  const after=(await getDoc(ref)).data();
  assert.deepEqual({...after,themeIndex:before.themeIndex},before);
});

test("inactive/hidden places and users without verified session are denied",async () => {
  const a=ownerDb("owner-a"),unverified=ownerDb("unverified");
  await assertFails(updateDoc(doc(a,"published_places","test_hidden_place"),
      {themeIndex:13}));
  await assertFails(setDoc(doc(unverified,...reactPath(accountA)),{
    liked:true, following:true,
  }));
  await assertFails(getDoc(doc(unverified,...reactPath(accountA))));
  await assertFails(setDoc(doc(a,"deda_spark_totals","test_hidden_place"),{
    followers:100,likes:100,
  }));
});

test("legacy Cloud Functions counters remain denied to direct client",async () => {
  const a=ownerDb("owner-a");
  await assertFails(setDoc(doc(a,"deda_place_engagement_totals",placeId),
      {followers:99,likes:99}));
});
