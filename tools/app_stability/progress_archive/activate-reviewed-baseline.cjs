'use strict';
// Trusted-server activation only. NOT deployed or exported as a client API.
// This consumes completed deployment/fence/settlement reviews; it cannot
// manufacture them from a phone, approve unknown purchases, or fence an APK.
const {isDeepStrictEqual}=require('node:util');
const core=require('./reconcile-core.cjs');
const {parseMigration}=require('./migration-gate.cjs');
const {validateBaselineEvidence}=require('./baseline-evidence.cjs');
const {validatePointTierCarryover}=require('./point-tier-carryover-proof.cjs');
const {saveLegacyOperationReview}=require('./legacy-operation-review.cjs');
const {parsePolicy,policyPath}=require('./baseline-review.cjs');
const deploymentPath='deda_progress_migrations/_policy/settings/verified-cutover-v1';
const protocol='deda-verified-progress-v1';
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{20,80}$/.test(v);
const uid=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const hash=v=>typeof v==='string'&&/^[a-f0-9]{64}$/.test(v);
function fail(code){throw Object.assign(new Error(code),{code});}
function exact(value,keys,code){
 if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).length!==keys.length||
  !keys.every(key=>Object.hasOwn(value,key)))fail(code);
}
function stamp(value){return value&&Number.isSafeInteger(value.seconds)&&Number.isSafeInteger(value.nanoseconds)&&
 value.nanoseconds>=0&&value.nanoseconds<1000000000;}
function sameStored(value,expected){return value&&stamp(value.createdAt)&&
 Object.keys(value).length===Object.keys(expected).length+1&&
 Object.keys(expected).every(key=>isDeepStrictEqual(value[key],expected[key]));}
function manager(value,email){return value&&value.active===true&&value.status==='active'&&
 value.role==='general_manager'&&value.mustChangePassword!==true&&typeof value.email==='string'&&
 value.email.trim().toLowerCase()===email.trim().toLowerCase();}
function parseDeployment(value){
 if(!value||value.enabled!==true)fail('cutover-deployment-not-approved');
 exact(value,['format','enabled','revision','protocol','enforcementRevision','clientBound','providersReady','atomicPurchasesReady'],
  'invalid-cutover-deployment');
 if(value.format!==1||!id(value.revision)||value.protocol!==protocol||!hash(value.enforcementRevision)||
  value.clientBound!==true||value.providersReady!==true||value.atomicPurchasesReady!==true)fail('cutover-integration-not-ready');
 return value;
}
function parseResolution(value,migration,settlementId){
 const keys=['format','accountKey','migrationId','evidenceDigest','baselineEventKey','settlementId',
  'originalId','operationReviewDigest','purchaseCaptureId','legacyFenceId','policyRevision','reviewerUid','reviewerEmail',
  'status','decision','pendingPurchases','pendingReservations','createdAt'];
 exact(value,keys,'cutover-reviewed-settlement-required');
 if(value.format!==1||value.accountKey!==migration.accountKey||value.migrationId!==migration.migrationId||
  value.evidenceDigest!==migration.evidenceDigest||value.baselineEventKey!==migration.baselineEventKey||
  value.settlementId!==settlementId||!/^@DEDA-[A-Z0-9]{6}$/.test(value.originalId)||
  !hash(value.operationReviewDigest)||(value.purchaseCaptureId!==null&&!id(value.purchaseCaptureId))||
  !id(value.legacyFenceId)||!id(value.policyRevision)||!uid(value.reviewerUid)||typeof value.reviewerEmail!=='string'||
  value.status!=='resolved'||value.decision!=='preserve-reviewed-balances-and-carried-rights'||
  value.pendingPurchases!==0||value.pendingReservations!==0||!stamp(value.createdAt))fail('cutover-operations-unresolved');
 return value;
}
function validateFence(value,migration,resolution,deployment){
 exact(value,['format','accountKey','migrationId','evidenceDigest','originalId','legacyFenceId',
  'protocol','deploymentRevision','enforcementRevision','status','createdAt'],'cutover-enforced-fence-required');
 if(value.format!==1||value.accountKey!==migration.accountKey||value.migrationId!==migration.migrationId||
  value.evidenceDigest!==migration.evidenceDigest||value.originalId!==resolution.originalId||
  value.legacyFenceId!==resolution.legacyFenceId||value.protocol!==protocol||value.status!=='enforced'||
  value.deploymentRevision!==deployment.revision||value.enforcementRevision!==deployment.enforcementRevision||
  !stamp(value.createdAt))fail('cutover-fence-conflict');
}
async function activateReviewedBaseline(options){
 exact(options,['store','auth','idToken','accountKey','migrationId','settlementId'], 'invalid-cutover-request');
 const {store,auth,idToken,accountKey,migrationId,settlementId}=options;
 core.account(accountKey);
 if(!id(migrationId)||!id(settlementId)||typeof idToken!=='string'||!idToken.length||
  !store||typeof store.runTransaction!=='function'||typeof store.serverTimestamp!=='function'||
  !auth||typeof auth.verifyIdToken!=='function')fail('invalid-cutover-dependencies');
 return store.runTransaction(async tx=>{
  const token=await auth.verifyIdToken(idToken,true);
  if(!token||!uid(token.uid)||typeof token.email!=='string'||!token.email.trim()||
   token.firebase?.sign_in_provider!=='password')fail('cutover-manager-sign-in-required');
  const root=`deda_progress_migrations/${accountKey}`;
  // Every worker starts with this shared account row, including SDK retries.
  const migration=parseMigration(await tx.get(root),accountKey);
  if(migration.migrationId!==migrationId||!['baseline-approved','cutover-complete'].includes(migration.phase))fail('cutover-reviewed-baseline-required');
  if(!manager(await tx.get(`admins/${token.uid}`),token.email))fail('cutover-general-manager-required');
  const deployment=parseDeployment(await tx.get(deploymentPath));
  const approval=await tx.get(`${root}/approvals/${migrationId}`);
  exact(approval,['format','accountKey','migrationId','evidenceDigest','policyRevision','decisionBasis',
   'reviewerUid','reviewerEmail','baselineEventKey','receipt','status','canReleaseBalance','createdAt'],
   'cutover-baseline-approval-conflict');
  if(!approval||approval.format!==1||approval.accountKey!==accountKey||approval.migrationId!==migrationId||
   approval.evidenceDigest!==migration.evidenceDigest||approval.baselineEventKey!==migration.baselineEventKey||
   approval.status!=='approved-awaiting-settlement'||approval.canReleaseBalance!==false||
   approval.decisionBasis!=='owner-reviewed-grandfathering'||!uid(approval.reviewerUid)||
   typeof approval.reviewerEmail!=='string'||!stamp(approval.createdAt))fail('cutover-baseline-approval-conflict');
  const receipt=core.parseReceipt(approval.receipt,accountKey);
  if(receipt.source!=='legacy-baseline-v1'||
   receipt.sourceId!==`legacy-review|${migrationId}|${migration.evidenceDigest}`||
   core.eventKey(receipt)!==migration.baselineEventKey)fail('cutover-baseline-approval-conflict');
  const policy=parsePolicy(await tx.get(policyPath),approval.policyRevision);
  if(!manager(await tx.get(`admins/${approval.reviewerUid}`),approval.reviewerEmail))fail('cutover-baseline-reviewer-inactive');
  const {raw,assessment}=await validateBaselineEvidence(tx,migration,receipt);
  if(assessment.issues.some(issue=>!policy.acceptedIssues.includes(issue)))fail('cutover-unaccepted-evidence-issues');
  await validatePointTierCarryover(tx,migration,raw,assessment);
  const resolution=parseResolution(await tx.get(`${root}/settlementReviews/${settlementId}`),migration,settlementId);
  if(resolution.policyRevision!==approval.policyRevision||
   !manager(await tx.get(`admins/${resolution.reviewerUid}`),resolution.reviewerEmail))fail('cutover-settlement-reviewer-inactive');
  validateFence(await tx.get(`${root}/fences/${resolution.legacyFenceId}`),migration,resolution,deployment);
  // Recompute the original operation review from current sources INSIDE this
  // transaction. A new/changed review would attempt a write: refuse it instead
  // of treating the saved count of zero as proof of current settlement.
  const readOnlyStore={serverTimestamp:()=>store.serverTimestamp(),runTransaction:work=>work({
   get:path=>tx.get(path),set:()=>fail('cutover-operation-review-changed'),
  })};
  if(migration.phase==='baseline-approved'){
   const operationOptions={store:readOnlyStore,accountKey,migrationId,originalId:resolution.originalId};
   if(resolution.purchaseCaptureId!==null)operationOptions.purchaseCaptureId=resolution.purchaseCaptureId;
   const operations=await saveLegacyOperationReview(operationOptions);
   if(operations.report.inputDigest!==resolution.operationReviewDigest)fail('cutover-operation-review-changed');
  }
  const eventKey=migration.baselineEventKey,receiptId=`baseline_${eventKey}`;
  const statePath=`deda_verified_progress/${accountKey}`,eventPath=`${statePath}/events/${eventKey}`;
  const receiptPath=`deda_progress_receipts/${accountKey}/events/${receiptId}`;
  const activationPath=`${root}/activations/${migrationId}`,settlementPath=`${root}/settlements/${settlementId}`;
  const state=await tx.get(statePath),event=await tx.get(eventPath),storedReceipt=await tx.get(receiptPath);
  const settlement=await tx.get(settlementPath),activation=await tx.get(activationPath);
  const settlementBody={format:1,accountKey,migrationId,evidenceDigest:migration.evidenceDigest,
   baselineEventKey:eventKey,legacyFenceId:resolution.legacyFenceId,pendingPurchases:0,pendingReservations:0};
  const activationBody={format:1,accountKey,migrationId,evidenceDigest:migration.evidenceDigest,
   baselineEventKey:eventKey,settlementId,receiptId,operationReviewDigest:resolution.operationReviewDigest,
   legacyFenceId:resolution.legacyFenceId,deploymentRevision:deployment.revision,
   enforcementRevision:deployment.enforcementRevision,policyRevision:approval.policyRevision,
   executedByUid:activation?.executedByUid??token.uid,
   executedByEmail:activation?.executedByEmail??token.email.trim().toLowerCase()};
  if(!uid(activationBody.executedByUid)||typeof activationBody.executedByEmail!=='string'||
   !activationBody.executedByEmail.trim())fail('cutover-existing-activation-conflict');
  if(migration.phase==='cutover-complete'){
   const current=core.parseState(state,accountKey);
   if(migration.settlementId!==settlementId||current.initializedBy!==eventKey||
    !isDeepStrictEqual(settlement,settlementBody)||!sameStored(activation,activationBody)||
    !event||event.format!==1||event.accountKey!==accountKey||event.eventKey!==eventKey||
    event.receiptId!==receiptId||event.appliedVersion!==1||!stamp(event.createdAt)||
    !isDeepStrictEqual(event.afterBalances,receipt.delta)||
    !core.sameEvent(core.parseReceipt(event.receipt,accountKey),receipt)||
    !core.sameEvent(core.parseReceipt(storedReceipt,accountKey),receipt))fail('cutover-existing-activation-conflict');
   return Object.freeze({replayed:true,state:current});
  }
  if(migration.settlementId!==null&&migration.settlementId!==settlementId)fail('cutover-settlement-conflict');
  if([state,event,storedReceipt,settlement,activation].some(value=>value!==null))fail('cutover-partial-or-existing-state');
  const next=core.applyEvent(null,receipt),createdAt=store.serverTimestamp();
  // No async effects, extra transaction, grants, charges or preference writes.
  // All six records commit together or none do; a retry revalidates every read.
  tx.set(receiptPath,receipt);
  tx.set(eventPath,{format:1,accountKey,eventKey,receipt,receiptId,appliedVersion:1,
   afterBalances:next.balances,createdAt});
  tx.set(statePath,{...next});
  tx.set(settlementPath,settlementBody);
  tx.set(activationPath,{...activationBody,createdAt});
  tx.set(root,{...migration,phase:'cutover-complete',settlementId});
  return Object.freeze({replayed:false,state:next});
 });
}
module.exports={activateReviewedBaseline,deploymentPath};
