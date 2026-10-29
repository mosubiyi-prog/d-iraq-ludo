"use strict";
/**
 * REAL Firestore emulator + REAL Admin SDK transactions. The Auth verifier
 * is a synthetic fixture here; no production Auth, Firestore or user data.
 * The isolated Rules emulator tests separately prove actual client denials.
 */
const {test,before,after}=require("node:test");
const assert=require("node:assert/strict");
const {createHash}=require("node:crypto");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore,Timestamp,FieldValue}=require("firebase-admin/firestore");
const fs=require("node:fs");
const {initializeTestEnvironment,assertSucceeds,assertFails}=
 require("@firebase/rules-unit-testing");
const {doc,updateDoc,getDoc,serverTimestamp}=require("firebase/firestore");
const core=require("../../tools/app_stability/progress_archive/reconcile-core.cjs");
const {createSecondPhoneLinkCallable}=
 require("../../tools/app_stability/progress_archive/second-phone-link-callable.cjs");

const PROJECT="demo-deda-restore-readiness",ACCOUNT="07701234567";
const OLD="original_emulator_uid_00000001",NEW="second_emulator_uid_00000002";
const ORIGINAL="@DEDA-ABC123",PREMIUM="@DEDA-ROYAL1";
const MIG="migration_reference_00000001",SETTLE="settlement_reference_000001";
const FENCE="legacy_fence_reference_000001";
const BASELINE={format:1,accountKey:ACCOUNT,source:"legacy-baseline-v1",
 sourceId:"legacy-review|"+MIG+"|"+"a".repeat(64),kind:"baseline",
 delta:{points:15,coins:30,xp:75,earnedDiamonds:400}};
const EVENT=core.eventKey(BASELINE),TIME=Timestamp.fromMillis(500000);
const TOKEN="synthetic_emulator_anon_firebase_token_123456789";
const LINK="deda_private_second_phone_links/"+NEW;
const ID_ROUTE="deda_share_ids/"+ORIGINAL;
const MONEY="deda_diamond_gift_balances/"+ORIGINAL;
let app,db,callable,auth;
class HttpsError extends Error{
 constructor(code,message){super(message);this.code=code;}
}
function checkGuard(){
 assert.equal(process.env.GCLOUD_PROJECT,PROJECT);
 assert.equal(process.env.FIRESTORE_EMULATOR_HOST,"127.0.0.1:8080");
 assert.equal(process.env.DEDA_RESTORE_AUDIT_EMULATOR_ONLY,"true");
 assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,"127.0.0.1:9099");
 assert.equal(process.env.FIREBASE_FUNCTIONS_EMULATOR_HOST,"127.0.0.1:5001");
 assert.match(process.env.DEDA_RESTORE_AUDIT_LINK_KEY_HEX||"",/^[a-f0-9]{64}$/);
}
function request(uid=NEW){
 return {auth:{uid,token:{firebase:{sign_in_provider:"anonymous"}}},
   data:{},rawRequest:{headers:{authorization:"Bearer "+TOKEN}}};
}
async function write(path,data){await db.doc(path).set(data);}
async function read(path){const s=await db.doc(path).get();return s.exists?s.data():null;}
before(async()=>{
 checkGuard();
 app=initializeApp({projectId:PROJECT},"deda-real-admin-qa");
 db=getFirestore(app);
 auth={
  async verifyIdToken(token){assert.equal(token,TOKEN);
    return {uid:NEW,firebase:{sign_in_provider:"anonymous"}};},
  async getUser(uid){return {uid,disabled:false,email:null,providerData:[]};},
 };
 callable=createSecondPhoneLinkCallable({
   onCall:(_options,callback)=>callback,HttpsError,db,auth,
   serverTimestamp:()=>FieldValue.serverTimestamp(),
 });
 const root="deda_progress_migrations/"+ACCOUNT;
 const docs=[
 ["deda_account_directory/"+ACCOUNT,{accountKey:ACCOUNT,active:true,createdUid:OLD}],
 ["deda_account_profiles/"+ACCOUNT,{accountKey:ACCOUNT,name:"QA Only"}],
 [ID_ROUTE,{publicId:ORIGINAL,kind:"personal",active:true,
    ownerUid:OLD,displayName:"Original",createdAt:TIME,updatedAt:TIME}],
 ["users/"+OLD,{accountKey:ACCOUNT,sharePersonalId:ORIGINAL,name:"Original owner"}],
 ["users/"+NEW,{accountKey:ACCOUNT,name:"Original owner's name",
    authMethod:"deda_pin_firestore_v1",trustedInstallIds:["qa-device"]}],
 ["deda_sessions/"+OLD,{uid:OLD,accountKey:ACCOUNT,installId:"qa-original"}],
 ["deda_sessions/"+NEW,{uid:NEW,accountKey:ACCOUNT,installId:"qa-device"}],
 ...[OLD,NEW].map(uid=>["deda_stage54_private_account_bindings/"+uid,
    {uid,accountKey:ACCOUNT,authProvider:"anonymous",
     state:"LOCAL_VERIFIED_HOLD_ONLY",emulatorOnly:true,canMigrate:false,
     canGrant:false,createdAt:TIME}]),
 [root,{format:1,accountKey:ACCOUNT,migrationId:MIG,phase:"cutover-complete",
   evidenceDigest:"a".repeat(64),baselineEventKey:EVENT,settlementId:SETTLE}],
 ["deda_verified_progress/"+ACCOUNT,{
   format:1,accountKey:ACCOUNT,version:1,initializedBy:EVENT,
   balances:{...BASELINE.delta}}],
 ["deda_progress_receipts/"+ACCOUNT+"/events/baseline_"+EVENT,BASELINE],
 ["deda_verified_progress/"+ACCOUNT+"/events/"+EVENT,{
   format:1,accountKey:ACCOUNT,eventKey:EVENT,receipt:BASELINE,
   receiptId:"baseline_"+EVENT,appliedVersion:1,
   afterBalances:{...BASELINE.delta},createdAt:TIME}],
 [root+"/settlementReviews/"+SETTLE,{
   accountKey:ACCOUNT,migrationId:MIG,settlementId:SETTLE,status:"resolved",
   originalId:ORIGINAL,legacyFenceId:FENCE,pendingPurchases:0,
   pendingReservations:0}],
 [root+"/settlements/"+SETTLE,{
   format:1,accountKey:ACCOUNT,migrationId:MIG,
   evidenceDigest:"a".repeat(64),baselineEventKey:EVENT,
   legacyFenceId:FENCE,pendingPurchases:0,pendingReservations:0}],
 [root+"/fences/"+FENCE,{
   format:1,accountKey:ACCOUNT,migrationId:MIG,
   evidenceDigest:"a".repeat(64),originalId:ORIGINAL,legacyFenceId:FENCE,
   protocol:"deda-verified-progress-v1",
   deploymentRevision:"deployment_revision_000001",
   enforcementRevision:"c".repeat(64),status:"enforced",createdAt:TIME}],
 ["deda_progress_migrations/_policy/settings/verified-cutover-v1",{
   format:1,enabled:true,revision:"deployment_revision_000001",
   protocol:"deda-verified-progress-v1",
   enforcementRevision:"c".repeat(64),clientBound:true,
   providersReady:true,atomicPurchasesReady:true}],
 [root+"/activations/"+MIG,{
   accountKey:ACCOUNT,migrationId:MIG,settlementId:SETTLE,
   baselineEventKey:EVENT,
   deploymentRevision:"deployment_revision_000001",
   enforcementRevision:"c".repeat(64)}],
 [MONEY,{publicId:ORIGINAL,balance:5000,createdAt:TIME,updatedAt:TIME}],
 ["deda_lab_frame_receipts/"+ORIGINAL+"/frames/FRAME_03",{
   kind:"lab_frame",publicId:ORIGINAL,frameId:"FRAME_03",cost:1000,
   createdAt:TIME}],
 ["deda_lab_owned_frames/"+ORIGINAL+"/frames/FRAME_03",{
   publicId:ORIGINAL,frameId:"FRAME_03",
   receiptId:ORIGINAL+"_FRAME_03",createdAt:TIME}],
 ["deda_stage66_card_receipts/"+ORIGINAL+"_gold",{
   kind:"card",publicId:ORIGINAL,style:"gold",cost:5000,createdAt:TIME}],
 ["deda_stage66_owned_cards/"+ORIGINAL+"_gold",{
   publicId:ORIGINAL,style:"gold",receiptId:ORIGINAL+"_gold",createdAt:TIME}],
 ["deda_owned_identifier_accounts/"+createHash("sha256").update(ACCOUNT).digest("hex"),{
   accountKey:ACCOUNT,originalId:ORIGINAL,
   activeId:PREMIUM,ownedIds:[ORIGINAL,PREMIUM]}],
 ["deda_owned_identifier_registry/"+PREMIUM,{
   identifier:PREMIUM,accountKey:ACCOUNT,originalId:ORIGINAL,status:"owned"}],
 ["deda_owned_identifier_aliases/"+PREMIUM,{
   identifier:PREMIUM,accountKey:ACCOUNT,originalId:ORIGINAL,
   kind:"permanent_alias"}],
 ];
 for(const [path,data] of docs)await write(path,data);
});
after(async()=>{if(app)await deleteApp(app);});

test("01 real Firestore Admin transaction moves original ID, preserves canonical wallet and receipts",async()=>{
 const originalWallet=await read(MONEY);
 const first=await callable(request());
 assert.equal(first.status,"ACCOUNT_LINKED_READONLY_EMULATOR_ONLY");
 assert.equal(first.replayed,false);
 assert.deepEqual(first.verifiedProgress,{
   format:1,version:1,points:15,coins:30,xp:75,earnedDiamonds:400,
   spendable:false,entitlementsVerified:false,
 });
 assert.deepEqual(first.verifiedEntitlements.ownedFrames,["FRAME_03"]);
 assert.deepEqual(first.verifiedEntitlements.ownedCards,["gold"]);
 assert.deepEqual(first.verifiedEntitlements.ownedPremiumIds,[PREMIUM]);
 assert.equal(first.verifiedEntitlements.activePremiumId,PREMIUM);
 assert.equal(first.verifiedEntitlements.grantAuthority,false);
 const canonical=await read(LINK),owned=await read(ID_ROUTE);
 assert.equal(canonical.oldUid,OLD);assert.equal(canonical.newUid,NEW);
 assert.equal(owned.publicId,ORIGINAL);assert.equal(owned.ownerUid,NEW);
 assert.deepEqual(await read(MONEY),originalWallet);
 assert.equal((await read("users/"+NEW)).sharePersonalId,ORIGINAL);
 assert.equal((await read("users/"+NEW)).name,"Original owner's name");
 assert.equal((await read("users/"+OLD)).sharePersonalId,ORIGINAL);
 assert.equal((await read("deda_migration_spend_authority/"+ORIGINAL)).activeUid,NEW);
 assert.equal((await read("deda_migration_account_authority/"+ACCOUNT)).activeUid,NEW);
 const retry=await callable(request());
 assert.equal(retry.replayed,true);
 assert.equal((await read(LINK)).digest,canonical.digest);
 assert.deepEqual(await read(MONEY),originalWallet);
});
test("02 third phone, forged UID, fake payload cannot claim original ID or spend balance",async()=>{
 const before=await read(MONEY),route=await read(ID_ROUTE);
 for(const forged of [
   {...request(),data:{earnedDiamonds:9999999}},
   {...request(),auth:{uid:OLD,token:{firebase:{sign_in_provider:"anonymous"}}}},
   {...request(),data:{originalId:ORIGINAL}},
 ]){
   await assert.rejects(callable(forged),e=>e.code==="permission-denied");
 }
 assert.deepEqual(await read(MONEY),before);
 assert.equal((await read(ID_ROUTE)).ownerUid,route.ownerUid);
});
test("03 SAME real Admin handover and real client Rules enforce exclusive wallet debit",async()=>{
 const candidatePath=process.env.DEDA_ADMIN_CANDIDATE_RULES;
 assert.match(candidatePath||"",/^\/tmp\/deda-second-phone-admin-candidate-[a-z0-9_-]+\.rules$/);
 const rules=fs.readFileSync(candidatePath,"utf8");
 assert.match(rules,/DEDA_NEW_PHONE_WALLET_WRITER_CUTOVER_CANDIDATE/);
 const env=await initializeTestEnvironment({
   projectId:PROJECT,firestore:{host:"127.0.0.1",port:8080,rules},
 });
 try{
   const oldClient=env.authenticatedContext(OLD).firestore();
   const newClient=env.authenticatedContext(NEW).firestore();
   const before=await read(MONEY);
   await assertFails(updateDoc(doc(oldClient,MONEY),{
     balance:1,updatedAt:serverTimestamp(),
   }));
   await assertSucceeds(updateDoc(doc(newClient,MONEY),{
     balance:4900,updatedAt:serverTimestamp(),
   }));
   assert.equal((await assertSucceeds(getDoc(doc(newClient,MONEY)))).data().balance,4900);
   assert.equal((await read(LINK)).newUid,NEW);
   assert.equal((await read(ID_ROUTE)).ownerUid,NEW);
   assert.equal(before.balance,5000);
   await assertFails(updateDoc(doc(oldClient,ID_ROUTE),{
     active:false,updatedAt:serverTimestamp(),
   }));
 }finally{await env.cleanup();}
});
test("04 tampered old ID route blocks retry without undoing good linked state",async()=>{
 const route=await read(ID_ROUTE);
 await write(ID_ROUTE,{...route,ownerUid:"attacker_disposable_uid_001"});
 await assert.rejects(callable(request()),e=>e.code==="unavailable");
 assert.equal((await read(ID_ROUTE)).ownerUid,"attacker_disposable_uid_001");
 assert.equal((await read(LINK)).newUid,NEW);
 assert.equal((await read(MONEY)).balance,4900);
});
