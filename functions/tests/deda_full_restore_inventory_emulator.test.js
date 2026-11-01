"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore}=require("firebase-admin/firestore");
const {rateDocumentId}=require("../deda_secure_pin_gate_core");
const {originalLockDocumentId}=require("../deda_canonical_account_proof_core");
const {scanAccountRestoreReadiness,InventoryDenied,DOMAINS,FRAMES}=
  require("../deda_full_restore_inventory_core_NOT_EXPORTED");
const PROJECT="demo-deda-100428-inventory-scan";
if(process.env.GCLOUD_PROJECT!==PROJECT ||
   process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080" ||
   process.env.GOOGLE_APPLICATION_CREDENTIALS !== undefined ||
   process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  throw new Error("REFUSE_NON_EMULATOR_ACCOUNT_SCAN");
}
const app=initializeApp({projectId:PROJECT}, "deda-step2-qa");
const db=getFirestore(app);
const secret="100428-only-private-emulator-strong-secret-not-real-123456";
const auth={getUser:async uid=>({uid,disabled:false,email:null,providerData:[]})};
const weekId="2026-10-31";
const state=n=>({
  accountKey:"077000"+String(n).padStart(5,"0"),
  originalId:"@DEDA-"+String(n).padStart(6,"0"),
  sourceUid:"source_uid_"+String(n),
  claimantUid:"device_uid_"+String(n),
  weekId,
});
const ref=p=>db.doc(p);
const req=s=>({
 db,auth,secret,accountKey:s.accountKey,originalId:s.originalId,
 claimantUid:s.claimantUid,weekId:s.weekId,
 freshCanonicalHold:{
   status:"PIN_VERIFIED_HOLD",serverOwned:true,
   productionMigrationEnabled:false,canonicalOriginalVerified:true,
   canonicalOriginalId:s.originalId,canRestoreAssets:false,canMigrate:false,
 },
});
async function write(p,v){await ref(p).set(v)}
async function seed(n,{wallet=true,frames=true,active=true,weekly=true}={}){
 const s=state(n),h=rateDocumentId(secret,s.accountKey),k=originalLockDocumentId(secret,s.originalId);
 const hold={sourceOwnerUid:s.sourceUid,originalId:s.originalId,
   status:"PIN_VERIFIED_HOLD",canRestoreAssets:false,canMigrate:false};
 await Promise.all([
  write("deda_secure_canonical_accounts/"+h,hold),
  write("deda_secure_original_id_owners/"+k,
   {...hold,accountHash:h,canCreditDiamonds:false}),
  write("deda_secure_account_bindings/"+s.claimantUid,{
    uid:s.claimantUid,accountKey:s.accountKey,status:"PIN_VERIFIED_HOLD",
    canRestoreAssets:false,canCreditDiamonds:false}),
  write("deda_account_directory/"+s.accountKey,{
    accountKey:s.accountKey,active:true,createdUid:s.sourceUid}),
  write("deda_credentials/"+s.accountKey,{
    accountKey:s.accountKey,active:true,createdUid:s.sourceUid,pin:"123456"}),
  write("deda_account_profiles/"+s.accountKey,{
    accountKey:s.accountKey,name:"Synthetic owner"}),
  write("users/"+s.sourceUid,{
    accountKey:s.accountKey,sharePersonalId:s.originalId}),
  write("deda_share_ids/"+s.originalId,{
    publicId:s.originalId,kind:"personal",active:true,ownerUid:s.sourceUid}),
 ]);
 if(wallet)await write("deda_diamond_gift_balances/"+s.originalId,{
   publicId:s.originalId,balance:725});
 if(frames){
   const name="FRAME_03";
   await write("deda_lab_frame_receipts/"+s.originalId+"/frames/"+name,{
      publicId:s.originalId,frameId:name,kind:"lab_frame",cost:1000});
   await write("deda_lab_owned_frames/"+s.originalId+"/frames/"+name,{
      publicId:s.originalId,frameId:name,
      receiptId:s.originalId+"_"+name});
 }
 if(active)await write("deda_stage71_active_identifier/"+s.originalId,{
   originalId:s.originalId,activeId:"@DEDA-VIP"+String(n).padStart(3,"0")});
 if(weekly){
   await write("deda_weekly_direct_accounts/"+s.originalId,{
      publicId:s.originalId,accountKey:s.accountKey,createdByUid:s.sourceUid});
   await write("deda_weekly_direct_weeks/"+weekId+"/scores/"+s.originalId,{
      publicId:s.originalId,weekId,weeklyXp:120});
 }
 return s;
}
test.after(async()=>{await deleteApp(app)});
test("full 13-domain audit reports ONLY validated read-only evidence; never monetary restore",async()=>{
 const s=await seed(1),before=(await ref("deda_diamond_gift_balances/"+s.originalId).get()).data();
 const r=await scanAccountRestoreReadiness(req(s));
 assert.equal(r.status,"READ_ONLY_INVENTORY_HOLD");
 assert.equal(r.safeToRestore,false);assert.equal(r.safeToCreditDiamonds,false);
 assert.equal(r.safeToTransferPremiumId,false);assert.equal(r.safeToRewriteWeek,false);
 assert.equal(r.scannedPaidFrameSlots,13);assert.equal(r.verifiedPaidFramePairs,1);
 assert.equal(r.verifiedGiftWalletPresent,true);
 assert.equal(r.activeDisplaySelectionPresent,true);
 assert.equal(Object.keys(r.domains).length,13);
 assert.equal(r.domains.levelAndXp,"not-audited");
 assert.equal(r.domains.taskPoints,"not-audited");
 assert.equal(r.domains.trafficQuestions,"not-audited");
 assert.equal(r.domains.diamondsAndBalances,"partial-verified-gift-wallet-only");
 assert.equal("balance" in r,false);assert.equal("accountKey" in r,false);
 assert.equal("originalId" in r,false);assert.equal("claimantUid" in r,false);
 assert.equal(Object.isFrozen(r),true);
 assert.deepEqual((await ref("deda_diamond_gift_balances/"+s.originalId).get()).data(),before);
});
test("new phone on another anonymous UID can inspect same original locked account, no migration",async()=>{
 const s=await seed(2);
 const other="another_uid_02";
 await write("deda_secure_account_bindings/"+other,{
   uid:other,accountKey:s.accountKey,status:"PIN_VERIFIED_HOLD",
   canRestoreAssets:false,canCreditDiamonds:false});
 const a=await scanAccountRestoreReadiness(req(s));
 const b=await scanAccountRestoreReadiness({...req(s),claimantUid:other});
 assert.deepEqual(a.domains,b.domains);
 assert.equal(b.safeToRestore,false);
 assert.deepEqual(a.verifiedPaidFramePairs,b.verifiedPaidFramePairs);
});
test("missing wallet is not zero and partial economic balances are never reconstructed",async()=>{
 const s=await seed(3,{wallet:false});
 const r=await scanAccountRestoreReadiness(req(s));
 assert.equal(r.verifiedGiftWalletPresent,false);
 assert.equal(r.domains.diamondsAndBalances,"unverified-wallet-sources");
 assert.equal(r.safeToCreditDiamonds,false);
});
test("missing half of frame receipt/ownership pair blocks and never creates item",async()=>{
 const s=await seed(4);
 await ref("deda_lab_owned_frames/"+s.originalId+"/frames/FRAME_03").delete();
 await assert.rejects(scanAccountRestoreReadiness(req(s)),InventoryDenied);
 assert.equal((await ref("deda_lab_owned_frames/"+s.originalId+"/frames/FRAME_03").get()).exists,false);
});
test("wrong owner's claimed premium alias cannot replace original ownership",async()=>{
 const s=await seed(5);
 await ref("deda_secure_original_id_owners/"+originalLockDocumentId(secret,s.originalId))
   .update({sourceOwnerUid:"other_source"});
 await assert.rejects(scanAccountRestoreReadiness(req(s)),InventoryDenied);
});
test("different account or unknown PIN hold is rejected",async()=>{
 const s=await seed(6);
 await assert.rejects(scanAccountRestoreReadiness({...req(s),accountKey:"07700099999"}),
   InventoryDenied);
 await assert.rejects(scanAccountRestoreReadiness({...req(s),claimantUid:"other-new-user"}),
   InventoryDenied);
});
test("ambiguous same legacy creator UID with two phone accounts fails closed",async()=>{
 const s=await seed(7);
 await write("deda_account_directory/07700077777",{
   active:true,accountKey:"07700077777",createdUid:s.sourceUid});
 await assert.rejects(scanAccountRestoreReadiness(req(s)),InventoryDenied);
});
test("no one-sided canonical/original mapping is repaired or created",async()=>{
 const s=await seed(8);
 const lock=ref("deda_secure_original_id_owners/"+
  originalLockDocumentId(secret,s.originalId));
 await lock.delete();
 await assert.rejects(scanAccountRestoreReadiness(req(s)),InventoryDenied);
 assert.equal((await lock.get()).exists,false);
});
test("revoked personal ID route denies access to ALL recovery sources",async()=>{
 const s=await seed(9);
 await ref("deda_share_ids/"+s.originalId).update({active:false});
 await assert.rejects(scanAccountRestoreReadiness(req(s)),InventoryDenied);
});
test("unverified current owner projection cannot select a different original ID",async()=>{
 const s=await seed(10);
 await ref("users/"+s.sourceUid).update({sharePersonalId:"@DEDA-FFFF00"});
 await assert.rejects(scanAccountRestoreReadiness(req(s)),InventoryDenied);
});
test("wallet mismatch or partial paid frame corruption never results in credit",async()=>{
 const s=await seed(11);
 await ref("deda_diamond_gift_balances/"+s.originalId).update({balance:-25});
 await assert.rejects(scanAccountRestoreReadiness(req(s)),InventoryDenied);
});
test("missing week score and active premium selection require review, not fabricated defaults",async()=>{
 const s=await seed(12,{weekly:false,active:false,frames:false});
 const r=await scanAccountRestoreReadiness(req(s));
 assert.equal(r.verifiedPaidFramePairs,0);
 assert.equal(r.domains.weeklyLeague,"week-score-unverified");
 assert.equal(r.domains.premiumIdentifier,"active-selection-absent-needs-review");
 assert.equal(r.safeToRestore,false);
});
test("wrong credential PIN or revoked Firebase Auth UID do not transfer identity",async()=>{
 const s=await seed(13);
 const disabled={getUser:async uid=>({uid,disabled:true,providerData:[]})};
 await assert.rejects(scanAccountRestoreReadiness({...req(s),auth:disabled}),InventoryDenied);
});
test("phone alias and active premium ID never count as canonical account identity",async()=>{
 const s=await seed(14);
 for(const altered of [{accountKey:"9647700014"},{originalId:"@DEDA-VIP014"},
   {accountKey:"07-700-0014"},{weekId:"2026/10/31"}]){
   await assert.rejects(scanAccountRestoreReadiness({...req(s),...altered}),InventoryDenied);
 }
});

test("fresh canonical PIN verification context is mandatory and cannot be supplied as a stale/alias receipt",async()=>{
 const s=await seed(15);
 const good=req(s);
 await assert.rejects(scanAccountRestoreReadiness({
   ...good,freshCanonicalHold:undefined,
 }),InventoryDenied);
 for(const bad of [
   {canonicalOriginalId:"@DEDA-VIP015"},
   {canonicalOriginalVerified:false},
   {canMigrate:true},
   {serverOwned:false},
   {productionMigrationEnabled:true},
 ]){
  await assert.rejects(scanAccountRestoreReadiness({
    ...good,freshCanonicalHold:{...good.freshCanonicalHold,...bad},
  }),InventoryDenied);
 }
 const result=await scanAccountRestoreReadiness(good);
 assert.equal(result.safeToRestore,false);
});
