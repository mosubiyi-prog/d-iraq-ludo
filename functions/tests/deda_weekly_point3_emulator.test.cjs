"use strict";
/* Actual local anonymous Auth + original Firestore Rules + Admin transaction.
 * The callable App Check context is synthetic in this test, not a production
 * attestation. The publisher record is synthetic, NOT a deployable source.
 */
const test=require("node:test"), assert=require("node:assert/strict");
const {initializeApp:initAdmin,deleteApp:deleteAdmin}=require("firebase-admin/app");
const {getFirestore:getAdminDb}=require("firebase-admin/firestore");
const {getAuth:getAdminAuth}=require("firebase-admin/auth");
const {initializeApp:initClient,deleteApp:deleteClient}=require("firebase/app");
const {getAuth,connectAuthEmulator,signInAnonymously}=require("firebase/auth");
const {getFirestore,connectFirestoreEmulator,doc,getDoc,setDoc}=require("firebase/firestore");
const {readVerifiedWeeklyStandings,WeeklyNotReady,serverSeal,viewerParticipantId}
  =require("../deda_weekly_verified_standings_reader_core");
const PROJECT="demo-deda-weekly-point3-qa";
if(process.env.GCLOUD_PROJECT!==PROJECT||
 process.env.DEDA_WEEKLY_POINT3_EMULATOR_ONLY!=="true"||
 !process.env.FIREBASE_AUTH_EMULATOR_HOST||
 !process.env.FIRESTORE_EMULATOR_HOST)
 throw Error("REFUSE_NON_DISPOSABLE_EMULATOR_TEST");
const ACCOUNT="07705554444";
const KEY="local-test-only-weekly-review-hmac-not-for-production";
const WEEK=7*86400000,CLOSE=WEEK-21600000;
const admin=initAdmin({projectId:PROJECT},"weekly-point3-admin");
const db=getAdminDb(admin),auth=getAdminAuth(admin);
let owner,outsider,serverNow;
const phones=[];
async function createPhone(){
 const app=initClient({
  apiKey:"local-firebase-only",appId:"1:5555:android:qa",projectId:PROJECT
 },"phone-"+phones.length);
 const a=getAuth(app);connectAuthEmulator(a,"http://127.0.0.1:9099",{disableWarnings:true});
 const fs=getFirestore(app);connectFirestoreEmulator(fs,"127.0.0.1",8080);
 const signed=await signInAnonymously(a);
 const p={app,uid:signed.user.uid,fs};phones.push(p);return p;
}
function req(p){
 return {auth:{uid:p.uid,token:{firebase:{sign_in_provider:"anonymous"}}},
  app:{appId:"synthetic-app-check-only"},data:{accountKey:ACCOUNT}};
}
function sample(){
 const open=serverNow-86400000;
 const previous=open-WEEK;
 const out={
  schema:1,issuer:"deda-weekly-reviewed-publisher-v1",issuedAtMs:serverNow-1000,
  sourceVerified:true,oldApkWriterFenced:true,
  canonicalAccountProofsVerified:true,payoutsAllowed:false,
  current:{weekId:"week_current_55",status:"live",openedAtMs:open,
   closeAtMs:open+CLOSE,nextOpenMs:open+WEEK,
   rows:[{place:1,participantId:viewerParticipantId(KEY,ACCOUNT),
     activePublicId:"@DEDA-Z12345",displayName:"Verified Member",
     weeklyPoints:40,verifiedTaskCompletions:2,diamondsIfFinalWinner:150}]},
  previous:{weekId:"week_previous_54",status:"closed",openedAtMs:previous,
   closeAtMs:previous+CLOSE,nextOpenMs:open,rows:[]}
 };
 out.signature=serverSeal(KEY,out);return out;
}
const run=p=>readVerifiedWeeklyStandings({
 request:req(p),db,auth,secret:KEY,nowMs:serverNow});
test.before(async()=>{
 serverNow=Date.now();
 owner=await createPhone();outsider=await createPhone();
 await db.doc("deda_account_directory/"+ACCOUNT).set({
  accountKey:ACCOUNT,active:true,createdUid:owner.uid,
 });
 await db.doc("deda_weekly_approved_publication/active").set(sample());
});
test.after(async()=>{
 for(const p of phones)await deleteClient(p.app);
 await deleteAdmin(admin);
});
test("1: even a live Auth UID cannot access ranking before server account bind",async()=>{
 await assert.rejects(run(owner),e=>e instanceof WeeklyNotReady);
});
test("2: private server binding unlocks read-only verified current/previous",async()=>{
 await db.doc("deda_secure_account_bindings/"+owner.uid).set({
  uid:owner.uid,accountKey:ACCOUNT,status:"PIN_VERIFIED_HOLD",
  canRestoreAssets:false,canMigrate:false,
 });
 const result=await run(owner);
 assert.equal(result.current.rows[0].weeklyPoints,40);
 assert.equal(result.current.viewerPlace,1);
 assert.equal(result.previous.rows.length,0);
 assert.equal(result.current.rewardsCredited,false);
});
test("3: second Auth UID remains denied without its own verified binding",async()=>{
 await assert.rejects(run(outsider),e=>e instanceof WeeklyNotReady);
});
test("4: full original Rules prohibit direct mobile tampering with source",async()=>{
 for(const path of [
  "deda_weekly_approved_publication/active",
  "deda_secure_account_bindings/"+owner.uid,
 ]){
  await assert.rejects(getDoc(doc(owner.fs,path)),
   e=>e.code==="permission-denied");
  await assert.rejects(setDoc(doc(owner.fs,path),{weeklyPoints:900000}),
   e=>e.code==="permission-denied");
 }
});
test("5: real original wallet untouched by verified standings reads",async()=>{
 await db.doc("users/"+owner.uid+"/wallet/original").set({
  diamonds:33,frames:["purchasedFrame"]});
 await run(owner);
 assert.deepEqual(
  (await db.doc("users/"+owner.uid+"/wallet/original").get()).data(),
  {diamonds:33,frames:["purchasedFrame"]});
 assert.equal((await db.doc("users/"+outsider.uid+"/wallet/original").get()).exists,false);
});
