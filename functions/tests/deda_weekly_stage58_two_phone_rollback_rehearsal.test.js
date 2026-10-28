"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore}=require("firebase-admin/firestore");
const {PROJECT,ROOT:ROOT55,migrationHold}=require(
 "../../tools/app_stability/stage55/private_two_phone_migration_hold.cjs");
const {ROOT:ROOT56,auditAssetProvenance}=require(
 "../../tools/app_stability/stage56/private_original_asset_provenance_audit.cjs");
const {ROOT,rehearseTwoPhoneHold}=require(
 "../../tools/app_stability/stage58/private_two_phone_rehearsal.cjs");
if(process.env.GCLOUD_PROJECT!==PROJECT||
   process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
   !["DEDA_STAGE55_EMULATOR_ONLY","DEDA_STAGE56_EMULATOR_ONLY",
      "DEDA_STAGE58_EMULATOR_ONLY"].every(k=>process.env[k]==="true"))
  throw Error("STAGE58_REQUIRES_ISOLATED_FIRESTORE_EMULATOR");
const app=initializeApp({projectId:PROJECT},"stage58-rollback-rehearsal");
const db=getFirestore(app),KEY=Buffer.alloc(32,0x58);
const ACCOUNT="07701234567",SECOND="07707654321",THIRD="07703456789";
const U1="stage58_old_phone_uid_A",U2="stage58_new_phone_uid_A";
const U3="stage58_old_phone_uid_B",U4="stage58_new_phone_uid_B";
const U5="stage58_old_phone_uid_C",U6="stage58_new_phone_uid_C";
const old={diamonds:943,xp:1550,coins:21,level:10,
 purchasedFrames:["royal","gold"],premiumId:"@DEDA-OLDA"};
const newWallet={diamonds:0,xp:0,coins:0,level:1,
 purchasedFrames:[],premiumId:"@DEDA-NEWB"};
const originalAdmin={diamonds:1000000,specialIds:["@DEDA-ADMIN100"]};
const GM="deda_admin_diamond_wallets/general_manager";
function all(account=ACCOUNT,one=U1,two=U2,action="prepare",overrides={}){
 return {db,accountKey:account,originalUid:one,newPhoneUid:two,
   serverKey:KEY,action,...overrides};
}
async function seed(account,one,two,{missingBinding=false,missingWallet=false}={}){
 const batch=db.batch();
 batch.set(db.doc("deda_account_directory/"+account),{
   accountKey:account,active:true,createdUid:one});
 batch.set(db.doc("deda_account_profiles/"+account),{
   accountKey:account,name:"Synthetic Account",trustedInstallIds:["copied-device"]});
 for(const [i,uid] of [one,two].entries()){
  if(!(i&&missingBinding))batch.set(db.doc(
   "deda_stage54_private_account_bindings/"+uid),{
    uid,accountKey:account,authProvider:"anonymous",
    state:"LOCAL_VERIFIED_HOLD_ONLY",emulatorOnly:true,
    canMigrate:false,canGrant:false
   });
  batch.set(db.doc("users/"+uid),{
   uid,accountKey:account,authMethod:"deda_pin_firestore_v1",
   premiumId:i?"@DEDA-NEWB":"@DEDA-OLDA",diamonds:i?0:943,
   xp:i?0:1550
  });
  if(!(i&&missingWallet))
    batch.set(db.doc("users/"+uid+"/wallet/original"),i?newWallet:old);
  batch.set(db.doc("deda_sessions/"+uid),{
   uid,accountKey:account,installId:"copied-device",
   signedInAt:0,lastSeenAt:0
  });
 }
 await batch.commit();
}
async function ancestors(account=ACCOUNT,one=U1,two=U2){
 const x=all(account,one,two,"prepare");
 const s55=await migrationHold(x);
 assert.equal(s55.status,"NEW_HOLD");
 const s56=await auditAssetProvenance({
  ...x,purchaseCaptureId:"stage58_purchase_capture_0001",
  receiptId:"a".repeat(64),giftId:"b".repeat(64),
  originalPersonalId:"@DEDA-STAGE58",
 });
 assert.equal(s56.status,"NEW_HOLD");
}
function safe(r){
 assert.equal(r.emulatorOnly,true);
 assert.equal(r.productionReady,false);
 assert.equal(r.approved,false);
 assert.equal(r.canMigrate,false);
 assert.equal(r.canTransferWallet,false);
 assert.equal(r.canTransferFrames,false);
 assert.equal(r.canTransferPremiumId,false);
 assert.equal(r.canTransferAccount,false);
 assert.equal(r.canCreditXp,false);
 assert.equal(r.canCreditSocialCoins,false);
 assert.equal(r.canCreditDiamonds,false);
 assert.equal(r.canIssueGift,false);
 assert.equal(r.canSettlePurchase,false);
 assert.equal(r.sourcePaymentProofVerified,false);
 assert.equal(r.productionAppCheckVerified,false);
 assert.equal(r.oldApkWriterFenced,false);
 assert.equal(r.realWalletRollbackPerformed,false);
 assert.equal(r.dataMoved,false);
 assert.ok(["NEW_HOLD","ALREADY_HELD","ABORTED_NO_TRANSFER"].includes(r.status));
 const json=JSON.stringify(r);
 for(const secret of [ACCOUNT,SECOND,THIRD,"@DEDA-OLDA",
   "copied-device",U1,U2])
   assert.equal(json.includes(secret),false,"no private data in report response");
}
test.before(async()=>{
 await seed(ACCOUNT,U1,U2);
 await db.doc(GM).set(originalAdmin);
});
test.after(async()=>deleteApp(app));

test("01: cannot create rehearsal without Stage55/56 independently held source reviews",async()=>{
 await assert.rejects(rehearseTwoPhoneHold(all()),/IMMUTABLE_PREVIOUS_HOLD_NOT_VALID/);
});
test("02: original two UIDs + existing Stage55/56 HOLD create an inert migration PLAN only",async()=>{
 await ancestors();
 const r=await rehearseTwoPhoneHold(all());safe(r);
 assert.equal(r.status,"NEW_HOLD");
 assert.ok(r.blockers.includes("STAGE56_EVIDENCE_SOURCES_CANNOT_BE_REHASHED_FROM_REPORT"));
 assert.ok(r.blockers.includes("NO_VERIFIED_LEVEL_XP_COIN_TRANSFER_OR_ROLLBACK"));
 const report=(await db.doc(ROOT+"/"+r.reportId).get()).data();
 assert.equal(report.status,"HOLD_PREPARED");
 assert.equal(report.dataMoved,false);
 assert.equal(report.realWalletRollbackPerformed,false);
 assert.equal(report.approved,false);
});
test("03: idempotent reprepare never duplicates records or credits",async()=>{
 const a=await rehearseTwoPhoneHold(all()),b=await rehearseTwoPhoneHold(all());
 a.status==="ALREADY_HELD"&&safe(a);safe(b);
 assert.equal(a.status,"ALREADY_HELD");assert.equal(a.reportId,b.reportId);
 assert.equal((await db.collection(ROOT).get()).size,1);
});
test("04: parallel prepare requests converge to single immutable report",async()=>{
 const before=(await db.collection(ROOT).get()).docs[0].data();
 const results=await Promise.all(Array.from({length:4},()=>rehearseTwoPhoneHold(all())));
 for(const x of results){safe(x);assert.equal(x.status,"ALREADY_HELD");}
 assert.equal((await db.collection(ROOT).get()).size,1);
 assert.deepEqual((await db.collection(ROOT).get()).docs[0].data(),before);
});
test("05: attacker cannot invent wallet coins, XP, diamonds or asset changes as action",async()=>{
 for(const action of ["commit","apply","release","credit","migrate","restore","rollback"])
  await assert.rejects(rehearseTwoPhoneHold(all(ACCOUNT,U1,U2,action)),/INVALID_BACKEND_REHEARSAL_INPUT/);
});
test("06: original wallet mutation after Stage55 always rejects new rehearsal planning",async()=>{
 const wallet=db.doc("users/"+U1+"/wallet/original");
 await wallet.update({diamonds:200000});
 await assert.rejects(rehearseTwoPhoneHold(all()),/LEGACY_SOURCE_CHANGED_AFTER_STAGE55_HOLD/);
 await wallet.set(old);
 safe(await rehearseTwoPhoneHold(all()));
});
test("07: original session copied install ID changed after Stage55 also blocks",async()=>{
 const r=db.doc("deda_sessions/"+U2);
 await r.update({installId:"stolen-from-another-device"});
 await assert.rejects(rehearseTwoPhoneHold(all()),/LEGACY_SOURCE_CHANGED_AFTER_STAGE55_HOLD/);
 await r.update({installId:"copied-device"});
 safe(await rehearseTwoPhoneHold(all()));
});
test("08: tampering Stage56 to award diamonds never allows rehearsal plan",async()=>{
 const q=(await db.collection(ROOT56).get()).docs[0],orig=q.data();
 await q.ref.update({canCreditDiamonds:true});
 await assert.rejects(rehearseTwoPhoneHold(all()),/PRIOR_HOLD_INVARIANT_TAMPERED/);
 await q.ref.set(orig);
 safe(await rehearseTwoPhoneHold(all()));
});
test("09: terminal abort changes ONLY original private plan, no legacy asset touched",async()=>{
 const r=await rehearseTwoPhoneHold(all(ACCOUNT,U1,U2,"abort"));safe(r);
 assert.equal(r.status,"ABORTED_NO_TRANSFER");
 assert.equal(r.rollbackPlanOnly,true);
 const plan=(await db.doc(ROOT+"/"+r.reportId).get()).data();
 assert.equal(plan.status,"ABORTED_NO_TRANSFER");
 assert.equal(plan.rollbackPlanOnly,true);
 assert.equal(plan.dataMoved,false);
 assert.equal(plan.realWalletRollbackPerformed,false);
});
test("10: abort is replay-safe and cannot create an additional rollback or award",async()=>{
 const r=await rehearseTwoPhoneHold(all(ACCOUNT,U1,U2,"abort"));safe(r);
 assert.equal(r.status,"ABORTED_NO_TRANSFER");
 assert.equal((await db.collection(ROOT).get()).size,1);
});
test("11: aborted HOLD cannot be reactivated by preparing again",async()=>{
 const r=await rehearseTwoPhoneHold(all());safe(r);
 assert.equal(r.status,"ABORTED_NO_TRANSFER");
 assert.equal((await db.collection(ROOT).get()).docs[0].data().status,"ABORTED_NO_TRANSFER");
});
test("12: abort remains possible after wallet/source DRIFT; still no data to roll back",async()=>{
 const wallet=db.doc("users/"+U1+"/wallet/original");
 await wallet.update({diamonds:123456});
 const r=await rehearseTwoPhoneHold(all(ACCOUNT,U1,U2,"abort"));safe(r);
 assert.equal(r.status,"ABORTED_NO_TRANSFER");
 await wallet.set(old);
});
test("13: missing plan cannot be aborted and creates no private records",async()=>{
 await assert.rejects(rehearseTwoPhoneHold(all(SECOND,U3,U4,"abort")),/NO_PLAN_TO_ABORT/);
});
test("14: two distinct canonical accounts have independent private aborted plans",async()=>{
 await seed(SECOND,U3,U4);
 await ancestors(SECOND,U3,U4);
 const made=await rehearseTwoPhoneHold(all(SECOND,U3,U4));safe(made);
 assert.equal(made.status,"NEW_HOLD");
 assert.notEqual(made.reportId,(await rehearseTwoPhoneHold(all())).reportId);
 const aborted=await rehearseTwoPhoneHold(all(SECOND,U3,U4,"abort"));safe(aborted);
 assert.equal(aborted.status,"ABORTED_NO_TRANSFER");
 assert.equal((await db.collection(ROOT).get()).size,2);
});
test("15: wrong UIDs or reversed original/new device order cannot abort existing report",async()=>{
 for(const x of [all(ACCOUNT,U2,U1,"abort"),all(ACCOUNT,U3,U4,"abort")])
  await assert.rejects(rehearseTwoPhoneHold(x),/ABORT_REFUSED_PLAN_IDENTITY_OR_SHAPE/);
});
test("16: missing private Stage54 UID binding cannot create another account rehearsal",async()=>{
 await seed(THIRD,U5,U6,{missingBinding:true});
 await assert.rejects(rehearseTwoPhoneHold(all(THIRD,U5,U6)),
   /IMMUTABLE_PREVIOUS_HOLD_NOT_VALID/);
});
test("17: tampered pre-existing plan cannot be aborted or re-authorized",async()=>{
 const reportId=(await rehearseTwoPhoneHold(all(ACCOUNT,U1,U2,"abort"))).reportId;
 const report=db.doc(ROOT+"/"+reportId);
 const original=(await report.get()).data();
 await report.update({dataMoved:true});
 await assert.rejects(rehearseTwoPhoneHold(all(ACCOUNT,U1,U2,"abort")),
   /ABORT_REFUSED_PLAN_IDENTITY_OR_SHAPE/);
 await report.set(original);
 safe(await rehearseTwoPhoneHold(all(ACCOUNT,U1,U2,"abort")));
});
test("18: arbitrary paths, same UID, invalid account or absent emulator flag fail closed",async()=>{
 for(const changes of [
  {accountKey:"../../adm"},{originalUid:U1,newPhoneUid:U1},
  {newPhoneUid:"/wallet"},{serverKey:Buffer.alloc(5)},
 ])
  await assert.rejects(rehearseTwoPhoneHold({...all(),...changes}),
    /INVALID_BACKEND_REHEARSAL_INPUT|REFUSE_OUTSIDE_LOCAL_EMULATOR/);
 const oldProject=process.env.GCLOUD_PROJECT;
 process.env.GCLOUD_PROJECT="deda-25b88";
 try{await assert.rejects(rehearseTwoPhoneHold(all()),/REFUSE_OUTSIDE_LOCAL_EMULATOR/);}
 finally{process.env.GCLOUD_PROJECT=oldProject;}
});
test("19: private reports never embed original phone, ID, wallet balance or frame names",async()=>{
 const collection=await db.collection(ROOT).get();
 assert.equal(collection.size,2);
 for(const p of collection.docs){
  const v=p.data(),serialized=JSON.stringify(v);
  for(const field of ["accountKey","phone","installId","premiumId","wallet",
    "diamonds","coins","xp","frames","pin","originalUid","newPhoneUid"])
   assert.equal(Object.hasOwn(v,field),false,field);
  for(const secret of [ACCOUNT,SECOND,U1,U2,"@DEDA-OLDA","royal","copied-device"])
   assert.equal(serialized.includes(secret),false,secret);
  assert.equal(v.canMigrate,false);
  assert.equal(v.dataMoved,false);
 }
});
test("20: NO user wallets, manager wallet, original ID, credits or gifts were changed",async()=>{
 assert.deepEqual((await db.doc("users/"+U1+"/wallet/original").get()).data(),old);
 assert.deepEqual((await db.doc("users/"+U2+"/wallet/original").get()).data(),newWallet);
 assert.deepEqual((await db.doc(GM).get()).data(),originalAdmin);
 assert.equal((await db.doc("users/"+U1).get()).data().premiumId,"@DEDA-OLDA");
 assert.equal((await db.collection("deda_progress_receipts/"+ACCOUNT+"/events").get()).size,0);
 assert.equal((await db.collection("deda_weekly_stage45_private_gift_inbox").get()).size,0);
 assert.equal((await db.collection("deda_verified_progress").get()).size,0);
 assert.equal((await db.collection(ROOT55).get()).size,2);
 assert.equal((await db.collection(ROOT56).get()).size,2);
});
