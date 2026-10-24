'use strict';
// Historical immutable carryover proof. Current reviewer/policy checks belong
// to the producer; later awards must not depend on a former manager's role.
const {createHash}=require('node:crypto');
const {isDeepStrictEqual}=require('node:util');
const core=require('./reconcile-core.cjs');
const {pointTierObservations}=require('./point-tier-history.cjs');
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
function buildPointTierCarryover(migration,raw,assessment,approval){
 const {accountKey,migrationId}=migration;
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
  if(typeof approval.policyRevision!=='string'||!/^[A-Za-z0-9_-]{20,80}$/.test(approval.policyRevision))fail('point-carryover-approval-conflict');
  const plan=pointTierObservations(raw,assessment);
  if(plan.issues.length||plan.observedUnclaimedReturns===null)fail('point-carryover-history-needs-review');
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
 return {records,summary};
}
async function validatePointTierCarryover(tx,migration,raw,assessment){
 const root=`deda_progress_migrations/${migration.accountKey}`;
 const plan=pointTierObservations(raw,assessment);
 if(plan.issues.length||plan.observedUnclaimedReturns===null)fail('point-carryover-history-needs-review');
 const stored=await tx.get(`${root}/pointTierCarryovers/${migration.migrationId}`);
 // A history with no stages creates no carried claim rights. Existing proofs,
 // even for an empty history, must still validate rather than being ignored.
 const stages=[];
 for(const tier of plan.tiers)stages.push(await tx.get(`${root}/pointTierEntitlements/${tier.threshold}`));
 if(stored===null&&plan.tiers.every(t=>!t.hasReserve&&!t.hasClaim)){
  if(stages.some(stage=>stage!==null))fail('migration-point-carryover-conflict');
  return;
 }
 if(stored===null)fail('migration-point-carryover-required');
 const approval=await tx.get(`${root}/approvals/${migration.migrationId}`);
 const {records,summary}=buildPointTierCarryover(migration,raw,assessment,approval);
 if(!sameStored(stored,summary))fail('migration-point-carryover-conflict');
 const stamp=time(stored.createdAt);
 for(const [index,expected] of records.entries()){
  const stage=stages[index];
  if(!sameStored(stage,expected)||!isDeepStrictEqual(time(stage.createdAt),stamp))fail('migration-point-carryover-conflict');
 }
}
module.exports={buildPointTierCarryover,validatePointTierCarryover,sameStored,time};
