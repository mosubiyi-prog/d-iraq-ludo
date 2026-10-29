"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {linkSecondPhoneToCanonicalAccount:link}=require("./second-phone-account-link.cjs");
process.env.GCLOUD_PROJECT="demo-deda-restore-readiness";
process.env.DEDA_RESTORE_AUDIT_EMULATOR_ONLY="true";
process.env.FIRESTORE_EMULATOR_HOST="127.0.0.1:8080";
const A="07701234567",O="first_verified_device_uid",N="second_verified_device_uid";
const M="migration_reference_00000001",S="settlement_reference_000001";
const K="b".repeat(64),T={seconds:100,nanoseconds:0};
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
 docs.set(root+"/settlementReviews/"+S,{accountKey:A,migrationId:M,
  settlementId:S,status:"resolved",pendingPurchases:0,pendingReservations:0});
 docs.set(root+"/settlements/"+S,{accountKey:A,baselineEventKey:K,
  pendingPurchases:0,pendingReservations:0});
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
test("incorrect Firebase session stops before accessing account",async()=>{
 const f=fixture();
 f.auth.verifyIdToken=async()=>({uid:O,firebase:{sign_in_provider:"anonymous"}});
 await assert.rejects(link(f.args),/UNVERIFIED_AUTH/);
 assert.equal(f.reads.length,0);
});
test("source is unavailable outside isolated emulator",async()=>{
 const f=fixture(),old=process.env.GCLOUD_PROJECT;
 process.env.GCLOUD_PROJECT="different-environment";
 try{await assert.rejects(link(f.args),/REFUSE_PRODUCTION/);}
 finally{process.env.GCLOUD_PROJECT=old;}
 assert.equal(f.reads.length,0);
});
