"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore,Timestamp}=require("firebase-admin/firestore");
const {PROJECT,ROOT,TASK,ACTION,ISSUER,originalClaim,
 recordOriginalAcceptedFriendAction:verify}=require(
 "../deda_weekly_original_friend_accepted_action_NOT_EXPORTED.js");
const {dayInIraq}=require("../deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const core=require("../../tools/app_stability/progress_archive/reconcile-core.cjs");
if(process.env.GCLOUD_PROJECT!==PROJECT||!process.env.FIRESTORE_EMULATOR_HOST)
 throw Error("ORIGINAL_FRIEND_ACTION_FIRESTORE_EMULATOR_ONLY");
const app=initializeApp({projectId:PROJECT},"friend-action-trusted-backend");
const db=getFirestore(app);
const FIRST=Date.UTC(2026,9,27,3),NOW=FIRST+8*3600000;
const A="original_friend_a",B="original_friend_b",C="original_friend_c";
const pa={uid:A,account:"07701234567",publicId:"@DEDA-AA1111"};
const pb={uid:B,account:"07707654321",publicId:"@DEDA-BB2222"};
const pc={uid:C,account:"07705555555",publicId:"@DEDA-CC3333"};
const rel=(a,b)=>[a.uid,b.uid].sort().join("__");
const t=ms=>Timestamp.fromMillis(ms);
function pair(a,b,at=NOW-1000){
 const created=at-60000;
 const before={pairKey:rel(a,b),members:[a.uid,b.uid],
  requesterUid:a.uid,recipientUid:b.uid,
  requesterPublicId:a.publicId,recipientPublicId:b.publicId,
  requesterName:"مستخدم "+a.uid,recipientName:"مستخدم "+b.uid,
  status:"pending",createdAt:t(created),updatedAt:t(created)};
 const after={...before,status:"accepted",updatedAt:t(at),respondedAt:t(at)};
 return {before,after};
}
const go=(a,b,now=NOW,ev=pair(a,b,now-1000))=>verify({
 db,relationId:rel(a,b),before:ev.before,after:ev.after,
 firstOpenMs:FIRST,serverNowMs:now,
});
async function seedAccepted(a,b,at=NOW-1000){
 const ev=pair(a,b,at);
 await db.doc("deda_friendships/"+rel(a,b)).set(ev.after);
 return ev;
}
test.before(async()=>{
 const batch=db.batch();
 for(const p of [pa,pb,pc]){
  batch.set(db.doc("users/"+p.uid),{
   uid:p.uid,accountKey:p.account,sharePersonalId:p.publicId,
  });
  batch.set(db.doc("deda_share_ids/"+p.publicId),{
   publicId:p.publicId,ownerUid:p.uid,kind:"personal",active:true,
  });
  batch.set(db.doc("deda_sessions/"+p.uid),{
   uid:p.uid,accountKey:p.account,installId:p.uid+"_phone1",
  });
  batch.set(db.doc("deda_account_profiles/"+p.account),{
   accountKey:p.account,trustedInstallIds:[p.uid+"_phone1"],
  });
  batch.set(db.doc("users/"+p.uid+"/wallet/original"),{
   diamonds:854,xp:1200,coins:75,points:500,
  });
 }
 await batch.commit();
 await seedAccepted(pa,pb);
});
test.after(async()=>deleteApp(app));
test("original approved friend action maps to immutable old 'long_trip' claim ID",()=>{
 const claim=originalClaim(pa.account,dayInIraq(NOW));
 assert.equal(TASK,"long_trip");
 assert.equal(ACTION,"friend_accepted");
 assert.equal(claim.receipt.sourceId,"daily-task|"+dayInIraq(NOW)+"|long_trip");
 assert.deepEqual(core.parseReceipt(claim.receipt,pa.account).delta,{
  points:5,coins:10,xp:20,earnedDiamonds:0,
 });
});
test("trusted PENDING -> ACCEPTED gives BOTH different accounts one proof, ZERO xp/diamonds",async()=>{
 const ev=pair(pa,pb);
 const result=await go(pa,pb,NOW,ev);
 assert.equal(result.outcome,"private_accepted_action_verified");
 assert.equal(result.proofsAdded,2);
 assert.equal(result.levelXpAdded,0);
 assert.equal(result.weeklyXpAdded,0);
 const day=dayInIraq(NOW);
 for(const p of [pa,pb]){
  const key=originalClaim(p.account,day).eventKey;
  const proof=(await db.doc(ROOT+"/"+key).get()).data();
  assert.equal(proof.issuer,ISSUER);
  assert.equal(proof.taskId,"long_trip");
  assert.equal(proof.approvedAction,"friend_accepted");
  assert.equal(proof.originalLocalClaimAwarded,"UNKNOWN_REQUIRES_MIGRATION_REVIEW");
  assert.equal(proof.canAuthorizeProduction,false);
  for(const k of ["xpGranted","coinsGranted","pointsGranted","diamondsGranted","leagueXpGranted"])
    assert.equal(proof[k],0);
  assert.deepEqual((await db.doc("users/"+p.uid+"/wallet/original").get()).data(),
   {diamonds:854,xp:1200,coins:75,points:500});
 }
});
test("replay from second trusted phone makes ZERO new proofs",async()=>{
 const r=await go(pa,pb);
 assert.equal(r.outcome,"already_verified");
 assert.equal(r.proofsAdded,0);
 assert.equal((await db.collection(ROOT).get()).size,2);
});
test("reject client-forged accepted state, missing pending origin, identity swap",async()=>{
 const ev=pair(pa,pb);
 for(const changed of [
  {before:{...ev.before,status:"accepted"}},
  {after:{...ev.after,status:"pending"}},
  {after:{...ev.after,recipientPublicId:"@DEDA-FAKE01"}},
  {after:{...ev.after,members:[pa.uid,pa.uid]}},
  {after:{...ev.after,requesterUid:pb.uid}},
  {after:{...ev.after,respondedAt:t(NOW+1000)}},
 ]){
  await assert.rejects(go(pa,pb,NOW,{...ev,...changed}),
   /DEDA_ORIGINAL_FRIEND_ACCEPTED_/);
 }
});
test("same canonical account / forged owner / untrusted phone cannot yield proof",async()=>{
 const ev=pair(pa,pb);
 await db.doc("users/"+pb.uid).update({accountKey:pa.account});
 await assert.rejects(go(pa,pb,NOW,ev),/original_account_or_public_id_not_owned/);
 await db.doc("users/"+pb.uid).update({accountKey:pb.account});
 await db.doc("deda_share_ids/"+pb.publicId).update({ownerUid:pc.uid});
 await assert.rejects(go(pa,pb,NOW,ev),/original_account_or_public_id_not_owned/);
 await db.doc("deda_share_ids/"+pb.publicId).update({ownerUid:pb.uid});
 await db.doc("deda_sessions/"+pb.uid).update({installId:"untrusted_second_phone"});
 await assert.rejects(go(pa,pb,NOW,ev),/untrusted_original_device/);
 await db.doc("deda_sessions/"+pb.uid).update({installId:pb.uid+"_phone1"});
});
test("altered original accepted record after onUpdate fails, no writes",async()=>{
 const ev=pair(pa,pb);
 await db.doc("deda_friendships/"+rel(pa,pb)).update({status:"rejected"});
 await assert.rejects(go(pa,pb,NOW,ev),/accepted_relation_modified_or_replayed/);
 await db.doc("deda_friendships/"+rel(pa,pb)).update({status:"accepted"});
});
test("second approved relation during midnight-to-six freeze proves action, credits ZERO",async()=>{
 const close=FIRST+7*86400000-6*3600000;
 const frozen=close+120000;
 const ev=await seedAccepted(pa,pc,frozen-1000);
 const r=await go(pa,pc,frozen,ev);
 assert.equal(r.outcome,"private_accepted_action_verified");
 assert.equal(r.proofsAdded,2);
 assert.equal(r.weeklyXpAdded,0);
 assert.equal(r.diamondsAdded,0);
 assert.equal((await db.collection(ROOT).get()).size,4);
});
test("production Firebase and client-supplied caller cannot issue proofs",async()=>{
 const old=process.env.GCLOUD_PROJECT;
 process.env.GCLOUD_PROJECT="deda-25b88";
 try{
  await assert.rejects(go(pa,pb),/emulator_only/);
 }finally{process.env.GCLOUD_PROJECT=old;}
 const index=require("node:fs").readFileSync("functions/index.js","utf8");
 assert.equal(index.includes("deda_weekly_original_friend_accepted_action_NOT_EXPORTED"),false);
});
