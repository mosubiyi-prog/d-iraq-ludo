"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const crypto=require("node:crypto");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore}=require("firebase-admin/firestore");
const core=require("../../tools/app_stability/progress_archive/reconcile-core.cjs");
const {PROJECT,BINDING_ROOT,ISSUER}=require(
 "../../tools/app_stability/stage62/private_account_bound_signed_xp_reader.cjs");
const {ROOT:SOURCE_ROOT,ISSUER:SOURCE_ISSUER,receiptFor}=require(
 "../deda_weekly_stage42_server_share_action_producer_NOT_EXPORTED.js");
const {ROOT:EPOCH_ROOT,ISSUER:EPOCH_ISSUER}=require(
 "../deda_weekly_stage43_reviewed_cutover_epoch_NOT_EXPORTED.js");
const {ROOT:LEAGUE_ROOT}=require(
 "../deda_weekly_stage43_cutover_epoch_atomic_NOT_EXPORTED.js");
const {profilePath}=require(
 "../deda_weekly_stage44_verified_ledger_top10_archive_NOT_EXPORTED.js");
const {AUTH_ISSUER,authPath,confirmedPath,sealFields,sign}=require(
 "../deda_weekly_stage46_private_signed_task_claim_NOT_EXPORTED.js");
const {dayInIraq}=require(
 "../deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
if(process.env.GCLOUD_PROJECT!==PROJECT||
   process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
   process.env.FIREBASE_AUTH_EMULATOR_HOST!=="127.0.0.1:9099"||
   process.env.FIREBASE_FUNCTIONS_EMULATOR_HOST!=="127.0.0.1:5001"||
   process.env.DEDA_STAGE62_EMULATOR_ONLY!=="true")
 throw Error("STAGE62_MUST_RUN_ALL_REAL_LOCAL_EMULATORS");
const app=initializeApp({projectId:PROJECT},"stage62-signed-original-ledger");
const db=getFirestore(app),KEY=Buffer.from(process.env.STAGE62_PRIVATE_KEY_HEX,"hex");
const FIRST=Date.UTC(2026,9,27,3),NOW=FIRST+3600000;
assert.equal(Number(process.env.STAGE62_FIRST_OPEN_MS),FIRST);
assert.equal(Number(process.env.STAGE62_NOW_MS),NOW);
const ACCOUNT=["07701234567","07707896543"];
const UID_BIND="deda_weekly_stage62_private_qa_auth_account_bindings";
const UID="stage62_user_private_demo";
const WEEK="deda-20261027-w00001";
const AUTH="http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:";
const FUNC="http://127.0.0.1:5001/"+PROJECT+
 "/us-central1/dedaStage62PrivateAccountScopedSignedXpPreview";
const hash=s=>crypto.createHash("sha256").update(s).digest("hex");
const hmac=s=>crypto.createHmac("sha256",KEY).update(s).digest("hex");
const promiseRead=async path=>{const s=await db.doc(path).get();return s.exists?s.data():null;};
let ownerA,ownerB,outsider,password,credentials={},receipts={};
async function auth(method,payload){
 const response=await fetch(AUTH+method+"?key=stage62-private-only",{
  method:"POST",headers:{"Content-Type":"application/json"},
  body:JSON.stringify(payload)
 });
 const result=await response.json();
 if(!response.ok||!result.idToken||!result.localId)
   throw Error("STAGE62_AUTH_EMULATOR_REQUEST_FAILED_"+JSON.stringify(result));
 return result;
}
async function call(user,body={},headers={}){
 const h={"Content-Type":"application/json",...headers};
 if(user)h.Authorization="Bearer "+user.idToken;
 const res=await fetch(FUNC,{method:"POST",headers:h,
  body:JSON.stringify({data:body})});
 return {status:res.status,payload:await res.json()};
}
function denied(r){
 assert.notEqual(r.status,200,JSON.stringify(r).slice(0,340));
 assert.equal(r.payload.result,undefined);
}
function valid(r){
 assert.equal(r.status,200,JSON.stringify(r).slice(0,340));
 const x=r.payload.result;
 for(const [name,value] of Object.entries({
   readOnly:true,emulatorOnly:true,verified:false,
   productionReady:false,productionAppCheckVerified:false,
   originalAuthOwnershipVerified:false,oldApkWriterFenced:false,
   accountAssetsMigrated:false,canCreditDiamonds:false,canIssueGift:false,
   canWriteLevelXp:false,canWriteWallet:false,originalQuizChanged:false,
   actuallyCreditedDiamonds:0
 }))assert.equal(x[name],value,name);
 assert.equal(x.source,"stage62_PRIVATE_SIGNED_XP_PREVIEW_NOT_VERIFIED_LEAGUE");
 assert.equal(x.phase,"active");
 assert.equal(x.weekId,WEEK);
 assert.equal(x.topTen.length,2);
 assert.equal(x.topTen[0].weeklyXp,20);
 assert.equal(x.topTen[1].weeklyXp,20);
 assert.equal(x.topTen[0].place,1);
 assert.equal(x.topTen[1].place,2);
 for(const a of ACCOUNT)assert.equal(JSON.stringify(x).includes(a),false);
 for(const uid of [ownerA.localId,ownerB.localId])
   assert.equal(JSON.stringify(x).includes(uid),false);
 return x;
}
async function bind(uid,account){
 await db.doc(BINDING_ROOT+"/"+uid).set({
  issuer:ISSUER,emulatorOnly:true,canAuthorizeProduction:false,
  canCreditDiamonds:false,authUid:uid,accountKey:account,
  accountDigest:hmac("account:"+account),kind:"read_only_auth_fixture"
 });
}
async function seedOne(account,i){
 const created=NOW-120000+i*40000;
 const dayId=dayInIraq(created),{eventKey,receipt}=receiptFor(account,dayId);
 const initial=core.parseReceipt({
  format:1,accountKey:account,source:"legacy-baseline-v1",
  sourceId:"legacy-review|stage62-migration-00000001|"+hash("legacy|"+account),
  kind:"baseline",delta:{points:30,coins:20,xp:60,earnedDiamonds:15}
 },account);
 let state=core.applyEvent(null,initial);
 state=core.applyEvent(state,receipt);
 const key=core.eventKey(initial),migrationId="stage62-migration-00000001";
 const settlementId="stage62-settlement-00000001",sourceShareId="ABCDE"+String(i).padStart(15,"0");
 const reviewerId="stage62_reviewer_decision_0000000"+i;
 const current=await db.batch();
 current.set(db.doc("deda_progress_receipts/"+account+"/events/"+eventKey),receipt);
 current.set(db.doc("deda_verified_progress/"+account+"/events/"+eventKey),{
  format:1,accountKey:account,eventKey,receipt,receiptId:eventKey,
  appliedVersion:state.version,afterBalances:state.balances,
  createdAtMs:created+200,emitter:"stage43_private_reviewed_cutover_atomic_emulator_only"
 });
 current.set(db.doc("deda_verified_progress/"+account),state);
 current.set(db.doc(SOURCE_ROOT+"/"+eventKey),{
  issuer:SOURCE_ISSUER,emulatorOnly:true,canAuthorizeProduction:false,
  serverVerifiedAction:true,accountKey:account,dayId,
  taskId:"share_personal_location",eventKey,originalShareId:sourceShareId,
  originalSenderUid:"stage62_private_sender_"+i,
  sourceCreatedAtMs:created,sourceVerifiedAtMs:created+100,
  originalLocalClaimAwarded:"UNKNOWN_REQUIRES_MIGRATION_REVIEW",
  verifiedAs:"original_cross_account_share_action_only",
  coinsGranted:0,xpGranted:0,pointsGranted:0,diamondsGranted:0
 });
 current.set(db.doc(LEAGUE_ROOT+"/"+WEEK+"_"+eventKey),{
  emulatorOnly:true,issuer:SOURCE_ISSUER,accountKey:account,
  weekId:WEEK,dayId,eventKey,taskId:"share_personal_location",
  amount:20,createdAtMs:created+200
 });
 current.set(db.doc("deda_progress_migrations/"+account),{
  format:1,accountKey:account,migrationId,phase:"cutover-complete",
  evidenceDigest:hash("legacy|"+account),baselineEventKey:key,settlementId
 });
 current.set(db.doc(EPOCH_ROOT+"/"+account),{
  issuer:EPOCH_ISSUER,emulatorOnly:true,canAuthorizeProduction:false,
  accountKey:account,migrationId,evidenceDigest:hash("legacy|"+account),
  baselineEventKey:key,settlementId,
  phase:"reviewed-server-only-private-fixture",
  pendingLocalClaims:0,pendingPurchases:0,pendingReservations:0,
  realOldApkRevocationVerified:false,effectiveAtMs:FIRST-60000,
  expiresAtMs:NOW+3600000
 });
 current.set(db.doc(profilePath(account,KEY)),{
  issuer:"stage44_private_profile_fixture_only",emulatorOnly:true,
  accountKey:account,displayName:"مشارك ديدا "+(i+1),
  activePublicId:"@DEDA-"+String(i+1).padStart(6,"0"),level:i+1
 });
 current.set(db.doc("users/"+account+"/wallet/live_user"),{
  originalDiamonds:900+i,premiumId:"@DEDA-OWN"+i,frames:["owner_frame"+i]
 });
 current.set(db.doc(authPath(account,eventKey)),{
  format:1,issuer:AUTH_ISSUER,emulatorOnly:true,
  canAuthorizeProduction:false,accountKey:account,eventKey,
  taskId:"share_personal_location",migrationId,
  sourceShareId,sourceCreatedAtMs:created,reviewerDecisionId:reviewerId,
  reviewedClaimStatus:"fresh_server_only_after_cutover_fixture",
  originalLocalTaskPointsReconciledInFixture:true,
  originalLocalXpReconciledInFixture:true,
  originalLocalCoinsReconciledInFixture:true,
  pendingLegacyClaimsInFixture:0,reviewedAtMs:created+150
 });
 const sealed=sealFields({accountKey:account,dayId,eventKey,
  originalShareId:sourceShareId,migrationId,
  reviewerDecisionId:reviewerId,sourceCreatedAtMs:created,
  serverConfirmedAtMs:created+300});
 current.set(db.doc(confirmedPath(eventKey)),{
  record:sealed,signature:sign(KEY,sealed),emulatorOnly:true,
  canAuthorizeProduction:false
 });
 await current.commit();
 receipts[account]={eventKey,sourceCreatedAtMs:created};
}
test.before(async()=>{
 [ownerA,ownerB,outsider,password]=await Promise.all([
  auth("signUp",{returnSecureToken:true}),
  auth("signUp",{returnSecureToken:true}),
  auth("signUp",{returnSecureToken:true}),
  auth("signUp",{email:"stage62@example.invalid",
   password:"Stage62_private_PW_321",returnSecureToken:true})
 ]);
 await Promise.all([seedOne(ACCOUNT[0],0),seedOne(ACCOUNT[1],1)]);
 await bind(ownerA.localId,ACCOUNT[0]);
 await bind(ownerB.localId,ACCOUNT[1]);
 await db.doc("deda_admin_diamond_wallets/gm").set({diamonds:1000000});
});
test.after(async()=>deleteApp(app));
test("01: real anonymous Auth Emulator UID A reads server-signed XP, not phone-supplied scores",async()=>{
 const x=valid(await call(ownerA));
 assert.equal(x.viewerPlace,1);assert.equal(x.weekXP,20);
});
test("02: Auth UID B gets same order but only its own viewer rank",async()=>{
 const x=valid(await call(ownerB));
 assert.equal(x.viewerPlace,2);assert.equal(x.weekXP,20);
});
test("03: unrelated original anonymous user cannot access ranking by copying install ID",async()=>{
 denied(await call(outsider));
});
test("04: tokenless caller fails closed before any account snapshot",async()=>{
 denied(await call(null));
});
test("05: Firebase password user not treated as original DEDA PIN anonymous session",async()=>{
 denied(await call(password));
});
test("06: request cannot forge canonical account, UID, XP, rank, receipts or diamonds",async()=>{
 for(const body of [
  {accountKey:ACCOUNT[0]},{uid:ownerB.localId},{xp:999},
  {weeklyPoints:999},{diamonds:150},{rank:1},{taskId:"share_personal_location"},
  {trustedInstallIds:["copied"]},{appCheck:true},{weekIndex:4}
 ])denied(await call(ownerA,body));
});
test("07: missing signed task receipt fails WHOLE ranking instead of partial optimistic display",async()=>{
 const p=db.doc(confirmedPath(receipts[ACCOUNT[0]].eventKey));
 const old=await promiseRead(p.path);await p.delete();
 denied(await call(ownerB));await p.set(old);valid(await call(ownerB));
});
test("08: forged signed task claim awards must not alter either user's rank",async()=>{
 const p=db.doc(confirmedPath(receipts[ACCOUNT[1]].eventKey));
 const original=await promiseRead(p.path);
 await p.update({"record.lifetimeXp":1000000});
 denied(await call(ownerA));
 await p.set(original);valid(await call(ownerA));
});
test("09: independently reviewed claim missing disqualifies all standings",async()=>{
 const path=authPath(ACCOUNT[0],receipts[ACCOUNT[0]].eventKey);
 const p=db.doc(path),old=await promiseRead(path);
 await p.delete();denied(await call(ownerA));
 await p.set(old);valid(await call(ownerA));
});
test("10: changing original applied XP event invalidates standings",async()=>{
 const p=db.doc("deda_verified_progress/"+ACCOUNT[0]+
  "/events/"+receipts[ACCOUNT[0]].eventKey);
 const old=await promiseRead(p.path);
 await p.update({appliedVersion:0});
 denied(await call(ownerB));
 await p.set(old);valid(await call(ownerB));
});
test("11: changing migration / old APK epoch breaks source proof",async()=>{
 const p=db.doc(EPOCH_ROOT+"/"+ACCOUNT[1]),old=await promiseRead(p.path);
 await p.update({pendingLocalClaims:1});
 denied(await call(ownerA));
 await p.set(old);valid(await call(ownerA));
});
test("12: account A binding cannot be switched to B without server HMAC",async()=>{
 const p=db.doc(BINDING_ROOT+"/"+ownerA.localId),old=await promiseRead(p.path);
 await p.update({accountKey:ACCOUNT[1]});
 denied(await call(ownerA));
 await p.set(old);valid(await call(ownerA));
});
test("13: production flag spoofing and fake App Check do not grant production authority",async()=>{
 const x=valid(await call(ownerA,{},{"X-Firebase-AppCheck":"fake"}));
 assert.equal(x.productionAppCheckVerified,false);
});
test("14: idempotent repeated reads never create awards or duplicate earned XP",async()=>{
 const all=await Promise.all([call(ownerA),call(ownerA),call(ownerB)]);
 all.forEach(valid);
 assert.equal((await db.collection(LEAGUE_ROOT).get()).size,2);
});
test("15: original accounts' wallets, premium IDs, frames, GM million remain unchanged",async()=>{
 for(let i=0;i<ACCOUNT.length;i++){
  assert.deepEqual(await promiseRead("users/"+ACCOUNT[i]+"/wallet/live_user"),
   {originalDiamonds:900+i,premiumId:"@DEDA-OWN"+i,frames:["owner_frame"+i]});
 }
 assert.deepEqual(await promiseRead("deda_admin_diamond_wallets/gm"),{diamonds:1000000});
 assert.equal((await db.collection("deda_weekly_stage45_private_gift_inbox").get()).size,0);
});
test("16: no PIN, original phone, raw UID, balance or fake production VERIFIED value leaked",async()=>{
 const x=valid(await call(ownerA));
 const text=JSON.stringify(x);
 for(const token of [ACCOUNT[0],ACCOUNT[1],ownerA.localId,ownerB.localId,
  "@DEDA-OWN0","originalDiamonds","sourceShareId","pin"])
  assert.equal(text.includes(token),false,token);
 assert.equal(x.verified,false);
});
