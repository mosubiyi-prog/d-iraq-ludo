"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore}=require("firebase-admin/firestore");
const {PROJECT,ROOT:STAGE55,migrationHold}=require(
  "../../tools/app_stability/stage55/private_two_phone_migration_hold.cjs");
const {ROOT,auditAssetProvenance}=require(
  "../../tools/app_stability/stage56/private_original_asset_provenance_audit.cjs");
if(process.env.GCLOUD_PROJECT!==PROJECT||
   process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
   process.env.DEDA_STAGE55_EMULATOR_ONLY!=="true"||
   process.env.DEDA_STAGE56_EMULATOR_ONLY!=="true")
 throw Error("STAGE56_REQUIRES_REAL_ORIGINAL_SCHEMA_PRIVATE_EMULATOR");
const app=initializeApp({projectId:PROJECT},"stage56-original-source-fixtures");
const db=getFirestore(app);
const KEY=Buffer.alloc(32,0x56);
const A="07701112233",B="07702223334",C="07703334445";
const ids={
  [A]:["stage56_original_uid_one","stage56_second_phone_two"],
  [B]:["stage56_valid_owner_B_one","stage56_valid_owner_B_two"],
  [C]:["stage56_valid_owner_C_one","stage56_valid_owner_C_two"]
};
const PURCHASE="stage56_original_purchase_capture_01";
const RECEIPT="a".repeat(64),GIFT="b".repeat(64);
const ALIAS="@DEDA-TEST56";
const WALLET_OLD={diamonds:923,xp:2250,coins:31,level:13,
 purchasedFrames:["gold","royal"],premiumId:"@DEDA-VIP777"};
const WALLET_NEW={diamonds:0,xp:0,coins:0,level:1,
 purchasedFrames:[],premiumId:"@DEDA-NEW01"};
const GM="deda_admin_diamond_wallets/general_manager";
function args(account=A){
 const [originalUid,newPhoneUid]=ids[account];
 return {db,accountKey:account,originalUid,newPhoneUid,serverKey:KEY,
  purchaseCaptureId:PURCHASE,receiptId:RECEIPT,giftId:GIFT,
  originalPersonalId:ALIAS};
}
async function seed(account,{sameWallet=false,missingSecondWallet=false}={}){
 const [oldUid,newUid]=ids[account],batch=db.batch();
 batch.set(db.doc("deda_account_directory/"+account),
   {accountKey:account,active:true,createdUid:oldUid});
 batch.set(db.doc("deda_account_profiles/"+account),
   {accountKey:account,name:"Stage56 Test Account",trustedInstallIds:["copyable-install"]});
 for(const [i,uid] of [oldUid,newUid].entries()){
  batch.set(db.doc("deda_stage54_private_account_bindings/"+uid),{
    uid,accountKey:account,authProvider:"anonymous",
    state:"LOCAL_VERIFIED_HOLD_ONLY",emulatorOnly:true,
    canMigrate:false,canGrant:false
  });
  batch.set(db.doc("users/"+uid),{
    uid,accountKey:account,name:"Synthetic device",
    premiumId:i?"@DEDA-NEW01":"@DEDA-VIP777",
    xp:i?0:2250,diamonds:i?0:923
  });
  batch.set(db.doc("deda_sessions/"+uid),
    {uid,accountKey:account,installId:"copyable-install",
     signedInAt:0,lastSeenAt:0});
  if(!(missingSecondWallet&&i))
   batch.set(db.doc("users/"+uid+"/wallet/original"),
    i&&!sameWallet?WALLET_NEW:WALLET_OLD);
 }
 await batch.commit();
}
function deny(r){
 assert.equal(r.canMigrate,false);
 assert.equal(r.canTransferWallet,false);
 assert.equal(r.canTransferFrames,false);
 assert.equal(r.canReplacePremiumId,false);
 assert.equal(r.canCreditXp,false);
 assert.equal(r.canCreditDiamonds,false);
 assert.equal(r.canIssueGift,false);
 assert.equal(r.canSettlePurchase,false);
 assert.equal(r.productionReady,false);
 assert.ok(["NEW_HOLD","ALREADY_HOLD"].includes(r.status));
}
test.before(async()=>{
 await seed(A);
 await db.doc(GM).set({diamonds:1000000,ids:["@DEDA-001001"]});
});
test.after(async()=>deleteApp(app));

test("01: Stage56 refuses unaudited account without immutable Stage55 HOLD",async()=>{
 await assert.rejects(auditAssetProvenance(args()),/MISSING_IMMUTABLE_STAGE55_HOLD/);
});
test("02: creates real Stage55 immutable source audit first, then Stage56 never auto-transfers",async()=>{
 const b=await migrationHold({
   db,accountKey:A,originalUid:ids[A][0],newPhoneUid:ids[A][1],serverKey:KEY
 });
 assert.equal(b.status,"NEW_HOLD");
 const r=await auditAssetProvenance(args());
 deny(r);assert.equal(r.status,"NEW_HOLD");
 assert.equal(r.sourceStatus.purchase,"MISSING_LEGACY_PURCHASE_CAPTURE");
 assert.equal(r.sourceStatus.receipt,"MISSING_NOMINATED_PROGRESS_RECEIPT");
 assert.ok(r.holdFlags.includes("NO_PAYMENT_PROVIDER_VERIFIED_RECEIPT"));
 assert.ok(r.holdFlags.includes("TWO_PHONE_PREMIUM_ID_DIFFERENCE"));
 assert.ok(r.holdFlags.includes("TWO_PHONE_PURCHASED_FRAME_DIFFERENCE"));
 assert.ok(r.holdFlags.includes("TWO_PHONE_DIAMONDS_DIFFERENCE"));
});
test("03: replay same snapshots yields same audit, no second report or credit",async()=>{
 const one=await auditAssetProvenance(args());
 const two=await auditAssetProvenance(args());
 deny(one);deny(two);
 assert.equal(one.status,"ALREADY_HOLD");
 assert.equal(one.reportId,two.reportId);
 assert.equal((await db.collection(ROOT).get()).size,1);
});
test("04: true parallel audit replays preserve a single immutable report",async()=>{
 const prior=(await db.collection(ROOT).get()).docs[0].data();
 const r=await Promise.all(Array.from({length:3},()=>auditAssetProvenance(args())));
 r.forEach(deny);
 assert.ok(r.every(x=>x.status==="ALREADY_HOLD"));
 assert.deepEqual((await db.collection(ROOT).get()).docs[0].data(),prior);
});
test("05: late client-written purchase journal cannot silently approve earlier report",async()=>{
 const path="deda_purchase_evidence/"+A+"/captures/"+PURCHASE;
 await db.doc(path).set({
  kind:"legacy-purchase-evidence",accountKey:A,
  sourceUid:ids[A][0],frame:"royal",status:"paid"
 });
 await assert.rejects(auditAssetProvenance(args()),/PREVIOUS_AUDIT_PROVENANCE_CHANGED/);
 await db.doc(path).delete();
 deny(await auditAssetProvenance(args()));
});
test("06: original old-device wallet changes after Stage55 are held BEFORE new asset review",async()=>{
 const wallet=db.doc("users/"+ids[A][0]+"/wallet/original");
 await wallet.update({diamonds:900000});
 await assert.rejects(auditAssetProvenance(args()),/PREVIOUS_STAGE55_SOURCE_DRIFT/);
 await wallet.set(WALLET_OLD);
 deny(await auditAssetProvenance(args()));
});
test("07: account with client purchase journal, old progress, spoofed receipt, shadow gift and legacy ID still HOLD",async()=>{
 await seed(B,{sameWallet:true});
 await db.doc("deda_purchase_evidence/"+B+"/captures/"+PURCHASE).set({
   kind:"legacy-purchase-evidence",accountKey:B,sourceUid:ids[B][0],
   frameJournal:"paid",installId:"copyable-install"
 });
 await db.doc("deda_progress_migrations/"+B).set({
   accountKey:B,phase:"cutover-complete",migrationId:"client-claimed"
 });
 await db.doc("deda_verified_progress/"+B).set({
   accountKey:B,lifetimeXp:1000000,source:"client_fixture"
 });
 await db.doc("deda_progress_receipts/"+B+"/events/"+RECEIPT).set({
   accountKey:B,points:999999,issuer:"client_claimed_server"
 });
 await db.doc("deda_weekly_stage45_private_gift_inbox/"+GIFT).set({
   issuer:"stage45_backend_fixture_only_NOT_LIVE",emulatorOnly:true,
   canAuthorizeProduction:false,amount:150,status:"pending"
 });
 await db.doc("deda_share_ids/"+ALIAS).set({
   kind:"personal",active:true,ownerUid:ids[B][0]
 });
 await migrationHold({db,accountKey:B,originalUid:ids[B][0],
   newPhoneUid:ids[B][1],serverKey:KEY});
 const r=await auditAssetProvenance(args(B));deny(r);
 assert.equal(r.sourceStatus.purchase,"UNTRUSTED_CLIENT_PURCHASE_JOURNAL");
 assert.equal(r.sourceStatus.progress,"UNVERIFIED_SERVER_MIGRATION_CANDIDATE");
 assert.equal(r.sourceStatus.receipt,"UNVERIFIED_RECEIPT_CANDIDATE");
 assert.equal(r.sourceStatus.gift,"PRIVATE_QA_GIFT_NOT_SPENDABLE");
 assert.equal(r.sourceStatus.originalId,"LEGACY_ALIAS_NOT_INDEPENDENT_OWNERSHIP_PROOF");
 assert.ok(r.holdFlags.includes("PURCHASE_JOURNAL_IS_NOT_PAYMENT_PROVIDER_RECEIPT"));
 assert.ok(r.holdFlags.includes("CUTOVER_LABEL_ALONE_CANNOT_PROVE_ORIGINAL_SETTLEMENT"));
 assert.ok(r.holdFlags.includes("STAGE45_PRIVATE_GIFT_NEVER_AUTHORISES_LIVE_DIAMONDS"));
});
test("08: forged client receipt is never marked independently paid",async()=>{
 const r=await auditAssetProvenance(args(B));deny(r);
 assert.ok(r.holdFlags.includes("RECEIPT_MUST_BE_REVIEWED_WITH_SIGNED_SERVER_ISSUER_AND_BASELINE"));
});
test("09: post-review gift fixture amount update cannot overwrite original provenance report",async()=>{
 const gift=db.doc("deda_weekly_stage45_private_gift_inbox/"+GIFT);
 await gift.update({amount:1000000});
 await assert.rejects(auditAssetProvenance(args(B)),/PREVIOUS_AUDIT_PROVENANCE_CHANGED/);
 await gift.update({amount:150});
 deny(await auditAssetProvenance(args(B)));
});
test("10: conflicting original gift shape and foreign share-ID owner are flagged, NEVER granted",async()=>{
 await seed(C,{missingSecondWallet:true});
 await db.doc("deda_weekly_stage45_private_gift_inbox/"+GIFT).update({
   emulatorOnly:false,canAuthorizeProduction:true
 });
 await db.doc("deda_share_ids/"+ALIAS).update({ownerUid:"another_test_uid"});
 await migrationHold({db,accountKey:C,originalUid:ids[C][0],
   newPhoneUid:ids[C][1],serverKey:KEY});
 const r=await auditAssetProvenance(args(C));deny(r);
 assert.ok(r.holdFlags.includes("PRIVATE_GIFT_FORGED_OR_NON_QA_SHAPE"));
 assert.ok(r.holdFlags.includes("PERSONAL_ID_LEGACY_OWNER_CONFLICT"));
 // Restore original (B audit must remain immutable/replayable).
 await db.doc("deda_weekly_stage45_private_gift_inbox/"+GIFT).update({
   emulatorOnly:true,canAuthorizeProduction:false
 });
 await db.doc("deda_share_ids/"+ALIAS).update({ownerUid:ids[B][0]});
 deny(await auditAssetProvenance(args(B)));
});
test("11: injected accountKey in existing receipt flags mismatch; cannot claim another account",async()=>{
 const rec=db.doc("deda_progress_receipts/"+B+"/events/"+RECEIPT);
 await rec.update({accountKey:A});
 await assert.rejects(auditAssetProvenance(args(B)),/PREVIOUS_AUDIT_PROVENANCE_CHANGED/);
 await rec.update({accountKey:B});
});
test("12: inconsistent Stage55 HOLD ownership cannot start asset audit",async()=>{
 const r=await db.collection(STAGE55).get();
 assert.equal(r.size,3);
 const prior=r.docs.find(x=>x.data().originalUid===ids[C][0]);
 await prior.ref.update({canMigrate:true});
 await assert.rejects(auditAssetProvenance(args(C)),/MISSING_IMMUTABLE_STAGE55_HOLD/);
 await prior.ref.update({canMigrate:false});
});
test("13: account alias and premium ID never leak into private audit report",async()=>{
 const rs=await db.collection(ROOT).get();
 assert.equal(rs.size,3);
 for(const x of rs.docs){
  const d=x.data();
  assert.equal(d.state,"HOLD_UNVERIFIED_ASSET_ORIGIN");
  assert.equal(d.emulatorOnly,true);
  for(const k of ["pin","phone","diamonds","xp","coins",
     "purchasedFrames","premiumId","originalPersonalId","originalWallet"])
    assert.equal(Object.hasOwn(d,k),false,k);
  const s=JSON.stringify(d);
  for(const privateValue of ["@DEDA-VIP777","@DEDA-TEST56","copyable-install"])
    assert.equal(s.includes(privateValue),false);
 }
});
test("14: wrong demo/project or missing private emulator flag stops execution",async()=>{
 const prior=process.env.GCLOUD_PROJECT;
 process.env.GCLOUD_PROJECT="deda-25b88";
 try{await assert.rejects(auditAssetProvenance(args()),/EMULATOR_ONLY/);}
 finally{process.env.GCLOUD_PROJECT=prior;}
});
test("15: untrusted path IDs or noncanonical UIDs are rejected before Firestore",async()=>{
 for(const p of [
  {purchaseCaptureId:"../wallet"},
  {receiptId:"forged"},
  {giftId:"/bad"},
  {originalPersonalId:"../original"},
  {originalUid:ids[A][1],newPhoneUid:ids[A][1]},
  {accountKey:"../../../admins"}
 ])await assert.rejects(auditAssetProvenance({...args(),...p}),
   /INVALID_SERVER_INPUT/);
});
test("16: reviewer cannot infer payment approval from identical old/new wallets",async()=>{
 const r=await auditAssetProvenance(args(B));deny(r);
 assert.equal(r.sourceStatus.purchase,"UNTRUSTED_CLIENT_PURCHASE_JOURNAL");
 assert.equal(r.productionReady,false);
});
test("17: no effect on any original wallets, account profile, manager diamonds or gifts",async()=>{
 assert.deepEqual((await db.doc("users/"+ids[A][0]+"/wallet/original").get()).data(),WALLET_OLD);
 assert.deepEqual((await db.doc("users/"+ids[A][1]+"/wallet/original").get()).data(),WALLET_NEW);
 assert.equal((await db.doc(GM).get()).data().diamonds,1000000);
 assert.equal((await db.doc("users/"+ids[A][0]).get()).data().premiumId,"@DEDA-VIP777");
 assert.equal((await db.doc("deda_weekly_stage45_private_gift_inbox/"+GIFT).get()).data().amount,150);
 assert.equal((await db.collection("deda_progress_receipts/"+A+"/events").get()).size,0);
});
test("18: private audit stores hold only, no spendable claim or approval",async()=>{
 const r=await db.collection(ROOT).get();
 assert.equal(r.size,3);
 for(const item of r.docs)for(const k of [
  "canMigrate","canTransferWallet","canTransferFrames",
  "canReplacePremiumId","canCreditXp","canCreditDiamonds",
  "canIssueGift","canSettlePurchase","productionReady"])
  assert.equal(item.data()[k],false);
});
