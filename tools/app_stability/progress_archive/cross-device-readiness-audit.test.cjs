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
 for(const uid of [OLD,NEXT])
   docs.set("deda_stage54_private_account_bindings/"+uid,{
     uid,accountKey:ACCOUNT,authProvider:"anonymous",
     state:"LOCAL_VERIFIED_HOLD_ONLY",
     emulatorOnly:true,canMigrate:false,canGrant:false,
     createdAt:stamp,
   });
 const root="deda_progress_migrations/"+ACCOUNT;
 docs.set(root,{format:1,accountKey:ACCOUNT,
  migrationId:MIGRATION_ID,settlementId:SETTLEMENT_ID,
  phase:"cutover-complete",evidenceDigest:DIGEST,baselineEventKey:key});
 docs.set("deda_verified_progress/"+ACCOUNT,{format:1,accountKey:ACCOUNT,
  version:3,initializedBy:key,
  balances:{points:57,coins:6,xp:2205,earnedDiamonds:330}});
 const receiptId="baseline_"+key;
 docs.set("deda_progress_receipts/"+ACCOUNT+"/events/"+receiptId,receipt);
 docs.set("deda_verified_progress/"+ACCOUNT+"/events/"+key,{
  format:1,accountKey:ACCOUNT,eventKey:key,receiptId,receipt,
  appliedVersion:1,afterBalances:{...receipt.delta},createdAt:stamp});
 // A signed-ledger candidate must include EVERY subsequent applied receipt,
 // not just the reviewed baseline. These fixture rows are NOT live proof.
 const earned={format:1,accountKey:ACCOUNT,source:"task-claim-v1",
  sourceId:"original-task-verified-claim-2026-10-29",
  kind:"award",delta:{points:5,coins:1,xp:5,earnedDiamonds:0}};
 const used={format:1,accountKey:ACCOUNT,source:"cosmetic-debit-v1",
  sourceId:"original-frame-debit-fixture-00001",
  kind:"spend",delta:{points:0,coins:0,xp:0,earnedDiamonds:-10}};
 const keyEarned=core.eventKey(earned),keyUsed=core.eventKey(used);
 const receiptEarned="receipt_task_000000000001",receiptUsed="receipt_spend_00000000001";
 docs.set("deda_progress_receipts/"+ACCOUNT+"/events/"+receiptEarned,earned);
 docs.set("deda_verified_progress/"+ACCOUNT+"/events/"+keyEarned,{
  format:1,accountKey:ACCOUNT,eventKey:keyEarned,
  receipt:earned,receiptId:receiptEarned,appliedVersion:2,
  afterBalances:{points:57,coins:6,xp:2205,earnedDiamonds:340},
  createdAt:stamp});
 docs.set("deda_progress_receipts/"+ACCOUNT+"/events/"+receiptUsed,used);
 docs.set("deda_verified_progress/"+ACCOUNT+"/events/"+keyUsed,{
  format:1,accountKey:ACCOUNT,eventKey:keyUsed,
  receipt:used,receiptId:receiptUsed,appliedVersion:3,
  afterBalances:{points:57,coins:6,xp:2205,earnedDiamonds:330},
  createdAt:stamp});
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
 },list:async (path,{limit})=>{
   calls.push("LIST:"+path);
   return [...docs.entries()]
     .filter(([key])=>key.startsWith(path+"/"))
     .slice(0,limit).map(([key,data])=>({
       id:key.slice(path.length+1),data
     }));
 }};
 const auth={
   verifyIdToken:async(token,revocation)=>{
     calls.push("AUTH:verify");
     assert.equal(revocation,true);
     if(token!=="emulator_test_id_token_0123456789")throw Error("INVALID_ID_TOKEN");
     return {uid:NEXT,firebase:{sign_in_provider:"anonymous"}};
   },
   getUser:async uid=>{
     calls.push("AUTH:getUser");
     return {uid,disabled:false,email:null,providerData:[]};
   },
 };
 return {docs,calls,reader,auth,key,receipt,request:{
   accountKey:ACCOUNT,oldUid:OLD,newUid:NEXT,reader,auth,
   idToken:"emulator_test_id_token_0123456789",
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
 assert.equal(r.serverOwnedDualPinBindingConsistent,true);
 assert.equal(r.parsedServerProgressState,true);
 assert.equal(r.reviewedMigrationPresent,true);
 assert.equal(r.baselineLedgerConsistent,true);
 assert.deepEqual([...f.docs],before);
 assert.equal(f.calls.length,21);
 assert.equal(r.cutoverRecordsConsistent,true);
 assert.equal(r.fullLedgerReconciled,true);
 assert.ok(r.blockers.includes("OLD_APK_FINANCIAL_WRITER_NOT_SERVER_FENCED"));
 assert.ok(r.blockers.includes("PAYMENT_GIFT_FRAME_AND_PREMIUM_ID_PROOFS_NOT_SETTLED"));
});
test("15: old/new UIDs must both have server-owned PIN binding proof",async()=>{
 const f=fixture();
 const old="deda_stage54_private_account_bindings/"+OLD;
 const next="deda_stage54_private_account_bindings/"+NEXT;
 const prior=f.docs.get(next);
 f.docs.delete(next);
 let r=await audit(f.request);
 noCredit(r);
 assert.equal(r.originalAccountChainConsistent,true);
 assert.equal(r.serverOwnedDualPinBindingConsistent,false);
 assert.ok(r.blockers.includes("SERVER_OWNED_DUAL_PIN_BINDING_UNVERIFIED"));
 f.docs.set(next,{...prior,accountKey:"07700000000"});
 assert.equal((await audit(f.request)).serverOwnedDualPinBindingConsistent,false);
 f.docs.set(next,prior);
 f.docs.set(old,{...f.docs.get(old),uid:NEXT});
 assert.equal((await audit(f.request)).serverOwnedDualPinBindingConsistent,false);
});
test("17: second-phone Auth UID cannot be asserted by caller or stolen token",async()=>{
 const f=fixture();
 const wrongToken={...f.request,idToken:"wrong_id_token_abcdefghijkl"};
 await assert.rejects(audit(wrongToken),/UNVERIFIED_NEW_DEVICE_AUTH/);
 assert.equal(f.calls.filter(x=>x.startsWith("deda_")).length,0);
 const original=f.auth.verifyIdToken;
 f.auth.verifyIdToken=async()=>({uid:OLD,firebase:{
   sign_in_provider:"anonymous",
 }});
 await assert.rejects(audit(f.request),/UNVERIFIED_NEW_DEVICE_AUTH/);
 f.auth.verifyIdToken=original;
 assert.equal(f.calls.some(x=>x.startsWith("deda_")),false);
});
test("18: disabled/non-anonymous Firebase Auth accounts cannot read restore proofs",async()=>{
 const f=fixture(),auth=f.auth;
 auth.verifyIdToken=async()=>({uid:NEXT,firebase:{
   sign_in_provider:"password",
 }});
 await assert.rejects(audit(f.request),/UNVERIFIED_NEW_DEVICE_AUTH/);
 auth.verifyIdToken=async()=>({uid:NEXT,firebase:{
   sign_in_provider:"anonymous",
 }});
 auth.getUser=async uid=>({uid,disabled:true,email:null,providerData:[]});
 await assert.rejects(audit(f.request),/UNVERIFIED_NEW_DEVICE_AUTH/);
 auth.getUser=async uid=>({uid,disabled:false,
   email:"lookalike@example.invalid",providerData:[]});
 await assert.rejects(audit(f.request),/UNVERIFIED_NEW_DEVICE_AUTH/);
 assert.equal(f.calls.some(x=>x.startsWith("deda_")),false);
});
test("16: copied install/device session or forgery never substitutes server PIN binding",async()=>{
 const f=fixture();
 const next="deda_stage54_private_account_bindings/"+NEXT;
 const original=f.docs.get(next);
 f.docs.set(next,{...original,canGrant:true});
 assert.equal((await audit(f.request)).serverOwnedDualPinBindingConsistent,false);
 f.docs.set(next,{...original,canGrant:false,installId:"copied-from-old-phone"});
 assert.equal((await audit(f.request)).serverOwnedDualPinBindingConsistent,false);
 f.docs.set(next,{...original,authProvider:"google.com"});
 assert.equal((await audit(f.request)).serverOwnedDualPinBindingConsistent,false);
 f.docs.set(next,original);
 const r=await audit(f.request);
 noCredit(r);
 assert.equal(r.serverOwnedDualPinBindingConsistent,true);
 assert.equal(r.status,"HOLD");
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
test("10: forged current wallet after valid receipts is never accepted",async()=>{
 const f=fixture(),path="deda_verified_progress/"+ACCOUNT;
 const before=structuredClone([...f.docs]);
 f.docs.set(path,{...f.docs.get(path),balances:{
   ...f.docs.get(path).balances,earnedDiamonds:99999
 }});
 const r=await audit(f.request);
 noCredit(r);
 assert.equal(r.baselineLedgerConsistent,true);
 assert.equal(r.cutoverRecordsConsistent,true);
 assert.equal(r.fullLedgerReconciled,false);
 assert.ok(r.blockers.includes("FULL_SERVER_RECEIPT_REPLAY_UNVERIFIED"));
 assert.deepEqual([...before].filter(([k])=>k!==path),
   [...f.docs].filter(([k])=>k!==path));
});
test("11: missing applied receipt or version gap cannot restore XP",async()=>{
 const f=fixture(),prefix="deda_verified_progress/"+ACCOUNT+"/events/";
 const earnedId=core.eventKey({
   format:1,accountKey:ACCOUNT,source:"task-claim-v1",
   sourceId:"original-task-verified-claim-2026-10-29",kind:"award",
   delta:{points:5,coins:1,xp:5,earnedDiamonds:0}
 });
 const p=prefix+earnedId,doc=f.docs.get(p);
 f.docs.delete(p);
 assert.equal((await audit(f.request)).fullLedgerReconciled,false);
 f.docs.set(p,{...doc,appliedVersion:4});
 assert.equal((await audit(f.request)).fullLedgerReconciled,false);
 f.docs.set(p,doc);
 assert.equal((await audit(f.request)).fullLedgerReconciled,true);
});
test("12: tampered independent receipt and event afterBalance fail closed",async()=>{
 const f=fixture(),key=core.eventKey({
   format:1,accountKey:ACCOUNT,source:"task-claim-v1",
   sourceId:"original-task-verified-claim-2026-10-29",kind:"award",
   delta:{points:5,coins:1,xp:5,earnedDiamonds:0}
 });
 const ep="deda_verified_progress/"+ACCOUNT+"/events/"+key,
       rp="deda_progress_receipts/"+ACCOUNT+"/events/receipt_task_000000000001";
 const original=f.docs.get(rp);
 f.docs.set(rp,{...original,sourceId:"tampered"});
 assert.equal((await audit(f.request)).fullLedgerReconciled,false);
 f.docs.set(rp,original);
 f.docs.set(ep,{...f.docs.get(ep),afterBalances:{
   points:57,coins:6,xp:9999,earnedDiamonds:340}});
 assert.equal((await audit(f.request)).fullLedgerReconciled,false);
});
test("13: no complete enumeration API is never treated as financial proof",async()=>{
 const f=fixture();
 delete f.reader.list;
 const r=await audit(f.request);
 noCredit(r);
 assert.equal(r.fullLedgerReconciled,false);
});
test("14: downstream receipt read outage cannot yield a passed ledger",async()=>{
 const f=fixture(),previous=f.reader.get;
 f.reader.get=async path=>{
   if(path.endsWith("/receipt_spend_00000000001"))
     throw Error("SERVER_PARTITION");
   return previous(path);
 };
 const r=await audit(f.request);
 noCredit(r);
 assert.equal(r.fullLedgerReconciled,false);
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
