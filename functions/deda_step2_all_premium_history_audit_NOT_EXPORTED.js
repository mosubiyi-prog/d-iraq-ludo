'use strict';
// PRIVATE Step2 original-owner PREMIUM history readback. No client callable,
// gift acceptance, ID activation, sale or wallet mutation. Stage71/74 only;
// older paid identifier issuers may need independent review, never delete.
const {withLinkedOwnerReadSession}=
 require('./deda_step2_linked_owner_read_session_NOT_EXPORTED.js');
const original=v=>typeof v==='string'&&/^@DEDA-[A-Z0-9]{6}$/.test(v);
const premium=v=>typeof v==='string'&&/^@DEDA-[A-Z0-9]{4,12}$/.test(v);
const stamp=v=>v&&typeof v.toMillis==='function'&&
 Number.isSafeInteger(v.toMillis())&&v.toMillis()>=0;
const error=code=>{throw Object.assign(new Error(code),{code});};
function validatePages(grants,receipts,originalId){
 if(!original(originalId)||!Array.isArray(grants)||!Array.isArray(receipts)||
    grants.length>200||receipts.length>200)
   error('step2-premium-history-unbounded');
 const owned=new Map(),ack=new Map();
 for(const item of grants){
   const g=item?.data,id=item?.id;
   if(!premium(id)||!g||g.identifier!==id||
      g.recipientOriginalId!==originalId||
      !['001','002'].includes(g.group)||
      !['gold','diamond','royal','pink'].includes(g.baseColor)||
      !['gifted','self_used'].includes(g.kind)||!stamp(g.grantedAt)||
      owned.has(id))
     error('step2-premium-history-grant-conflict');
   owned.set(id,g);
 }
 for(const item of receipts){
   const r=item?.data,id=item?.id;
   if(!premium(id)||!r||r.identifier!==id||
      r.originalId!==originalId||!['001','002'].includes(r.group)||
      !stamp(r.receivedAt)||ack.has(id))
     error('step2-premium-history-receipt-conflict');
   ack.set(id,r);
 }
 const states=[];
 let giftedPending=0,giftedReceived=0,selfUsed=0;
 for(const [id,g] of owned){
   const receipt=ack.get(id);
   if(g.kind==='self_used'){
     if(receipt)error('step2-premium-history-self-gift-conflict');
     selfUsed++;
     states.push(Object.freeze({identifier:id,state:'self-used-server-grant'}));
   }else if(receipt){
     if(receipt.group!==g.group ||
        receipt.receivedAt.toMillis()<g.grantedAt.toMillis())
       error('step2-premium-history-receipt-grant-conflict');
     giftedReceived++;
     states.push(Object.freeze({identifier:id,state:'gift-received-once'}));
   }else{
     giftedPending++;
     states.push(Object.freeze({identifier:id,state:'gift-awaits-receipt'}));
   }
 }
 for(const id of ack.keys())if(!owned.has(id))
   error('step2-premium-history-orphan-receipt');
 states.sort((a,b)=>a.identifier.localeCompare(b.identifier));
 return Object.freeze({
   status:'STAGE71_74_PREMIUM_HISTORY_READONLY_HOLD',
   stage71GrantRows:grants.length,stage74ReceiptRows:receipts.length,
   selfUsed,receivedGiftCount:giftedReceived,pendingGiftCount:giftedPending,
   states:Object.freeze(states),
   // Scanned all bounded Stage71/74 server rows, NOT legacy paid aliases.
   stage71And74ServerSourcesScanned:true,
   allPremiumIdsRecovered:false,
   legacyPaidAndUnscopedGiftsUnknown:true,
   canGrantPremium:false,canActivatePremium:false,
   canReceiveGift:false,canReissueGift:false,
   canCreditDiamonds:false,allowPhoneCutover:false,
 });
}
async function inspectOriginalPremiumHistory({reader,originalId}){
 if(!original(originalId)||typeof reader?.listPremiumHistory!=='function')
   error('step2-premium-history-owner-unverified');
 // Both pages are inside the same owner-verified read-only transaction;
 // the server adapter must refuse truncated 201-row pages.
 const grants=await reader.listPremiumHistory('grants');
 const receipts=await reader.listPremiumHistory('receipts');
 return validatePages(grants,receipts,originalId);
}
async function previewOriginalPremiumHistory({store,auth,idToken}){
 return withLinkedOwnerReadSession({store,auth,idToken},
   (reader,_account,owner)=>
     inspectOriginalPremiumHistory({reader,originalId:owner.originalId}));
}
module.exports={validatePages,inspectOriginalPremiumHistory,previewOriginalPremiumHistory};
