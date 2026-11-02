'use strict';
// PRIVATE QA / NOT_EXPORTED / READ ONLY. Inspect existing historical weekly
// gift documents for the immutable original ID AND bounded Stage71 aliases.
// No payout, no claim, no balance migration or client endpoint.
const {ORIGIN,WEEK_MS,weekStart}=
 require('./deda_weekly_direct_prize_plan.js');
const {withLinkedOwnerReadSession}=
 require('./deda_step2_linked_owner_read_session_NOT_EXPORTED.js');
const {inspectOriginalPremiumHistory}=
 require('./deda_step2_all_premium_history_audit_NOT_EXPORTED.js');
const ORIG=/^@DEDA-[A-Z0-9]{6}$/;
const ALIAS=/^@DEDA-[A-Z0-9]{4,12}$/;
const MAX_WEEKS=12,MAX_ALIASES=12;
const stop=code=>{throw Object.assign(new Error(code),{code});};
const safe=n=>Number.isSafeInteger(n)&&n>=0;
function completedWeeks(nowMs){
 if(!safe(nowMs)||nowMs>4102444800000)
   stop('step2-historical-week-clock-untrusted');
 const total=nowMs<ORIGIN+WEEK_MS?0:
   Math.floor((nowMs-ORIGIN)/WEEK_MS);
 const count=Math.min(total,MAX_WEEKS);
 const starts=[];
 for(let i=total-count;i<total;i++){
   const start=ORIGIN+i*WEEK_MS;
   const local=new Date(start+3*3600000);
   const pad=n=>String(n).padStart(2,'0');
   const id=local.getUTCFullYear()+'-'+pad(local.getUTCMonth()+1)+
     '-'+pad(local.getUTCDate());
   if(weekStart(id)!==start)stop('step2-historical-week-boundary-invalid');
   starts.push(Object.freeze({id,start,end:start+WEEK_MS}));
 }
 return Object.freeze({weeks:Object.freeze(starts),
   olderWeeksNotScanned:total>MAX_WEEKS,totalCompletedWeeks:total});
}
function candidateIds(originalId,premium){
 if(!ORIG.test(originalId)||!premium||
    premium.status!=='STAGE71_74_PREMIUM_HISTORY_READONLY_HOLD'||
    !premium.stage71And74ServerSourcesScanned||
    !Array.isArray(premium.states)||
    premium.states.length>200)
   stop('step2-historical-owner-proof-incomplete');
 const seen=new Set([originalId]);
 for(const row of premium.states){
   if(!row||!ALIAS.test(row.identifier)||
      !['self-used-server-grant','gift-received-once',
        'gift-awaits-receipt'].includes(row.state)||
      seen.has(row.identifier))
     stop('step2-historical-premium-candidates-conflict');
   seen.add(row.identifier);
 }
 if(seen.size-1>MAX_ALIASES)stop('step2-historical-alias-scan-over-limit');
 return Object.freeze([...seen].sort());
}
async function inspectHistoricalWeeklyGiftReceipts({reader,originalId,premium,nowMs}){
 if(typeof reader?.get!=='function')
   stop('step2-historical-readonly-owner-required');
 const ids=candidateIds(originalId,premium);
 const {weeks,olderWeeksNotScanned,totalCompletedWeeks}=completedWeeks(nowMs);
 const seenWeeks=new Set(),rows=[];
 let pending=0,claimed=0,missing=0;
 for(const week of weeks){
   for(const alias of ids){
     const giftId='deda-weekly-'+week.id+'-'+alias.slice(1);
     const gift=await reader.get('deda_diamond_gifts/'+giftId);
     if(gift===null){missing++;continue;}
     const ms=gift?.createdAt?.toMillis?.();
     if(!gift||gift.giftId!==giftId||
        gift.sourceType!=='weekly_league'||
        gift.targetPublicId!==alias||
        !safe(gift.amount)||gift.amount===0||
        !['pending','claimed'].includes(gift.status)||
        !safe(ms)||ms<week.end||ms>nowMs)
       stop('step2-historical-weekly-receipt-conflict');
     // Multiple gifts for the same linked owner/week are a conflict to
     // adjudicate, not an invitation to redeem the difference.
     if(seenWeeks.has(week.id))
       stop('step2-historical-duplicate-weekly-owner-prize');
     seenWeeks.add(week.id);
     if(gift.status==='pending')pending++;else claimed++;
     rows.push(Object.freeze({weekId:week.id,
       giftId,publicIdAtReceipt:alias,amountObserved:gift.amount,
       status:gift.status==='pending'?'pending-do-not-credit-on-restore':
         'claimed-no-reissue'}));
   }
 }
 return Object.freeze({
   status:'HISTORICAL_WEEKLY_GIFTS_READONLY_HOLD',
   checkedClosedWeeks:weeks.length,
   completedWeeksSinceOrigin:totalCompletedWeeks,
   ownerIdentifierCandidates:ids.length,
   knownPendingGiftDocuments:pending,
   knownClaimedGiftDocuments:claimed,
   notFoundUnknownDocumentSlots:missing,
   historicalSourceRows:Object.freeze(rows),
   // No source-week score adjudication or fully attested legacy alias
   // transfer: even a valid gift doc is NOT a second wallet credit.
   allHistoricalPrizesRecovered:false,
   olderWeeksNotScanned,
   legacyPremiumAliasesUnverified:true,
   prizeSourceAndWalletReconciled:false,
   canCreateGift:false,canClaimGift:false,canCreditDiamonds:false,
   canReissueWeeklyPrize:false,canRestoreBalances:false,
   allowPhoneCutover:false,
 });
}
async function previewHistoricalWeeklyGifts({store,auth,idToken}){
 if(!store||typeof store.serverNowMs!=='function')
   stop('step2-historical-server-clock-required');
 return withLinkedOwnerReadSession({store,auth,idToken},async(reader,_account,owner)=>{
   const premium=await inspectOriginalPremiumHistory({
     reader,originalId:owner.originalId});
   // The authenticated server clock is a private adapter, NOT input from
   // the handset, its device clock or the game UI.
   const nowMs=store.serverNowMs();
   return inspectHistoricalWeeklyGiftReceipts({
     reader,originalId:owner.originalId,premium,nowMs});
 });
}
module.exports={completedWeeks,candidateIds,inspectHistoricalWeeklyGiftReceipts,
 previewHistoricalWeeklyGifts};
