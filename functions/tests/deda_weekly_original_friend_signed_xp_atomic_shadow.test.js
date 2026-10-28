"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const fs=require("node:fs");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore,Timestamp}=require("firebase-admin/firestore");
const {PROJECT,EVENT_ROOT,TALLY_ROOT,recordPrivateFriendCandidateWeeklyXp:score}=
 require("../deda_weekly_original_friend_signed_xp_atomic_shadow_NOT_EXPORTED.js");
const {recordOriginalAcceptedFriendAction,originalClaim}=require(
 "../deda_weekly_original_friend_accepted_action_NOT_EXPORTED.js");
const {ROOT:EPOCH_ROOT,ISSUER:EPOCH_ISSUER}=require(
 "../deda_weekly_stage43_reviewed_cutover_epoch_NOT_EXPORTED.js");
const {REVIEW_ISSUER,reviewPath,issuePrivateReviewedFriendClaim:issue}=
 require("../deda_weekly_original_friend_reviewed_signed_claim_NOT_EXPORTED.js");
const {dayInIraq}=require("../deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const {windowFor}=require("../deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
if(process.env.GCLOUD_PROJECT!==PROJECT||
   process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
   process.env.DEDA_FRIEND_REVIEW_EMULATOR_ONLY!=="true"||
   process.env.DEDA_FRIEND_ATOMIC_SHADOW_ONLY!=="true")
 throw Error("PRIVATE_ONLY_NO_REAL_ACCOUNTS");
const app=initializeApp({projectId:PROJECT},"friend-private-candidate-xp-test");
const db=getFirestore(app);
const SECRET=Buffer.from("ac".repeat(32),"hex");
const WRONG=Buffer.from("cd".repeat(32),"hex");
const FIRST=Date.UTC(2026,9,27,3);
const NOW=FIRST+8*3600000;
const DAY2=NOW+86400000;
const WEEK=windowFor(FIRST,0);
const FREEZE=WEEK.closeAtMs+120000;
const A={uid:"shadow_friend_a_11",account:"07701234567",id:"@DEDA-AA1111"};
const B={uid:"shadow_friend_b_22",account:"07707654321",id:"@DEDA-BB2222"};
const C={uid:"shadow_friend_c_33",account:"07705554444",id:"@DEDA-CC3333"};
const D={uid:"shadow_friend_d_44",account:"07703334444",id:"@DEDA-DD4444"};
const MIGRATION="shadow_friend_migration_0001";
const SETTLEMENT="shadow_friend_settlement_0001";
const BASELINE="b".repeat(64),EVIDENCE="a".repeat(64);
const t=ms=>Timestamp.fromMillis(ms);
const relation=(x,y)=>[x.uid,y.uid].sort().join("__");
const canonical=(time)=>({
 accountKey:A.account,dayId:dayInIraq(time),
 eventKey:originalClaim(A.account,dayInIraq(time)).eventKey
});
function pair(x,y,approvedAt){
 const pendingAt=approvedAt-60000;
 const before={
  pairKey:relation(x,y),members:[x.uid,y.uid],
  requesterUid:x.uid,recipientUid:y.uid,
  requesterPublicId:x.id,recipientPublicId:y.id,
  requesterName:"verified "+x.uid,recipientName:"verified "+y.uid,
  status:"pending",createdAt:t(pendingAt-10000),
  updatedAt:t(pendingAt),
 };
 return {before,after:{...before,status:"accepted",
  respondedAt:t(approvedAt),updatedAt:t(approvedAt)}};
}
function migration(){
 return {
  format:1,accountKey:A.account,migrationId:MIGRATION,
  phase:"cutover-complete",evidenceDigest:EVIDENCE,
  baselineEventKey:BASELINE,settlementId:SETTLEMENT
 };
}
const epoch=()=>({
 format:1,issuer:EPOCH_ISSUER,emulatorOnly:true,
 canAuthorizeProduction:false,realOldApkRevocationVerified:false,
 phase:"reviewed-server-only-private-fixture",
 accountKey:A.account,migrationId:MIGRATION,
 evidenceDigest:EVIDENCE,baselineEventKey:BASELINE,settlementId:SETTLEMENT,
 effectiveAtMs:FIRST-100000,expiresAtMs:WEEK.nextOpenMs+86400000,
 pendingLocalClaims:0,pendingPurchases:0,pendingReservations:0
});
const record=async({other,now})=>{
 const acceptedAt=now-1000;
 const x=pair(A,other,acceptedAt);
 await db.doc("deda_friendships/"+relation(A,other)).set(x.after);
 const result=await recordOriginalAcceptedFriendAction({
  db,relationId:relation(A,other),before:x.before,after:x.after,
  firstOpenMs:FIRST,serverNowMs:now
 });
 assert.equal(result.proofsAdded,2);
 return acceptedAt;
};
const reviewer=(when,other)=>({
 issuer:REVIEW_ISSUER,emulatorOnly:true,
 canAuthorizeProduction:false,oldApkRevocationVerified:false,
 accountKey:A.account,dayId:dayInIraq(when),
 eventKey:originalClaim(A.account,dayInIraq(when)).eventKey,
 taskId:"long_trip",migrationId:MIGRATION,
 originalRelationId:relation(A,other),
 reviewedClaimStatus:"fresh_server_only_after_cutover_fixture",
 originalLocalTaskPointsReconciledInFixture:true,
 originalLocalXpReconciledInFixture:true,
 originalLocalCoinsReconciledInFixture:true,
 historicClaimAlreadyCredited:false,
 pendingLegacyClaimsInFixture:0,
 reviewerDecisionId:"original_independent_xp_review_00001",
 reviewedAtMs:when-500
});
async function signed({other,now}){
 const acceptedAt=await record({other,now});
 const {dayId,eventKey}=canonical(acceptedAt);
 await db.doc(reviewPath(A.account,eventKey)).set(reviewer(now,other));
 const out=await issue({
  db,backendSecret:SECRET,accountKey:A.account,
  dayId,eventKey,serverNowMs:now
 });
 assert.equal(out.outcome,"private_reviewed_claim_signed");
 return {dayId,eventKey};
}
const go=(now,options={})=>score({
 db,backendSecret:SECRET,accountKey:A.account,
 dayId:dayInIraq(now-1000),firstOpenMs:FIRST,serverNowMs:now,
 ...options
});
test.before(async()=>{
 const b=db.batch();
 for(const p of [A,B,C,D]){
  b.set(db.doc("users/"+p.uid),{uid:p.uid,
   accountKey:p.account,sharePersonalId:p.id});
  b.set(db.doc("deda_share_ids/"+p.id),{
   publicId:p.id,ownerUid:p.uid,kind:"personal",active:true
  });
  b.set(db.doc("deda_sessions/"+p.uid),{
   uid:p.uid,accountKey:p.account,installId:p.uid+"_install"
  });
  b.set(db.doc("deda_account_profiles/"+p.account),{
   accountKey:p.account,trustedInstallIds:[p.uid+"_install"]
  });
  b.set(db.doc("users/"+p.uid+"/wallet/original"),{
   diamonds:4500,xp:790,coins:205,points:125
  });
 }
 b.set(db.doc("deda_progress_migrations/"+A.account),migration());
 b.set(db.doc(EPOCH_ROOT+"/"+A.account),epoch());
 await b.commit();
 await record({other:B,now:NOW});
});
test.after(async()=>deleteApp(app));
test("1. Original accepted action alone is not enough for private XP tally",async()=>{
 await assert.rejects(go(NOW),/SIGNED_FRIEND_NOT_FRESH/);
 const {eventKey}=canonical(NOW-1000);
 assert.equal((await db.doc(EVENT_ROOT+"/"+WEEK.weekId+"_"+eventKey).get()).exists,false);
});
test("2. Independently reviewed signed claim produces EXACTLY 20 PRIVATE candidate week XP",async()=>{
 const {eventKey,dayId}=canonical(NOW-1000);
 await db.doc(reviewPath(A.account,eventKey)).set(reviewer(NOW,B));
 const claim=await issue({
  db,backendSecret:SECRET,accountKey:A.account,
  dayId,eventKey,serverNowMs:NOW
 });
 assert.equal(claim.outcome,"private_reviewed_claim_signed");
 const award=await go(NOW);
 assert.equal(award.outcome,"private_candidate_weekly_xp_recorded");
 assert.equal(award.privateCandidateWeeklyXpAdded,20);
 for(const k of ["actualLevelXpAdded","actualLeagueXpAdded","actualDiamondsAdded"])
  assert.equal(award[k],0);
 const marker=(await db.doc(EVENT_ROOT+"/"+WEEK.weekId+"_"+eventKey).get()).data();
 assert.equal(marker.eligiblePrivateWeeklyXp,20);
 assert.equal(marker.originalTaskId,"long_trip");
 assert.equal(marker.canAuthorizeProduction,false);
 assert.equal(marker.canCreditOriginalXp,false);
 const tally=(await db.doc(TALLY_ROOT+"/"+WEEK.weekId+"_"+A.account).get()).data();
 assert.equal(tally.eligiblePrivateWeeklyXp,20);
 assert.equal(tally.approvedTaskCount,1);
 for(const p of [A,B,C,D]){
  assert.deepEqual((await db.doc("users/"+p.uid+"/wallet/original").get()).data(),{
   diamonds:4500,xp:790,coins:205,points:125
  });
 }
 assert.equal((await db.doc("deda_verified_progress/"+A.account).get()).exists,false);
});
test("3. Double click / second phone concurrent request adds ZERO extra XP",async()=>{
 const res=await Promise.all([go(NOW+100),go(NOW+100)]);
 for(const x of res){
  assert.equal(x.outcome,"already_recorded");
  assert.equal(x.privateCandidateWeeklyXpAdded,0);
 }
 const tally=(await db.doc(TALLY_ROOT+"/"+WEEK.weekId+"_"+A.account).get()).data();
 assert.equal(tally.eligiblePrivateWeeklyXp,20);
});
test("4. New approved friend next Baghdad day adds another 20 to same PRIVATE tally",async()=>{
 await signed({other:C,now:DAY2});
 const result=await go(DAY2);
 assert.equal(result.outcome,"private_candidate_weekly_xp_recorded");
 assert.equal(result.privateCandidateWeeklyXpAdded,20);
 const tally=(await db.doc(TALLY_ROOT+"/"+WEEK.weekId+"_"+A.account).get()).data();
 assert.equal(tally.eligiblePrivateWeeklyXp,40);
 assert.equal(tally.approvedTaskCount,2);
});
test("5. Midnight-to-six Baghdad acceptance is frozen forever with ZERO candidate XP",async()=>{
 await signed({other:D,now:FREEZE});
 const result=await go(FREEZE);
 assert.equal(result.outcome,"frozen_zero_score");
 assert.equal(result.privateCandidateWeeklyXpAdded,0);
 const again=await go(FREEZE+100);
 assert.equal(again.outcome,"already_recorded");
 const tally=(await db.doc(TALLY_ROOT+"/"+WEEK.weekId+"_"+A.account).get()).data();
 assert.equal(tally.eligiblePrivateWeeklyXp,40);
 assert.equal(tally.approvedTaskCount,2);
 const {eventKey}=canonical(FREEZE-1000);
 const proof=(await db.doc(EVENT_ROOT+"/"+WEEK.weekId+"_"+eventKey).get()).data();
 assert.equal(proof.score,0);
 assert.equal(proof.eligiblePrivateWeeklyXp,0);
});
test("6. Frozen action cannot be carried into next league week at 06:00",async()=>{
 const time=WEEK.nextOpenMs+120000;
 await assert.rejects(go(time,{dayId:dayInIraq(FREEZE-1000)}),
  /SIGNED_FRIEND_NOT_FRESH|FRIEND_ACTION_NOT_IN_CURRENT_WEEK_OR_DAY/);
 const time2=WEEK.nextOpenMs+120000;
 assert.equal((await db.doc(TALLY_ROOT+"/"+WEEK.weekId+"_"+A.account).get()).data().eligiblePrivateWeeklyXp,40);
 assert.equal((await db.doc(TALLY_ROOT+"/"+windowFor(FIRST,1).weekId+"_"+A.account).get()).exists,false);
});
test("7. Forged backend secret, false account, removed review or old-APK claim block candidate score",async()=>{
 await assert.rejects(go(DAY2,{backendSecret:WRONG}),/SIGNED_FRIEND_REVIEW_INVALID/);
 await assert.rejects(go(DAY2,{accountKey:B.account}),/SIGNED_FRIEND_NOT_FRESH|INVALID_ORIGINAL_ACCOUNT_TASK/);
 const {eventKey}=canonical(DAY2-1000);
 const ref=db.doc(reviewPath(A.account,eventKey));
 await ref.update({historicClaimAlreadyCredited:true});
 await assert.rejects(go(DAY2),/INDEPENDENT_LEGACY_CLAIM_REVIEW_REQUIRED/);
 await ref.set(reviewer(DAY2,C));
});
test("8. Tampering with past candidate event blocks replay, leaves original wallets unchanged",async()=>{
 const {eventKey}=canonical(DAY2-1000);
 const ref=db.doc(EVENT_ROOT+"/"+WEEK.weekId+"_"+eventKey);
 const old=(await ref.get()).data();
 await ref.update({eligiblePrivateWeeklyXp:500});
 await assert.rejects(go(DAY2),/TAMPERED_OR_PARTIAL_PREVIOUS_CANDIDATE_EVENT/);
 await ref.set(old);
 assert.equal((await go(DAY2)).privateCandidateWeeklyXpAdded,0);
 assert.deepEqual((await db.doc("users/"+A.uid+"/wallet/original").get()).data(),{
  diamonds:4500,xp:790,coins:205,points:125
 });
});
test("9. Real Firebase, production functions, gifts and original XP cannot use this model",async()=>{
 const old=process.env.GCLOUD_PROJECT;
 process.env.GCLOUD_PROJECT="deda-25b88";
 try{await assert.rejects(go(NOW),/STRICT_EMULATOR_ONLY/);}
 finally{process.env.GCLOUD_PROJECT=old;}
 const original=fs.readFileSync("functions/index.js","utf8");
 assert.ok(!original.includes("deda_weekly_original_friend_signed_xp_atomic_shadow_NOT_EXPORTED"));
 assert.equal((await db.collection("deda_weekly_stage45_private_gift_inbox").get()).size,0);
 assert.equal((await db.collection("deda_weekly_stage42_private_league_receipts").get()).size,0);
 assert.equal((await db.collection("deda_progress_receipts").get()).size,0);
});
