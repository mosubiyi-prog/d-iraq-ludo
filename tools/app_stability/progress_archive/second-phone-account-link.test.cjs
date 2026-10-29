"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {linkSecondPhoneToCanonicalAccount:link}=require("./second-phone-account-link.cjs");
const core=require("./reconcile-core.cjs");
process.env.GCLOUD_PROJECT="demo-deda-restore-readiness";
process.env.DEDA_RESTORE_AUDIT_EMULATOR_ONLY="true";
process.env.FIRESTORE_EMULATOR_HOST="127.0.0.1:8080";
const A="07701234567",O="first_verified_device_uid",N="second_verified_device_uid";
const M="migration_reference_00000001",S="settlement_reference_000001";
const baseline={format:1,accountKey:A,source:"legacy-baseline-v1",
 sourceId:"legacy-review|"+M+"|"+"a".repeat(64),
 kind:"baseline",delta:{points:5,coins:2,xp:25,earnedDiamonds:400}};
const K=core.eventKey(baseline),T={seconds:100,nanoseconds:0};
const F="legacy_fence_reference_000001",ORIGINAL="@DEDA-ABC123";
function fixture(){
 const docs=new Map(),writes=[],reads=[];
 const root="deda_progress_migrations/"+A;
 docs.set("deda_account_directory/"+A,{accountKey:A,active:true,createdUid:O});
 docs.set("deda_account_profiles/"+A,{accountKey:A});
 for(const uid of [O,N])docs.set("deda_stage54_private_account_bindings/"+uid,{
  uid,accountKey:A,authProvider:"anonymous",state:"LOCAL_VERIFIED_HOLD_ONLY",
  emulatorOnly:true,canMigrate:false,canGrant:false,createdAt:T});
 docs.set(root,{format:1,accountKey:A,migrationId:M,phase:"cutover-complete",
  evidenceDigest:"a".repeat(64),baselineEventKey:K,settlementId:S});
 docs.set("deda_verified_progress/"+A,{format:1,accountKey:A,
  version:1,initializedBy:K,balances:{points:5,coins:2,xp:25,earnedDiamonds:400}});
 docs.set("deda_progress_receipts/"+A+"/events/baseline_"+K,baseline);
 docs.set("deda_verified_progress/"+A+"/events/"+K,{
  format:1,accountKey:A,eventKey:K,receiptId:"baseline_"+K,
  receipt:baseline,appliedVersion:1,afterBalances:{...baseline.delta},
  createdAt:T,
 });
 docs.set(root+"/settlementReviews/"+S,{accountKey:A,migrationId:M,
  settlementId:S,status:"resolved",originalId:ORIGINAL,legacyFenceId:F,
  pendingPurchases:0,pendingReservations:0});
 docs.set(root+"/settlements/"+S,{format:1,accountKey:A,migrationId:M,
  evidenceDigest:"a".repeat(64),baselineEventKey:K,legacyFenceId:F,
  pendingPurchases:0,pendingReservations:0});
 docs.set(root+"/fences/"+F,{format:1,accountKey:A,migrationId:M,
  evidenceDigest:"a".repeat(64),originalId:ORIGINAL,legacyFenceId:F,
  protocol:"deda-verified-progress-v1",
  deploymentRevision:"deployment_revision_000001",
  enforcementRevision:"c".repeat(64),status:"enforced",createdAt:T});
 docs.set("deda_progress_migrations/_policy/settings/verified-cutover-v1",{
  format:1,enabled:true,revision:"deployment_revision_000001",
  protocol:"deda-verified-progress-v1",enforcementRevision:"c".repeat(64),
  clientBound:true,providersReady:true,atomicPurchasesReady:true});
 docs.set(root+"/activations/"+M,{accountKey:A,migrationId:M,settlementId:S,
  baselineEventKey:K,deploymentRevision:"deployment_revision_000001",
  enforcementRevision:"c".repeat(64)});
 const store={serverTimestamp:()=>T,runTransaction:async action=>{
  const pending=[];
  const result=await action({
   get:async p=>{reads.push(p);return docs.get(p)??null;},
   list:async(path,{limit})=>[...docs.entries()]
    .filter(([p])=>p.startsWith(path+"/"))
    .slice(0,limit).map(([p,data])=>({id:p.slice(path.length+1),data})),
   set:(p,d)=>pending.push([p,d]),
  });
  for(const [p,d] of pending){docs.set(p,d);writes.push(p);}
  return result;
 }};
 const auth={verifyIdToken:async()=>({uid:N,firebase:{sign_in_provider:"anonymous"}}),
  getUser:async uid=>({uid,disabled:false,email:null,providerData:[]})};
 return {docs,writes,reads,auth,store,args:{store,auth,idToken:"synthetic_auth_test_123",
  accountKey:A,oldUid:O,newUid:N,linkId:"second_device_account_link_001"}};
}
test("first valid link is atomic and never credits any balance",async()=>{
 const f=fixture(),before=f.docs.get("deda_verified_progress/"+A);
 const r=await link(f.args);
 assert.equal(r.replayed,false);assert.equal(r.canCreditDiamonds,false);
 assert.deepEqual(r.verifiedProgress,{
   format:1,version:1,points:5,coins:2,xp:25,earnedDiamonds:400,
   spendable:false,entitlementsVerified:false,
 });
 assert.deepEqual(f.writes,["deda_private_second_phone_links/"+N]);
 assert.deepEqual(f.docs.get("deda_verified_progress/"+A),before);
});
test("repeating same link is idempotent and cannot overwrite it",async()=>{
 const f=fixture();await link(f.args);
 assert.equal((await link(f.args)).replayed,true);
 assert.equal(f.writes.length,1);
 await assert.rejects(link({...f.args,linkId:"second_device_account_link_002"}),/EXISTING_LINK_CONFLICT/);
});
test("additional XP and task points preserve original canonical link",async()=>{
 const f=fixture();
 await link(f.args);
 const path="deda_verified_progress/"+A;
 f.docs.set(path,{...f.docs.get(path),version:2,balances:{
   points:10,coins:2,xp:30,earnedDiamonds:400}});
 const earned={format:1,accountKey:A,source:"task-claim-v1",
  sourceId:"verified_second_task_claim_0001",kind:"award",
  delta:{points:5,coins:0,xp:5,earnedDiamonds:0}};
 const nextKey=core.eventKey(earned),receiptId="verified_task_receipt_000001";
 f.docs.set("deda_progress_receipts/"+A+"/events/"+receiptId,earned);
 f.docs.set("deda_verified_progress/"+A+"/events/"+nextKey,{
   format:1,accountKey:A,eventKey:nextKey,receiptId,
   receipt:earned,appliedVersion:2,afterBalances:{
     points:10,coins:2,xp:30,earnedDiamonds:400,
   },createdAt:T,
 });
 const r=await link(f.args);
 assert.equal(r.replayed,true);
 assert.equal(f.writes.length,1);
 assert.equal(f.docs.get(path).balances.xp,30);
});
test("missing server PIN proof for either device denies link",async()=>{
 for(const uid of [O,N]){
  const f=fixture();f.docs.delete("deda_stage54_private_account_bindings/"+uid);
  await assert.rejects(link(f.args),/SERVER_ACCOUNT_PROOF_MISSING/);
  assert.equal(f.writes.length,0);
 }
});
test("unsettled purchase blocks links and never changes wallet",async()=>{
 const f=fixture(),p="deda_progress_migrations/"+A+"/settlementReviews/"+S;
 f.docs.set(p,{...f.docs.get(p),pendingPurchases:1});
 await assert.rejects(link(f.args),/TRUSTED_CUTOVER_UNVERIFIED/);
 assert.equal(f.writes.length,0);
});
test("old installed APK write fence must be proven, not just claimed",async()=>{
 const f=fixture(),path="deda_progress_migrations/"+A+"/fences/"+F;
 f.docs.set(path,{...f.docs.get(path),status:"pending"});
 await assert.rejects(link(f.args),/LEGACY_FINANCIAL_WRITER_NOT_FENCED/);
 assert.equal(f.writes.length,0);
});
test("incorrect Firebase session stops before accessing account",async()=>{
 const f=fixture();
 f.auth.verifyIdToken=async()=>({uid:O,firebase:{sign_in_provider:"anonymous"}});
 await assert.rejects(link(f.args),/UNVERIFIED_AUTH/);
 assert.equal(f.reads.length,0);
});
test("modified verified XP balance cannot create canonical second-phone link",async()=>{
 const f=fixture(),p="deda_verified_progress/"+A;
 f.docs.set(p,{...f.docs.get(p),balances:{points:5,coins:2,xp:99999,earnedDiamonds:400}});
 await assert.rejects(link(f.args),/RECEIPT_CHAIN_NOT_RECONCILED/);
 assert.deepEqual(f.writes,[]);
});
test("missing independent server-issued baseline receipt rejects linking",async()=>{
 const f=fixture();
 f.docs.delete("deda_progress_receipts/"+A+"/events/baseline_"+K);
 await assert.rejects(link(f.args),/RECEIPT_CHAIN_NOT_RECONCILED/);
 assert.deepEqual(f.writes,[]);
});
test("a tampered event key and incomplete version chain never link",async()=>{
 const f=fixture();
 const ep="deda_verified_progress/"+A+"/events/"+K;
 f.docs.set(ep,{...f.docs.get(ep),eventKey:"0".repeat(64)});
 await assert.rejects(link(f.args),/RECEIPT_CHAIN_NOT_RECONCILED/);
 assert.deepEqual(f.writes,[]);
});
test("canonical account link requires full transactional ledger listing",async()=>{
 const f=fixture(),original=f.store.runTransaction;
 f.store.runTransaction=action=>original(tx=>action({
  get:tx.get,set:tx.set,
 }));
 await assert.rejects(link(f.args),/RECEIPT_CHAIN_NOT_RECONCILED/);
 assert.deepEqual(f.writes,[]);
});
test("source is unavailable outside isolated emulator",async()=>{
 const f=fixture(),old=process.env.GCLOUD_PROJECT;
 process.env.GCLOUD_PROJECT="different-environment";
 try{await assert.rejects(link(f.args),/REFUSE_PRODUCTION/);}
 finally{process.env.GCLOUD_PROJECT=old;}
 assert.equal(f.reads.length,0);
});
