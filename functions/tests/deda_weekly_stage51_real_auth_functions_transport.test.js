"use strict";
/**
 * REAL NETWORK integration across Firebase Auth Emulator + Firebase Functions
 * v2 Emulator + Firestore Emulator. Emits zero real or shadow reward writes.
 *
 * Auth Emulator creates UNSIGNED TEST-ONLY ID tokens; Functions Emulator
 * accepts them only for local QA. This is NOT proof that production token
 * signatures, App Check attestation, replay protection or device integrity
 * have been verified. The App Check gate is tested as a rejection boundary,
 * because no real App Check attestation can be minted by Auth Emulator.
 */
const test=require("node:test");
const assert=require("node:assert/strict");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore}=require("firebase-admin/firestore");

const PROJECT="demo-deda-stage51-auth-functions-qa";
if(process.env.GCLOUD_PROJECT!==PROJECT||
   !process.env.FIREBASE_AUTH_EMULATOR_HOST||
   !process.env.FIRESTORE_EMULATOR_HOST||
   !process.env.FIREBASE_FUNCTIONS_EMULATOR_HOST)
 throw Error("STAGE51_REAL_AUTH_FUNCTIONS_FIRESTORE_EMULATORS_REQUIRED");
const AUTH="http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:";
const FUNC="http://127.0.0.1:5001/"+PROJECT+"/us-central1/";
const ACCOUNT="07701234567";
const app=initializeApp({projectId:PROJECT},"deda-stage51-network");
const db=getFirestore(app);
const PASSWORD="FAKE_LOCAL_EMULATOR_ONLY_!23456789";
const users=[];
const REQUEST_BAD=[
  {xp:20},{coins:10},{diamonds:500},{accountKey:ACCOUNT},
  {rank:1},{weekId:"2026-10-27"},{installId:"claimed"},
  {trustedInstallIds:["claimed"]},{taskId:"share_personal_location"},
  {token:"fake"},{uid:"someone_else"},{request:{}}
];
async function auth(method,data){
 const r=await fetch(AUTH+method+"?key=stage51-emulator-not-real",{
  method:"POST",headers:{"Content-Type":"application/json"},
  body:JSON.stringify(data)
 });
 const body=await r.json();
 if(!r.ok)throw Error("STAGE51_TEST_AUTH_EMULATOR_FAILED_"+
   method+"_"+r.status+"_"+JSON.stringify(body).slice(0,200));
 return body;
}
async function invoke(name,{token=null,body={},appcheck=null,rawAuth=null}={}){
 const headers={"Content-Type":"application/json"};
 if(token)headers.Authorization="Bearer "+token;
 if(rawAuth)headers.Authorization=rawAuth;
 if(appcheck!==null)headers["X-Firebase-AppCheck"]=appcheck;
 const r=await fetch(FUNC+name,{
   method:"POST",headers,body:JSON.stringify({data:body})
 });
 let response;
 try{response=await r.json();}
 catch(e){throw Error("STAGE51_NON_JSON_FUNCTION_RESPONSE_"+r.status);}
 return {status:r.status,response};
}
function isHold(o){
 assert.equal(o.status,200,JSON.stringify(o).slice(0,300));
 assert.equal(o.response?.result?.readOnly,true);
 assert.equal(o.response.result.productionRewardReady,false);
 assert.equal(o.response.result.awardState,"HOLD_NO_GRANTS");
 for(const x of ["canCreditTaskPoints","canCreditLifetimeXp",
  "canCreditSocialCoins","canCreditLeagueXp",
  "canIssueWinnerGift","canCreditDiamonds"])
  assert.equal(o.response.result[x],false);
 const str=JSON.stringify(o.response);
 assert.equal(str.includes(ACCOUNT),false);
 assert.equal(str.includes(users[0]?.localId||"__never__"),false);
 assert.equal(str.includes("99999"),false);
}
test.before(async()=>{
 // REST signUp *actually* creates Firebase Auth emulator users/tokens.
 // No real Firebase account is provisioned.
 const one=await auth("signUp",{
  email:"stage51-one@example.invalid",password:PASSWORD,
  returnSecureToken:true
 });
 const two=await auth("signUp",{
  email:"stage51-two@example.invalid",password:PASSWORD,
  returnSecureToken:true
 });
 const outsider=await auth("signUp",{
  email:"stage51-outsider@example.invalid",password:PASSWORD,
  returnSecureToken:true
 });
 const anonymous=await auth("signUp",{returnSecureToken:true});
 users.push(one,two,outsider,anonymous);
 const batch=db.batch();
 for(let i=0;i<users.length;i++){
  const uid=users[i].localId;
  const account=i<2?ACCOUNT:"07707654321";
  batch.set(db.doc("users/"+uid),{
   uid,accountKey:account,diamonds:99999,
   personalId:"@DEDA-SECRET_STAGE51",name:"Synthetic Stage51"
  });
  batch.set(db.doc("deda_sessions/"+uid),{
   uid,accountKey:account,installId:"mobile_can_change_this"}
  );
 }
 batch.set(db.doc("deda_account_profiles/"+ACCOUNT),{
  accountKey:ACCOUNT,trustedInstallIds:["mobile_can_change_this"]
 });
 batch.set(db.doc("deda_account_profiles/07707654321"),{
  accountKey:"07707654321",trustedInstallIds:["other_install"]
 });
 batch.set(db.doc("users/"+one.localId+"/wallet/original"),{
  diamonds:99999,xp:1000,coins:200,frames:["silver"]
 });
 batch.set(db.doc("deda_admin_diamond_wallets/gm"),{diamonds:1000000});
 await batch.commit();
});
test.after(async()=>deleteApp(app));

test("ACTUAL Auth Emulator email/password sign-in issues an HTTP-usable ID token",async()=>{
 const again=await auth("signInWithPassword",{
  email:"stage51-one@example.invalid",password:PASSWORD,
  returnSecureToken:true
 });
 assert.equal(again.localId,users[0].localId);
 assert.equal(typeof again.idToken,"string");
 assert.ok(again.idToken.length>60);
 const call=await invoke("dedaStage51AuthOnlyProbe",{token:again.idToken});
 isHold(call);
 assert.equal(call.response.result.verifiedByLocalAuthEmulator,true);
 assert.equal(call.response.result.realAppCheckDeviceVerified,false);
});
test("SECOND authenticated phone/UID same canonical DEDA account remains HOLD",async()=>{
 const a=await invoke("dedaStage51AuthOnlyProbe",{token:users[0].idToken});
 const b=await invoke("dedaStage51AuthOnlyProbe",{token:users[1].idToken});
 isHold(a);isHold(b);
 assert.deepEqual(a.response.result,b.response.result);
});
test("unauthenticated HTTP callable request cannot impersonate a DEDA user",async()=>{
 const o=await invoke("dedaStage51AuthOnlyProbe");
 assert.notEqual(o.status,200);
 assert.equal(o.response?.result,undefined);
});
test("forged JWT and malformed Bearer header fail real Functions Auth parsing",async()=>{
 for(const rawAuth of [
  "Bearer eyJhbGciOiJub25lIn0.eyJzdWIiOiJzdGFnZTUxIn0.",
  "Bearer not.a.real.auth.token",
  "Bearer broken",
  "Basic fake",
 ]){
  const r=await invoke("dedaStage51AuthOnlyProbe",{rawAuth});
  assert.notEqual(r.status,200,rawAuth);
 }
});
test("Auth Emulator anonymous identity does not authorize DEDA reward readiness",async()=>{
 const r=await invoke("dedaStage51AuthOnlyProbe",{token:users[3].idToken});
 assert.notEqual(r.status,200);
});
test("valid locally-emulated Firebase UID with body-injected XP/account rejected",async()=>{
 for(const body of REQUEST_BAD){
  const r=await invoke("dedaStage51AuthOnlyProbe",{
   token:users[0].idToken,body
  });
  assert.notEqual(r.status,200,JSON.stringify(body));
 }
});
test("Auth token cannot authorize a true Stage50 reward without real App Check",async()=>{
 const checked=await invoke("dedaStage51ProtectedPreflight",{
  token:users[0].idToken
 });
 // App Check onCall V2 is configured to enforce; emulator may support
 // only a synthetic context, NOT a genuine production App Check token.
 // Either denies; at no time may the response approve XP/coins/diamonds.
 if(checked.status===200) {
  assert.equal(checked.response?.result?.productionRewardReady,false);
  assert.equal(checked.response?.result?.canCreditDiamonds,false);
 }else{
  assert.equal(checked.response?.result,undefined);
 }
});
test("forged App Check token is not sufficient for true Stage50 rewards",async()=>{
 const checked=await invoke("dedaStage51ProtectedPreflight",{
  token:users[0].idToken,appcheck:"stage51_forged_appcheck_token_not_signed"
 });
 if(checked.status===200){
  assert.equal(checked.response?.result?.productionRewardReady,false);
  assert.equal(checked.response?.result?.canCreditLifetimeXp,false);
 }else assert.equal(checked.response?.result,undefined);
});
test("trying to send original task/league reward IDs to the protected callable never succeeds",async()=>{
 for(const body of [
  {xp:20,coins:10,taskId:"share_personal_location"},
  {accountKey:ACCOUNT,diamonds:1000000},
  {winnerPlace:1,expectedDiamonds:150},
 ]){
  const r=await invoke("dedaStage51ProtectedPreflight",{
   token:users[0].idToken,body
  });
  assert.notEqual(r.response?.result?.productionRewardReady,true);
  assert.notEqual(r.response?.result?.canCreditTaskPoints,true);
  assert.notEqual(r.response?.result?.canCreditDiamonds,true);
 }
});
test("changing original mobile session install and trusted devices cannot enable rewards",async()=>{
 await db.doc("deda_sessions/"+users[0].localId).update({
  installId:"client_spoofed_install"
 });
 await db.doc("deda_account_profiles/"+ACCOUNT).update({
  trustedInstallIds:["client_spoofed_install"]
 });
 isHold(await invoke("dedaStage51AuthOnlyProbe",{token:users[0].idToken}));
 const protectedResponse=await invoke("dedaStage51ProtectedPreflight",{
  token:users[0].idToken
 });
 assert.notEqual(protectedResponse.response?.result?.productionRewardReady,true);
});
test("no local user diamonds/XP/coins or admin wallets touched by Auth or AppCheck probes",async()=>{
 const user=(await db.doc("users/"+users[0].localId+"/wallet/original").get()).data();
 assert.deepEqual(user,{
  diamonds:99999,xp:1000,coins:200,frames:["silver"]
 });
 const gm=(await db.doc("deda_admin_diamond_wallets/gm").get()).data();
 assert.equal(gm.diamonds,1000000);
 assert.equal((await db.collection("deda_verified_progress").get()).size,0);
 assert.equal((await db.collection("deda_weekly_stage45_private_gift_inbox").get()).size,0);
 assert.equal((await db.collection("deda_weekly_stage49_private_server_uid_bindings").get()).size,0);
});
