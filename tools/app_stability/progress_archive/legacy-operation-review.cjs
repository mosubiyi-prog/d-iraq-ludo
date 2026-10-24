'use strict';
// INTERNAL, UNDEPLOYED. Inventory/review only: never charges, refunds, clears
// pendingFrames, changes ownership, or marks a migration settled.
const {createHash}=require('node:crypto');
const {isDeepStrictEqual}=require('node:util');
const {account}=require('./reconcile-core.cjs');
const {parseMigration}=require('./migration-gate.cjs');
const {loadReviewedEvidence}=require('./baseline-evidence.cjs');
const {frames}=require('./purchase-frames.cjs');
const {assessPurchaseEvidence}=require('./purchase-evidence.cjs');
const thresholds=Object.freeze([5000,10000,15000,20000,25000]);
function fail(code){throw Object.assign(new Error(code),{code});}
function stable(value){
 if(value===null||typeof value!=='object')return value;
 if(typeof value.toDate==='function'&&Number.isSafeInteger(value.seconds)&&Number.isSafeInteger(value.nanoseconds))return {firestoreTimestamp:[value.seconds,value.nanoseconds]};
 if(Array.isArray(value))return value.map(stable);
 return Object.fromEntries(Object.keys(value).sort().map(key=>[key,stable(value[key])]));
}
function digest(value){return createHash('sha256').update(JSON.stringify(stable(value))).digest('hex');}
function pointTierObservations(raw,assessment){
 const issues=new Set(),tiers=[];
 if(assessment.observedBalances.points===null||assessment.issues.some(v=>['taskPoints:duplicate-json-key','taskPoints:unsupported-version','taskPoints:invalid-awards','taskPoints:invalid-amount'].includes(v)))
 return {tiers:[],observedUnclaimedReturns:null,issues:['point-tier-evidence-unreadable']};
 const awards=JSON.parse(raw.records.taskPoints).awards;
 if(Object.hasOwn(awards,'point_tier|5000'))issues.add('legacy-stage-one-entry-requires-review');
 for(const key of Object.keys(awards))if(key.startsWith('point_tier_')&&!thresholds.some(t=>key===`point_tier_reserve|${t}`||key===`point_tier_claim|${t}`))issues.add('unknown-point-tier-entry');
 let observedUnclaimedReturns=0;
 for(const threshold of thresholds){
  const reserveKey=`point_tier_reserve|${threshold}`,claimKey=`point_tier_claim|${threshold}`;
  const hasReserve=Object.hasOwn(awards,reserveKey),hasClaim=Object.hasOwn(awards,claimKey);
  const reserve=hasReserve?awards[reserveKey]:null,claim=hasClaim?awards[claimKey]:null;
  const bonus=threshold/100;
  let status=!hasReserve&&!hasClaim?'not-observed':hasClaim?'returned-in-raw-balance':threshold===25000?'terminal-prize-reserve':'unclaimed-return';
  const valid=(v,key,amount,type)=>v&&typeof v==='object'&&!Array.isArray(v)&&v.points===amount&&
   (v.id===undefined||v.id===key)&&(v.type===undefined||v.type===type)&&
   (v.threshold===undefined||v.threshold===threshold)&&(v.reservedPoints===undefined||v.reservedPoints===threshold)&&
   (v.bonusPoints===undefined||v.bonusPoints===bonus);
  if((hasReserve&&!valid(reserve,reserveKey,-threshold,'point_tier_reserve'))||
   (hasClaim&&!valid(claim,claimKey,threshold+bonus,'point_tier_claim'))||(hasClaim&&!hasReserve)){
   status='requires-review';issues.add(`point-tier-${threshold}:invalid-pair`);
  }
  if(hasClaim&&threshold===25000){status='requires-review';issues.add('obsolete-final-claim-preserved-needs-review');}
  const previous=thresholds[thresholds.indexOf(threshold)-1];
  if((hasReserve||hasClaim)&&previous&&!Object.hasOwn(awards,`point_tier_claim|${previous}`)){
   status='requires-review';issues.add(`point-tier-${threshold}:previous-claim-missing`);
  }
  if(status==='unclaimed-return')observedUnclaimedReturns++;
  tiers.push({threshold,bonus:threshold===25000?0:bonus,reserveKey,claimKey,hasReserve,hasClaim,
   recordedReservePoints:hasReserve?reserve?.points??null:null,recordedClaimPoints:hasClaim?claim?.points??null:null,
   status,canAutoRefund:false});
 }
 if(issues.size)observedUnclaimedReturns=null;
 return {tiers,observedUnclaimedReturns,issues:[...issues].sort()};
}
async function saveLegacyOperationReview(options){
 const keys=['store','accountKey','migrationId','originalId'];
 if(!options||![keys.length,keys.length+1].includes(Object.keys(options).length)||!keys.every(k=>Object.hasOwn(options,k))||
 Object.keys(options).some(k=>!keys.includes(k)&&k!=='purchaseCaptureId'))fail('invalid-operation-review-request');
 const {store,accountKey,migrationId,originalId,purchaseCaptureId}=options;
 if(Object.hasOwn(options,'purchaseCaptureId')&&(typeof purchaseCaptureId!=='string'||!/^[A-Za-z0-9_-]{20,80}$/.test(purchaseCaptureId)))fail('invalid-purchase-capture-id');
 account(accountKey);
 if(!store||typeof store.runTransaction!=='function'||typeof store.serverTimestamp!=='function')fail('invalid-operation-review-store');
 if(typeof originalId!=='string'||!/^@DEDA-[A-Z0-9]{6}$/.test(originalId))fail('canonical-original-required');
 if(typeof migrationId!=='string'||!/^[A-Za-z0-9_-]{20,80}$/.test(migrationId))fail('invalid-migration-id');
 return store.runTransaction(async tx=>{
  const root=`deda_progress_migrations/${accountKey}`;
  const migration=parseMigration(await tx.get(root),accountKey);
  if(migration.migrationId!==migrationId||migration.phase==='pending')fail('operation-review-evidence-required');
  const {raw,assessment}=await loadReviewedEvidence(tx,migration);
  if(!/^[A-Za-z0-9_-]{1,128}$/.test(raw.sourceUid))fail('operation-review-owner-not-proven');
  const profile=await tx.get(`users/${raw.sourceUid}`),route=await tx.get(`deda_share_ids/${originalId}`);
  if(!profile||profile.accountKey!==accountKey||profile.sharePersonalId!==originalId||
   !route||route.publicId!==originalId||route.kind!=='personal'||route.active!==true||
   typeof route.ownerUid!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(route.ownerUid))fail('operation-review-owner-not-proven');
  const routeOwner=await tx.get(`users/${route.ownerUid}`);
  if(!routeOwner||routeOwner.accountKey!==accountKey||
   (routeOwner.sharePersonalId!=null&&routeOwner.sharePersonalId!==originalId))fail('operation-review-owner-not-proven');
  let purchaseRaw=null,purchaseJournalEvidence=null;
  if(purchaseCaptureId!==undefined){
   purchaseRaw=await tx.get(`deda_purchase_evidence/${accountKey}/captures/${purchaseCaptureId}`);
   purchaseJournalEvidence=assessPurchaseEvidence(purchaseRaw,{accountKey,captureId:purchaseCaptureId,originalId,
    progressCaptureId:assessment.captureId,sourceUid:raw.sourceUid,installId:raw.installId});
  }
  const native=await tx.get(`deda_native_account_cosmetics/${originalId}`);
  if(native!==null&&native.originalId!==originalId)fail('operation-review-cosmetic-owner-conflict');
  const issues=new Set(['legacy-writer-fence-not-established','style-checkout-has-no-atomic-payment-inventory-proof']);
  issues.add(purchaseJournalEvidence===null?'local-native-payment-journal-not-captured':'local-payment-journal-not-server-attested');
  const list=field=>{
   if(native===null||!Object.hasOwn(native,field)){issues.add(`native-${field}:not-recorded`);return null;}
   const values=native[field];
   if(!Array.isArray(values)||values.some(v=>typeof v!=='string')||new Set(values).size!==values.length){issues.add(`native-${field}:invalid`);return null;}
   if(values.some(v=>!frames.includes(v)))issues.add(`native-${field}:unknown-frame-preserved`);
   return values;
  };
  const pending=list('pendingFrames'),owned=list('ownedFrames');
  const receiptInputs=[],frameObservations=[];
  for(const frameId of frames){
   const receipt=await tx.get(`deda_lab_frame_receipts/${originalId}/frames/${frameId}`);
   const ownership=await tx.get(`deda_lab_owned_frames/${originalId}/frames/${frameId}`);
   receiptInputs.push({frameId,receipt,ownership});
   const confirmed=receipt!==null&&ownership!==null&&receipt.kind==='lab_frame'&&receipt.publicId===originalId&&
    receipt.frameId===frameId&&receipt.cost===1000&&ownership.publicId===originalId&&ownership.frameId===frameId&&
    ownership.receiptId===`${originalId}_${frameId}`;
   if(!confirmed&&(receipt!==null||ownership!==null))issues.add(`frame-${frameId}:partial-or-invalid-receipt-pair`);
   frameObservations.push({frameId,localJournal:purchaseJournalEvidence===null?{state:'not-captured',valueType:null}:purchaseJournalEvidence.journals[frameId],receiptConfirmed:confirmed,nativePending:pending===null?null:pending.includes(frameId),
    nativeOwned:owned===null?null:owned.includes(frameId),
    disposition:confirmed?'ownership-confirmed-payment-review-still-required':'payment-not-proven',canAutoCharge:false,canAutoRefund:false});
  }
  const pointTiers=pointTierObservations(raw,assessment);
  for(const issue of pointTiers.issues)issues.add(issue);
  const inputDigest=digest({accountKey,migrationId,originalId,evidenceDigest:assessment.evidenceDigest,profile,route,routeOwner,native,receiptInputs,purchaseRaw});
  const report={format:1,accountKey,migrationId,originalId,evidenceDigest:assessment.evidenceDigest,inputDigest,
   status:'requires-operation-review',canAutoSettle:false,canReleaseBalance:false,
   purchaseJournalEvidence,pendingPurchases:'unknown',nativePendingFrames:pending,nativeOwnedFrames:owned,
   nativeSnapshot:native,frames:frameObservations,pointTiers,issues:[...issues].sort()};
  const path=`${root}/operationReviews/${inputDigest}`,stored=await tx.get(path);
  if(stored!==null){
   if(stored.createdAt==null||Object.keys(stored).length!==Object.keys(report).length+1||
    !Object.keys(report).every(k=>Object.hasOwn(stored,k)&&isDeepStrictEqual(stored[k],report[k])))fail('operation-review-conflict');
   return Object.freeze({replayed:true,path,report});
  }
  tx.set(path,{...report,createdAt:store.serverTimestamp()});
  return Object.freeze({replayed:false,path,report});
 });
}
module.exports={saveLegacyOperationReview,pointTierObservations,frames};
