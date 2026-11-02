'use strict';
// STEP2 / PRIVATE QA / NOT_EXPORTED / READ ONLY. No grants, no wallet writes.
// A server-visible artifact is NOT sufficient proof that old 100340 rights
// have been completely recovered. Missing rows are UNKNOWN, never zero.
const {withLinkedOwnerReadSession}=
 require('./deda_step2_linked_owner_read_session_NOT_EXPORTED.js');
const {weekStart}=require('./deda_weekly_direct_prize_plan.js');
const frames=Object.freeze([
 'FRAME_03','FRAME_05','FRAME_06','FRAME_07','FRAME_08','FRAME_09',
 'FRAME_10','FRAME_11','FRAME_12','FRAME_13','FRAME_14','FRAME_15','FRAME_16',
]);
const id=value=>typeof value==='string'&&/^@DEDA-[A-Z0-9]{4,12}$/.test(value);
const reject=code=>{throw Object.assign(new Error(code),{code});};
const stamp=value=>value&&typeof value.toMillis==='function'&&
 Number.isSafeInteger(value.toMillis())&&value.toMillis()>=0;

/**
 * Consume ONLY a read-locked session proven by the linked-password original
 * UID guard. weekId is supplied by an INTERNAL trusted clock/worker, never
 * from a client. All reads share one transaction; the caller has no write API.
 * This is not an enumeration of historical premium gifts or prize weeks.
 */
async function inspectLinkedOwnerRights({tx,accountKey,originalId,weekId}){
 if(!tx||typeof tx.get!=='function'||typeof accountKey!=='string'||
    !/^[0-9]{10,16}$/.test(accountKey)||
    !/^@DEDA-[A-Z0-9]{6}$/.test(originalId))
   reject('step2-rights-owner-scope-invalid');
 if(weekId!==undefined){
   // Validates real DEDA league week cadence; rejects invented week IDs.
   try{weekStart(weekId);}catch(_){reject('step2-rights-week-invalid');}
 }
 const statuses={};
 let verifiedPairs=0;
 for(const frame of frames){
   const receipt=await tx.get('deda_lab_frame_receipts/'+originalId+'/frames/'+frame);
   const owned=await tx.get('deda_lab_owned_frames/'+originalId+'/frames/'+frame);
   if(receipt===null&&owned===null){
     statuses[frame]='no-server-pair-legacy-unknown';
     continue;
   }
   if(!receipt||!owned||receipt.publicId!==originalId||
      receipt.kind!=='lab_frame'||receipt.frameId!==frame||
      receipt.cost!==1000||owned.publicId!==originalId||
      owned.frameId!==frame||owned.receiptId!==originalId+'_'+frame)
     reject('step2-frame-receipt-ownership-conflict');
   statuses[frame]='confirmed-server-receipt-pair-readonly';
   verifiedPairs++;
 }
 const selection=await tx.get('deda_stage71_active_identifier/'+originalId);
 let activeIdStatus='selection-absent-unknown';
 if(selection!==null){
   const chosen=selection.activeId;
   if(selection.originalId!==originalId||!id(chosen))
     reject('step2-premium-selection-corrupt');
   if(chosen===originalId){
     activeIdStatus='original-id-selected-not-premium';
   }else{
     const grant=await tx.get('deda_stage71_granted_registry/'+chosen);
     const receipt=await tx.get('deda_stage74_id_gift_receipts/'+chosen);
     if(grant===null){
       if(receipt!==null)reject('step2-premium-receipt-without-grant');
       // Other paid/legacy premium alias registries may exist: don't erase.
       activeIdStatus='active-alias-independent-ownership-unverified';
     }else{
       if(grant.identifier!==chosen||grant.recipientOriginalId!==originalId||
          !['001','002'].includes(grant.group)||
          !['gold','diamond','royal','pink'].includes(grant.baseColor)||
          !['gifted','self_used'].includes(grant.kind)||
          !stamp(grant.grantedAt))
         reject('step2-premium-grant-owner-conflict');
       if(grant.kind==='self_used'){
         if(receipt!==null)reject('step2-self-use-must-not-have-gift-receipt');
         activeIdStatus='stage71-self-use-grant-readonly';
       }else if(receipt===null){
         // Grant alone is NOT the recipient's acceptance of the gift.
         activeIdStatus='stage71-gift-awaiting-recipient-receipt';
       }else{
         if(receipt.identifier!==chosen||receipt.originalId!==originalId||
            receipt.group!==grant.group||!stamp(receipt.receivedAt))
           reject('step2-premium-gift-receipt-conflict');
         activeIdStatus='stage71-gift-received-readonly';
       }
     }
   }
 }
 let weeklyGiftStatus='week-not-audited';
 if(weekId!==undefined){
   // Deterministic ID comes from the REAL weekly prize worker/plan.
   const giftId='deda-weekly-'+weekId+'-'+originalId.slice(1);
   const gift=await tx.get('deda_diamond_gifts/'+giftId);
   if(gift===null){
     weeklyGiftStatus='weekly-receipt-not-found-history-unknown';
   }else{
     if(gift.giftId!==giftId||gift.sourceType!=='weekly_league'||
        gift.targetPublicId!==originalId||
        !Number.isSafeInteger(gift.amount)||gift.amount<=0||
        !['pending','claimed'].includes(gift.status)||!stamp(gift.createdAt))
       reject('step2-weekly-prize-receipt-conflict');
     // 'claimed' is an observation, NOT a second gift wallet credit.
     weeklyGiftStatus=gift.status==='claimed'
       ?'claimed-weekly-gift-already-processed'
       :'pending-weekly-gift-do-not-credit-on-restore';
   }
 }
 return Object.freeze({
   status:'LINKED_RIGHTS_READONLY_HOLD',
   scannedFrameSlots:frames.length,verifiedFramePairs:verifiedPairs,
   frameSources:Object.freeze(statuses),
   activeIdStatus,weeklyGiftStatus,
   completeHistoricalGiftInbox:false,completeWeeklyPrizeHistory:false,
   allPurchasedFramesRecovered:false,
   canGrantFrames:false,canActivateId:false,canAcceptGift:false,
   canCreditWeeklyDiamonds:false,canReissueAwards:false,
   canRestoreBalances:false,allowPhoneCutover:false,
 });
}
async function previewLinkedOwnerRights({store,auth,idToken,weekId}){
 return withLinkedOwnerReadSession({store,auth,idToken},(tx,accountKey,owner)=>
   inspectLinkedOwnerRights({tx,accountKey,originalId:owner.originalId,weekId}));
}
module.exports={inspectLinkedOwnerRights,previewLinkedOwnerRights,frames};
