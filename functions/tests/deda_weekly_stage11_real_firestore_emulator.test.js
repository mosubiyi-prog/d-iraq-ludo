"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const crypto=require("node:crypto");
const {initializeApp,deleteApp,getApps} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {PROJECT,ROOT,simulateAtomicShadowTaskXp}=
  require("../deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const {opaqueReceiptId}=
  require("../deda_weekly_owner_receipt_gate_NOT_EXPORTED.js");

if(!process.env.FIRESTORE_EMULATOR_HOST ||
   process.env.GCLOUD_PROJECT!==PROJECT) {
  throw Error("STAGE11_REAL_FIRESTORE_EMULATOR_ONLY_DO_NOT_PAY");
}
const ACCOUNT="07712341234",UIDA="anonymous_first_phone",
      UIDB="anonymous_second_phone",TASK="traffic_skills";
const NOW=Date.UTC(2026,9,27,11);
const DAY="2026-10-27";
const week={weekId:"private_admin_configured_week",
  startMs:Date.UTC(2026,9,26,21),
  endMs:Date.UTC(2026,10,2,21)};
const APP=initializeApp({projectId:PROJECT},"deda_weekly_stage11_qa");
const db=getFirestore(APP);

function request(uid) {
  return {auth:{uid},app:{appId:"attested_deda_emulator_app"},data:{}};
}
function receipt(taskId) {
  return opaqueReceiptId({accountKey:ACCOUNT,dayId:DAY,taskId});
}
function input(uid,taskId) {
  return {db,request:request(uid),serverNowMs:NOW,
    serverTaskId:taskId,weekConfig:week};
}
async function seed() {
  const writes=[];
  for(const [uid,install] of [
    [UIDA,"installA"],[UIDB,"installB"],
  ]) {
    writes.push(db.doc("users/"+uid).set({
      accountKey:ACCOUNT,uid,xp:999,earnedDiamonds:777,
      originalLevel:45,originalTaskPoints:888,
    }));
    writes.push(db.doc("deda_sessions/"+uid).set({
      uid,accountKey:ACCOUNT,installId:install,
    }));
    writes.push(db.doc("deda_weekly_identity_attestations/"+uid).set({
      issuer:"privileged_identity_verifier_v1",state:"verified",
      uid,accountKey:ACCOUNT,installId:install,
      issuedAtMs:NOW-2000,expiresAtMs:NOW+2000,
    }));
  }
  writes.push(db.doc("deda_account_profiles/"+ACCOUNT).set({
    accountKey:ACCOUNT,trustedInstallIds:["installA","installB"],
    originalLevel:45,earnedDiamonds:777,
  }));
  await Promise.all(writes);
}
async function proof(taskId,overrides={}) {
  const id=receipt(taskId);
  await db.doc(ROOT.proof+"/"+id).set({
    issuer:"emulator_fixture_only_verified_task_v1",
    status:"emulator_task_and_xp_confirmed",
    eventId:id,accountKey:ACCOUNT,dayId:DAY,taskId,
    weekId:week.weekId,taskPointsAwarded:true,levelXpApplied:true,
    levelXpAmount:20,verifiedAtMs:NOW-1000,
    ...overrides,
  });
  return id;
}
test.after(async()=>{await deleteApp(APP);});
test("real Firestore transactions: same daily mission credited ONCE across two phones",async()=>{
  await seed();const id=await proof(TASK);
  const pre=await db.doc("users/"+UIDA).get();
  const outputs=await Promise.all([
    simulateAtomicShadowTaskXp(input(UIDA,TASK)),
    simulateAtomicShadowTaskXp(input(UIDB,TASK)),
  ]);
  assert.deepEqual(outputs.map(x=>x.outcome).sort(),
    ["already_recorded","shadow_recorded"]);
  assert.deepEqual(outputs.map(x=>x.shadowXpAdded).sort((a,b)=>a-b),
    [0,20]);
  const after=await db.doc("users/"+UIDA).get();
  assert.deepEqual(after.data(),pre.data());
  const actual=await db.doc(ROOT.receipt+"/"+id).get();
  assert.equal(actual.exists,true);
  assert.equal(actual.get("amount"),20);
  assert.equal(actual.get("shadowOnly"),true);
  assert.equal(actual.get("issuer"),"emulator_only_weekly_xp_shadow_v1");
  assert.equal((await db.collection(ROOT.receipt).get()).size,1);
});
test("real Firestore transaction safely sums DIFFERENT task receipts without wallet writes",async()=>{
  await proof("open_map");
  const res=await simulateAtomicShadowTaskXp(input(UIDA,"open_map"));
  assert.equal(res.outcome,"shadow_recorded");
  const weekKey=crypto.createHash("sha256").update(ACCOUNT).digest("hex");
  const weekDoc=await db.doc(ROOT.week+"/"+week.weekId+"_"+weekKey).get();
  assert.equal(weekDoc.get("xp"),40);
  assert.equal(weekDoc.get("count"),2);
  const original=await db.doc("users/"+UIDB).get();
  assert.equal(original.get("earnedDiamonds"),777);
  assert.equal(original.get("xp"),999);
  assert.equal(original.get("originalLevel"),45);
});
test("no server task proof means no simulated XP; ordinary answer 5 is NOT level XP",async()=>{
  await proof("traffic_answer_only",{
    levelXpAmount:5,levelXpApplied:false,
  });
  await assert.rejects(simulateAtomicShadowTaskXp(input(
    UIDA,"traffic_answer_only")),/missing_privileged_task_proof/);
  assert.equal((await db.doc(ROOT.receipt+"/"+receipt("traffic_answer_only"))
    .get()).exists,false);
});
test("cannot supply client points, mobile rank, phone, or alias to issuer",async()=>{
  for(const injected of [{xp:160},{points:999},{diamonds:1000},
    {accountKey:ACCOUNT},{dayId:DAY},{weeklyRank:1}]) {
    const arg=input(UIDA,TASK);
    arg.request={...request(UIDA),data:injected};
    await assert.rejects(simulateAtomicShadowTaskXp(arg),
      /client_input_forbidden/);
  }
  assert.equal((await db.collection(ROOT.receipt).get()).size,2);
});
