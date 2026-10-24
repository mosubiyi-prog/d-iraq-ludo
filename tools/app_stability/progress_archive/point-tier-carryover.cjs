'use strict';
// INTERNAL, UNDEPLOYED derived carryover after a protected manual review.
// Writes private candidate entitlements only. No wallet, refund, new reward,
// public API, settlement counter, verified receipt or cutover is produced.
const {isDeepStrictEqual}=require('node:util');
const core=require('./reconcile-core.cjs');
const {parseMigration}=require('./migration-gate.cjs');
const {loadReviewedEvidence}=require('./baseline-evidence.cjs');
const {parsePolicy,policyPath}=require('./baseline-review.cjs');
const {buildPointTierCarryover,sameStored,time}=require('./point-tier-carryover-proof.cjs');
function fail(code){throw Object.assign(new Error(code),{code});}
function exact(value,keys,code){if(!value||typeof value!=='object'||Array.isArray(value)||
 Object.keys(value).length!==keys.length||!keys.every(k=>Object.hasOwn(value,k)))fail(code);}
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
  const {records,summary}=buildPointTierCarryover(migration,raw,assessment,approval);
  const policy=parsePolicy(await tx.get(policyPath),approval.policyRevision);
  if(assessment.issues.some(issue=>!policy.acceptedIssues.includes(issue)))fail('point-carryover-unaccepted-issues');
  // Worker consumes the protected prior approval, not a new user token. The
  // current role/policy are rechecked in this transaction; this is not an API
  // authorization or fresh SDK revocation check for the historical reviewer.
  const reviewer=await tx.get(`admins/${approval.reviewerUid}`);
  if(!reviewer||reviewer.active!==true||reviewer.status!=='active'||reviewer.role!=='general_manager'||
   reviewer.mustChangePassword===true||typeof reviewer.email!=='string'||
   reviewer.email.trim().toLowerCase()!==approval.reviewerEmail)fail('point-carryover-reviewer-inactive');
  if(await tx.get(`deda_verified_progress/${accountKey}`)!==null)fail('point-carryover-already-activated');
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
