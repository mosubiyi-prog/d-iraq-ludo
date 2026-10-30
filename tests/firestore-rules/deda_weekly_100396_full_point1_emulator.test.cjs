"use strict";
/* REAL local Firestore+Auth emulator. Deliberately synthetic action records,
 * never production proof or real player data. No app build or deploy.
 */
const {test,before,after}=require("node:test");
const assert=require("node:assert/strict");
const {initializeApp:adminApp,deleteApp:deleteAdmin}=require("firebase-admin/app");
const {getFirestore}=require("firebase-admin/firestore");
const {getAuth:getAdminAuth}=require("firebase-admin/auth");
const {initializeApp:clientApp,deleteApp:deleteClient}=require("firebase/app");
const {getAuth,connectAuthEmulator,signInAnonymously}=require("firebase/auth");
const {getFirestore:getClientDb,connectFirestoreEmulator,doc,getDoc,setDoc}=
 require("firebase/firestore");
const progress=require("../../tools/app_stability/progress_archive/reconcile-core.cjs");
const {processProof}=require("../../functions/deda_weekly_100396_task_xp_trigger_core.js");
const {readWeeklyStandings}=require("../../functions/deda_weekly_100396_standings_reader_core.js");
const {seal}=require("../../functions/deda_weekly_verified_xp_mirror_NOT_EXPORTED.js");
const PROJECT="demo-deda-restore-readiness";
if(process.env.GCLOUD_PROJECT!==PROJECT||
   process.env.DEDA_CANONICAL_LEAGUE_EMULATOR_ONLY!=="true"||
   !process.env.FIRESTORE_EMULATOR_HOST||
   !process.env.FIREBASE_AUTH_EMULATOR_HOST)
 throw Error("DEDA_EMULATOR_ONLY_DO_NOT_TOUCH_REAL_USERS");
const FIRST=Date.UTC(2026,9,19,3),WEEK=7*86400000;
const PREV_TIME=FIRST+3*86400000,CUR_TIME=FIRST+WEEK+3*86400000;
const NOW=CUR_TIME+3600000,KEY=Buffer.alloc(32,87),VIEW=Buffer.alloc(32,65);
const ID="@DEDA-AC1234",ACCOUNT="07708881234",OTHER="07708881235";
const admin=adminApp({projectId:PROJECT},"e2e-stage100396");
const db=getFirestore(admin),auth=getAdminAuth(admin),phones=[];
async function phone(){
 const app=clientApp({apiKey:"emulator-only",projectId:PROJECT,
  appId:"1:45678:android:emulator"},"e2e-client-"+phones.length);
 const a=getAuth(app);
 connectAuthEmulator(a,"http://127.0.0.1:9099",{disableWarnings:true});
 const fs=getClientDb(app);
 connectFirestoreEmulator(fs,"127.0.0.1",8080);
 const u=await signInAnonymously(a);
 const p={app,uid:u.user.uid,fs};phones.push(p);return p;
}
function day(ms){
 const date=new Intl.DateTimeFormat("en-CA",{
  timeZone:"Asia/Baghdad",year:"numeric",month:"2-digit",day:"2-digit",
 }).formatToParts(new Date(ms));
 const p=Object.fromEntries(date.map(x=>[x.type,x.value]));
 return p.year+"-"+p.month+"-"+p.day;
}
async function apply(account,taskId,when,n=1){
 const receipt={format:1,accountKey:account,source:"task-claim-v1",
  sourceId:"daily-task|"+day(when)+"|"+taskId,kind:"award",
  delta:{points:5,coins:10,xp:20,earnedDiamonds:0}};
 const eventKey=progress.eventKey(receipt);
 const appliedVersion=n+1;
 const event={format:1,accountKey:account,eventKey,receipt,
  appliedVersion,createdAt:new Date(when),
  afterBalances:{xp:n*20,points:n*5,coins:n*10,earnedDiamonds:0}};
 const proofFields={accountKey:account,dayId:day(when),taskId,
  eventKey,appliedVersion,awardedAtMs:when,
  actionId:"emulatorServerAction_"+taskId+"_"+n};
 const proof={schema:1,issuer:"deda_server_verified_original_action_v1",
  productionApproved:true,...proofFields,
  signature:seal(KEY,proofFields)};
 await Promise.all([
  db.doc("deda_verified_progress/"+account+"/events/"+eventKey).set(event),
  db.doc("deda_weekly_server_action_proofs/"+eventKey).set(proof),
 ]);
 return {proof,eventKey,account,when};
}
const run=e=>processProof({
 db,proof:e.proof,eventKey:e.eventKey,secret:KEY,nowMs:e.when+1000});
const request=p=>({
 auth:{uid:p.uid,token:{firebase:{sign_in_provider:"anonymous"}}},
 app:{appId:"1:45678:android:fake-app-check-emulator-only"},
 data:{accountKey:ACCOUNT},
});
const standings=p=>readWeeklyStandings({
 db,auth,request:request(p),secret:VIEW,nowMs:NOW,
});
let owner,outsider,second,oldTask,currentTask,otherTask;
before(async()=>{
 owner=await phone();outsider=await phone();second=await phone();
 const batch=db.batch();
 batch.set(db.doc("deda_weekly_verified_calendar/active"),{
  enabled:true,publisherApproved:true,firstOpenMs:FIRST,
  allowLocalTaskBooleanProofs:false,allowClientMintedXp:false,
 });
 batch.set(db.doc("deda_account_directory/"+ACCOUNT),{
  accountKey:ACCOUNT,active:true,createdUid:owner.uid});
 batch.set(db.doc("deda_account_profiles/"+ACCOUNT),{
  accountKey:ACCOUNT,name:"مستخدم تجريبي"});
 batch.set(db.doc("users/"+owner.uid),{
  accountKey:ACCOUNT,sharePersonalId:ID,diamonds:500});
 batch.set(db.doc("deda_share_ids/"+ID),{
  publicId:ID,ownerUid:owner.uid,active:true,kind:"personal"});
 batch.set(db.doc("users/"+owner.uid+"/wallet/original"),{
  diamonds:500,frames:["purchased-frame"]});
 batch.set(db.doc("deda_account_directory/"+OTHER),{
  accountKey:OTHER,active:true,createdUid:outsider.uid});
 batch.set(db.doc("deda_account_profiles/"+OTHER),{
  accountKey:OTHER,name:"منافس تجريبي"});
 batch.set(db.doc("users/"+outsider.uid),{
  accountKey:OTHER,sharePersonalId:"@DEDA-AC1235"});
 batch.set(db.doc("deda_share_ids/@DEDA-AC1235"),{
  publicId:"@DEDA-AC1235",ownerUid:outsider.uid,active:true,kind:"personal"});
 await batch.commit();
});
after(async()=>{
 for(const p of phones)await deleteClient(p.app);
 await deleteAdmin(admin);
});
test("01 already-applied verified XP in prior and current weeks mirrors once",async()=>{
 oldTask=await apply(ACCOUNT,"open_map",PREV_TIME);
 currentTask=await apply(ACCOUNT,"open_map",CUR_TIME);
 assert.equal((await run(oldTask)).status,"COUNTED");
 assert.equal((await run(currentTask)).status,"COUNTED");
 assert.equal((await run(currentTask)).status,"ALREADY_COUNTED");
 const view=await standings(owner);
 assert.equal(view.current.rows.length,1);
 assert.equal(view.current.rows[0].weeklyPoints,20);
 assert.equal(view.previous.rows[0].weeklyPoints,20);
 assert.equal(view.current.viewerPlace,1);
 assert.equal(view.current.rewardsCredited,false);
 assert.equal(JSON.stringify(view).includes(ACCOUNT),false);
});
test("02 second real competition account enters same weekly top10",async()=>{
 otherTask=await apply(OTHER,"open_map",CUR_TIME,1);
 await run(otherTask);
 const extra=await apply(ACCOUNT,"open_saved_place",CUR_TIME+30000,2);
 await run(extra);
 const view=await standings(owner);
 assert.deepEqual(view.current.rows.map(x=>x.weeklyPoints),[40,20]);
 assert.equal(view.current.rows[0].diamondsIfFinalWinner,150);
 assert.equal(view.current.rows[1].diamondsIfFinalWinner,100);
});
test("03 real original wallet unchanged after weekly rank projection",async()=>{
 const wallet=(await db.doc("users/"+owner.uid+"/wallet/original").get()).data();
 assert.deepEqual(wallet,{diamonds:500,frames:["purchased-frame"]});
 const user=(await db.doc("users/"+owner.uid).get()).data();
 assert.equal(user.diamonds,500);
});
test("04 unrelated authenticated UID cannot impersonate owner leaderboard view",async()=>{
 await assert.rejects(standings(second),/ACCOUNT_OR_CALENDAR_UNVERIFIED/);
});
test("05 second anonymous phone with server PIN binding sees same account rank",async()=>{
 await db.doc("deda_secure_account_bindings/"+second.uid).set({
  uid:second.uid,accountKey:ACCOUNT,status:"PIN_VERIFIED_HOLD",
  canMigrate:false,canRestoreAssets:false});
 const first=await standings(owner),later=await standings(second);
 assert.equal(first.current.viewerPlace,later.current.viewerPlace);
 assert.deepEqual(first.current.rows,later.current.rows);
});
test("06 real original Firestore rules deny mobile reading/forging private league",async()=>{
 for(const path of [
  "deda_weekly_verified_calendar/active",
  "deda_weekly_server_action_proofs/"+currentTask.eventKey,
  "deda_weekly_verified_xp_mirror_private/deda-20261026-w00002/scores/fake",
 ]){
  await assert.rejects(getDoc(doc(owner.fs,path)),e=>e.code==="permission-denied");
  await assert.rejects(setDoc(doc(owner.fs,path),{weeklyPoints:999999}),
   e=>e.code==="permission-denied");
 }
});
