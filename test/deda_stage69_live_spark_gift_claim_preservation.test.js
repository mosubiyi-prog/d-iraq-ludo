"use strict";
// Stage69: preserve REAL deployed policy's genuine user gift-claim path after
// removing only unreceipted gift-wallet debits and adding atomic 5k checkout.
// Uses synthetic emulator records and a temporary published-rules-derived
// candidate. Never connects to production Firestore, never logs real rules.
const test=require("node:test"),assert=require("node:assert/strict");
const {readFileSync}=require("node:fs");
const {resolve}=require("node:path");
const {createRequire}=require("node:module");
const req=createRequire(resolve(__dirname,"../functions/package.json"));
const {initializeTestEnvironment,assertFails,assertSucceeds}=
  req("@firebase/rules-unit-testing");
const {doc,getDoc,setDoc,writeBatch,serverTimestamp}=
  req("firebase/firestore");
const projectId="demo-deda-stage69-preserve-real-gifts";
assert.match(process.env.FIRESTORE_EMULATOR_HOST||"",
 /^(127\.0\.0\.1|localhost):[0-9]{2,5}$/);
const rules=readFileSync("/tmp/deda-stage66-candidate.rules","utf8");
assert.match(rules,/STAGE69_SPARK_ADDITIVE_CARD_ALLOWANCE_OFFLINE_ONLY/);
const owner={uid:"stage69_verified_person",key:"stage69_verified_account",
  original:"@DEDA-TR4U5Q"};
const giftId="stage69_real_gift_00001";
let env;
const wallet="deda_diamond_gift_balances/"+owner.original;
test.before(async()=>{
  env=await initializeTestEnvironment({
    projectId,
    firestore:{host:"127.0.0.1",port:8080,rules},
  });
});
test.after(async()=>{if(env)await env.cleanup()});
test.beforeEach(async()=>{
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    await Promise.all([
      setDoc(doc(db,"users",owner.uid),{accountKey:owner.key,
        sharePersonalId:owner.original}),
      setDoc(doc(db,"deda_sessions",owner.uid),{uid:owner.uid,
        accountKey:owner.key}),
      setDoc(doc(db,"deda_share_ids",owner.original),{
        publicId:owner.original,ownerUid:owner.uid,
        kind:"personal",active:true}),
      setDoc(doc(db,wallet),{publicId:owner.original,balance:1000,
        lastClaimGiftId:"synthetic_previous_gift",
        createdAt:new Date(2026,9,1),updatedAt:new Date(2026,9,1)}),
      setDoc(doc(db,"deda_diamond_gifts",giftId),{
        giftId,targetPublicId:owner.original,amount:100,status:"pending",
        sourceType:"admin",adminUid:"synthetic_manager",
        createdAt:new Date(2026,9,1)}),
    ]);
  });
});
test("genuine pending gift can still be claimed once with atomic wallet credit",async()=>{
  const db=env.authenticatedContext(owner.uid).firestore();
  const b=writeBatch(db);
  b.update(doc(db,"deda_diamond_gifts",giftId),{
    status:"received",claimedAt:serverTimestamp()});
  b.update(doc(db,wallet),{
    balance:1100,lastClaimGiftId:giftId,updatedAt:serverTimestamp()});
  await assertSucceeds(b.commit());
  assert.equal((await assertSucceeds(getDoc(doc(db,wallet)))).data().balance,1100);
  const replay=writeBatch(db);
  replay.update(doc(db,"deda_diamond_gifts",giftId),{
    status:"received",claimedAt:serverTimestamp()});
  replay.update(doc(db,wallet),{
    balance:1200,lastClaimGiftId:giftId,updatedAt:serverTimestamp()});
  await assertFails(replay.commit());
  assert.equal((await assertSucceeds(getDoc(doc(db,wallet)))).data().balance,1100);
});
test("standalone balance reduction is blocked after hardened live-policy merge",async()=>{
  const db=env.authenticatedContext(owner.uid).firestore();
  const b=writeBatch(db);
  b.update(doc(db,wallet),{balance:995,updatedAt:serverTimestamp()});
  await assertFails(b.commit());
  assert.equal((await assertSucceeds(getDoc(doc(db,wallet)))).data().balance,1000);
});
test("stranger cannot claim a gift or read owner's wallet",async()=>{
  const db=env.authenticatedContext("stage69_attacker").firestore();
  await assertFails(getDoc(doc(db,wallet)));
  const b=writeBatch(db);
  b.update(doc(db,"deda_diamond_gifts",giftId),{
    status:"received",claimedAt:serverTimestamp()});
  b.update(doc(db,wallet),{
    balance:1100,lastClaimGiftId:giftId,updatedAt:serverTimestamp()});
  await assertFails(b.commit());
});
