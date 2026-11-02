'use strict';
// PRIVATE STEP2 / NOT_EXPORTED / READ-ONLY. Legacy 100340 source lineage.
// Local snapshots and observed wallets NEVER authorize money or phone cutover.
const crypto=require('node:crypto');
const ACCOUNT=/^[0-9]{10,16}$/;
const ORIGINAL=/^@DEDA-[A-Z0-9]{6}$/;
const CAPTURE=/^[A-Za-z0-9_-]{20,80}$/;
const PARTS=Object.freeze(['taskPoints','socialCoinsAndXp','earnedDiamonds']);
const FRAMES=Object.freeze(['FRAME_03','FRAME_05','FRAME_06','FRAME_07',
 'FRAME_08','FRAME_09','FRAME_10','FRAME_11','FRAME_12','FRAME_13',
 'FRAME_14','FRAME_15','FRAME_16']);
const stop=code=>{throw Object.assign(new Error(code),{code});};
const isMap=x=>x!==null&&typeof x==='object'&&!Array.isArray(x);
const nonnegative=x=>Number.isSafeInteger(x)&&x>=0;
const stamp=x=>isMap(x)&&Number.isSafeInteger(x.seconds)&&
 Number.isSafeInteger(x.nanoseconds)&&x.nanoseconds>=0&&x.nanoseconds<1000000000;
function hasDuplicateKeys(raw){
 const tokens=raw.match(/"(?:[^"\\]|\\.)*"|[{}\[\]:,]|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null/g)||[];
 const stack=[];
 for(let i=0;i<tokens.length;i++){
  if(tokens[i]==='{')stack.push(new Set());
  else if(tokens[i]==='[')stack.push(null);
  else if(tokens[i]==='}'||tokens[i]===']')stack.pop();
  else if(tokens[i].startsWith('"')&&tokens[i+1]===':'){
   const top=stack.at(-1),key=JSON.parse(tokens[i]);
   if(!(top instanceof Set))stop('step2-legacy-json-structure-conflict');
   if(top.has(key))return true;
   top.add(key);
  }
 }
 return false;
}
function parseOldPart(raw,name){
 if(raw===null)return 'not-captured-unknown';
 if(typeof raw!=='string'||Buffer.byteLength(raw,'utf8')>200000)
  stop('step2-legacy-progress-payload-invalid');
 let value;
 try{value=JSON.parse(raw);}catch(_){stop('step2-legacy-progress-json-invalid');}
 if(!isMap(value)||hasDuplicateKeys(raw))stop('step2-legacy-progress-json-conflict');
 if(name==='earnedDiamonds'&&value.balance!==undefined&&
    !nonnegative(value.balance))stop('step2-legacy-earned-diamonds-invalid');
 if(name==='socialCoinsAndXp'&&
   ((value.coins!==undefined&&!nonnegative(value.coins))||
    (value.xp!==undefined&&!nonnegative(value.xp))))
    stop('step2-legacy-social-amount-invalid');
 return 'captured-local-untrusted';
}
function inspectProgressCapture(raw,accountKey,originalUid,expectedCaptureId){
 if(raw===null)return Object.freeze({status:'no-original-phone-capture-unknown',
  parts:Object.freeze(Object.fromEntries(PARTS.map(p=>[p,'not-captured-unknown'])))});
 if(!isMap(raw)||raw.format!==1||raw.kind!=='legacy-local-evidence'||
   raw.accountKey!==accountKey||raw.sourceUid!==originalUid||
   raw.captureId!==expectedCaptureId||!CAPTURE.test(raw.captureId)||
   typeof raw.installId!=='string'||raw.installId.length<1||
   raw.installId.length>128||!stamp(raw.createdAt)||
   !isMap(raw.records)||Object.keys(raw.records).length!==PARTS.length||
   !PARTS.every(p=>Object.hasOwn(raw.records,p)))
  stop('step2-legacy-progress-owner-or-capture-conflict');
 const parts=Object.freeze(Object.fromEntries(PARTS.map(p=>
   [p,parseOldPart(raw.records[p],p)])));
 return Object.freeze({status:'captured-evidence-not-financial-authority',parts,
  allThreePresent:PARTS.every(p=>parts[p]==='captured-local-untrusted')});
}
function inspectPurchaseCapture(raw,accountKey,originalId,originalUid,expectedId,progressId,installId){
 if(raw===null)return Object.freeze({status:'old-purchase-journal-unknown',pending:null,paid:null,journalStates:null});
 if(!isMap(raw)||raw.format!==1||raw.kind!=='legacy-purchase-evidence'||
    raw.accountKey!==accountKey||raw.sourceUid!==originalUid||
    raw.captureId!==expectedId||!CAPTURE.test(expectedId)||
    raw.installId!==installId||!stamp(raw.createdAt)||!isMap(raw.records)||
    raw.records.originalId!==originalId||
    raw.records.progressCaptureId!==progressId||
    typeof raw.records.localSnapshot!=='string'||
    Buffer.byteLength(raw.records.localSnapshot,'utf8')>200000)
    stop('step2-legacy-purchase-owner-or-parent-conflict');
 const str=raw.records.localSnapshot;
 let snapshot;
 try{snapshot=JSON.parse(str);}catch(_){stop('step2-legacy-purchase-json-invalid');}
 if(hasDuplicateKeys(str)||!isMap(snapshot)||snapshot.format!==1||
    snapshot.accountKey!==accountKey||snapshot.originalId!==originalId||
    !isMap(snapshot.frameJournals)||
    Object.keys(snapshot.frameJournals).length!==FRAMES.length||
    !FRAMES.every(frame=>Object.hasOwn(snapshot.frameJournals,frame)))
    stop('step2-legacy-purchase-journal-conflict');
 let pending=0,paid=0;
 const journalStates={};
 for(const frame of FRAMES){
  const value=snapshot.frameJournals[frame];
  if(value==='charging'){pending++;journalStates[frame]='charging-recorded';}
  else if(value==='paid'){paid++;journalStates[frame]='paid-recorded';}
  else if(value===null)journalStates[frame]='not-recorded-on-original-phone';
  else stop('step2-legacy-purchase-journal-ambiguous');
 }
 if(snapshot.inventory!==null&&typeof snapshot.inventory!=='string'&&
    !Array.isArray(snapshot.inventory))stop('step2-legacy-inventory-invalid');
 return Object.freeze({status:'captured-purchase-journal-not-payment-proof',
  pending,paid,inventoryRecorded:snapshot.inventory!==null,journalStates:Object.freeze(journalStates)});
}

function inspectNativeFrameState(native,originalId){
 if(native===null)return Object.freeze({status:'native-row-unknown',
   pendingFrames:null,ownedFrames:null,unknownFrameIds:Object.freeze([])});
 if(!isMap(native)||native.originalId!==originalId)
   stop('step2-legacy-native-owner-conflict');
 function read(name){
  if(!Object.hasOwn(native,name))return null;
  const value=native[name];
  if(!Array.isArray(value)||value.some(x=>typeof x!=='string')||
     new Set(value).size!==value.length)
    stop('step2-legacy-native-frames-invalid');
  return Object.freeze([...value]);
 }
 const pendingFrames=read('pendingFrames'),ownedFrames=read('ownedFrames');
 const unknownFrameIds=Object.freeze(
   [...new Set([...(pendingFrames||[]),...(ownedFrames||[])])]
     .filter(frame=>!FRAMES.includes(frame)).sort());
 return Object.freeze({status:'native-account-row-untrusted',
   pendingFrames,ownedFrames,unknownFrameIds});
}
async function auditLegacyFrameCrossSources(reader,originalId,purchase){
 if(typeof reader?.get!=='function'||!ORIGINAL.test(originalId))
   stop('step2-legacy-frame-audit-scope');
 const native=inspectNativeFrameState(
   await reader.get('deda_native_account_cosmetics/'+originalId),originalId);
 const frameSources={},unverifiedLocalFrames=[],legacyChargingFrames=[];
 let verifiedServerPairs=0;
 for(const frame of FRAMES){
   const receipt=await reader.get('deda_lab_frame_receipts/'+originalId+'/frames/'+frame);
   const owned=await reader.get('deda_lab_owned_frames/'+originalId+'/frames/'+frame);
   if((receipt===null)!==(owned===null))
     stop('step2-legacy-frame-partial-server-pair');
   const pair=receipt!==null;
   if(pair){
    if(!isMap(receipt)||!isMap(owned)||receipt.kind!=='lab_frame'||
       receipt.publicId!==originalId||receipt.frameId!==frame||
       receipt.cost!==1000||owned.publicId!==originalId||
       owned.frameId!==frame||owned.receiptId!==originalId+'_'+frame)
      stop('step2-legacy-frame-mismatched-server-pair');
    verifiedServerPairs++;
   }
   const journal=purchase.journalStates?.[frame]??'old-phone-journal-unknown';
   const nativePending=native.pendingFrames?.includes(frame)??null;
   const nativeOwned=native.ownedFrames?.includes(frame)??null;
   const oldPending=journal==='charging-recorded'||nativePending===true;
   const oldRight=oldPending||journal==='paid-recorded'||nativeOwned===true;
   if(oldPending)legacyChargingFrames.push(frame);
   if(!pair&&oldRight)unverifiedLocalFrames.push(frame);
   const classification=pair
      ?(oldPending?'server-receipt-and-old-charge-pending-review':'server-pair-readonly-no-new-charge')
      :(oldRight?'old-local-right-without-server-pair-review':'missing-server-pair-unknown');
   frameSources[frame]=Object.freeze({classification,journal,nativePending,nativeOwned,
     pairConfirmed:pair,canCreditOrCharge:false});
 }
 return Object.freeze({status:'FRAME_SOURCE_CROSSCHECK_READONLY_HOLD',
   scannedFrames:FRAMES.length,verifiedServerPairs,
   nativeSource:native,frameSources:Object.freeze(frameSources),
   unverifiedLocalFrames:Object.freeze(unverifiedLocalFrames),
   legacyChargingFrames:Object.freeze(legacyChargingFrames),
   allPaidRightsRecovered:false,canGrantFrame:false,canChargeFrame:false,
   canRefundFrame:false,allowPhoneCutover:false});
}

/**
 * All server-side paths derive from verified original UID/account/ID, inside
 * a single read-only transaction. Archive selectors come from reviewed server
 * documents, not from the client. No code path credits or refunds anything.
 */
async function inspectLegacy340FinancialLineage({reader,accountKey,originalUid,originalId}){
 if(typeof reader?.get!=='function'||!ACCOUNT.test(accountKey)||
   !ORIGINAL.test(originalId)||typeof originalUid!=='string'||
   !/^[A-Za-z0-9_-]{1,128}$/.test(originalUid))
   stop('step2-legacy-owner-scope-unproven');
 const root='deda_progress_migrations/'+accountKey;
 const migration=await reader.get(root);
 let progress=Object.freeze({status:'migration-not-started-unknown'});
 let purchase=Object.freeze({status:'old-purchase-journal-unknown',pending:null,paid:null,journalStates:null});
 let phase='no-migration-record';
 if(migration!==null){
  if(!isMap(migration)||migration.accountKey!==accountKey||
    migration.format!==1||!CAPTURE.test(migration.migrationId)||
    !['pending','evidence-saved','baseline-approved','cutover-complete'].includes(migration.phase))
    stop('step2-legacy-migration-scope-conflict');
  phase=migration.phase;
  if(phase!=='pending'){
   if(!/^[a-f0-9]{64}$/.test(migration.evidenceDigest))
     stop('step2-legacy-review-digest-invalid');
   const review=await reader.get(root+'/reviews/'+migration.migrationId);
   if(!isMap(review)||review.accountKey!==accountKey||
      review.migrationId!==migration.migrationId||
      review.evidenceDigest!==migration.evidenceDigest||
      !CAPTURE.test(review.captureId))
      stop('step2-legacy-reviewed-source-not-proven');
   const raw=await reader.get('deda_progress_evidence/'+accountKey+'/captures/'+review.captureId);
   if(raw===null)stop('step2-legacy-reviewed-capture-vanished');
   progress=inspectProgressCapture(raw,accountKey,originalUid,review.captureId);
   const observedDigest=crypto.createHash('sha256').update(JSON.stringify([
     'untrusted-legacy-evidence-v1',accountKey,review.captureId,
     raw.sourceUid,raw.installId,[raw.createdAt.seconds,raw.createdAt.nanoseconds],
     ...PARTS.map(part=>raw.records[part]),
   ]),'utf8').digest('hex');
   if(observedDigest!==migration.evidenceDigest)
      stop('step2-legacy-capture-review-digest-conflict');
   if(phase==='baseline-approved'||phase==='cutover-complete'){
    if(!CAPTURE.test(migration.settlementId)){
     if(phase==='cutover-complete'||migration.settlementId!==null)
       stop('step2-legacy-settlement-id-conflict');
    }else{
     const settled=await reader.get(root+'/settlementReviews/'+migration.settlementId);
     if(settled!==null){
      if(!isMap(settled)||settled.accountKey!==accountKey||
        settled.migrationId!==migration.migrationId||
        settled.originalId!==originalId||settled.evidenceDigest!==migration.evidenceDigest||
        !CAPTURE.test(settled.purchaseCaptureId))
        stop('step2-legacy-settlement-cross-account-conflict');
      const rawPurchase=await reader.get('deda_purchase_evidence/'+accountKey+
        '/captures/'+settled.purchaseCaptureId);
      purchase=inspectPurchaseCapture(rawPurchase,accountKey,originalId,originalUid,
        settled.purchaseCaptureId,review.captureId,raw.installId);
      if(rawPurchase===null)stop('step2-legacy-settlement-purchase-capture-vanished');
     }else if(phase==='cutover-complete'){
      stop('step2-legacy-completed-settlement-review-missing');
     }
    }
   }
  }
 }
 const observedGift=await reader.get('deda_diamond_gift_balances/'+originalId);
 let giftWallet='not-found-unknown-not-zero';
 if(observedGift!==null){
  if(!isMap(observedGift)||observedGift.publicId!==originalId||
      !nonnegative(observedGift.balance))
      stop('step2-legacy-gift-wallet-owner-or-amount-conflict');
  giftWallet='independent-gift-wallet-observed-no-double-credit';
 }
 const frameCrosscheck=await auditLegacyFrameCrossSources(reader,originalId,purchase);
 const state=await reader.get('deda_verified_progress/'+accountKey);
 if(state!==null&&phase!=='cutover-complete')
  stop('step2-legacy-premature-verified-state-conflict');
 if(state===null&&phase==='cutover-complete')
  stop('step2-legacy-completed-verified-state-missing');
 return Object.freeze({status:'LEGACY_100340_FINANCIAL_LINEAGE_READONLY_HOLD',
   migrationPhase:phase,progressSource:progress,purchaseSource:purchase,
   giftWalletSource:giftWallet,frameCrosscheck,verifiedProgressDocumentObserved:state!==null,
   sourceReviewAndLegacyWriterFenceProven:false,
   allHistoricalSpendsAndRefundsReconciled:false,
   allTwentyThreeDomainsRestored:false,
   canMergeOldDeviceWallet:false,canCreditDiamonds:false,
   canRestoreXpOrPoints:false,canChargeOrRefundFrame:false,
   canReissueGiftOrPrize:false,allowPhoneCutover:false});
}
async function previewLegacy340FinancialLineage({store,auth,idToken}){
 const {withLinkedOwnerReadSession}=
   require('./deda_step2_linked_owner_read_session_NOT_EXPORTED.js');
 return withLinkedOwnerReadSession({store,auth,idToken},
   (reader,key,owner)=>inspectLegacy340FinancialLineage({reader,
      accountKey:key,originalUid:owner.uid,originalId:owner.originalId}));
}
module.exports={inspectProgressCapture,inspectPurchaseCapture,inspectNativeFrameState,
 auditLegacyFrameCrossSources,inspectLegacy340FinancialLineage,previewLegacy340FinancialLineage};
