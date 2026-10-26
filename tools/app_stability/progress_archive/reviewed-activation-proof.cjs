'use strict';
// Read-only link from an owner API to the actual six-record activation writer.
// It does not treat phase/counters alone as proof, issue a fence, or enable one.
const uid=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{20,80}$/.test(v);
const hash=v=>typeof v==='string'&&/^[a-f0-9]{64}$/.test(v);
function fail(){throw Object.assign(new Error('reviewed-activation-proof-required'),{code:'reviewed-activation-proof-required'});}
function stamp(t){return t&&Number.isSafeInteger(t.seconds)&&Number.isSafeInteger(t.nanoseconds)&&t.nanoseconds>=0&&t.nanoseconds<1000000000;}
async function requireReviewedActivation(tx,{root,migration,state}){
 const a=await tx.get(`${root}/activations/${migration.migrationId}`);
 const keys=['format','accountKey','migrationId','evidenceDigest','baselineEventKey','settlementId','receiptId',
  'operationReviewDigest','legacyFenceId','deploymentRevision','enforcementRevision','policyRevision',
  'executedByUid','executedByEmail','createdAt'];
 if(!a||Object.keys(a).length!==keys.length||!keys.every(k=>Object.hasOwn(a,k))||
  a.format!==1||a.accountKey!==migration.accountKey||a.migrationId!==migration.migrationId||
  a.evidenceDigest!==migration.evidenceDigest||a.baselineEventKey!==migration.baselineEventKey||
  state.initializedBy!==a.baselineEventKey||a.settlementId!==migration.settlementId||
  a.receiptId!==`baseline_${migration.baselineEventKey}`||!hash(a.operationReviewDigest)||
  !id(a.legacyFenceId)||!id(a.deploymentRevision)||!hash(a.enforcementRevision)||!id(a.policyRevision)||
  !uid(a.executedByUid)||typeof a.executedByEmail!=='string'||!a.executedByEmail.trim()||!stamp(a.createdAt))fail();
 const fence=await tx.get(`${root}/fences/${a.legacyFenceId}`);
 const settlement=await tx.get(`${root}/settlementReviews/${a.settlementId}`);
 if(!fence||fence.format!==1||fence.accountKey!==a.accountKey||fence.migrationId!==a.migrationId||
  fence.evidenceDigest!==a.evidenceDigest||fence.legacyFenceId!==a.legacyFenceId||
  fence.protocol!=='deda-verified-progress-v1'||fence.status!=='enforced'||
  fence.deploymentRevision!==a.deploymentRevision||fence.enforcementRevision!==a.enforcementRevision||
  !stamp(fence.createdAt)||!settlement||settlement.format!==1||settlement.accountKey!==a.accountKey||
  settlement.migrationId!==a.migrationId||settlement.evidenceDigest!==a.evidenceDigest||
  settlement.baselineEventKey!==a.baselineEventKey||settlement.settlementId!==a.settlementId||
  settlement.originalId!==fence.originalId||settlement.legacyFenceId!==a.legacyFenceId||
  settlement.policyRevision!==a.policyRevision||settlement.operationReviewDigest!==a.operationReviewDigest||
  settlement.status!=='resolved'||settlement.decision!=='preserve-reviewed-balances-and-carried-rights'||
  settlement.pendingPurchases!==0||settlement.pendingReservations!==0||!stamp(settlement.createdAt))fail();
 return a;
}
module.exports={requireReviewedActivation};
