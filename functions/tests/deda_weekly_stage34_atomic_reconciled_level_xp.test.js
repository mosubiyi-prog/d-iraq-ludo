"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore}=require("firebase-admin/firestore");
const {opaqueReceiptId}=require("../deda_weekly_owner_receipt_gate_NOT_EXPORTED.js");
const {dayInIraq}=require("../deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const {clockState}=require("../deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
const {PROJECT,SHADOW,ISSUER,MIGRATION,TASK,TASK_POINTS,hash,
  simulateLevelXpAndLeagueReceipt:award}=require(
  "../deda_weekly_stage34_atomic_reconciled_level_xp_NOT_EXPORTED.js");
if(process.env.GCLOUD_PROJECT!==PROJECT||!process.env.FIRESTORE_EMULATOR_HOST)
  throw Error("STAGE34_LOCAL_TEST_ENV_ONLY");
const app=initializeApp({projectId:PROJECT},"deda-stage34-qa");
const db=getFirestore(app);
const START=Date.UTC(2026,9,27,3);
const NOW=START+8*3600000;
const FROZEN=START+7*86400000-6*3600000+60000;
const NEXT=START+8*86400000+2000;
const A="07701234567",B="07707654321";
const users=[["qa_a1",A,"one"],["qa_a2",A,"two"],["qa_b",B,"other"]];
const req=uid=>({auth:{uid},app:{appId:"fixture_app"},data:{}});
const id=(account,now)=>opaqueReceiptId({
  accountKey:account,dayId:dayInIraq(now),taskId:TASK});
const baselinePath=account=>SHADOW.account+"/"+hash(account);
async function identities(now){
 const batch=db.batch();
 for(const [uid,account,installId] of users){
   batch.set(db.doc("users/"+uid),{uid,accountKey:account});
   batch.set(db.doc("deda_sessions/"+uid),{uid,accountKey:account,installId});
   batch.set(db.doc("deda_weekly_identity_attestations/"+uid),{
     issuer:"privileged_identity_verifier_v1",state:"verified",
     uid,accountKey:account,installId,
     issuedAtMs:now-1000,expiresAtMs:now+180000});
 }
 for(const account of [A,B])batch.set(
   db.doc("deda_account_profiles/"+account),{
     accountKey:account,trustedInstallIds:
       account===A?["one","two"]:["other"]});
 await batch.commit();
}
async function baseline(account){
 await db.doc(baselinePath(account)).set({
  issuer:MIGRATION,emulatorOnly:true,canonicalAccountKey:account,
  status:"reconciled",legacyLocalDataRetained:true,
  authoritativeBaselineVerified:true,baselineTaskClaimsReviewed:true,
  originalLevelXpBaseline:1250,levelXp:1250,newAwardsCount:0,revision:1});
}
async function claim(account,now,extra={}){
 const rid=id(account,now);
 await db.doc(SHADOW.task+"/"+rid).set({
  issuer:ISSUER,emulatorOnly:true,canonicalAccountKey:account,
  taskId:TASK,taskReceiptId:rid,dayId:dayInIraq(now),
  claimType:"daily_task_claim",sourceType:"original_app_location_share",
  backendCheckedOriginalShare:true,backendCheckedActualTaskClaim:true,
  ordinaryTaskPointsConfirmed:true,originalOrdinaryTaskPoints:TASK_POINTS,
  levelXpAlreadyApplied:false,verifiedAtMs:now-2000,...extra});
}
function run(uid,when){return award({
 db,request:req(uid),firstOpenMs:START,serverNowMs:when});}
test.before(async()=>{await identities(NOW);});
test.after(async()=>{await deleteApp(app);});
test("missing verified baseline and task independently deny award",async()=>{
 await claim(A,NOW);
 await assert.rejects(run("qa_a1",NOW),/missing_reconciled_level_account/);
 await baseline(A);
 await baseline(B);
 await assert.rejects(run("qa_b",NOW),/missing_independent_trusted_task_claim/);
});
test("conflicting legacy baseline and client-sourced claim are rejected",async()=>{
 await db.doc(baselinePath(A)).update({authoritativeBaselineVerified:false});
 await assert.rejects(run("qa_a1",NOW),/unverified_or_conflicting_baseline/);
 await db.doc(baselinePath(A)).update({authoritativeBaselineVerified:true});
 await claim(A,NOW,{ordinaryTaskPointsConfirmed:false});
 await assert.rejects(run("qa_a1",NOW),/untrusted_or_stale_task_claim_fixture/);
 await claim(A,NOW);
});
test("two devices sharing canonical account issue exactly one +20 award",async()=>{
 const res=await Promise.all([run("qa_a1",NOW),run("qa_a2",NOW)]);
 assert.equal(res.reduce((a,x)=>a+x.levelXpAdded,0),20);
 assert.equal(res.reduce((a,x)=>a+x.leagueXpAdded,0),20);
 assert.equal((await db.doc(baselinePath(A)).get()).get("levelXp"),1270);
 assert.equal((await db.collection(SHADOW.receipt).get()).size,1);
 assert.equal((await db.collection(SHADOW.league).get()).size,1);
 const retry=await run("qa_a2",NOW);
 assert.equal(retry.levelXpAdded,0);
 assert.equal(retry.leagueXpAdded,0);
});
test("different account cannot reuse first account's XP receipt",async()=>{
 await claim(B,NOW);
 const result=await run("qa_b",NOW);
 assert.equal(result.levelXpAdded,20);
 assert.equal((await db.doc(baselinePath(B)).get()).get("levelXp"),1270);
 assert.equal((await db.doc(baselinePath(A)).get()).get("levelXp"),1270);
});
test("00–06 pause applies only to league, not canonical lifetime XP",async()=>{
 await identities(FROZEN);
 await claim(A,FROZEN);
 assert.equal(clockState({firstOpenMs:START,serverNowMs:FROZEN}).phase,"frozen");
 const result=await run("qa_a1",FROZEN);
 assert.equal(result.levelXpAdded,20);
 assert.equal(result.leagueXpAdded,0);
 assert.equal((await db.doc(baselinePath(A)).get()).get("levelXp"),1290);
 assert.equal((await db.collection(SHADOW.league).get()).size,2);
});
test("new week's XP is distinct and no original wallet changes",async()=>{
 await identities(NEXT);
 await claim(A,NEXT);
 const result=await run("qa_a2",NEXT);
 assert.equal(result.levelXpAdded,20);
 assert.equal(result.leagueXpAdded,20);
 assert.equal((await db.doc(baselinePath(A)).get()).get("levelXp"),1310);
 assert.equal((await db.collection(SHADOW.league).get()).size,3);
 assert.equal((await db.collection("deda_admin_diamond_wallets").get()).size,0);
});
