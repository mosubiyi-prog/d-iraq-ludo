"use strict";

// Real Firestore Emulator ONLY: server-generated 5k+10k checkout receipts,
// then READ-ONLY audit. No production Firebase secrets or project available.
const test=require("node:test"),assert=require("node:assert/strict");
const {resolve}=require("node:path");
const {createRequire}=require("node:module");
const host=process.env.FIRESTORE_EMULATOR_HOST||"";
assert.match(host,/^(127\.0\.0\.1|localhost):[0-9]+$/);
assert.equal(process.env.GCLOUD_PROJECT,"demo-deda-owner19-stage54-receipt");
const req=createRequire(resolve(__dirname,"../functions/package.json"));
const {initializeApp,deleteApp}=req("firebase-admin/app");
const {getFirestore}=req("firebase-admin/firestore");
const {checkoutIdCard}=require(
  "../tools/deda_intakadha_point13_atomic_id_card_checkout_2026_10_19.js");
const {createApprovedSaleCatalog,checkoutVerifiedIdentifier}=require(
  "../tools/deda_stage18_private_atomic_identifier_checkout_2026_10_19.js");
const {auditRecordedPurchaseReceipt:audit}=require(
  "../tools/deda_owner19_stage54_purchase_receipt_audit_private_2026_10_20.js");
const catalog=createApprovedSaleCatalog({
  reservedSuffixes:Array.from({length:100},(_,i)=>String(i+1).padStart(6,"0")),
  approvedSuffixes:["AAAAAA"],
});
const uid="stage54_UID",account="stage54_buyer",orig="@DEDA-X1Y2Z3";
const exclusive="@DEDA-ABCD",purchased="@DEDA-AAAAAA";
const cardReq="stage54_card_real_001",idReq="stage54_id_real_001";
let app,db;
test.before(async()=>{
  app=initializeApp({projectId:"demo-deda-owner19-stage54-receipt"},
    "stage54-emulator-only");
  db=getFirestore(app);
  const batch=db.batch();
  batch.set(db.collection("users").doc(uid),{
    accountKey:account,sharePersonalId:orig,
  });
  batch.set(db.collection("deda_sessions").doc(uid),{
    uid,accountKey:account,
  });
  batch.set(db.collection("deda_share_ids").doc(orig),{
    publicId:orig,kind:"personal",active:true,ownerUid:uid,
  });
  batch.set(db.collection("deda_diamond_gift_balances").doc(orig),{
    publicId:orig,balance:30000,
  });
  const {createHash}=require("node:crypto");
  const hashed=createHash("sha256").update(account).digest("hex");
  batch.set(db.collection("deda_owned_identifier_accounts").doc(hashed),{
    accountKey:account,originalId:orig,activeId:exclusive,
    ownedIds:[orig,exclusive],
  });
  batch.set(db.collection("deda_owned_identifier_registry").doc(exclusive),{
    identifier:exclusive,accountKey:account,originalId:orig,
    status:"owned",acquisition:"general_manager_gift",
    assignedColor:"diamond",
  });
  batch.set(db.collection("deda_owned_identifier_aliases").doc(exclusive),{
    identifier:exclusive,accountKey:account,originalId:orig,
    kind:"permanent_alias",
  });
  batch.set(db.collection("deda_verified_id_sale_catalog").doc(purchased),{
    identifier:purchased,group:"002",status:"verified_available",
    ownerApproved:true,priceDiamonds:10000,
  });
  await batch.commit();
});
test.after(async()=>{if(app)await deleteApp(app);});
test("real server transactions produce reconciled 5k + 10k receipts with no extra audit debit",async()=>{
  const wallet=db.collection("deda_diamond_gift_balances").doc(orig);
  const first=await checkoutIdCard(db,{
    uid,color:"gold",requestId:cardReq,
  });
  assert.equal(first.diamondsCharged,5000);
  const second=await checkoutVerifiedIdentifier(db,{
    uid,identifier:purchased,requestId:idReq,approvedCatalog:catalog,
  });
  assert.equal(second.diamondsCharged,10000);
  assert.equal((await wallet.get()).data().balance,15000);
  const c=await audit(db,{uid,kind:"card",requestId:cardReq});
  const i=await audit(db,{uid,kind:"identifier",requestId:idReq});
  assert.deepEqual([c.diamondsCharged,i.diamondsCharged],[5000,10000]);
  assert.equal(c.receiptMatchesOwnership,true);
  assert.equal(i.receiptMatchesOwnership,true);
  assert.equal(c.purchaseReleaseApproved,false);
  assert.equal(i.historicWalletProvenanceEstablished,false);
  assert.equal((await wallet.get()).data().balance,15000);
  await audit(db,{uid,kind:"identifier",requestId:idReq});
  assert.equal((await wallet.get()).data().balance,15000);
  const {createHash}=require("node:crypto");
  const hashed=createHash("sha256").update(account).digest("hex");
  const rec=db.collection("deda_id_purchase_requests").doc(hashed)
    .collection("requests").doc(idReq);
  await rec.update({giftCharged:9999});
  await assert.rejects(audit(db,{uid,kind:"identifier",requestId:idReq}),
    e=>e.code==="failed-precondition");
  assert.equal((await wallet.get()).data().balance,15000);
});
