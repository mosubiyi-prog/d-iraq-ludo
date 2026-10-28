"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore}=require("firebase-admin/firestore");
const {onCall,HttpsError}=require("firebase-functions/v2/https");
const {REQUIRED_OPTIONS,BLOCKERS,
 makeStage50ReadOnlyPreflightCallable:make}
 =require("../deda_weekly_stage50_auth_appcheck_readonly_preflight_NOT_EXPORTED.js");

const PROJECT="demo-deda-weekly-xp-stage9";
if(process.env.GCLOUD_PROJECT!==PROJECT||
   !process.env.FIRESTORE_EMULATOR_HOST)
  throw Error("STAGE50_TEST_REQUIRES_LOCAL_FIRESTORE_EMULATOR");
const app=initializeApp({projectId:PROJECT},"deda-stage50");
const db=getFirestore(app);
const ACCOUNT="07701234567",OTHER="07707654321";
const A="stage50_original_phone_uid";
const B="stage50_second_phone_uid";
const X="stage50_outsider_uid";
const APP_ID="1:00000:android:stage50-qa";
const ALT_APP_ID="1:99999:android:forged-stage50";
let capture={},handler,realCallable;
const stubOnCall=(opts,fn)=>{
 capture={opts,fn};
 return fn;
};
const mk=(uid=A,data={},appId=APP_ID,provider="password")=>({
 auth:{uid,token:{firebase:{sign_in_provider:provider}}},
 app:{appId},data
});
const init=()=>{
 handler=make({onCall:stubOnCall,HttpsError,db,
  approvedAppIds:[APP_ID],serverClock:()=>1793200000000});
 realCallable=make({onCall,HttpsError,db,
  approvedAppIds:[APP_ID],serverClock:()=>1793200000000});
};
async function qaUser(uid,accountKey){
 await db.doc("users/"+uid).set({uid,accountKey,
  sharePersonalId:"@DEDA-QA0001",name:"Stage50 QA",level:900,
  xp:100000,coins:10000,diamonds:50000});
 await db.doc("deda_sessions/"+uid).set({uid,accountKey,
  installId:uid+"_untrusted_mobile_install"});
}
test.before(async()=>{
 await Promise.all([
  qaUser(A,ACCOUNT),qaUser(B,ACCOUNT),qaUser(X,OTHER)
 ]);
 await Promise.all([
  db.doc("deda_account_profiles/"+ACCOUNT).set({
   accountKey:ACCOUNT,trustedInstallIds:["old_install","new_install"],
   diamonds:222222,level:1000}),
  db.doc("deda_account_profiles/"+OTHER).set({
   accountKey:OTHER,trustedInstallIds:["outsider_install"]}),
  db.doc("users/"+A+"/wallet/original").set({
   diamonds:9999,coins:701,xp:2024,frames:["royal"]}),
  db.doc("deda_admin_diamond_wallets/gm").set({diamonds:1000000})
 ]);
 init();
});
test.after(async()=>deleteApp(app));
function assertHold(x){
 assert.equal(x.readOnly,true);
 assert.equal(x.awardState,"HOLD_NO_GRANTS");
 for(const k of [
  "canCreditTaskPoints","canCreditLifetimeXp",
  "canCreditSocialCoins","canCreditLeagueXp",
  "canIssueWinnerGift","canCreditDiamonds",
  "productionRewardReady","realOldApkRevocationVerified"
 ])assert.equal(x[k],false,k);
 assert.deepEqual(x.blockers,BLOCKERS);
 const raw=JSON.stringify(x);
 assert.equal(raw.includes(ACCOUNT),false);
 assert.equal(raw.includes(A),false);
 assert.equal(raw.includes("9999"),false);
}
test("REAL Firebase Functions v2 onCall opts enforce AppCheck and limited-use consumption",()=>{
 assert.deepEqual(capture.opts,REQUIRED_OPTIONS);
 assert.equal(capture.opts.enforceAppCheck,true);
 assert.equal(capture.opts.consumeAppCheckToken,true);
 assert.equal(typeof realCallable,"function");
 // Actual SDK uses options; unit tests below supply synthetic request
 // contexts, NOT cryptographically verified Firebase Auth/App Check.
});
test("authenticated original UID with apparent App Check gets HOLD only, no wallet writes",async()=>{
 const result=await handler(mk());
 assertHold(result);
 assert.equal(result.authorizedAccountRecordExists,true);
 assert.equal((await db.doc("users/"+A+"/wallet/original").get()).data().diamonds,9999);
 assert.equal((await db.doc("deda_admin_diamond_wallets/gm").get()).data().diamonds,1000000);
});
test("same canonical account on another UID/phone also gets HOLD, no duplicate XP",async()=>{
 const [r1,r2]=await Promise.all([handler(mk(A)),handler(mk(B))]);
 assertHold(r1);assertHold(r2);
 assert.deepEqual(r1,r2);
 assert.equal((await db.collection("deda_verified_progress").get()).size,0);
 assert.equal((await db.collection("deda_weekly_stage45_private_shadow_earned_diamonds").get()).size,0);
});
test("mobile changing installId/trustedInstallIds never authorizes points",async()=>{
 await db.doc("deda_sessions/"+A).update({
  installId:"mobile_changed_to_claim_new_device"});
 await db.doc("deda_account_profiles/"+ACCOUNT).update({
  trustedInstallIds:["mobile_changed_to_claim_new_device"]});
 assertHold(await handler(mk(A)));
 assert.equal((await db.doc("deda_progress_receipts").get()).exists,false);
});
test("client may not supply own accountKey, XP, week, place, installation or diamonds",async()=>{
 for(const data of [
   {accountKey:ACCOUNT},{uid:A},{appId:APP_ID},{installId:"trusted"},
   {taskPoints:5},{xp:20},{coins:10},{earnedDiamonds:370},
   {weekId:"fake"},{rank:1},{shareId:"ABCDEFGHIJKLMNOPQRST"},
   {taskId:"share_personal_location"},{token:"fake"},{request:{}}
 ]){
  await assert.rejects(handler(mk(A,data)),e=>{
   assert.equal(e.code,"invalid-argument");return true;
  });
 }
});
test("unauthenticated or anonymous Auth context denied",async()=>{
 for(const r of [
  {data:{},app:{appId:APP_ID}},
  mk(""),
  mk(A,{},APP_ID,"anonymous")
 ]){
  await assert.rejects(handler(r),e=>{
   assert.equal(e.code,"unauthenticated");return true;
  });
 }
});
test("unapproved, absent or spoofed application ID denied",async()=>{
 for(const r of [
  mk(A,{},ALT_APP_ID),
  {auth:{uid:A},data:{}},
  mk(A,{},""),
 ]){
  await assert.rejects(handler(r),e=>{
   assert.equal(e.code,"permission-denied");return true;
  });
 }
});
test("unknown Firebase UID cannot read another account's information",async()=>{
 await assert.rejects(handler(mk("not_a_real_stage50_uid")),e=>{
  assert.equal(e.code,"failed-precondition");return true;
 });
 assertHold(await handler(mk(X)));
});
test("missing or conflicting user/session profile rejects rather than defaulting to another account",async()=>{
 const session=db.doc("deda_sessions/"+A);
 const old=(await session.get()).data();
 await session.update({accountKey:OTHER});
 await assert.rejects(handler(mk(A)),e=>{
  assert.equal(e.code,"failed-precondition");return true;
 });
 await session.set(old);
 const profile=db.doc("deda_account_profiles/"+ACCOUNT);
 const oldP=(await profile.get()).data();
 await profile.update({accountKey:OTHER});
 await assert.rejects(handler(mk(A)),e=>{
  assert.equal(e.code,"failed-precondition");return true;
 });
 await profile.set(oldP);
 assertHold(await handler(mk(A)));
});
test("temporary Firestore backend read errors fail closed, never allow",async()=>{
 const failing={doc:()=>({get:async()=>{throw Error("QA_backend_failure");}})};
 const fn=make({onCall:stubOnCall,HttpsError,db:failing,
  approvedAppIds:[APP_ID],serverClock:()=>1793200000000});
 await assert.rejects(fn(mk()),e=>{
  assert.equal(e.code,"unavailable");return true;
 });
});
test("empty or duplicate server App Check allowlists refuse function registration",()=>{
 for(const ids of [[],[APP_ID,APP_ID],["invalid app id"],[123]]){
  assert.throws(()=>make({onCall:stubOnCall,HttpsError,db,
   approvedAppIds:ids,serverClock:()=>1793200000000}),
   /STAGE50_SERVER_CONFIGURATION_MISSING/);
 }
});
test("source SDK onCall handler executable locally but does NOT prove real token verification",async()=>{
 assert.equal(typeof realCallable.run,"function");
 const result=await realCallable.run(mk(A));
 assertHold(result);
});
test("output never contains phone install ID, premium ID, balance, public ID or Auth tokens",async()=>{
 const r=await handler(mk(A));
 const text=JSON.stringify(r);
 for(const leak of [ACCOUNT,A,B,"mobile_changed_to_claim_new_device",
  "@DEDA-QA0001","9999","1000000","fake"]){
  assert.equal(text.includes(leak),false,leak);
 }
});
