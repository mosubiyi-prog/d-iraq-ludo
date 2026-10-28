"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore}=require("firebase-admin/firestore");
const {PROJECT,ROOT,migrationHold}=require(
  "../../tools/app_stability/stage55/private_two_phone_migration_hold.cjs");
if(process.env.GCLOUD_PROJECT!==PROJECT||
   process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
   process.env.DEDA_STAGE55_EMULATOR_ONLY!=="true")
 throw Error("STAGE55_REQUIRES_ISOLATED_FIRESTORE_EMULATOR");
const app=initializeApp({projectId:PROJECT},"stage55-private-migration-emulator");
const db=getFirestore(app);
const SECRET=Buffer.alloc(32,0x55);
const A="07701112233",B="07702223334",C="07703334445",D="07704445556",
  E="07705556667",F="07706667778",G="07707778889";
const O="stage55_original_uid_0001",N="stage55_new_phone_uid_0002";
const userRoot="users/"+O;
const walletRoot=userRoot+"/wallet/original";
const gmRoot="deda_admin_diamond_wallets/general_manager";
const originalWallet={
  diamonds:923,coins:31,xp:2200,level:13,
  purchasedFrames:["gold","royal"],premiumId:"@DEDA-VIP777"
};
const nextWallet={
  diamonds:0,coins:0,xp:0,level:1,
  purchasedFrames:[],premiumId:"@DEDA-NEW01"
};
function args(account=A,u1=O,u2=N,secret=SECRET){
 return {db,accountKey:account,originalUid:u1,newPhoneUid:u2,
   serverKey:secret};
}
function safe(r){
 assert.equal(r.canMigrate,false);
 assert.equal(r.canCreditXp,false);
 assert.equal(r.canCreditDiamonds,false);
 assert.equal(r.canIssueGift,false);
 assert.equal(r.canReplacePremiumId,false);
 assert.ok(["NEW_HOLD","ALREADY_HOLD"].includes(r.status));
 const s=JSON.stringify(r);
 assert.equal(s.includes("VIP777"),false);
 assert.equal(s.includes("07701112233"),false);
}
async function seed(account,u1,u2,opts={}){
 const batch=db.batch();
 batch.set(db.doc("deda_account_directory/"+account),{
   accountKey:account,active:true,createdUid:u1});
 batch.set(db.doc("deda_account_profiles/"+account),{
   accountKey:account,name:"Synthetic",trustedInstallIds:["device-copyable"],
   updatedAt:1000});
 for(const [index,uid] of [u1,u2].entries()){
  if(!(opts.missingSecondBinding&&index===1))
   batch.set(db.doc("deda_stage54_private_account_bindings/"+uid),{
    uid,accountKey:opts.mismatchSecondBinding&&index===1?B:account,
    authProvider:"anonymous",state:"LOCAL_VERIFIED_HOLD_ONLY",
    emulatorOnly:true,canMigrate:false,canGrant:false
   });
  if(!(opts.missingSecondUser&&index===1))
   batch.set(db.doc("users/"+uid),{
    uid,accountKey:index===1&&opts.mismatchSecondUser?B:account,
    accountType:"user",authMethod:"deda_pin_firestore_v1",
    name:"Test Device",xp:index?0:2200,diamonds:index?0:923,
    premiumId:index?"@DEDA-NEW01":"@DEDA-VIP777"
   });
  if(!(opts.missingSecondWallet&&index===1))
   batch.set(db.doc("users/"+uid+"/wallet/original"),
      opts.equalWallets?originalWallet:index?nextWallet:originalWallet);
  batch.set(db.doc("deda_sessions/"+uid),{
   uid,accountKey:account,installId:"device-copyable",
   signedInAt:0,lastSeenAt:0
  });
 }
 await batch.commit();
}
test.before(async()=>{
 await seed(A,O,N);
 await db.doc(gmRoot).set({
   diamonds:1000000,specialIds:["@DEDA-001001"]
 });
});
test.after(async()=>deleteApp(app));

test("01: two original anonymous UIDs same account produce HOLD, not account transfer",async()=>{
 const r=await migrationHold(args());
 safe(r);
 assert.equal(r.status,"NEW_HOLD");
 assert.ok(r.flags.includes("TWO_PHONE_DIAMONDS_MISMATCH"));
 assert.ok(r.flags.includes("TWO_PHONE_XP_MISMATCH"));
 assert.ok(r.flags.includes("TWO_PHONE_PREMIUMID_MISMATCH"));
 assert.ok(r.flags.includes("TWO_PHONE_PURCHASEDFRAMES_MISMATCH"));
 const stored=(await db.doc(ROOT+"/"+r.reportId).get()).data();
 assert.equal(stored.state,"HOLD_MANUAL_REVIEW_ONLY");
 assert.equal(stored.canTransferWallet,false);
 assert.equal(stored.canTransferFrames,false);
 assert.equal(stored.canTransferAccount,false);
 assert.equal(stored.sourceWalletRowsPresent,2);
 assert.equal(stored.holdFlags.includes("NO_INDEPENDENT_PURCHASE_OR_GIFT_PROVENANCE"),true);
});
test("02: replay has same report and cannot grant XP or diamonds twice",async()=>{
 const old=(await db.collection(ROOT).get()).size;
 const first=await migrationHold(args()),second=await migrationHold(args());
 safe(first);safe(second);
 assert.equal(first.status,"ALREADY_HOLD");
 assert.equal(second.status,"ALREADY_HOLD");
 assert.equal(first.reportId,second.reportId);
 assert.equal((await db.collection(ROOT).get()).size,old);
});
test("03: same-account concurrent requests are idempotent, immutable report unchanged",async()=>{
 const original=(await db.collection(ROOT).get()).docs[0].data();
 const results=await Promise.all([
   migrationHold(args()),migrationHold(args()),
   migrationHold(args())
 ]);
 for(const r of results){safe(r);assert.equal(r.status,"ALREADY_HOLD");}
 assert.deepEqual((await db.collection(ROOT).get()).docs[0].data(),original);
});
test("04: old phone wallet changed AFTER initial hold -> stale report error, zero overwritten",async()=>{
 const ref=db.doc(walletRoot);
 await ref.update({diamonds:999999,xp:900000});
 await assert.rejects(migrationHold(args()),/PREVIOUS_IMMUTABLE_REPORT_CHANGED_SOURCE/);
 assert.equal((await db.collection(ROOT).get()).size,1);
 await ref.set(originalWallet);
 safe(await migrationHold(args()));
});
test("05: spoofed original account with NO Stage54 server binding blocks",async()=>{
 const u1="stage55_no_binding_old",u2="stage55_no_binding_new";
 await seed(B,u1,u2,{missingSecondBinding:true});
 await assert.rejects(migrationHold(args(B,u1,u2)),/MISSING_STAGE54_SERVER_HOLD_BINDING/);
});
test("06: cross-account Stage54 binding cannot be used to migrate another account",async()=>{
 const u1="stage55_other_account_old",u2="stage55_other_account_new";
 await seed(C,u1,u2,{mismatchSecondBinding:true});
 await assert.rejects(migrationHold(args(C,u1,u2)),/MISSING_STAGE54_SERVER_HOLD_BINDING/);
});
test("07: original legacy user row has different canonical account => conflict HOLD",async()=>{
 const u1="stage55_wrong_user_old",u2="stage55_wrong_user_new";
 await seed(D,u1,u2,{mismatchSecondUser:true});
 const r=await migrationHold(args(D,u1,u2));
 safe(r);assert.ok(r.flags.includes("USER_ACCOUNT_MISMATCH_NEW"));
});
test("08: missing second phone wallet and profile data must NOT invent a migrated balance",async()=>{
 const u1="stage55_missing_wallet_old",u2="stage55_missing_wallet_new";
 await seed(E,u1,u2,{missingSecondUser:true,missingSecondWallet:true});
 const r=await migrationHold(args(E,u1,u2));
 safe(r);
 assert.ok(r.flags.includes("MISSING_UID_LEGACY_USER_ROW"));
 assert.ok(r.flags.includes("MISSING_UID_WALLET_SNAPSHOT"));
 assert.equal((await db.doc(ROOT+"/"+r.reportId).get()).data().sourceUserRowsPresent,1);
});
test("09: even equal two-phone XP/diamond/frame snapshots remain HOLD without server receipts",async()=>{
 const u1="stage55_equal_balance_old",u2="stage55_equal_balance_new";
 await seed(F,u1,u2,{equalWallets:true});
 const r=await migrationHold(args(F,u1,u2));
 safe(r);
 assert.ok(r.flags.includes("NO_AUTOMATIC_LEGACY_BALANCE_TRUST"));
 assert.ok(r.flags.includes("LOCAL_DAILY_POINTS_CANNOT_BE_SERVER_VERIFIED"));
 assert.equal((await db.doc(ROOT+"/"+r.reportId).get()).data().canMigrate,false);
});
test("10: copied install ID is never accepted as server-owned account identity",async()=>{
 const u1="stage55_copy_install_old",u2="stage55_copy_install_new";
 await seed(G,u1,u2,{missingSecondBinding:true});
 await assert.rejects(migrationHold(args(G,u1,u2)),/MISSING_STAGE54_SERVER_HOLD_BINDING/);
 assert.equal((await db.collection(ROOT).get()).size,4);
});
test("11: changed original account profile after successful hold triggers immutable-review conflict",async()=>{
 const profile=db.doc("deda_account_profiles/"+A);
 await profile.update({name:"Altered on second phone"});
 await assert.rejects(migrationHold(args()),/PREVIOUS_IMMUTABLE_REPORT_CHANGED_SOURCE/);
 await profile.update({name:"Synthetic"});
 safe(await migrationHold(args()));
});
test("12: reversed phone order for prior account cannot overwrite existing held report",async()=>{
 await assert.rejects(
  migrationHold(args(A,N,O)),
  /PREVIOUS_IMMUTABLE_REPORT_CHANGED_SOURCE/);
});
test("13: no report contains real wallet balances, original ID, or copied install string",async()=>{
 const records=await db.collection(ROOT).get();
 assert.equal(records.size,4);
 for(const snap of records.docs){
  const d=snap.data();
  assert.equal(d.canTransferWallet,false);
  assert.equal(d.canCreditDiamonds,false);
  assert.equal(d.emulatorOnly,true);
  const serialized=JSON.stringify(d);
  for(const secret of ["@DEDA-VIP777","device-copyable","original-bought"])
   assert.equal(serialized.includes(secret),false);
  for(const forbiddenField of ["diamonds","xp","coins","premiumId","purchasedFrames"])
   assert.equal(Object.hasOwn(d,forbiddenField),false);
 }
});
test("14: no original wallet, admin diamonds, real gift inbox, frame or premium ID modified",async()=>{
 assert.deepEqual((await db.doc(walletRoot).get()).data(),originalWallet);
 assert.equal((await db.doc(userRoot).get()).data().premiumId,"@DEDA-VIP777");
 assert.equal((await db.doc(gmRoot).get()).data().diamonds,1000000);
 assert.equal((await db.collection("deda_weekly_stage45_private_gift_inbox").get()).size,0);
 assert.equal((await db.collection("deda_verified_progress").get()).size,0);
 assert.equal((await db.collection("deda_progress_receipts").get()).size,0);
});
test("15: stage55 cannot run against production project even when called with Admin SDK",async()=>{
 const previous=process.env.GCLOUD_PROJECT;
 process.env.GCLOUD_PROJECT="deda-25b88";
 try { await assert.rejects(migrationHold(args()),/EMULATOR_ONLY/);}
 finally {process.env.GCLOUD_PROJECT=previous;}
});
test("16: no-key or wrong-length backend HMAC key fails closed",async()=>{
 await assert.rejects(migrationHold(args(A,O,N,Buffer.alloc(10))),/EMULATOR_ONLY/);
});
test("17: same UID twice, malformed UID/account, or arbitrary paths fail closed",async()=>{
 await assert.rejects(migrationHold(args(A,O,O)),/INVALID_TWO_UID_INPUT/);
 await assert.rejects(migrationHold(args(A,O,"/crosspath")),/INVALID_TWO_UID_INPUT/);
 await assert.rejects(migrationHold(args("77_bad",O,N)),/INVALID_TWO_UID_INPUT/);
});
test("18: immutable hold report exists only in server-only namespace, no credit authorizers",async()=>{
 const snap=await db.collection(ROOT).get();
 assert.equal(snap.size,4);
 for(const x of snap.docs)for(const k of [
   "canMigrate","canCreditXp","canCreditDiamonds",
   "canIssueGift","canReplacePremiumId","canTransferWallet",
   "canTransferFrames","canTransferAccount"])
   assert.equal(x.data()[k],false,k);
});
