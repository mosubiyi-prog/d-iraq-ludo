"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore,Timestamp}=require("firebase-admin/firestore");
const {PROJECT,ROOT,REVIEW_ISSUER,reviewPath,
 issuePrivateReviewedFriendClaim:issue,
 validatePrivateReviewedFriendClaim:validate}=
 require("../deda_weekly_original_friend_reviewed_signed_claim_NOT_EXPORTED.js");
const {ROOT:EPOCH_ROOT,ISSUER:EPOCH_ISSUER}=
 require("../deda_weekly_stage43_reviewed_cutover_epoch_NOT_EXPORTED.js");
const {recordOriginalAcceptedFriendAction,originalClaim,ROOT:ACTION_ROOT}=
 require("../deda_weekly_original_friend_accepted_action_NOT_EXPORTED.js");
const {dayInIraq}=require("../deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const fs=require("node:fs");
if(process.env.GCLOUD_PROJECT!==PROJECT||
   process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
   process.env.DEDA_FRIEND_REVIEW_EMULATOR_ONLY!=="true")
 throw Error("DEDA_FRIEND_SIGNED_REVIEW_EMULATOR_ONLY");
const app=initializeApp({projectId:PROJECT},"reviewed-friend-signed-qa");
const db=getFirestore(app);
const secret=Buffer.from("8b".repeat(32),"hex"),badSecret=Buffer.from("9c".repeat(32),"hex");
const FIRST=Date.UTC(2026,9,27,3);
const NOW=FIRST+8*3600000,APPROVED=NOW-1000;
const DAY=dayInIraq(APPROVED);
const A="friend_signed_original_a",B="friend_signed_original_b";
const ACCOUNT="07701234567",OTHER="07707654321";
const FROM="@DEDA-AA1111",TO="@DEDA-BB2222";
const PAIR=[A,B].sort().join("__");
const event=originalClaim(ACCOUNT,DAY).eventKey;
const MIGRATION="friend_migration_review_00001";
const SETTLEMENT="friend_settlement_review_00001";
const EVIDENCE="a".repeat(64),BASELINE="b".repeat(64);
const REVIEW="friend_review_independent_00001";
const t=n=>Timestamp.fromMillis(n);
const before={pairKey:PAIR,members:[A,B],requesterUid:A,
 recipientUid:B,requesterPublicId:FROM,recipientPublicId:TO,
 requesterName:"A",recipientName:"B",status:"pending",
 createdAt:t(APPROVED-80000),updatedAt:t(APPROVED-80000)};
const after={...before,status:"accepted",
 updatedAt:t(APPROVED),respondedAt:t(APPROVED)};
const claim=(overrides={})=>issue({db,backendSecret:secret,
 accountKey:ACCOUNT,dayId:DAY,eventKey:event,serverNowMs:NOW,...overrides});
const check=(overrides={})=>validate({db,backendSecret:secret,
 accountKey:ACCOUNT,dayId:DAY,eventKey:event,serverNowMs:NOW,...overrides});
const epoch={
 format:1,issuer:EPOCH_ISSUER,emulatorOnly:true,
 canAuthorizeProduction:false,realOldApkRevocationVerified:false,
 phase:"reviewed-server-only-private-fixture",accountKey:ACCOUNT,
 migrationId:MIGRATION,evidenceDigest:EVIDENCE,
 baselineEventKey:BASELINE,settlementId:SETTLEMENT,
 effectiveAtMs:APPROVED-200000,expiresAtMs:NOW+600000,
 pendingLocalClaims:0,pendingPurchases:0,pendingReservations:0
};
const reviewer={
 issuer:REVIEW_ISSUER,emulatorOnly:true,
 canAuthorizeProduction:false,oldApkRevocationVerified:false,
 accountKey:ACCOUNT,dayId:DAY,eventKey:event,taskId:"long_trip",
 migrationId:MIGRATION,originalRelationId:PAIR,
 reviewedClaimStatus:"fresh_server_only_after_cutover_fixture",
 originalLocalTaskPointsReconciledInFixture:true,
 originalLocalXpReconciledInFixture:true,
 originalLocalCoinsReconciledInFixture:true,
 historicClaimAlreadyCredited:false,
 pendingLegacyClaimsInFixture:0,
 reviewerDecisionId:REVIEW,reviewedAtMs:NOW-4000
};
test.before(async()=>{
 const batch=db.batch();
 for(const [uid,account,id] of [[A,ACCOUNT,FROM],[B,OTHER,TO]]){
  batch.set(db.doc("users/"+uid),{uid,accountKey:account,
   sharePersonalId:id});
  batch.set(db.doc("deda_share_ids/"+id),{publicId:id,
   ownerUid:uid,active:true,kind:"personal"});
  batch.set(db.doc("deda_sessions/"+uid),{uid,accountKey:account,
   installId:uid+"_phone1"});
  batch.set(db.doc("deda_account_profiles/"+account),{
   accountKey:account,trustedInstallIds:[uid+"_phone1"]});
  batch.set(db.doc("users/"+uid+"/wallet/original"),{
   diamonds:900,coins:31,xp:400,points:120});
 }
 batch.set(db.doc("deda_friendships/"+PAIR),after);
 await batch.commit();
 const proof=await recordOriginalAcceptedFriendAction({
  db,relationId:PAIR,before,after,firstOpenMs:FIRST,serverNowMs:NOW});
 assert.equal(proof.proofsAdded,2);
});
test.after(async()=>deleteApp(app));
test("1: raw accepted action alone cannot sign original XP claim",async()=>{
 await assert.rejects(claim(),/ORIGINAL_LEGACY_BASELINE_NOT_SETTLED/);
 assert.equal((await db.doc(ROOT+"/"+event).get()).exists,false);
});
test("2: migrated baseline WITHOUT independent reviewer cannot sign",async()=>{
 await db.doc("deda_progress_migrations/"+ACCOUNT).set({
  accountKey:ACCOUNT,phase:"cutover-complete",
  migrationId:MIGRATION,evidenceDigest:EVIDENCE,
  baselineEventKey:BASELINE,settlementId:SETTLEMENT});
 await db.doc(EPOCH_ROOT+"/"+ACCOUNT).set(epoch);
 await assert.rejects(claim(),/INDEPENDENT_LEGACY_CLAIM_REVIEW_REQUIRED/);
 assert.equal((await db.doc(ROOT+"/"+event).get()).exists,false);
});
test("3: independent reviewed fixture signs one read-only action receipt; no XP or cash",async()=>{
 await db.doc(reviewPath(ACCOUNT,event)).set(reviewer);
 const got=await claim();
 assert.equal(got.outcome,"private_reviewed_claim_signed");
 assert.equal(got.created,1);
 assert.equal(got.actuallyCreditedXp,0);
 assert.equal(got.actuallyCreditedLeagueXp,0);
 assert.equal(got.actuallyCreditedDiamonds,0);
 const raw=(await db.doc(ROOT+"/"+event).get()).data();
 assert.equal(raw.record.taskId,"long_trip");
 assert.equal(raw.record.action,"friend_accepted");
 assert.equal(raw.record.levelXpIfIndependentlySettled,20);
 assert.equal(raw.record.actuallyCreditedXp,0);
 assert.equal(raw.record.actuallyCreditedDiamonds,0);
 assert.equal(raw.record.oldApkRevocationVerified,false);
 assert.match(raw.signature,/^[a-f0-9]{64}$/);
 for(const uid of [A,B]){
  assert.deepEqual((await db.doc("users/"+uid+"/wallet/original").get()).data(),
   {diamonds:900,coins:31,xp:400,points:120});
 }
 assert.equal((await db.doc("deda_verified_progress/"+ACCOUNT).get()).exists,false);
});
test("4: validator checks private HMAC plus independent source/review in transaction",async()=>{
 const v=await check();
 assert.equal(v.readOnly,true);
 assert.equal(v.canCreditXp,false);
 assert.equal(v.canCreditLeague,false);
 assert.equal(v.canCreditDiamonds,false);
 assert.equal(v.canAuthorizeProduction,false);
});
test("5: retry from another phone never mints second reviewed signed claim",async()=>{
 const [a,b]=await Promise.all([claim(),claim()]);
 for(const result of [a,b]){
  assert.equal(result.outcome,"already_signed");
  assert.equal(result.created,0);
 }
 assert.equal((await db.collection(ROOT).get()).size,1);
});
test("6: historical XP already credited or reviewer modified => HOLD, existing signed proof untouched",async()=>{
 const path=reviewPath(ACCOUNT,event);
 await db.doc(path).update({historicClaimAlreadyCredited:true});
 await assert.rejects(claim(),/INDEPENDENT_LEGACY_CLAIM_REVIEW_REQUIRED/);
 await assert.rejects(check(),/INDEPENDENT_LEGACY_CLAIM_REVIEW_REQUIRED/);
 await db.doc(path).set(reviewer);
 assert.equal((await db.doc(ROOT+"/"+event).get()).exists,true);
});
test("7: forged account, missing cutover or private signing key rejects",async()=>{
 await assert.rejects(claim({accountKey:OTHER}),/INVALID_ORIGINAL_ACCOUNT_TASK/);
 await assert.rejects(check({backendSecret:badSecret}),/SIGNED_FRIEND_REVIEW_INVALID/);
 await db.doc(EPOCH_ROOT+"/"+ACCOUNT).update({pendingLocalClaims:1});
 await assert.rejects(claim(),/REVIEWED_EMULATOR_CUTOVER_MISSING/);
 await db.doc(EPOCH_ROOT+"/"+ACCOUNT).set(epoch);
});
test("8: stale claim validation and forged HMAC are never accepted",async()=>{
 await assert.rejects(check({serverNowMs:NOW+310000}),
   /SIGNATURE_EXPIRED_REQUIRES_HISTORICAL_REVIEW/);
 const ref=db.doc(ROOT+"/"+event);
 const good=(await ref.get()).data();
 await ref.update({signature:"0".repeat(64)});
 await assert.rejects(check(),/SIGNED_FRIEND_REVIEW_INVALID/);
 await assert.rejects(claim(),/SIGNED_CLAIM_REPLAY_TAMPERED/);
 await ref.set(good);
 assert.equal((await check()).readOnly,true);
});
test("9: real project or user wallet can never use QA signer",async()=>{
 const previous=process.env.GCLOUD_PROJECT;
 process.env.GCLOUD_PROJECT="deda-25b88";
 try{await assert.rejects(claim(),/EMULATOR_ONLY/);}
 finally{process.env.GCLOUD_PROJECT=previous;}
 const prod=fs.readFileSync("functions/index.js","utf8");
 assert.equal(prod.includes("deda_weekly_original_friend_reviewed_signed_claim_NOT_EXPORTED"),false);
 assert.equal((await db.collection("deda_weekly_stage42_private_league_receipts").get()).size,0);
 assert.equal((await db.collection("deda_weekly_stage45_private_gift_inbox").get()).size,0);
});
