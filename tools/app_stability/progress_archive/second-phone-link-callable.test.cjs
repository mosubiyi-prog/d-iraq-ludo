"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const core=require("./reconcile-core.cjs");
const {createSecondPhoneLinkCallable:create}=
 require("./second-phone-link-callable.cjs");
process.env.GCLOUD_PROJECT="demo-deda-restore-readiness";
process.env.FIRESTORE_EMULATOR_HOST="127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST="127.0.0.1:9099";
process.env.FIREBASE_FUNCTIONS_EMULATOR_HOST="127.0.0.1:5001";
process.env.DEDA_RESTORE_AUDIT_EMULATOR_ONLY="true";
process.env.DEDA_RESTORE_AUDIT_LINK_KEY_HEX="a".repeat(64);
const A="07701234567",O="old_owner_firebase_uid_0001",N="new_owner_firebase_uid_0002";
const M="migration_reference_00000001",S="settlement_reference_000001";
const F="legacy_fence_reference_000001",T={seconds:100,nanoseconds:0};
const bearer="Bearer emulator_firebase_id_token_abcdefghijklmnopqrstuvwxyz";
class HttpsError extends Error{
 constructor(code,message){super(message);this.code=code;}
}
function fixture(){
 const docs=new Map(),writes=[],queries=[];
 const root="deda_progress_migrations/"+A;
 const baseline={format:1,accountKey:A,source:"legacy-baseline-v1",
   sourceId:"legacy-review|"+M+"|"+"b".repeat(64),kind:"baseline",
   delta:{points:25,coins:10,xp:125,earnedDiamonds:200}};
 const K=core.eventKey(baseline);
 docs.set("deda_account_directory/"+A,{accountKey:A,active:true,createdUid:O});
 docs.set("deda_account_profiles/"+A,{accountKey:A});
 docs.set("deda_share_ids/@DEDA-ABC123",{
   publicId:"@DEDA-ABC123",kind:"personal",active:true,ownerUid:O,
 });
 docs.set("users/"+O,{accountKey:A,sharePersonalId:"@DEDA-ABC123"});
 for(const uid of [O,N])docs.set("deda_stage54_private_account_bindings/"+uid,{
   uid,accountKey:A,authProvider:"anonymous",state:"LOCAL_VERIFIED_HOLD_ONLY",
   emulatorOnly:true,canMigrate:false,canGrant:false,createdAt:T});
 docs.set(root,{format:1,accountKey:A,migrationId:M,phase:"cutover-complete",
   evidenceDigest:"b".repeat(64),baselineEventKey:K,settlementId:S});
 docs.set("deda_verified_progress/"+A,{format:1,accountKey:A,version:1,
   initializedBy:K,balances:{...baseline.delta}});
 docs.set("deda_progress_receipts/"+A+"/events/baseline_"+K,baseline);
 docs.set("deda_verified_progress/"+A+"/events/"+K,{
   format:1,accountKey:A,eventKey:K,receipt:baseline,receiptId:"baseline_"+K,
   appliedVersion:1,afterBalances:{...baseline.delta},createdAt:T});
 docs.set(root+"/settlementReviews/"+S,{
   accountKey:A,migrationId:M,settlementId:S,status:"resolved",
   originalId:"@DEDA-ABC123",legacyFenceId:F,pendingPurchases:0,pendingReservations:0});
 docs.set(root+"/settlements/"+S,{
   format:1,accountKey:A,migrationId:M,evidenceDigest:"b".repeat(64),
   baselineEventKey:K,legacyFenceId:F,pendingPurchases:0,pendingReservations:0});
 docs.set(root+"/fences/"+F,{
   format:1,accountKey:A,migrationId:M,evidenceDigest:"b".repeat(64),
   originalId:"@DEDA-ABC123",legacyFenceId:F,protocol:"deda-verified-progress-v1",
   deploymentRevision:"deployment_revision_000001",
   enforcementRevision:"c".repeat(64),status:"enforced",createdAt:T});
 docs.set("deda_progress_migrations/_policy/settings/verified-cutover-v1",{
   format:1,enabled:true,revision:"deployment_revision_000001",
   protocol:"deda-verified-progress-v1",enforcementRevision:"c".repeat(64),
   clientBound:true,providersReady:true,atomicPurchasesReady:true});
 docs.set(root+"/activations/"+M,{
   accountKey:A,migrationId:M,settlementId:S,baselineEventKey:K,
   deploymentRevision:"deployment_revision_000001",
   enforcementRevision:"c".repeat(64)});
 const ref=path=>({path,get:async()=>({
   exists:docs.has(path),data:()=>docs.get(path),
 })});
 const db={
   doc:ref,
   collection:path=>({orderBy:(k,order)=>{
     assert.equal(k,"appliedVersion");assert.equal(order,"asc");
     return {limit:n=>({path,limit:n})};
   }}),
   async runTransaction(action){
     const pending=[];
     const result=await action({
       get:async q=>{
         queries.push(q.path);
         if(q.limit){
           return {docs:[...docs.entries()]
             .filter(([k])=>k.startsWith(q.path+"/"))
             .sort((a,b)=>a[1].appliedVersion-b[1].appliedVersion)
             .slice(0,q.limit)
             .map(([key,v])=>({id:key.slice(q.path.length+1),data:()=>v}))};
         }
         return {exists:docs.has(q.path),data:()=>docs.get(q.path)};
       },
       set:(q,data)=>pending.push([q.path,data]),
     });
     for(const [p,data] of pending){docs.set(p,data);writes.push(p);}
     return result;
   },
 };
 const auth={
   verifyIdToken:async()=>({uid:N,firebase:{sign_in_provider:"anonymous"}}),
   getUser:async uid=>({uid,disabled:false,email:null,providerData:[]}),
 };
 let options;
 const onCall=(opts,fn)=>{options=opts;return fn;};
 const callable=create({onCall,HttpsError,db,auth,serverTimestamp:()=>T});
 const request={auth:{uid:N,token:{firebase:{sign_in_provider:"anonymous"}}},
   data:{},rawRequest:{headers:{authorization:bearer}}};
 const call=(updates={})=>callable({...request,...updates});
 return {docs,writes,queries,auth,options,call,request};
}
const linkPath="deda_private_second_phone_links/"+N;
test("01 calls original canonical link without client account or wallet payload",async()=>{
 const f=fixture();
 const r=await f.call();
 assert.equal(r.status,"ACCOUNT_LINKED_READONLY_EMULATOR_ONLY");
 assert.deepEqual(r.verifiedProgress,{
   format:1,version:1,points:25,coins:10,xp:125,earnedDiamonds:200,
   spendable:false,entitlementsVerified:false,
 });
 assert.equal(r.replayed,false);
 for(const key of ["canRestoreFinancialBalances","canCreditXp","canCreditDiamonds",
   "canRestoreFrames","canRestorePremiumId","canIssueLeagueGift","productionReady"])
   assert.equal(r[key],false,key);
 assert.deepEqual(f.writes,[linkPath,"deda_migration_spend_authority/@DEDA-ABC123","deda_migration_account_authority/"+A]);
 const record=f.docs.get(linkPath);
 assert.equal(record.accountKey,A);assert.equal(record.oldUid,O);
 assert.equal(record.newUid,N);
 assert.equal(record.canCreditDiamonds,false);
 assert.equal(JSON.stringify(r).includes(A),false);
 assert.equal(f.options.enforceAppCheck,false);
});
test("02 retry is idempotent and no financial changes occur",async()=>{
 const f=fixture(),original=f.docs.get("deda_verified_progress/"+A);
 await f.call();
 const r=await f.call();
 assert.equal(r.replayed,true);assert.deepEqual(f.writes,[linkPath,"deda_migration_spend_authority/@DEDA-ABC123","deda_migration_account_authority/"+A]);
 assert.deepEqual(f.docs.get("deda_verified_progress/"+A),original);
});
test("03 request cannot supply identity, balance, old UID or rank",async()=>{
 for(const data of [{accountKey:A},{oldUid:O},{xp:99999},{diamonds:150},{installId:"copied"},{rank:1}]){
   const f=fixture();
   await assert.rejects(f.call({data}),e=>e.code==="permission-denied");
   assert.equal(f.queries.length,0);assert.deepEqual(f.writes,[]);
 }
});
test("04 forged signed-in user and revoked token fail before Firestore reads",async()=>{
 const f=fixture();
 f.auth.verifyIdToken=async()=>{throw Error("REVOKED");};
 await assert.rejects(f.call(),e=>e.code==="permission-denied");
 assert.equal(f.queries.length,0);
 const g=fixture();
 await assert.rejects(g.call({auth:{uid:O,token:{firebase:{sign_in_provider:"anonymous"}}}}),
   e=>e.code==="permission-denied");
 assert.equal(g.queries.length,0);
});
test("05 private server binding and full receipt chain are mandatory",async()=>{
 const f=fixture();
 f.docs.delete("deda_stage54_private_account_bindings/"+N);
 await assert.rejects(f.call(),e=>e.code==="permission-denied");
 assert.deepEqual(f.writes,[]);
 const g=fixture();
 for(const k of g.docs.keys())if(k.includes("deda_progress_receipts/"))g.docs.delete(k);
 await assert.rejects(g.call(),e=>e.code==="unavailable");
 assert.deepEqual(g.writes,[]);
});
test("06 wrong server balance or unfenced APK cannot issue link",async()=>{
 const f=fixture(),v="deda_verified_progress/"+A;
 f.docs.set(v,{...f.docs.get(v),balances:{
   points:25,coins:10,xp:125,earnedDiamonds:9999}});
 await assert.rejects(f.call(),e=>e.code==="unavailable");
 assert.deepEqual(f.writes,[]);
 const g=fixture();
 const fence="deda_progress_migrations/"+A+"/fences/"+F;
 g.docs.set(fence,{...g.docs.get(fence),status:"pending"});
 await assert.rejects(g.call(),e=>e.code==="unavailable");
 assert.deepEqual(g.writes,[]);
});
test("07 missing live emulator flag cannot execute callable",async()=>{
 const f=fixture(),old=process.env.GCLOUD_PROJECT;
 process.env.GCLOUD_PROJECT="production-deda";
 try{await assert.rejects(f.call(),/REFUSE_PRODUCTION/);}
 finally{process.env.GCLOUD_PROJECT=old;}
 assert.equal(f.queries.length,0);assert.deepEqual(f.writes,[]);
});
