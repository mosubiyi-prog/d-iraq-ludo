"use strict";
/**
 * Cross-device ORIGINAL DEDA ownership proof; emulator-only, read-only and
 * strictly non-granting. Reuses actual 13 LAB frame and four ID-card receipt
 * schemas plus the 200-ID account registry. NEVER trusts an install's local
 * wallet/journal, a single receipt, or writable cosmetic inventory.
 */
const {createHash}=require("node:crypto");
const FRAMES=Object.freeze([
 "FRAME_03","FRAME_05","FRAME_06","FRAME_07","FRAME_08","FRAME_09",
 "FRAME_10","FRAME_11","FRAME_12","FRAME_13","FRAME_14","FRAME_15","FRAME_16",
]);
const COLORS=Object.freeze(["gold","diamond","royal","pink"]);
const ACCOUNT=/^[0-9]{10,16}$/;
const ORIGINAL=/^@DEDA-[A-Z0-9]{6}$/;
const PREMIUM=/^@DEDA-[A-Z0-9]{4,12}$/;
const UID=/^[A-Za-z0-9_-]{8,128}$/;
function fail(code){throw Error("DEDA_ENTITLEMENTS_"+code);}
async function verifyOriginalAccount(tx,accountKey,originalId) {
 if(!ACCOUNT.test(accountKey)||!ORIGINAL.test(originalId))fail("INVALID_SCOPE");
 const share=await tx.get("deda_share_ids/"+originalId);
 if(share?.kind!=="personal"||share?.publicId!==originalId||
    share?.active!==true||!UID.test(share?.ownerUid||""))
   fail("ORIGINAL_ID_ROUTE_NOT_VERIFIED");
 const owner=await tx.get("users/"+share.ownerUid);
 if(owner?.accountKey!==accountKey||
    (owner.sharePersonalId!=null&&owner.sharePersonalId!==originalId))
   fail("ORIGINAL_ID_OWNER_NOT_VERIFIED");
}
async function readOwnedEntitlements(tx,accountKey,originalId){
 if(!tx||typeof tx.get!=="function")fail("TRANSACTION_REQUIRED");
 await verifyOriginalAccount(tx,accountKey,originalId);
 const verifiedFrames=[];
 for(const frameId of FRAMES){
   const receipt=await tx.get(`deda_lab_frame_receipts/${originalId}/frames/${frameId}`);
   const owned=await tx.get(`deda_lab_owned_frames/${originalId}/frames/${frameId}`);
   if(receipt===null&&owned===null)continue;
   if(!receipt||!owned||receipt.kind!=="lab_frame"||
      receipt.publicId!==originalId||receipt.frameId!==frameId||
      receipt.cost!==1000||owned.publicId!==originalId||
      owned.frameId!==frameId||
      owned.receiptId!==originalId+"_"+frameId)
     fail("LAB_FRAME_RECEIPT_OWNERSHIP_CONFLICT");
   verifiedFrames.push(frameId);
 }
 const verifiedCards=[];
 for(const style of COLORS){
   const id=originalId+"_"+style;
   const receipt=await tx.get("deda_stage66_card_receipts/"+id);
   const owned=await tx.get("deda_stage66_owned_cards/"+id);
   if(receipt===null&&owned===null)continue;
   if(!receipt||!owned||receipt.kind!=="card"||
      receipt.publicId!==originalId||receipt.style!==style||
      receipt.cost!==5000||owned.publicId!==originalId||
      owned.style!==style||owned.receiptId!==id)
     fail("ID_CARD_RECEIPT_OWNERSHIP_CONFLICT");
   verifiedCards.push(style);
 }
 const native=await tx.get("deda_native_account_cosmetics/"+originalId);
 let unreviewedNativeFrames=[];
 let nativePending=[];
 if(native!==null){
   if(native.originalId!==originalId||
      (native.ownedFrames!==undefined&&
        (!Array.isArray(native.ownedFrames)||
        native.ownedFrames.some(x=>!FRAMES.includes(x))||
        new Set(native.ownedFrames).size!==native.ownedFrames.length))||
      (native.pendingFrames!==undefined&&
        (!Array.isArray(native.pendingFrames)||
        native.pendingFrames.some(x=>!FRAMES.includes(x))||
        new Set(native.pendingFrames).size!==native.pendingFrames.length)))
     fail("NATIVE_INVENTORY_CONFLICT");
   // Native wallet/local payment may have been approved by the old APK;
   // never let client-writeable ownedFrames become receipt-backed ownership.
   unreviewedNativeFrames=(native.ownedFrames||[]).filter(x=>!verifiedFrames.includes(x));
   nativePending=native.pendingFrames||[];
 }
 const hash=createHash("sha256").update(accountKey,"utf8").digest("hex");
 const ledger=await tx.get("deda_owned_identifier_accounts/"+hash);
 let premiumLedgerStatus="missing-needs-review";
 let activeId=null,verifiedPremiumIds=[];
 if(ledger!==null){
   const ids=ledger.ownedIds;
   if(ledger.accountKey!==accountKey||ledger.originalId!==originalId||
      !Array.isArray(ids)||ids.length<1||ids.length>250||
      ids[0]!==originalId||new Set(ids).size!==ids.length||
      !ids.every(x=>PREMIUM.test(x))||
      !ids.includes(ledger.activeId))
     fail("PREMIUM_ID_ACCOUNT_LEDGER_CONFLICT");
   verifiedPremiumIds=ids.slice(1);
   activeId=ledger.activeId===originalId?null:ledger.activeId;
   for(const id of verifiedPremiumIds){
     const reg=await tx.get("deda_owned_identifier_registry/"+id);
     const alias=await tx.get("deda_owned_identifier_aliases/"+id);
     if(!reg||!alias||reg.identifier!==id||reg.accountKey!==accountKey||
        reg.originalId!==originalId||reg.status!=="owned"||
        alias.identifier!==id||alias.accountKey!==accountKey||
        alias.originalId!==originalId||alias.kind!=="permanent_alias")
       fail("PREMIUM_ID_REGISTRY_OWNERSHIP_CONFLICT");
   }
   premiumLedgerStatus="registry-confirmed";
 }
 return Object.freeze({
   format:1,readOnly:true,spendable:false,grantAuthority:false,
   ownedFrames:Object.freeze(verifiedFrames),
   ownedCards:Object.freeze(verifiedCards),
   ownedPremiumIds:Object.freeze(verifiedPremiumIds),
   activePremiumId:activeId,
   premiumLedgerStatus,
   unreviewedNativeFrames:Object.freeze(unreviewedNativeFrames),
   pendingNativeFrames:Object.freeze(nativePending),
   fullySettled:false,
 });
}
module.exports={readOwnedEntitlements,FRAMES,COLORS};
