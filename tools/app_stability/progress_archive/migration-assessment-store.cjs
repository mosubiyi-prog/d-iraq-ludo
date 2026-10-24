'use strict';
// INTERNAL UNDEPLOYED worker. Not exported from Functions or callable by a
// client. Produces only private evidence-saved review inputs, NEVER approval.
const {assessLegacyEvidence}=require('./legacy-assessment.cjs');
const {parseMigration}=require('./migration-gate.cjs');
const {account}=require('./reconcile-core.cjs');
const {isDeepStrictEqual}=require('node:util');
function fail(code){throw Object.assign(new Error(code),{code});}
function id(value){return typeof value==='string'&&/^[A-Za-z0-9_-]{20,80}$/.test(value);}
function sameReview(stored,expected){
  if(!stored||typeof stored!=='object'||Array.isArray(stored)||!Object.hasOwn(stored,'createdAt')||stored.createdAt==null||
     Object.keys(stored).length!==Object.keys(expected).length+1)return false;
  return Object.keys(expected).every(key=>Object.hasOwn(stored,key)&&isDeepStrictEqual(stored[key],expected[key]));
}
async function saveMigrationAssessment(options){
  const keys=['store','accountKey','captureId','migrationId'];
  if(!options||Object.keys(options).length!==keys.length||!keys.every(key=>Object.hasOwn(options,key)))fail('invalid-assessment-request');
  const {store,accountKey,captureId,migrationId}=options;account(accountKey);
  if(!id(captureId)||!id(migrationId))fail('invalid-assessment-identity');
  if(!store||typeof store.runTransaction!=='function'||typeof store.serverTimestamp!=='function')fail('invalid-assessment-store');
  return store.runTransaction(async tx=>{
    const source=`deda_progress_evidence/${accountKey}/captures/${captureId}`;
    const root=`deda_progress_migrations/${accountKey}`,reviewPath=`${root}/reviews/${migrationId}`;
    const raw=await tx.get(source);
    const assessment=assessLegacyEvidence(raw,accountKey,captureId);
    const old=await tx.get(root),stored=await tx.get(reviewPath);
    const review={...assessment,migrationId,sourcePath:source};
    if(old!==null){
      const migration=parseMigration(old,accountKey);
      if(migration.migrationId!==migrationId)fail('migration-review-conflict');
      if(migration.phase!=='pending'){
        if(migration.evidenceDigest!==assessment.evidenceDigest||!sameReview(stored,review))fail('migration-review-conflict');
        // A later trusted approval must NEVER be downgraded by a retry here.
        return Object.freeze({replayed:true,phase:migration.phase,assessment});
      }
    }
    if(stored!==null)fail('migration-review-conflict');
    const migration=parseMigration({format:1,accountKey,migrationId,phase:'evidence-saved',
      evidenceDigest:assessment.evidenceDigest,baselineEventKey:null,settlementId:null},accountKey);
    // Archive is immutable and read-only here. Only these two private records
    // are committed together; no balances/receipts/users/roles are written.
    tx.set(reviewPath,{...review,createdAt:store.serverTimestamp()});
    tx.set(root,{...migration});
    return Object.freeze({replayed:false,phase:'evidence-saved',assessment});
  });
}
module.exports={saveMigrationAssessment};
