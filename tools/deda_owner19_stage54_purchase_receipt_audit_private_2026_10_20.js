"use strict";

// DEDA Owner19 Stage54 — READ ONLY, private receipt/ownership reconciliation.
// Not imported by functions/index.js, no callable, no writes, no real users.
// Reconcile ALREADY RECORDED card/ID purchases from authenticated owner UID.
// Important: receipts alone NEVER attest the origins of legacy diamonds;
// no price, wallet or entitlement migration, no live purchase approval.
const {createHash}=require("node:crypto");
const PRICE_CARD=5000, PRICE_ID=10000;
const VALID_COLORS=new Set(["gold","diamond","royal","pink"]);
const UID=/^[A-Za-z0-9_-]{1,160}$/;
const KEY=/^[A-Za-z0-9_-]{4,160}$/;
const ORIGINAL=/^@DEDA-[A-Z0-9]{6}$/;
const PREMIUM=/^@DEDA-[A-Z0-9]{4,12}$/;
const REQUEST=/^[A-Za-z0-9_-]{8,80}$/;
const sha=x=>createHash("sha256").update(x,"utf8").digest("hex");
function fail(code="failed-precondition"){
  const e=new Error("deda-stage54-purchase-receipt-not-reconciled");
  e.code=code;
  throw e;
}
function row(s){return s.exists ? s.data()||{} : {};}
function isMoney(value){return Number.isSafeInteger(value)&&value>=0&&value<=1073741824;}
function receiptAmounts(p,r){
  if(!isMoney(r.diamondsCharged)||!isMoney(r.giftCharged)||
      !isMoney(r.gmPersonalCharged)||
      r.diamondsCharged!==r.giftCharged+r.gmPersonalCharged||
      r.diamondsCharged!==p) fail();
}
function validLedger(ledger,key,original,needed){
  if(!ledger||ledger.accountKey!==key||ledger.originalId!==original||
      !Array.isArray(ledger.ownedIds)||
      ledger.ownedIds[0]!==original||
      ledger.ownedIds.length<2||ledger.ownedIds.length>250||
      new Set(ledger.ownedIds).size!==ledger.ownedIds.length||
      !ledger.ownedIds.every(id=>typeof id==="string"&&PREMIUM.test(id))||
      !ledger.ownedIds.includes(ledger.activeId)||
      !ledger.ownedIds.includes(needed)) fail();
}

async function auditRecordedPurchaseReceipt(db,{uid,kind,requestId}={}){
  if(!db||typeof db.runTransaction!=="function"||
      typeof uid!=="string"||!UID.test(uid)) fail("unauthenticated");
  if(!["card","identifier"].includes(kind)||
      typeof requestId!=="string"||!REQUEST.test(requestId)){
    fail("invalid-argument");
  }
  return db.runTransaction(async tx=>{
    const users=db.collection("users");
    const [us,ss]=await Promise.all([
      tx.get(users.doc(uid)),
      tx.get(db.collection("deda_sessions").doc(uid)),
    ]);
    const user=row(us),session=row(ss),key=user.accountKey,original=user.sharePersonalId;
    if(!us.exists||!ss.exists||
        typeof key!=="string"||!KEY.test(key)||
        typeof original!=="string"||!ORIGINAL.test(original)||
        session.uid!==uid||session.accountKey!==key) fail("permission-denied");
    const sh=await tx.get(db.collection("deda_share_ids").doc(original));
    const share=row(sh);
    if(!sh.exists||share.kind!=="personal"||share.active!==true||
        share.publicId!==original||typeof share.ownerUid!=="string"||
        !UID.test(share.ownerUid)) fail("permission-denied");
    const historic=await tx.get(users.doc(share.ownerUid));
    if(!historic.exists||row(historic).accountKey!==key){
      fail("permission-denied");
    }
    const account=sha(key);
    const receiptRef=kind==="card" ?
      db.collection("deda_id_card_purchase_requests").doc(account)
        .collection("requests").doc(requestId) :
      db.collection("deda_id_purchase_requests").doc(account)
        .collection("requests").doc(requestId);
    const snap=await tx.get(receiptRef);
    if(!snap.exists) fail("not-found");
    const receipt=row(snap);
    if(receipt.accountKey!==key||receipt.requestId!==requestId||
        receipt.serverConfirmed!==true) fail();
    let paid, verifiedType;
    if(kind==="card"){
      const color=receipt.color;
      if(typeof color!=="string"||!VALID_COLORS.has(color)||
          receipt.publicId!==original||
          typeof receipt.alreadyOwned!=="boolean"||
          receipt.transactionId!==sha(key+":"+requestId+":"+color)) fail();
      paid=receipt.alreadyOwned?0:PRICE_CARD;
      verifiedType="owned_card_color";
      receiptAmounts(paid,receipt);
      const entSnap=await tx.get(
        db.collection("deda_id_card_entitlements").doc(account));
      const ent=row(entSnap);
      if(!entSnap.exists||ent.accountKey!==key||
          !ent.colors||typeof ent.colors!=="object"||
          Array.isArray(ent.colors)||ent.colors[color]!==true) fail();
    }else{
      const identifier=receipt.identifier;
      if(typeof identifier!=="string"||
          !/^@DEDA-[A-Z0-9]{6}$/.test(identifier)||
          receipt.originalId!==original||
          receipt.transactionId!==sha(key+":"+requestId+":"+identifier)||
          receipt.alreadyOwned===true) fail();
      paid=PRICE_ID;
      verifiedType="owned_group002_identifier";
      receiptAmounts(paid,receipt);
      const [ownSnap,regSnap,aliasSnap,saleSnap,collisionSnap]=await Promise.all([
        tx.get(db.collection("deda_owned_identifier_accounts").doc(account)),
        tx.get(db.collection("deda_owned_identifier_registry").doc(identifier)),
        tx.get(db.collection("deda_owned_identifier_aliases").doc(identifier)),
        tx.get(db.collection("deda_verified_id_sale_catalog").doc(identifier)),
        tx.get(db.collection("deda_share_ids").doc(identifier)),
      ]);
      validLedger(row(ownSnap),key,original,identifier);
      const reg=row(regSnap),alias=row(aliasSnap),sale=row(saleSnap);
      if(!ownSnap.exists||!regSnap.exists||!aliasSnap.exists||
          !saleSnap.exists||collisionSnap.exists||
          reg.identifier!==identifier||reg.accountKey!==key||
          reg.originalId!==original||reg.status!=="owned"||
          reg.acquisition!=="diamond_purchase"||
          alias.identifier!==identifier||alias.accountKey!==key||
          alias.originalId!==original||alias.kind!=="permanent_alias"||
          sale.identifier!==identifier||sale.group!=="002"||
          sale.status!=="sold"||sale.ownerAccountHash!==account) fail();
    }
    // Current account wallet is NOT compared with historic receipt amount:
    // gifts, valid other purchases and verified rewards can have happened later.
    // This only proves recorded ONE transaction's internal invariants.
    return Object.freeze({
      serverConfirmed:true,kind,requestId,verifiedType,
      diamondsCharged:paid,
      receiptMatchesOwnership:true,
      historicWalletProvenanceEstablished:false,
      purchaseReleaseApproved:false,
    });
  },{maxAttempts:5});
}
module.exports={auditRecordedPurchaseReceipt};
