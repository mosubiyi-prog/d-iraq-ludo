'use strict';
// INTERNAL, UNDEPLOYED review producer. Never exports a callable, writes a
// receipt/wallet, or enables policy. Token verifier is the SERVER Admin SDK.
const core=require('./reconcile-core.cjs');
const {parseMigration}=require('./migration-gate.cjs');
const {validateBaselineEvidence}=require('./baseline-evidence.cjs');
const {isDeepStrictEqual}=require('node:util');
const policyPath='deda_progress_migrations/_policy/settings/legacy-manual-v1';
const requiredIssues=['local-values-not-server-attested','legacy-writer-fence-not-established','pending-operations-not-reviewed'];
function fail(code){throw Object.assign(new Error(code),{code});}
function exact(value,keys,code){
 if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).length!==keys.length||
 !keys.every(key=>Object.hasOwn(value,key)))fail(code);
}
const id=value=>typeof value==='string'&&/^[A-Za-z0-9_-]{20,80}$/.test(value);
const hash=value=>typeof value==='string'&&/^[a-f0-9]{64}$/.test(value);
function parsePolicy(raw,revision){
 if(!raw||raw.enabled!==true)fail('baseline-review-policy-disabled');
 exact(raw,['format','enabled','revision','decisionBasis','acceptedIssues'],'invalid-baseline-review-policy');
 if(raw.format!==1||!id(raw.revision)||raw.revision!==revision||
 raw.decisionBasis!=='owner-reviewed-grandfathering'||!Array.isArray(raw.acceptedIssues)||
 raw.acceptedIssues.length>64||raw.acceptedIssues.some(v=>typeof v!=='string'||v.length>128)||
 new Set(raw.acceptedIssues).size!==raw.acceptedIssues.length||
 requiredIssues.some(issue=>!raw.acceptedIssues.includes(issue)))fail('invalid-baseline-review-policy');
 return raw;
}
async function approveLegacyBaseline(options){
 exact(options,['store','auth','idToken','accountKey','migrationId','expectedEvidenceDigest','policyRevision'],'invalid-baseline-review-request');
 const {store,auth,idToken,accountKey,migrationId,expectedEvidenceDigest,policyRevision}=options;
 core.account(accountKey);
 if(!id(migrationId)||!id(policyRevision)||!hash(expectedEvidenceDigest)||typeof idToken!=='string'||!idToken.length)fail('invalid-baseline-review-request');
 if(!store||typeof store.runTransaction!=='function'||typeof store.serverTimestamp!=='function'||
 !auth||typeof auth.verifyIdToken!=='function')fail('invalid-baseline-review-dependencies');
 return store.runTransaction(async tx=>{
  // Reverify on EVERY transaction attempt (including revocation/disabled user).
  // No reviewer UID, role, verified flag or amount is accepted from a client.
  const token=await auth.verifyIdToken(idToken,true);
  if(!token||typeof token.uid!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(token.uid)||
  typeof token.email!=='string'||!token.email.length||token.firebase?.sign_in_provider!=='password')fail('baseline-review-admin-sign-in-required');
  const admin=await tx.get(`admins/${token.uid}`);
  if(!admin||admin.active!==true||admin.status!=='active'||admin.role!=='general_manager'||
  admin.mustChangePassword===true||typeof admin.email!=='string'||
  admin.email.trim().toLowerCase()!==token.email.trim().toLowerCase())fail('baseline-review-general-manager-required');
  const policy=parsePolicy(await tx.get(policyPath),policyRevision);
  const root=`deda_progress_migrations/${accountKey}`;
  const migration=parseMigration(await tx.get(root),accountKey);
  if(migration.migrationId!==migrationId||migration.evidenceDigest!==expectedEvidenceDigest)fail('baseline-review-migration-conflict');
  if(migration.phase==='pending')fail('baseline-review-evidence-required');
  const review=await tx.get(`${root}/reviews/${migrationId}`);
  if(!review)fail('migration-reviewed-evidence-required');
  const receipt=core.parseReceipt({format:1,accountKey,source:'legacy-baseline-v1',
   sourceId:`legacy-review|${migrationId}|${expectedEvidenceDigest}`,kind:'baseline',delta:review.observedBalances},accountKey);
  await validateBaselineEvidence(tx,migration,receipt);
  if(review.issues.some(issue=>!policy.acceptedIssues.includes(issue)))fail('baseline-review-unaccepted-issues');
  const baselineEventKey=core.eventKey(receipt);
  const approvalPath=`${root}/approvals/${migrationId}`;
  const stored=await tx.get(approvalPath);
  const state=await tx.get(`deda_verified_progress/${accountKey}`);
  const approval={format:1,accountKey,migrationId,evidenceDigest:expectedEvidenceDigest,
   policyRevision,decisionBasis:policy.decisionBasis,reviewerUid:token.uid,
   reviewerEmail:token.email.trim().toLowerCase(),baselineEventKey,receipt,
   status:'approved-awaiting-settlement',canReleaseBalance:false};
  if(migration.phase!=='evidence-saved'){
   if(migration.baselineEventKey!==baselineEventKey||!stored||stored.createdAt==null||
   Object.keys(stored).length!==Object.keys(approval).length+1||
   !Object.keys(approval).every(key=>Object.hasOwn(stored,key)&&isDeepStrictEqual(stored[key],approval[key])))fail('baseline-review-approval-conflict');
   return Object.freeze({replayed:true,phase:migration.phase,baselineEventKey,canReleaseBalance:false});
  }
  if(stored!==null||state!==null)fail('baseline-review-existing-state-conflict');
  const next=parseMigration({...migration,phase:'baseline-approved',baselineEventKey,settlementId:null},accountKey);
  tx.set(approvalPath,{...approval,createdAt:store.serverTimestamp()});
  tx.set(root,{...next});
  return Object.freeze({replayed:false,phase:next.phase,baselineEventKey,canReleaseBalance:false});
 });
}
module.exports={approveLegacyBaseline,policyPath};
