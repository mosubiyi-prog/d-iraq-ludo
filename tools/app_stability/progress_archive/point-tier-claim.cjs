'use strict';
// INTERNAL, UNDEPLOYED trusted worker. No public/callable API or client auth
// facade. A future server entry MUST independently prove the requested account.
// Not a cutover/fence producer: live use is blocked until those are implemented.
const {isDeepStrictEqual}=require('node:util');
const core=require('./reconcile-core.cjs');
const {loadMigratedContext}=require('./migration-gate.cjs');
const {time}=require('./point-tier-carryover-proof.cjs');
function fail(code){throw Object.assign(new Error(code),{code});}
function sameFields(raw,expected){return raw&&typeof raw==='object'&&!Array.isArray(raw)&&
 Object.keys(raw).length===Object.keys(expected).length&&
 Object.keys(expected).every(k=>Object.hasOwn(raw,k)&&isDeepStrictEqual(raw[k],expected[k]));}
function sameReceipt(raw,receipt){
 try{return raw!==null&&core.sameEvent(core.parseReceipt(raw,receipt.accountKey),receipt);}
 catch{return false;}
}
async function claimMigratedPointTier(options){
 if(!options||typeof options!=='object'||Array.isArray(options)||Object.keys(options).length!==3||
 !['store','accountKey','threshold'].every(k=>Object.hasOwn(options,k)))fail('invalid-point-tier-claim-request');
 const {store,accountKey,threshold}=options;core.account(accountKey);
 if(![5000,10000,15000,20000].includes(threshold))fail('point-tier-return-ineligible');
 if(!store||typeof store.runTransaction!=='function'||typeof store.serverTimestamp!=='function')fail('invalid-point-tier-claim-store');
 return store.runTransaction(async tx=>{
  // Re-read all cutover, settlement, baseline, archive, approval and immutable
  // stage proof on every attempt. No cached proof or current UID forms the key.
  const {root,migration,state,carryover}=await loadMigratedContext(tx,accountKey);
  const stage=carryover?.records.find(record=>record.threshold===threshold);
  if(!stage||stage.status!=='reserved-awaiting-cutover'||stage.futureReturnPoints!==threshold+threshold/100)
   fail('point-tier-return-ineligible');
  const receipt=core.parseReceipt({format:1,accountKey,source:'point-tier-return-v1',
   sourceId:`${migration.migrationId}|${threshold}|${stage.basisDigest}`,kind:'award',
   delta:{points:stage.futureReturnPoints,coins:0,xp:0,earnedDiamonds:0}},accountKey);
  const key=core.eventKey(receipt),receiptPath=`deda_progress_receipts/${accountKey}/events/${key}`;
  const eventPath=`deda_verified_progress/${accountKey}/events/${key}`;
  const claimPath=`${root}/pointTierClaims/${threshold}`,classificationPath=`${root}/classifications/${key}`;
  const oldClaim=await tx.get(claimPath),oldReceipt=await tx.get(receiptPath);
  const oldEvent=await tx.get(eventPath),oldClassification=await tx.get(classificationPath);
  const classification={format:1,accountKey,migrationId:migration.migrationId,
   evidenceDigest:migration.evidenceDigest,disposition:'after-cutover',receipt};
  const claim={format:1,accountKey,migrationId:migration.migrationId,evidenceDigest:migration.evidenceDigest,
   baselineEventKey:migration.baselineEventKey,basisDigest:stage.basisDigest,threshold,
   returnedPoints:stage.futureReturnPoints,eventKey:key,receiptId:key,status:'claimed'};
  if(oldClaim!==null){
   if(!Number.isSafeInteger(oldClaim.appliedVersion)||oldClaim.appliedVersion<2||oldClaim.appliedVersion>state.version||
    !sameFields(oldClaim,{...claim,appliedVersion:oldClaim.appliedVersion,createdAt:oldClaim.createdAt})||
    !sameReceipt(oldReceipt,receipt)||!sameFields(oldClassification,classification)||!oldEvent||
    oldEvent.format!==1||oldEvent.accountKey!==accountKey||oldEvent.eventKey!==key||oldEvent.receiptId!==key||
    oldEvent.appliedVersion!==oldClaim.appliedVersion||!sameReceipt(oldEvent.receipt??null,receipt)||
    !isDeepStrictEqual(time(oldClaim.createdAt),time(oldEvent.createdAt)))fail('point-tier-claim-conflict');
   // The immutable claim is the once-only marker; return CURRENT balances,
   // never its historic after-balance after later spending or other awards.
   return Object.freeze({replayed:true,threshold,returnedPoints:claim.returnedPoints,eventKey:key,state});
  }
  // Partial history is an error, never justification for another award or
  // overwriting a protected receipt/marker/classification from another worker.
  if(oldReceipt!==null||oldEvent!==null||oldClassification!==null)fail('point-tier-claim-conflict');
  const next=core.applyEvent(state,receipt),createdAt=store.serverTimestamp();
  tx.set(receiptPath,{...receipt});
  tx.set(classificationPath,{...classification});
  tx.set(eventPath,{format:1,accountKey,eventKey:key,receipt,receiptId:key,appliedVersion:next.version,
   afterBalances:next.balances,createdAt});
  tx.set(`deda_verified_progress/${accountKey}`,{...next});
  tx.set(claimPath,{...claim,appliedVersion:next.version,createdAt});
  return Object.freeze({replayed:false,threshold,returnedPoints:claim.returnedPoints,eventKey:key,state:next});
 });
}
module.exports={claimMigratedPointTier};
