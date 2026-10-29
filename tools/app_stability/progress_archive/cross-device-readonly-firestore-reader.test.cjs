"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {makeReadOnlyFirestoreReader:make}=
 require("./cross-device-readonly-firestore-reader.cjs");
const ACCOUNT="07701234567",TOKEN="a".repeat(64);
const ENV={
 GCLOUD_PROJECT:process.env.GCLOUD_PROJECT,
 FIRESTORE_EMULATOR_HOST:process.env.FIRESTORE_EMULATOR_HOST,
 DEDA_RESTORE_AUDIT_EMULATOR_ONLY:process.env.DEDA_RESTORE_AUDIT_EMULATOR_ONLY,
};
process.env.GCLOUD_PROJECT="demo-deda-restore-readiness";
process.env.FIRESTORE_EMULATOR_HOST="127.0.0.1:8080";
process.env.DEDA_RESTORE_AUDIT_EMULATOR_ONLY="true";
const snapshotDocs=new Map([
 ["deda_account_directory/"+ACCOUNT,{accountKey:ACCOUNT,active:true}],
 ["deda_verified_progress/"+ACCOUNT+"/events/"+TOKEN,
   {appliedVersion:1,accountKey:ACCOUNT,eventKey:TOKEN}],
]);
function fake(){
 const flags=[],operations=[];
 const db={
   doc(path){return {kind:"doc",path};},
   collection(path){return {
     orderBy(field,dir){
       assert.equal(field,"appliedVersion");
       assert.equal(dir,"asc");
       return {limit(n){return {kind:"query",path,n};}};
     },
   };},
   async runTransaction(callback,opts){
     flags.push(opts);
     // Simulated one server snapshot, independent of later external writes.
     const original=new Map(structuredClone([...snapshotDocs.entries()]));
     const txn={
       get:async ref=>{
         operations.push(ref);
         if(ref.kind==="doc"){
           const found=original.has(ref.path);
           return {exists:found,data:()=>original.get(ref.path)};
         }
         if(ref.kind==="query"){
           return {docs:[...original.entries()].filter(([key])=>
             key.startsWith(ref.path+"/"))
             .map(([key,data])=>({id:key.slice(ref.path.length+1),
               data:()=>data}))
             .sort((a,b)=>a.data().appliedVersion-b.data().appliedVersion)
             .slice(0,ref.n)};
         }
         throw Error("UNSUPPORTED_REFERENCE");
       },
     };
     return callback(txn);
   },
 };
 return {db,flags,operations};
}
test("01 only server read-only transaction, no commit methods exposed",async()=>{
 const f=fake();
 const reader=make(f.db);
 const returned=await reader.runReadOnlyTransaction(async view=>{
   assert.equal(typeof view.set,"undefined");
   assert.equal(typeof view.update,"undefined");
   assert.equal(typeof view.delete,"undefined");
   assert.equal(Object.isFrozen(view),true);
   const first=await view.get("deda_account_directory/"+ACCOUNT);
   assert.equal(first.active,true);
   const result=await view.list("deda_verified_progress/"+ACCOUNT+"/events",{limit:256});
   assert.equal(result.length,1);
   assert.equal(result[0].id,TOKEN);
   assert.equal(result[0].data.appliedVersion,1);
   return "HOLD";
 });
 assert.equal(returned,"HOLD");
 assert.deepEqual(f.flags,[{readOnly:true}]);
 assert.equal(f.operations.length,2);
});
test("02 refuses any unapproved document or collection or unbounded query",async()=>{
 const f=fake(),reader=make(f.db);
 await reader.runReadOnlyTransaction(async tx=>{
   for(const path of [
     "users","users/new_phone/wallet/original",
     "deda_admin_diamond_wallets/global",
     "deda_verified_progress/"+ACCOUNT+"/events/"+TOKEN+"/extra/forged",
     "deda_verified_progress/"+ACCOUNT+"/events/anything",
   ])await assert.rejects(tx.get(path),/DENIED_READONLY_DOCUMENT_PATH/);
   for(const [path,limit] of [
     ["deda_progress_receipts/"+ACCOUNT+"/events",20],
     ["deda_verified_progress/"+ACCOUNT+"/events",999],
     ["deda_verified_progress/"+ACCOUNT+"/events",0],
     ["users",5],
   ])await assert.rejects(tx.list(path,{limit}),/DENIED_READONLY_COLLECTION_QUERY/);
 });
 assert.equal(f.operations.length,0);
});
test("03 missing live Firestore Emulator environment stops execution",async()=>{
 const f=fake(),reader=make(f.db);
 const old=process.env.GCLOUD_PROJECT;
 process.env.GCLOUD_PROJECT="real-owner-deda-production";
 try{
   assert.throws(()=>make(f.db),/EMULATOR_REQUIRED/);
   await assert.rejects(reader.runReadOnlyTransaction(async()=>{}),/EMULATOR_REQUIRED/);
 }finally{process.env.GCLOUD_PROJECT=old;}
 assert.equal(f.operations.length,0);
 assert.equal(f.flags.length,0);
});
test("04 unavailable Admin SDK fails closed, not silently uses a cache",async()=>{
 const f=fake(),reader=make({...f.db,runTransaction:async()=>{throw Error("SERVER_DOWN");}});
 await assert.rejects(reader.runReadOnlyTransaction(async()=>true),/SERVER_DOWN/);
 assert.equal(f.flags.length,0);
});
test("05 a changing collection cannot mix document reads inside one transaction",async()=>{
 const f=fake(),reader=make(f.db);
 const original=snapshotDocs.get("deda_account_directory/"+ACCOUNT);
 try{
   const result=await reader.runReadOnlyTransaction(async view=>{
     const before=await view.get("deda_account_directory/"+ACCOUNT);
     snapshotDocs.set("deda_account_directory/"+ACCOUNT,{accountKey:ACCOUNT,active:false});
     const after=await view.get("deda_account_directory/"+ACCOUNT);
     assert.deepEqual(before,after);
     return "HOLD";
   });
   assert.equal(result,"HOLD");
 }finally{snapshotDocs.set("deda_account_directory/"+ACCOUNT,original);}
});
test.after(()=>{
 for(const [key,val] of Object.entries(ENV)){
   if(val===undefined)delete process.env[key];
   else process.env[key]=val;
 }
});
