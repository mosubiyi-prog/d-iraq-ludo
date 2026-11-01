'use strict';
// DEDA 100429: one-transaction, READ-ONLY, reviewed-state recovery preview.
// This only composes EXISTING verified progress, owner session, canonical
// original, received-gift and GM wallet sources. NO CLIENT CALLABLE and NO
// migration or release of legacy balances or daily/quiz rewards.
const {withVerifiedOwnerSession}=require('../tools/app_stability/progress_archive/point-tier-session.cjs');
const {loadMigratedContext}=require('../tools/app_stability/progress_archive/migration-gate.cjs');
const {requireReviewedActivation}=require('../tools/app_stability/progress_archive/reviewed-activation-proof.cjs');
const safe=v=>Number.isSafeInteger(v)&&v>=0;
const orig=v=>typeof v==='string'&&/^@DEDA-[A-Z0-9]{6}$/.test(v);
const week=v=>typeof v==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(v);
const VALID_DAILY_TASKS=new Set(["share_personal_location","open_map",
 "share_registered_place","open_saved_place","open_received_place",
 "review_added_place","traffic_skills","long_trip"]);
function isWeeklyTaskKey(key,weekId){
 if(typeof key!=="string"||key.length>120)return false;
 const parts=key.split("|");
 if(parts.length!==2||!week(parts[0])||
    !VALID_DAILY_TASKS.has(parts[1]))return false;
 const actual=Date.parse(parts[0]+"T00:00:00Z");
 const start=Date.parse(weekId+"T00:00:00Z");
 return Number.isFinite(actual)&&Number.isFinite(start)&&
   new Date(actual).toISOString().startsWith(parts[0]) &&
   new Date(start).toISOString().startsWith(weekId) &&
   actual>=start && actual-start<7*86400000;
}
function stop(code='progress-recovery-hold'){throw Object.assign(new Error(code),{code});}
function add(a,b){if(!safe(a)||!safe(b)||!safe(a+b))stop('progress-overflow');return a+b;}
function ownerRoute(user,route,oldUser,accountKey,originalId,uid){
  if(!user||user.accountKey!==accountKey||
     user.sharePersonalId!==originalId||
     !route||route.kind!=='personal'||route.active!==true||
     route.publicId!==originalId||
     typeof route.ownerUid!=='string'||route.ownerUid.length===0||
     !oldUser||oldUser.accountKey!==accountKey||
     oldUser.sharePersonalId!==originalId)stop('progress-original-owner-mismatch');
  return uid;
}
function walletSources(state,gift,gm,gateway,accountKey,originalId){
 const earned=state.balances.earnedDiamonds;
 if(!safe(earned))stop('progress-earned-source-corrupt');
 // Absent gift wallet does NOT mean zero unless separate vetted review says so.
 let gifted=null;
 if(gift!==null){
   if(gift.publicId!==originalId||!safe(gift.balance))stop('progress-gift-source-conflict');
   gifted=gift.balance;
 }
 const isManager=gateway!==null &&
   gateway.accountKey===accountKey&&gateway.active===true&&
   gateway.status==='active'&&gateway.accessType==='general_manager_gateway'&&
   gateway.allowedRole==='general_manager';
 let manager=null;
 if(isManager){
   if(!gm||gm.accountKey!==accountKey||gm.initialBalance!==1000000||
      !safe(gm.balance))stop('progress-manager-wallet-conflict');
   manager=gm.balance;
 }
 // Never collapse missing gift source to zero, or combine GM personal wallet
 // with the separate admin grant pool. Spendable policy is deliberately
 // different from DISPLAY policy in the existing purchase implementation.
 const ordinary=gifted===null?null:add(earned,gifted);
 const visible=ordinary===null?null:add(ordinary,manager??0);
 const purchase=manager??ordinary;
 return Object.freeze({earned,gifted,manager,ordinary,visible,purchase,
   allDiamondSourcesVerified:gifted!==null,
   sourceLabels:Object.freeze(['earned-reviewed-progress','received-gift-balance',
     ...(isManager?['general-manager-personal-wallet']:[])])});
}
function weeklyReceipt(existing,originalId,weekId){
 if(existing===null)return Object.freeze({status:'not-confirmed',claimCount:null,weeklyXp:null});
 const keys=existing.claimedKeys;
 if(existing.publicId!==originalId||existing.weekId!==weekId||
    !Array.isArray(keys)||keys.length>56||
    keys.some(k=>!isWeeklyTaskKey(k,weekId))||
    new Set(keys).size!==keys.length||
    !safe(existing.completedTasks)||!safe(existing.weeklyXp)||
    existing.completedTasks!==keys.length||existing.weeklyXp!==20*keys.length)
    stop('progress-weekly-receipt-conflict');
 return Object.freeze({status:'read-only-verified-week-claims',
   claimCount:keys.length,weeklyXp:existing.weeklyXp});
}
/**
 * CALLER CONTRACT: idToken is freshly checked by Firebase Admin SDK in the
 * existing withVerifiedOwnerSession adapter, including revocation, on every
 * transaction attempt. weekId must be provided by a trusted backend clock,
 * never client-submitted. Existing actual settlement and enforced-fence
 * readers make missing financial cutover fail CLOSED.
 */
async function readReviewedStep2Snapshot({store,auth,idToken,weekId}){
 if(!week(weekId)||!store||!auth||typeof idToken!=='string'||!idToken)
   stop('progress-recovery-invalid-input');
 return withVerifiedOwnerSession({store,auth,idToken},
   async(tx,accountKey,actor)=>{
     const context=await loadMigratedContext(tx,accountKey);
     const activation=await requireReviewedActivation(tx,context);
     const fence=await tx.get(`${context.root}/fences/${activation.legacyFenceId}`);
     const originalId=fence?.originalId;
     if(!orig(originalId))stop('progress-canonical-original-required');
     const user=await tx.get(`users/${actor.uid}`);
     const route=await tx.get(`deda_share_ids/${originalId}`);
     const oldUser=route?.ownerUid?await tx.get(`users/${route.ownerUid}`):null;
     ownerRoute(user,route,oldUser,accountKey,originalId,actor.uid);
     const state=context.state;
     if(!safe(state.version)||state.version<1||
       !['points','coins','xp','earnedDiamonds']
        .every(k=>safe(state.balances[k])))stop('progress-verified-state-missing');
     const gift=await tx.get(`deda_diamond_gift_balances/${originalId}`);
     const gateway=await tx.get(`admin_entry_access/${accountKey}`);
     const gm=await tx.get(`deda_gm_personal_diamond_wallets/${accountKey}`);
     const diamonds=walletSources(state,gift,gm,gateway,accountKey,originalId);
     const existing=await tx.get(`deda_weekly_direct_weeks/${weekId}/scores/${originalId}`);
     const weekly=weeklyReceipt(existing,originalId,weekId);
     return Object.freeze({
       status:'REVIEWED_PROGRESS_READONLY',
       version:state.version,originalId,points:state.balances.points,
       coins:state.balances.coins,xp:state.balances.xp,
       // A historical local level is NOT proven by a verified XP projection
       // alone. Actual level display must use confirmed original level policy.
       level:null,levelStatus:'needs-canonical-level-policy-readback',
       diamonds,
       dailyTasks:Object.freeze({
         status:'full-daily-history-not-server-attested',
         currentWeekVerifiedClaimCount:weekly.claimCount,
         // NEVER turn existing weekly score into newly claimable level XP.
         canAwardOnRestore:false,
       }),
       trafficQuiz:Object.freeze({
         status:'historical-question-answers-local-only-not-backed-up',
         canAwardOnRestore:false,
       }),
       currentWeek:weekly,
       canWritePrefs:false,canMigrate:false,
       canCreditDiamonds:false,canCreditPoints:false,
       canRepeatOldRewards:false,canReapplyDebits:false,
     });
   });
}
module.exports={readReviewedStep2Snapshot,walletSources,weeklyReceipt};
