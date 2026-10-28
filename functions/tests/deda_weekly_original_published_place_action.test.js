"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const fs=require("node:fs");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore,Timestamp}=require("firebase-admin/firestore");
const core=require("../../tools/app_stability/progress_archive/reconcile-core.cjs");
const {PROJECT,ROOT,receiptFor,verifyOriginalPublishedPlaceShareAction:verify}=
  require("../deda_weekly_original_published_place_action_NOT_EXPORTED.js");
const {dayInIraq}=require("../deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
if(process.env.GCLOUD_PROJECT!==PROJECT||!process.env.FIRESTORE_EMULATOR_HOST)
  throw Error("ORIGINAL_PLACE_PROOF_REAL_FIRESTORE_EMULATOR_ONLY");
const app=initializeApp({projectId:PROJECT},"deda-place-action-test");
const db=getFirestore(app);
const START=Date.UTC(2026,9,27,3);
const NOW=START+8*3600000;
const ACCOUNT="07701234567",OTHER="07707654321";
const SENDER="place_share_sender_1",RECIPIENT="place_share_recipient_2";
const FROM="@DEDA-C12345",TO="@DEDA-B12345";
const PLACE="published_place_0001",NAME="مكاني المعتمد";
const SHARE="PLCES123456789012345",AGAIN="PLCES123456789012346";
const val=(t)=>Timestamp.fromMillis(t);
function item(at=NOW-1000,changes={}){
 return {senderUid:SENDER,senderPublicId:FROM,recipientPublicId:TO,
   shareType:"place",status:"pending",senderName:NAME,placeName:NAME,
   placeId:PLACE,latitude:35.4,longitude:44.1,durationMinutes:15,
   createdAt:val(at),updatedAt:val(at),expiresAt:val(at+14*60000),...changes};
}
const run=(id=SHARE,at=NOW)=>verify({
 db,shareId:id,firstOpenMs:START,serverNowMs:at
});
test.before(async()=>{
 const batch=db.batch();
 batch.set(db.doc("users/"+SENDER),{
   uid:SENDER,accountKey:ACCOUNT,sharePlaceId:FROM,name:"مالك المكان"
 });
 batch.set(db.doc("users/"+RECIPIENT),{
   uid:RECIPIENT,accountKey:OTHER,sharePersonalId:TO,name:"المستلم"
 });
 batch.set(db.doc("deda_share_ids/"+FROM),{
   kind:"place",active:true,ownerUid:SENDER,publicId:FROM
 });
 batch.set(db.doc("deda_share_ids/"+TO),{
   kind:"personal",active:true,ownerUid:RECIPIENT,publicId:TO
 });
 batch.set(db.doc("published_places/"+PLACE),{
   published:true,accountKey:ACCOUNT,ownerUid:SENDER,
   placeName:NAME,latitude:35.4,longitude:44.1
 });
 batch.set(db.doc("deda_sessions/"+SENDER),{
   uid:SENDER,accountKey:ACCOUNT,installId:"place_trusted_install_1"
 });
 batch.set(db.doc("deda_account_profiles/"+ACCOUNT),{
   accountKey:ACCOUNT,trustedInstallIds:["place_trusted_install_1"]
 });
 batch.set(db.doc("deda_location_shares/"+SHARE),item());
 batch.set(db.doc("users/"+SENDER+"/wallet/actual"),{
   diamonds:654,points:300,xp:240,coins:120
 });
 await batch.commit();
});
test.after(async()=>deleteApp(app));
test("original client 'place' share records backend action WITHOUT XP/coins/prizes",async()=>{
 const first=await run();
 assert.equal(first.outcome,"place_action_verified");
 assert.equal(first.levelXpAdded,0);assert.equal(first.leagueXpAdded,0);
 assert.equal(first.pointsAdded,0);assert.equal(first.coinsAdded,0);
 assert.equal(first.diamondsAdded,0);
 const key=receiptFor(ACCOUNT,dayInIraq(NOW)).eventKey;
 const proof=(await db.doc(ROOT+"/"+key).get()).data();
 assert.equal(proof.issuer,"private_original_published_place_share_action_v1_emulator_only");
 assert.equal(proof.publishedPlaceId,PLACE);
 assert.equal(proof.originalLocalClaimAwarded,"UNKNOWN_REQUIRES_MIGRATION_REVIEW");
 assert.equal(proof.canAuthorizeProduction,false);
 assert.equal((await db.collection("deda_verified_progress").get()).size,0);
 assert.equal((await db.collection("deda_progress_receipts").get()).size,0);
 assert.deepEqual((await db.doc("users/"+SENDER+"/wallet/actual").get()).data(),
   {diamonds:654,points:300,xp:240,coins:120});
});
test("separate share ID same account+task+Baghdad day is idempotent",async()=>{
 await db.doc("deda_location_shares/"+AGAIN).set(item());
 const twice=await Promise.all([run(),run(AGAIN)]);
 for(const r of twice){
   assert.equal(r.outcome,"already_verified");
   assert.equal(r.levelXpAdded,0);assert.equal(r.diamondsAdded,0);
 }
 assert.equal((await db.collection(ROOT).get()).size,1);
});
test("canonical receipt matches original task rewards but does NOT mint them",()=>{
 const q=receiptFor(ACCOUNT,dayInIraq(NOW));
 assert.deepEqual(core.parseReceipt(q.receipt,ACCOUNT).delta,
   {points:5,coins:10,xp:20,earnedDiamonds:0});
 assert.equal(q.receipt.sourceId,
   "daily-task|"+dayInIraq(NOW)+"|share_registered_place");
 assert.match(q.eventKey,/^[a-f0-9]{64}$/);
});
test("reject wrong share type, owner, publish status, place geometry and same-account recipient",async()=>{
 const bads=[
  {shareType:"current"},
  {senderPublicId:"@DEDA-ZZZZZZ"},
  {senderName:"نام غير مطابق"},
  {placeName:"مكان غير مطابق"},
  {placeId:"place_not_published"},
  {latitude:35.6},
  {recipientPublicId:FROM},
  {status:"accepted"},
 ];
 for(let n=0;n<bads.length;n++){
   const id="REJCT"+String(n).padStart(15,"0");
   await db.doc("deda_location_shares/"+id).set(item(NOW-1000,bads[n]));
   await assert.rejects(run(id),/DEDA_ORIGINAL_PLACE_ACTION_/);
 }
 await db.doc("users/"+RECIPIENT).update({accountKey:ACCOUNT});
 const id="REJCT000000000000009";
 await db.doc("deda_location_shares/"+id).set(item());
 await assert.rejects(run(id),/cross_account_or_trusted_install/);
 await db.doc("users/"+RECIPIENT).update({accountKey:OTHER});
});
test("reject untrusted installation without changing the original profile",async()=>{
 const old=(await db.doc("deda_sessions/"+SENDER).get()).data();
 await db.doc("deda_sessions/"+SENDER).update({installId:"untrusted_install_002"});
 const id="REJCT000000000000010";
 await db.doc("deda_location_shares/"+id).set(item());
 await assert.rejects(run(id),/cross_account_or_trusted_install/);
 await db.doc("deda_sessions/"+SENDER).set(old);
});
test("reject share outside Baghdad day or outside original league window",async()=>{
 const id="REJCT000000000000011";
 await db.doc("deda_location_shares/"+id).set(item(NOW-8*3600000));
 await assert.rejects(run(id),/place_share_baghdad_window/);
});
test("freeze period can prove action but must award ZERO weekly points",async()=>{
 const close=START+7*86400000-6*3600000;
 const frozen=close+120000, id="FROZN123456789012345";
 await db.doc("deda_location_shares/"+id).set(item(frozen-1000));
 const r=await run(id,frozen);
 assert.equal(r.outcome,"place_action_verified");
 assert.equal(r.levelXpAdded,0);assert.equal(r.leagueXpAdded,0);
 const proof=(await db.doc(ROOT+"/"+receiptFor(ACCOUNT,dayInIraq(frozen)).eventKey).get()).data();
 assert.equal(proof.xpGranted,0);assert.equal(proof.diamondsGranted,0);
});
test("untrusted server project never acts or reads real data",async()=>{
 const old=process.env.GCLOUD_PROJECT;
 try{
   process.env.GCLOUD_PROJECT="deda-25b88";
   await assert.rejects(run(),/emulator_only/);
 }finally{process.env.GCLOUD_PROJECT=old;}
 const index=fs.readFileSync("functions/index.js","utf8");
 assert.ok(!index.includes("deda_weekly_original_published_place_action_NOT_EXPORTED"));
});
