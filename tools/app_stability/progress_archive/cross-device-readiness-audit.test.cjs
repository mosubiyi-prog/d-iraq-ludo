"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const core=require("./reconcile-core.cjs");
const {auditCrossDeviceServerReadiness:audit}=
  require("./cross-device-readiness-audit.cjs");

process.env.GCLOUD_PROJECT="demo-deda-restore-readiness";
process.env.DEDA_RESTORE_AUDIT_EMULATOR_ONLY="true";
process.env.FIRESTORE_EMULATOR_HOST="127.0.0.1:8080";

const ACCOUNT="07701234567",OLD="verified_old_phone_uid_0001",NEXT="verified_second_phone_uid_0002";
const DIGEST="a".repeat(64),ENFORCE="b".repeat(64),REVIEW="c".repeat(64);
const MIGRATION_ID="migration_reference_000001";
const SETTLEMENT_ID="settlement_reference_000001";
const FENCE_ID="original_legacy_fence_000001";
const POLICY_ID="owner_policy_revision_000001";
const REVISION_ID="deployment_revision_000001";
const stamp={seconds:100,nanoseconds:0};
function fixture(){
 const docs=new Map(),calls=[];
 const receipt={format:1,accountKey:ACCOUNT,source:"legacy-baseline-v1",
   sourceId:"legacy-review|migration_reference_000001|"+DIGEST,
   kind:"baseline",delta:{points:52,coins:5,xp:2200,earnedDiamonds:340}};
 const key=core.eventKey(receipt);
 docs.set("deda_account_directory/"+ACCOUNT,
  {accountKey:ACCOUNT,active:true,createdUid:OLD});
 docs.set("deda_account_profiles/"+ACCOUNT,{accountKey:ACCOUNT,name:"Private fixture"});
 docs.set("users/"+OLD,{accountKey:ACCOUNT,xp:2200,diamonds:340});
 docs.set("users/"+NEXT,{accountKey:ACCOUNT,xp:0,diamonds:0});
 const root="deda_progress_migrations/"+ACCOUNT;
 docs.set(root,{format:1,accountKey:ACCOUNT,
  migrationId:MIGRATION_ID,settlementId:SETTLEMENT_ID,
  phase:"cutover-complete",evidenceDigest:DIGEST,baselineEventKey:key});
 docs.set("deda_verified_progress/"+ACCOUNT,{format:1,accountKey:ACCOUNT,
  version:2,initializedBy:key,
  balances:{points:70,coins:6,xp:2210,earnedDiamonds:330}});
 const receiptId="baseline_"+key;
 docs.set("deda_progress_receipts/"+ACCOUNT+"/events/"+receiptId,receipt);
 docs.set("deda_verified_progress/"+ACCOUNT+"/events/"+key,{
  format:1,accountKey:ACCOUNT,eventKey:key,receiptId,receipt,
  appliedVersion:1,afterBalances:{...receipt.delta},createdAt:stamp});
 docs.set(root+"/settlements/"+SETTLEMENT_ID,{
  format:1,accountKey:ACCOUNT,migrationId:MIGRATION_ID,evidenceDigest:DIGEST,
  baselineEventKey:key,legacyFenceId:FENCE_ID,
  pendingPurchases:0,pendingReservations:0});
 docs.set(root+"/settlementReviews/"+SETTLEMENT_ID,{
  format:1,accountKey:ACCOUNT,migrationId:MIGRATION_ID,evidenceDigest:DIGEST,
  baselineEventKey:key,settlementId:SETTLEMENT_ID,legacyFenceId:FENCE_ID,
  originalId:"@DEDA-ABC123",
  policyRevision:POLICY_ID,operationReviewDigest:REVIEW,createdAt:stamp,
  status:"resolved",decision:"preserve-reviewed-balances-and-carried-rights",
  pendingPurchases:0,pendingReservations:0});
 docs.set("deda_progress_migrations/_policy/settings/verified-cutover-v1",{
  format:1,enabled:true,revision:REVISION_ID,
  protocol:"deda-verified-progress-v1",enforcementRevision:ENFORCE,
  clientBound:true,providersReady:true,atomicPurchasesReady:true});
 docs.set(root+"/fences/"+FENCE_ID,{
  format:1,accountKey:ACCOUNT,migrationId:MIGRATION_ID,evidenceDigest:DIGEST,
  originalId:"@DEDA-ABC123",legacyFenceId:FENCE_ID,
  protocol:"deda-verified-progress-v1",deploymentRevision:REVISION_ID,
  enforcementRevision:ENFORCE,status:"enforced",createdAt:stamp});
 docs.set(root+"/activations/"+MIGRATION_ID,{
  format:1,accountKey:ACCOUNT,migrationId:MIGRATION_ID,evidenceDigest:DIGEST,
  baselineEventKey:key,settlementId:SETTLEMENT_ID,receiptId,
  operationReviewDigest:REVIEW,legacyFenceId:FENCE_ID,
  deploymentRevision:REVISION_ID,enforcementRevision:ENFORCE,
  policyRevision:POLICY_ID,createdAt:stamp});
 const reader={get:async path=>{
   calls.push(path);
   return docs.has(path)?docs.get(path):null;
 }};
 return {docs,calls,reader,key,receipt,request:{
   accountKey:ACCOUNT,oldUid:OLD,newUid:NEXT,reader,
 }};
}
const noCredit=r=>{
 assert.equal(r.status,"HOLD");
 assert.equal(r.emulatorOnly,true);
 for(const key of ["canRestoreAccount","canRestoreXp","canRestoreDiamonds",
   "canRestoreFrames","canRestorePremiumId","canIssueLeagueGift",
   "canWriteVerifiedProgress","canSettlePurchase",
   "oldApkWriterFenced","productionAuthAttested",
   "productionAppCheckVerified"])assert.equal(r[key],false,key);
 const s=JSON.stringify(r);
 assert.equal(s.includes(ACCOUNT),false);
 assert.equal(s.includes(OLD),false);
 assert.equal(s.includes(NEXT),false);
 assert.equal(s.includes("@DEDA-"),false);
 assert.equal(s.includes("2200"),false);
};
test("01: no source records: HOLD, no zeros inserted or invented",async()=>{
 const f=fixture();f.docs.clear();
 const r=await audit(f.request);
 noCredit(r);
 assert.equal(r.parsedServerProgressState,false);
 assert.ok(r.blockers.includes("ORIGINAL_ACCOUNT_UID_CHAIN_UNVERIFIED"));
 assert.ok(r.blockers.includes("VERIFIED_SERVER_PROGRESS_MISSING_OR_INVALID"));
 assert.equal(f.docs.size,0);
});
test("02: complete synthetic canonical progress, still NO wallet or XP transfer",async()=>{
 const f=fixture();const before=structuredClone([...f.docs]);
 const r=await audit(f.request);
 noCredit(r);
 assert.equal(r.originalAccountChainConsistent,true);
 assert.equal(r.parsedServerProgressState,true);
 assert.equal(r.reviewedMigrationPresent,true);
 assert.equal(r.baselineLedgerConsistent,true);
 assert.deepEqual([...f.docs],before);
 assert.equal(f.calls.length,13);
 assert.equal(r.cutoverRecordsConsistent,true);
 assert.ok(r.blockers.includes("OLD_APK_FINANCIAL_WRITER_NOT_SERVER_FENCED"));
 assert.ok(r.blockers.includes("PAYMENT_GIFT_FRAME_AND_PREMIUM_ID_PROOFS_NOT_SETTLED"));
});
test("03: changed baseline receipt payload cannot be blessed by existing event key",async()=>{
 const f=fixture();
 f.docs.set("deda_progress_receipts/"+ACCOUNT+"/events/baseline_"+f.key,{
  ...f.receipt,delta:{...f.receipt.delta,earnedDiamonds:999999}});
 const r=await audit(f.request);
 noCredit(r);assert.equal(r.baselineLedgerConsistent,false);
 assert.ok(r.blockers.includes("INDEPENDENT_BASELINE_RECEIPT_CHAIN_UNVERIFIED"));
});
test("04: mismatched applied receipt or replayed version cannot validate ledger",async()=>{
 const f=fixture();
 const path="deda_verified_progress/"+ACCOUNT+"/events/"+f.key;
 f.docs.set(path,{...f.docs.get(path),appliedVersion:99});
 assert.equal((await audit(f.request)).baselineLedgerConsistent,false);
 f.docs.set(path,{...f.docs.get(path),appliedVersion:1,
   receipt:{...f.receipt,sourceId:"changed-source-do-not-replay"}});
 assert.equal((await audit(f.request)).baselineLedgerConsistent,false);
});
test("05: altered settlement, old-client fence or activation stays on HOLD",async()=>{
 const f=fixture(),root="deda_progress_migrations/"+ACCOUNT;
 const fence=root+"/fences/"+FENCE_ID;
 f.docs.set(fence,{...f.docs.get(fence),status:"pending"});
 let r=await audit(f.request);
 noCredit(r);assert.equal(r.baselineLedgerConsistent,true);
 assert.equal(r.cutoverRecordsConsistent,false);
 f.docs.set(fence,{...f.docs.get(fence),status:"enforced"});
 const activation=root+"/activations/"+MIGRATION_ID;
 f.docs.set(activation,{...f.docs.get(activation),enforcementRevision:"forged"});
 assert.equal((await audit(f.request)).cutoverRecordsConsistent,false);
 f.docs.set(activation,{...f.docs.get(activation),enforcementRevision:ENFORCE});
 const settlement=root+"/settlements/"+SETTLEMENT_ID;
 f.docs.set(settlement,{...f.docs.get(settlement),pendingPurchases:1});
 assert.equal((await audit(f.request)).cutoverRecordsConsistent,false);
 f.docs.set(settlement,{...f.docs.get(settlement),pendingPurchases:0});
 assert.equal((await audit(f.request)).cutoverRecordsConsistent,true);
});
test("05: different original account owner or new-user scope rejects identity chain",async()=>{
 const f=fixture();
 f.docs.set("deda_account_directory/"+ACCOUNT,{accountKey:ACCOUNT,
  active:true,createdUid:"wrong_original_uid"});
 noCredit(await audit(f.request));
 assert.equal((await audit(f.request)).originalAccountChainConsistent,false);
 f.docs.set("deda_account_directory/"+ACCOUNT,
  {accountKey:ACCOUNT,active:true,createdUid:OLD});
 f.docs.set("users/"+NEXT,{accountKey:"07705554444"});
 assert.equal((await audit(f.request)).originalAccountChainConsistent,false);
});
test("06: malformed/negative state cannot authorize historical money",async()=>{
 const f=fixture(),path="deda_verified_progress/"+ACCOUNT;
 f.docs.set(path,{...f.docs.get(path),balances:{
  points:70,coins:6,xp:2210,earnedDiamonds:-330}});
 const r=await audit(f.request);
 noCredit(r);assert.equal(r.parsedServerProgressState,false);
 assert.equal(r.baselineLedgerConsistent,false);
});
test("07: production environment / account spoof is rejected BEFORE any server reads",async()=>{
 const f=fixture();const old=process.env.GCLOUD_PROJECT;
 process.env.GCLOUD_PROJECT="genuine-live-project";
 try{await assert.rejects(audit(f.request),/EMULATOR_ONLY/);}
 finally{process.env.GCLOUD_PROJECT=old;}
 assert.equal(f.calls.length,0);
 await assert.rejects(audit({...f.request,accountKey:"../users"}),/INVALID_ACCOUNT/);
 await assert.rejects(audit({...f.request,newUid:OLD}),/INVALID_ACCOUNT/);
 await assert.rejects(audit({...f.request,clientApproved:true}),/EMULATOR_ONLY/);
 assert.equal(f.calls.length,0);
});
test("08: source network failure rejects instead of returning success",async()=>{
 const f=fixture();
 f.reader.get=async()=>{throw Error("SERVER_UNAVAILABLE");};
 await assert.rejects(audit(f.request),/SERVER_UNAVAILABLE/);
});
