"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore,Timestamp}=require("firebase-admin/firestore");
const {PROJECT,ROOT}=require(
  "../deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const {auditOriginalShareRecipientProvenance:audit}=require(
  "../deda_weekly_stage36_original_source_provenance_NOT_EXPORTED.js");
const {ROOT_CANDIDATE}=require(
  "../deda_weekly_stage32_original_share_candidate_NOT_EXPORTED.js");
if(process.env.GCLOUD_PROJECT!==PROJECT||!process.env.FIRESTORE_EMULATOR_HOST)
  throw Error("STAGE36_PRIVATE_FIRESTORE_EMULATOR_REQUIRED");
const app=initializeApp({projectId:PROJECT},"deda-stage36-readonly-provenance");
const db=getFirestore(app);
const FIRST=Date.UTC(2026,9,27,3); // 06:00 Baghdad
const NOW=Date.UTC(2026,9,27,11);
const CLOSE=FIRST+7*86400000-6*3600000;
const SOURCE_ID="FGHIJ123456789012345";
const SENDER="stage36_sender",RECEIVER="stage36_recipient";
const A="07701234567",B="07707654321";
const FROM="@DEDA-A12345",TO="@DEDA-B12345";
const accountWallet={points:500,xp:1250,coins:80,diamonds:9000};
const managerWallet={diamonds:1000000};
function location(change={},at=NOW-2000){
  return {
    senderUid:SENDER,senderPublicId:FROM,recipientPublicId:TO,
    shareType:"current",status:"pending",placeName:"",placeId:"",
    senderName:"Fixture sender",latitude:35.4,longitude:44.1,
    durationMinutes:15,
    createdAt:Timestamp.fromMillis(at),
    updatedAt:Timestamp.fromMillis(at),
    expiresAt:Timestamp.fromMillis(at+14*60000),...change
  };
}
function inspect(now=NOW,shareId=SOURCE_ID){
  return audit({db,shareId,firstOpenMs:FIRST,serverNowMs:now});
}
async function replaceShare(data=location()){
  await db.doc("deda_location_shares/"+SOURCE_ID).set(data);
}
async function restoreRecipient(){
  await db.doc("deda_share_ids/"+TO).set({
    ownerUid:RECEIVER,kind:"personal",active:true,publicId:TO});
  await db.doc("users/"+RECEIVER).set({
    uid:RECEIVER,accountKey:B,sharePersonalId:TO});
}
test.before(async()=>{
  const batch=db.batch();
  batch.set(db.doc("users/"+SENDER),{
    uid:SENDER,accountKey:A,sharePersonalId:FROM,name:"Fixture sender"});
  batch.set(db.doc("deda_sessions/"+SENDER),{
    uid:SENDER,accountKey:A,installId:"fixture_phone_1"});
  batch.set(db.doc("deda_account_profiles/"+A),{
    accountKey:A,trustedInstallIds:["fixture_phone_1","fixture_phone_2"]});
  batch.set(db.doc("deda_share_ids/"+FROM),{
    ownerUid:SENDER,kind:"personal",active:true,publicId:FROM});
  batch.set(db.doc("deda_share_ids/"+TO),{
    ownerUid:RECEIVER,kind:"personal",active:true,publicId:TO});
  batch.set(db.doc("users/"+RECEIVER),{
    uid:RECEIVER,accountKey:B,sharePersonalId:TO});
  batch.set(db.doc("users/"+SENDER+"/wallet/original"),accountWallet);
  batch.set(db.doc("deda_admin_diamond_wallets/general_manager"),managerWallet);
  await batch.commit();
});
test.after(async()=>{await deleteApp(app);});
test("missing original source refuses any provenance",async()=>{
  await assert.rejects(inspect(),/DEDA_ORIGINAL_SHARE_TASK_BLOCK_missing/);
});
test("valid original persisted cross-account share produces READ ONLY audit, not XP",async()=>{
  await replaceShare();
  const result=await inspect();
  assert.equal(result.sourceOwnershipValidated,true);
  assert.equal(result.distinctRecipientCanonicalAccount,true);
  assert.equal(result.serverVerifiedOriginalTaskClaim,false);
  assert.equal(result.serverReconciledOriginalLevelXp,false);
  assert.equal(result.migrationCutoverVerified,false);
  assert.equal(result.originalLifetimeXpAdded,0);
  assert.equal(result.originalTaskPointsAdded,0);
  assert.equal(result.leagueXpAdded,0);
  assert.equal(result.canWriteVerifiedProgress,false);
  assert.equal(result.canGrantDiamonds,false);
  assert.equal(result.blockedBy.length,3);
  assert.deepEqual((await db.doc("users/"+SENDER+"/wallet/original").get()).data(),accountWallet);
  assert.deepEqual((await db.doc("deda_admin_diamond_wallets/general_manager").get()).data(),managerWallet);
  assert.equal((await db.collection(ROOT_CANDIDATE).get()).size,0);
  assert.equal((await db.collection(ROOT.receipt).get()).size,0);
  assert.equal((await db.collection(ROOT.proof).get()).size,0);
});
test("different recipient UID but SAME CANONICAL ACCOUNT must not count",async()=>{
  await db.doc("users/"+RECEIVER).update({accountKey:A});
  await assert.rejects(inspect(),/recipient_not_a_distinct_verified_account/);
  await db.doc("users/"+RECEIVER).update({accountKey:B});
});
test("recipient reference owned by the sender is rejected",async()=>{
  await db.doc("deda_share_ids/"+TO).update({ownerUid:SENDER});
  await assert.rejects(inspect(),/recipient_same_uid_or_missing/);
  await restoreRecipient();
});
test("recipient ID cannot be borrowed from a different user",async()=>{
  await db.doc("users/"+RECEIVER).update({sharePersonalId:"@DEDA-C12345"});
  await assert.rejects(inspect(),/recipient_not_a_distinct_verified_account/);
  await restoreRecipient();
});
test("recipient missing or disabled fails closed",async()=>{
  await db.doc("deda_share_ids/"+TO).update({active:false});
  await assert.rejects(inspect(),/DEDA_STAGE36_PROVENANCE_BLOCK_|DEDA_ORIGINAL_SHARE_TASK_BLOCK_/);
  await db.doc("deda_share_ids/"+TO).update({active:true});
  await db.doc("users/"+RECEIVER).delete();
  await assert.rejects(inspect(),/missing_recipient/);
  await restoreRecipient();
});
test("client-authored self-share, modified timestamp, fake location, alias rejected",async()=>{
  for(const patch of [
    {recipientPublicId:FROM},
    {updatedAt:Timestamp.fromMillis(NOW+123)},
    {latitude:999},
    {senderPublicId:"@DEDA-PREMIUM"},
    {status:"deleted"},
    {shareType:"place"}
  ]){
    await replaceShare(location(patch));
    await assert.rejects(inspect(),/DEDA_ORIGINAL_SHARE_TASK_BLOCK_|DEDA_STAGE36_PROVENANCE_BLOCK_/);
  }
  await replaceShare();
});
test("sender session/account switch is never treated as trusted",async()=>{
  await db.doc("deda_sessions/"+SENDER).update({accountKey:B});
  await assert.rejects(inspect(),/DEDA_ORIGINAL_SHARE_TASK_BLOCK_|DEDA_STAGE36_PROVENANCE_BLOCK_/);
  await db.doc("deda_sessions/"+SENDER).update({accountKey:A});
  await db.doc("deda_account_profiles/"+A).update({trustedInstallIds:[]});
  await assert.rejects(inspect(),/DEDA_ORIGINAL_SHARE_TASK_BLOCK_|DEDA_STAGE36_PROVENANCE_BLOCK_/);
  await db.doc("deda_account_profiles/"+A).update({trustedInstallIds:["fixture_phone_1"]});
});
test("new source during 00:00 to 06:00 freeze never enters league",async()=>{
  await assert.rejects(inspect(CLOSE+1000),/not_an_active_league_window/);
  const nextStart=FIRST+7*86400000;
  await replaceShare(location({},CLOSE+3000));
  await assert.rejects(inspect(nextStart+1000),
    /DEDA_ORIGINAL_SHARE_TASK_BLOCK_|DEDA_STAGE36_PROVENANCE_BLOCK_/);
  await replaceShare();
});
test("production environment cannot run private provenance evaluator",async()=>{
  const previous=process.env.GCLOUD_PROJECT;
  process.env.GCLOUD_PROJECT="deda-25b88";
  try{
    await assert.rejects(inspect(),/private_emulator_required/);
  }finally{process.env.GCLOUD_PROJECT=previous;}
});
test("no new account progress or manager records were written by failed audits",async()=>{
  assert.deepEqual((await db.doc("users/"+SENDER+"/wallet/original").get()).data(),accountWallet);
  assert.deepEqual((await db.doc("deda_admin_diamond_wallets/general_manager").get()).data(),managerWallet);
  assert.equal((await db.collection(ROOT_CANDIDATE).get()).empty,true);
  assert.equal((await db.collection(ROOT.receipt).get()).empty,true);
});
