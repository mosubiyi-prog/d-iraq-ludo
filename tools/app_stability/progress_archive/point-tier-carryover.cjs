'use strict';
// INTERNAL, UNDEPLOYED derived carryover after a protected manual review.
// Writes private candidate entitlements only. No wallet, refund, new reward,
// public API, settlement counter, verified receipt or cutover is produced.
const {createHash}=require('node:crypto');
const {isDeepStrictEqual}=require('node:util');
const core=require('./reconcile-core.cjs');
const {parseMigration}=require('./migration-gate.cjs');
const {loadReviewedEvidence}=require('./baseline-evidence.cjs');
const {parsePolicy,policyPath}=require('./baseline-review.cjs');
const {pointTierObservations}=require('./legacy-operation-review.cjs');
function fail(code){throw Object.assign(new Error(code),{code});}
function exact(value,keys,code){if(!value||typeof value!=='object'||Array.isArray(value)||
 Object.keys(value).length!==keys.length||!keys.every(k=>Object.hasOwn(value,k)))fail(code);}
function time(value){
 if(!value||!Number.isSafeInteger(value.seconds)||!Number.isSafeInteger(value.nanoseconds)||
 value.nanoseconds<0||value.nanoseconds>=1000000000)fail('point-carryover-invalid-approval-time');
 return [value.seconds,value.nanoseconds];
}
function sameStored(stored,expected){
 return stored!==null&&stored.createdAt!=null&&Object.keys(stored).length===Object.keys(expected).length+1&&
 Object.keys(expected).every(k=>Object.hasOwn(stored,k)&&isDeepStrictEqual(stored[k],expected[k]));
}
async function savePointTierCarryover(options){
 exact(options,['store','accountKey','migrationId'],'invalid-point-carryover-request');
 const {store,accountKey,migrationId}=options;core.account(accountKey);
 if(typeof migrationId!=='string'||!/^[A-Za-z0-9_-]{20,80}$/.test(migrationId))fail('invalid-point-carryover-migration');
 if(!store||typeof store.runTransaction!=='function'||typeof store.serverTimestamp!=='function')fail('invalid-point-carryover-store');
 return store.runTransaction(async tx=>{
  const root=`deda_progress_migrations/${accountKey}`;
  const migration=parseMigration(await tx.get(root),accountKey);
  if(migration.migrationId!==migrationId||migration.phase!=='baseline-approved')fail('point-carryover-reviewed-baseline-required');
  const {raw,assessment}=await loadReviewedEvidence(tx,migration);
  const approval=await tx.get(`${root}/approvals/${migrationId}`);
  exact(approval,['format','accountKey','migrationId','evidenceDigest','policyRevision','decisionBasis',
   'reviewerUid','reviewerEmail','baselineEventKey','receipt','status','canReleaseBalance','createdAt'],'point-carryover-approval-required');
  if(approval.format!==1||approval.accountKey!==accountKey||approval.migrationId!==migrationId||
   approval.evidenceDigest!==migration.evidenceDigest||approval.baselineEventKey!==migration.baselineEventKey||
   approval.decisionBasis!=='owner-reviewed-grandfathering'||approval.status!=='approved-awaiting-settlement'||
   approval.canReleaseBalance!==false||typeof approval.reviewerUid!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(approval.reviewerUid)||
   typeof approval.reviewerEmail!=='string')fail('point-carryover-approval-conflict');
  const approvedAt=time(approval.createdAt);
  const receipt=core.parseReceipt(approval.receipt,accountKey);
  if(receipt.source!=='legacy-baseline-v1'||receipt.sourceId!==`legacy-review|${migrationId}|${migration.evidenceDigest}`||
   core.eventKey(receipt)!==migration.baselineEventKey||!isDeepStrictEqual(receipt.delta,assessment.observedBalances))fail('point-carryover-baseline-conflict');
  const policy=parsePolicy(await tx.get(policyPath),approval.policyRevision);
  if(assessment.issues.some(issue=>!policy.acceptedIssues.includes(issue)))fail('point-carryover-unaccepted-issues');
  // Worker consumes the protected prior approval, not a new user token. The
  // current role/policy are rechecked in this transaction; this is not an API
  // authorization or fresh SDK revocation check for the historical reviewer.
  const reviewer=await tx.get(`admins/${approval.reviewerUid}`);
  if(!reviewer||reviewer.active!==true||reviewer.status!=='active'||reviewer.role!=='general_manager'||
   reviewer.mustChangePassword===true||typeof reviewer.email!=='string'||
   reviewer.email.trim().toLowerCase()!==approval.reviewerEmail)fail('point-carryover-reviewer-inactive');
  const plan=pointTierObservations(raw,assessment);
  if(plan.issues.length||plan.observedUnclaimedReturns===null)fail('point-carryover-history-needs-review');
  if(await tx.get(`deda_verified_progress/${accountKey}`)!==null)fail('point-carryover-already-activated');
  const basisDigest=createHash('sha256').update(JSON.stringify(['point-tier-carryover-v1',accountKey,migrationId,
   migration.evidenceDigest,migration.baselineEventKey,approval.policyRevision,approval.reviewerUid,
   approval.reviewerEmail,approvedAt,receipt.sourceId,core.units.map(k=>receipt.delta[k]),plan.tiers])).digest('hex');
  const common={format:1,accountKey,migrationId,evidenceDigest:migration.evidenceDigest,
   baselineEventKey:migration.baselineEventKey,policyRevision:approval.policyRevision,basisDigest};
  const records=plan.tiers.map(tier=>({...common,threshold:tier.threshold,
   sourceReserveKey:tier.reserveKey,sourceClaimKey:tier.claimKey,
   recordedReservePoints:tier.recordedReservePoints,recordedClaimPoints:tier.recordedClaimPoints,
   status:tier.status==='unclaimed-return'?'reserved-awaiting-cutover':
    tier.status==='returned-in-raw-balance'?'claimed-in-baseline':
    tier.status==='terminal-prize-reserve'?'terminal-prize-spent':'not-observed',
   futureReturnPoints:tier.status==='unclaimed-return'?tier.threshold+tier.bonus:null,
   canClaimNow:false,canRefundNow:false}));
  const summary={...common,status:'carried-awaiting-cutover',stageCount:5,
   observedUnclaimedReturns:plan.observedUnclaimedReturns,
   terminalPrizeReserved:plan.tiers.some(t=>t.status==='terminal-prize-reserve'),
   canReleaseBalance:false,canAutoSettle:false};
  const summaryPath=`${root}/pointTierCarryovers/${migrationId}`;
  const stored=await tx.get(summaryPath),oldStages=[];
  for(const stage of records)oldStages.push(await tx.get(`${root}/pointTierEntitlements/${stage.threshold}`));
  if(stored!==null){
   if(!sameStored(stored,summary)||oldStages.some((stage,i)=>!sameStored(stage,records[i])||
    !isDeepStrictEqual(time(stage.createdAt),time(stored.createdAt))))fail('point-carryover-conflict');
   return Object.freeze({replayed:true,path:summaryPath,summary});
  }
  if(oldStages.some(stage=>stage!==null))fail('point-carryover-conflict');
  const createdAt=store.serverTimestamp();
  for(const stage of records)tx.set(`${root}/pointTierEntitlements/${stage.threshold}`,{...stage,createdAt});
  tx.set(summaryPath,{...summary,createdAt});
  return Object.freeze({replayed:false,path:summaryPath,summary});
 });
}
module.exports={savePointTierCarryover};
