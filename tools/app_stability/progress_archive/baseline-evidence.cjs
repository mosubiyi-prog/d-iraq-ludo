'use strict';
// UNDEPLOYED consistency check, NOT authority to approve client balances.
const {assessLegacyEvidence}=require('./legacy-assessment.cjs');
const {isDeepStrictEqual}=require('node:util');
function fail(code){throw Object.assign(new Error(code),{code});}
async function loadReviewedEvidence(tx,migration){
  const {accountKey,migrationId,evidenceDigest}=migration;
  const review=await tx.get(`deda_progress_migrations/${accountKey}/reviews/${migrationId}`);
  if(!review||typeof review.captureId!=='string'||!/^[A-Za-z0-9_-]{20,80}$/.test(review.captureId))fail('migration-reviewed-evidence-required');
  const sourcePath=`deda_progress_evidence/${accountKey}/captures/${review.captureId}`;
  const raw=await tx.get(sourcePath);
  const assessment=assessLegacyEvidence(raw,accountKey,review.captureId);
  const expected={...assessment,migrationId,sourcePath};
  if(assessment.evidenceDigest!==evidenceDigest||review.createdAt==null||
     Object.keys(review).length!==Object.keys(expected).length+1||
     !Object.keys(expected).every(key=>Object.hasOwn(review,key)&&isDeepStrictEqual(review[key],expected[key])))fail('migration-reviewed-evidence-conflict');
  return {raw,assessment,sourcePath};
}
async function validateBaselineEvidence(tx,migration,receipt){
  const {assessment}=await loadReviewedEvidence(tx,migration);
  // Unknown/negative legacy values cannot be silently zeroed or replaced by
  // derived GM bonuses. Reject instead; separate policy/review is still needed.
  if(!isDeepStrictEqual(receipt.delta,assessment.observedBalances))fail('migration-baseline-evidence-conflict');
}
module.exports={validateBaselineEvidence,loadReviewedEvidence};
