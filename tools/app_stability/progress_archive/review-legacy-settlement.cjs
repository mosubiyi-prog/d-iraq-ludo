'use strict';
// Trusted-server producer, not deployed. Resolves only a reviewed, captured
// absence of unfinished purchases. Ambiguous charges require separate proof;
// no client counters, automatic refund, debit, grant or journal clearing.
const {isDeepStrictEqual}=require('node:util');
const core=require('./reconcile-core.cjs');
const {parseMigration}=require('./migration-gate.cjs');
const {parsePolicy,policyPath}=require('./baseline-review.cjs');
const {validateBaselineEvidence}=require('./baseline-evidence.cjs');
const {validatePointTierCarryover}=require('./point-tier-carryover-proof.cjs');
const {saveLegacyOperationReview}=require('./legacy-operation-review.cjs');
const {deploymentPath,parseDeployment,validateFence}=require('./activate-reviewed-baseline.cjs');
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{20,80}$/.test(v);
const hash=v=>typeof v==='string'&&/^[a-f0-9]{64}$/.test(v);
function fail(code){throw Object.assign(new Error(code),{code});}
function manager(value,email){return value&&value.active===true&&value.status==='active'&&
 value.role==='general_manager'&&value.mustChangePassword!==true&&typeof value.email==='string'&&
 value.email.trim().toLowerCase()===email.trim().toLowerCase();}
function stamp(t){return t&&Number.isSafeInteger(t.seconds)&&Number.isSafeInteger(t.nanoseconds)&&
 t.nanoseconds>=0&&t.nanoseconds<1000000000;}
function sameStored(stored,body){return stored&&stamp(stored.createdAt)&&
 Object.keys(stored).length===Object.keys(body).length+1&&
 Object.keys(body).every(k=>isDeepStrictEqual(stored[k],body[k]));}
async function reviewLegacySettlement(options){
 const keys=['store','auth','idToken','accountKey','migrationId','settlementId',
  'expectedOperationReviewDigest','purchaseCaptureId','originalId','legacyFenceId'];
 if(!options||typeof options!=='object'||Array.isArray(options)||Object.keys(options).length!==keys.length||
  !keys.every(k=>Object.hasOwn(options,k)))fail('invalid-settlement-review-request');
 const {store,auth,idToken,accountKey,migrationId,settlementId,expectedOperationReviewDigest,
  purchaseCaptureId,originalId,legacyFenceId}=options;
 core.account(accountKey);
 if(!id(migrationId)||!id(settlementId)||!id(purchaseCaptureId)||!id(legacyFenceId)||
  !hash(expectedOperationReviewDigest)||typeof originalId!=='string'||!/^@DEDA-[A-Z0-9]{6}$/.test(originalId)||
  typeof idToken!=='string'||!idToken.length)fail('invalid-settlement-review-request');
 if(!store||typeof store.runTransaction!=='function'||typeof store.serverTimestamp!=='function'||
  !auth||typeof auth.verifyIdToken!=='function')fail('invalid-settlement-review-dependencies');
 return store.runTransaction(async tx=>{
  const token=await auth.verifyIdToken(idToken,true);
  if(!token||typeof token.uid!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(token.uid)||
   typeof token.email!=='string'||!token.email.trim()||token.firebase?.sign_in_provider!=='password')fail('settlement-manager-sign-in-required');
  const root=`deda_progress_migrations/${accountKey}`;
  const migration=parseMigration(await tx.get(root),accountKey);
  if(migration.migrationId!==migrationId||!['baseline-approved','cutover-complete'].includes(migration.phase))fail('settlement-approved-baseline-required');
  if(!manager(await tx.get(`admins/${token.uid}`),token.email))fail('settlement-general-manager-required');
  const approval=await tx.get(`${root}/approvals/${migrationId}`);
  if(!approval||approval.status!=='approved-awaiting-settlement'||approval.canReleaseBalance!==false||
   approval.accountKey!==accountKey||approval.migrationId!==migrationId||
   approval.evidenceDigest!==migration.evidenceDigest||approval.baselineEventKey!==migration.baselineEventKey||
   !manager(await tx.get(`admins/${approval.reviewerUid}`),approval.reviewerEmail))fail('settlement-baseline-approval-required');
  const policy=parsePolicy(await tx.get(policyPath),approval.policyRevision);
  const receipt=core.parseReceipt(approval.receipt,accountKey);
  if(receipt.source!=='legacy-baseline-v1'||receipt.sourceId!==`legacy-review|${migrationId}|${migration.evidenceDigest}`||
   core.eventKey(receipt)!==migration.baselineEventKey)fail('settlement-baseline-approval-required');
  const {raw,assessment}=await validateBaselineEvidence(tx,migration,receipt);
  if(assessment.issues.some(issue=>!policy.acceptedIssues.includes(issue)))fail('settlement-unaccepted-evidence-issues');
  await validatePointTierCarryover(tx,migration,raw,assessment);
  const deployment=parseDeployment(await tx.get(deploymentPath));
  validateFence(await tx.get(`${root}/fences/${legacyFenceId}`),migration,{originalId,legacyFenceId},deployment);
  const path=`${root}/settlementReviews/${settlementId}`,stored=await tx.get(path);
  const body={format:1,accountKey,migrationId,evidenceDigest:migration.evidenceDigest,
   baselineEventKey:migration.baselineEventKey,settlementId,originalId,
   operationReviewDigest:expectedOperationReviewDigest,purchaseCaptureId,legacyFenceId,
   policyRevision:approval.policyRevision,reviewerUid:stored?.reviewerUid??token.uid,
   reviewerEmail:stored?.reviewerEmail??token.email.trim().toLowerCase(),status:'resolved',
   decision:'preserve-reviewed-balances-and-carried-rights',pendingPurchases:0,pendingReservations:0};
  if(stored&&!sameStored(stored,body))fail('settlement-review-conflict');
  if(stored&&(!manager(await tx.get(`admins/${stored.reviewerUid}`),stored.reviewerEmail)))fail('settlement-reviewer-inactive');
  if(migration.phase==='cutover-complete'){
   if(!stored||migration.settlementId!==settlementId)fail('settlement-already-activated');
   return Object.freeze({replayed:true,settlementId,canReleaseBalance:false});
  }
  const readOnlyStore={serverTimestamp:()=>store.serverTimestamp(),runTransaction:work=>work({
   get:p=>tx.get(p),set:()=>fail('settlement-operation-review-changed'),
  })};
  const {report}=await saveLegacyOperationReview({store:readOnlyStore,accountKey,migrationId,originalId,purchaseCaptureId});
  if(report.inputDigest!==expectedOperationReviewDigest)fail('settlement-operation-review-changed');
  // Source absence is evidence, not a proof that another old handset cannot
  // spend: the independent enforced fence above remains mandatory.
  if(!report.purchaseJournalEvidence||report.purchaseJournalEvidence.captureId!==purchaseCaptureId||
   report.frames.some(frame=>frame.localJournal.state!=='absent-on-source'))fail('settlement-payment-journal-needs-review');
  if(report.purchaseJournalEvidence.inventoryValueType!=='absent')fail('settlement-style-history-needs-review');
  if(!Array.isArray(report.nativePendingFrames)||report.nativePendingFrames.length!==0||
   !Array.isArray(report.nativeOwnedFrames)||
   report.issues.some(issue=>issue.includes('partial-or-invalid-receipt-pair')||
    issue.includes('unknown-frame-preserved')||issue.startsWith('native-')))fail('settlement-native-purchases-needs-review');
  // Carried reservations above retain their future right; none is refunded
  // or returned here. Unknown/invalid tier history fails that validation.
  if(stored)return Object.freeze({replayed:true,settlementId,canReleaseBalance:false});
  tx.set(path,{...body,createdAt:store.serverTimestamp()});
  return Object.freeze({replayed:false,settlementId,canReleaseBalance:false});
 });
}
module.exports={reviewLegacySettlement};
