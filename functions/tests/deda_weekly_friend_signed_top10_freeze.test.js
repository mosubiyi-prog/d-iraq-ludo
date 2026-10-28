"use strict";
const test=require("node:test"),assert=require("node:assert/strict"),fs=require("node:fs");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore,Timestamp}=require("firebase-admin/firestore");
const {PROJECT,ROOT,freezePrivateFriendSignedTopTen:freeze,
 readReleasedPrivateFriendTopTen:released}=require(
 "../deda_weekly_friend_signed_top10_freeze_NOT_EXPORTED.js");
const {recordOriginalAcceptedFriendAction,originalClaim}=require(
 "../deda_weekly_original_friend_accepted_action_NOT_EXPORTED.js");
const {ROOT:EPOCH_ROOT,ISSUER:EPOCH_ISSUER}=require(
 "../deda_weekly_stage43_reviewed_cutover_epoch_NOT_EXPORTED.js");
const {REVIEW_ISSUER,reviewPath,
 issuePrivateReviewedFriendClaim:issue}=require(
 "../deda_weekly_original_friend_reviewed_signed_claim_NOT_EXPORTED.js");
const {recordPrivateFriendCandidateWeeklyXp:writeCandidate,
 EVENT_ROOT,TALLY_ROOT}=require(
 "../deda_weekly_original_friend_signed_xp_atomic_shadow_NOT_EXPORTED.js");
const {qaId,profilePath}=require(
 "../deda_weekly_stage44_verified_ledger_top10_archive_NOT_EXPORTED.js");
const {dayInIraq}=require("../deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const {windowFor,PRIZES}=require(
 "../deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
if(process.env.GCLOUD_PROJECT!==PROJECT||
  process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
  process.env.DEDA_FRIEND_REVIEW_EMULATOR_ONLY!=="true"||
  process.env.DEDA_FRIEND_ATOMIC_SHADOW_ONLY!=="true"||
  process.env.DEDA_FRIEND_TOP10_EMULATOR_ONLY!=="true")
 throw Error("PRIVATE_TOP10_MUST_BE_FIRESTORE_EMULATOR");
const app=initializeApp({projectId:PROJECT},"top10-reviewed-friend-qa");
const db=getFirestore(app);
const SECRET=Buffer.from("ab".repeat(32),"hex");
const BAD=Buffer.from("dc".repeat(32),"hex");
const FIRST=Date.UTC(2026,9,27,3); // 06 Baghdad
const W=windowFor(FIRST,0);
const CLOSE=W.closeAtMs,FROZEN=CLOSE+3*60000,RELEASE=W.nextOpenMs;
const participants=Array.from({length:12},(_,i)=>({
 uid:"top10_original_player_"+String(i).padStart(2,"0"),
 account:"077012"+String(10000+i),
 id:"@DEDA-"+String(i+1).padStart(6,"0"),
 name:"مشارك ديدا "+String(i+1)
}));
const R={uid:"top10_shared_receiver1",account:"07708990001",id:"@DEDA-R00001"};
const R2={uid:"top10_shared_receiver2",account:"07708990002",id:"@DEDA-R00002"};
const R3={uid:"top10_frozen_receiver3",account:"07708990003",id:"@DEDA-R00003"};
const t=ms=>Timestamp.fromMillis(ms);
const relation=(a,b)=>[a.uid,b.uid].sort().join("__");
const mig=p=>({
 accountKey:p.account,phase:"cutover-complete",
 migrationId:"friend_top10_migration_"+p.uid,
 evidenceDigest:"a".repeat(64),baselineEventKey:"b".repeat(64),
 settlementId:"friend_top10_settlement_"+p.uid,
});
const epoch=p=>({
 format:1,issuer:EPOCH_ISSUER,emulatorOnly:true,
 canAuthorizeProduction:false,realOldApkRevocationVerified:false,
 phase:"reviewed-server-only-private-fixture",accountKey:p.account,
 migrationId:mig(p).migrationId,
 evidenceDigest:"a".repeat(64),baselineEventKey:"b".repeat(64),
 settlementId:mig(p).settlementId,
 effectiveAtMs:FIRST-90000,
 expiresAtMs:RELEASE+86400000,
 pendingLocalClaims:0,pendingPurchases:0,pendingReservations:0
});
const reviewers=(p,when,other)=>({
 issuer:REVIEW_ISSUER,emulatorOnly:true,canAuthorizeProduction:false,
 oldApkRevocationVerified:false,accountKey:p.account,
 dayId:dayInIraq(when),
 eventKey:originalClaim(p.account,dayInIraq(when)).eventKey,
 taskId:"long_trip",migrationId:mig(p).migrationId,
 originalRelationId:relation(p,other),
 reviewedClaimStatus:"fresh_server_only_after_cutover_fixture",
 originalLocalTaskPointsReconciledInFixture:true,
 originalLocalXpReconciledInFixture:true,
 originalLocalCoinsReconciledInFixture:true,
 historicClaimAlreadyCredited:false,pendingLegacyClaimsInFixture:0,
 reviewerDecisionId:"reviewed_friend_top10_claim_00001",
 reviewedAtMs:when-500
});
async function accepted(p,receiver,when){
 const pair=relation(p,receiver),beforeAt=when-65000;
 const before={
  pairKey:pair,members:[p.uid,receiver.uid],
  requesterUid:p.uid,recipientUid:receiver.uid,
  requesterPublicId:p.id,recipientPublicId:receiver.id,
  requesterName:"لاعب "+p.uid,recipientName:"مستلم "+receiver.uid,
  status:"pending",createdAt:t(beforeAt-5000),updatedAt:t(beforeAt)
 };
 const after={...before,status:"accepted",
  updatedAt:t(when),respondedAt:t(when)};
 await db.doc("deda_friendships/"+pair).set(after);
 await recordOriginalAcceptedFriendAction({
  db,relationId:pair,before,after,firstOpenMs:FIRST,serverNowMs:when+1000
 });
 const {eventKey}=originalClaim(p.account,dayInIraq(when));
 await db.doc(reviewPath(p.account,eventKey)).set(reviewers(p,when,receiver));
 const signed=await issue({
  db,backendSecret:SECRET,accountKey:p.account,
  dayId:dayInIraq(when),eventKey,serverNowMs:when+1000
 });
 assert.equal(signed.created,1);
 const candidate=await writeCandidate({
  db,backendSecret:SECRET,accountKey:p.account,
  dayId:dayInIraq(when),firstOpenMs:FIRST,serverNowMs:when+1100
 });
 assert.equal(candidate.actualLevelXpAdded,0);
 assert.equal(candidate.actualDiamondsAdded,0);
 return candidate;
}
function freezeAt(now=FROZEN,extra={}){
 return freeze({db,backendSecret:SECRET,
  firstOpenMs:FIRST,weekIndex:0,serverNowMs:now,...extra});
}
function releaseAt(now=RELEASE+1000,extra={}){
 return released({db,backendSecret:SECRET,
  firstOpenMs:FIRST,weekIndex:0,serverNowMs:now,...extra});
}
test.before(async()=>{
 const batch=db.batch();
 for(const p of [...participants,R,R2,R3]){
  batch.set(db.doc("users/"+p.uid),{
   uid:p.uid,accountKey:p.account,sharePersonalId:p.id
  });
  batch.set(db.doc("deda_share_ids/"+p.id),{
   publicId:p.id,kind:"personal",active:true,ownerUid:p.uid
  });
  batch.set(db.doc("deda_sessions/"+p.uid),{
   uid:p.uid,accountKey:p.account,installId:p.uid+"_device_1"
  });
  batch.set(db.doc("deda_account_profiles/"+p.account),{
   accountKey:p.account,trustedInstallIds:[p.uid+"_device_1"]
  });
  batch.set(db.doc("users/"+p.uid+"/wallet/original"),{
   points:545,xp:1640,coins:250,diamonds:874
  });
 }
 for(const [i,p] of participants.entries()){
  batch.set(db.doc("deda_progress_migrations/"+p.account),mig(p));
  batch.set(db.doc(EPOCH_ROOT+"/"+p.account),epoch(p));
  batch.set(db.doc(profilePath(p.account,SECRET)),{
   issuer:"stage44_private_profile_fixture_only",
   emulatorOnly:true,accountKey:p.account,
   displayName:p.name,activePublicId:p.id,level:i+1
  });
 }
 await batch.commit();
 for(const [i,p] of participants.entries()){
  await accepted(p,R,FIRST+3600000+i*20000);
 }
 for(let i=0;i<2;i++){
  await accepted(participants[i],R2,FIRST+86400000+3600000+i*20000);
 }
 const frozen=await accepted(participants[11],R3,CLOSE+70000);
 assert.equal(frozen.outcome,"frozen_zero_score");
 assert.equal(frozen.privateCandidateWeeklyXpAdded,0);
});
test.after(async()=>deleteApp(app));
test("1. private freeze before 00:00 blocked, 06:00 release not early",async()=>{
 await assert.rejects(freezeAt(CLOSE-1),/ONLY_BAGHDAD_0000_TO_0600/);
 await assert.rejects(releaseAt(FROZEN),/WINNERS_NOT_RELEASED_UNTIL_0600/);
});
test("2. signed XP source yields EXACT 10 of 12 stable sorted leaders, intended prizes only",async()=>{
 const result=await freezeAt();
 assert.equal(result.outcome,"frozen_private_snapshot_created");
 assert.equal(result.rankedCount,12);
 assert.equal(result.topTen.length,10);
 assert.deepEqual(result.topTen.map(r=>r.plannedDiamonds),PRIZES);
 assert.equal(result.plannedTotalDiamonds,370);
 assert.equal(result.actuallyCreditedDiamonds,0);
 assert.equal(result.topTen[0].weeklyXp,40);
 assert.equal(result.topTen[1].weeklyXp,40);
 assert.equal(result.topTen[2].weeklyXp,20);
 assert.deepEqual(result.topTen.slice(0,2).map(r=>r.participantId),
  participants.slice(0,2).map(p=>qaId(p.account,SECRET)));
 assert.equal(result.topTen[9].weeklyXp,20);
 assert.equal(result.topTen.some(r=>r.activePublicId===participants[11].id),false);
 assert.equal(result.productionReady,false);
 assert.equal(result.realAccountMigrationDone,false);
 assert.equal(result.oldApkWriterFenced,false);
 assert.equal(result.canCreditDiamonds,false);
 assert.equal(JSON.stringify(result.topTen).includes("077012"),false);
});
test("3. repeated freeze during 00–06 is immutable, does not reissue prizes",async()=>{
 const old=await freezeAt();
 const replay=await freezeAt(FROZEN+1000);
 assert.equal(replay.outcome,"already_sealed");
 assert.deepEqual(replay.topTen,old.topTen);
 assert.equal(replay.sealedAtMs,old.sealedAtMs);
 assert.equal(replay.actuallyCreditedDiamonds,0);
 assert.equal((await db.collection(ROOT).get()).size,1);
});
test("4. first opening after 06 shows identical frozen top 10 and never recomputes winners",async()=>{
 const prior=await freezeAt();
 const shown=await releaseAt();
 assert.equal(shown.outcome,"released_private_preview");
 assert.deepEqual(shown.topTen,prior.topTen);
 assert.equal(shown.releaseAtMs,RELEASE);
 assert.equal(shown.plannedTotalDiamonds,370);
});
test("5. forged accepted source, altered private score, or reviewer drift fail closed",async()=>{
 const p=participants[3];
 const {eventKey}=originalClaim(p.account,dayInIraq(FIRST+3600000+3*20000));
 const source=db.doc(EVENT_ROOT+"/"+W.weekId+"_"+eventKey);
 const saved=(await source.get()).data();
 await source.update({eligiblePrivateWeeklyXp:9000});
 await assert.rejects(freezeAt(FROZEN+2000),
  /UNVERIFIED_SOURCE_OR_BAGHDAD_FREEZE/);
 await source.set(saved);
 const reviewer=db.doc(reviewPath(p.account,eventKey));
 const old=(await reviewer.get()).data();
 await reviewer.update({historicClaimAlreadyCredited:true});
 await assert.rejects(freezeAt(FROZEN+2000),
  /INDEPENDENT_LEGACY_CLAIM_REVIEW_REQUIRED/);
 await reviewer.set(old);
});
test("6. changed private tally/QA profile cannot rewrite a sealed frozen ranking",async()=>{
 const p=participants[4];
 const ref=db.doc(TALLY_ROOT+"/"+W.weekId+"_"+p.account);
 const old=(await ref.get()).data();
 await ref.update({eligiblePrivateWeeklyXp:8880});
 await assert.rejects(freezeAt(FROZEN+2500),/MISSING_OR_CHANGED_SIGNED_TALLY/);
 await ref.set(old);
 const pf=db.doc(profilePath(p.account,SECRET));
 const oldP=(await pf.get()).data();
 await pf.update({displayName:"متلاعب"});
 await assert.rejects(freezeAt(FROZEN+2500),
  /IMMUTABLE_FREEZE_SOURCE_OR_PROFILE_DRIFT/);
 await pf.set(oldP);
});
test("7. tampering after frozen snapshot is detected at 06, no winner change",async()=>{
 const ref=db.doc(ROOT+"/"+W.weekId);
 const stored=(await ref.get()).data();
 await ref.update({"payload.plannedTotalDiamonds":999999});
 await assert.rejects(releaseAt(),/TAMPERED_OR_UNSEALED_FROZEN_RANKING/);
 await ref.set(stored);
 assert.equal((await releaseAt()).plannedTotalDiamonds,370);
});
test("8. original user wallets, level XP and app files always untouched",async()=>{
 for(const p of [...participants,R,R2,R3]){
  assert.deepEqual((await db.doc("users/"+p.uid+"/wallet/original").get()).data(),{
   points:545,xp:1640,coins:250,diamonds:874
  });
 }
 assert.equal((await db.collection("deda_weekly_stage45_private_gift_inbox").get()).size,0);
 assert.equal((await db.collection("deda_progress_receipts").get()).size,0);
 const index=fs.readFileSync("functions/index.js","utf8");
 assert.ok(!index.includes("deda_weekly_friend_signed_top10_freeze_NOT_EXPORTED"));
});
test("9. production Firebase, untrusted key and arbitrary client top ten override blocked",async()=>{
 await assert.rejects(freezeAt(FROZEN,{topTen:[{weeklyXp:9999}]}),
  /UNTRUSTED_CLIENT_OVERRIDE/);
 await assert.rejects(freezeAt(FROZEN,{backendSecret:BAD}),
  /SIGNED_FRIEND_REVIEW_INVALID|UNVERIFIED_SOURCE_OR_BAGHDAD_FREEZE/);
 const old=process.env.GCLOUD_PROJECT;
 process.env.GCLOUD_PROJECT="deda-25b88";
 try{await assert.rejects(freezeAt(),/EMULATOR_ONLY/);}
 finally{process.env.GCLOUD_PROJECT=old;}
});
