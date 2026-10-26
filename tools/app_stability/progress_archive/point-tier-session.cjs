'use strict';
// INTERNAL, UNDEPLOYED session adapter; no HTTP/callable export or activation.
// Auth is the trusted Admin SDK, not a caller-supplied decoded-token payload.
const {claimMigratedPointTier}=require('./point-tier-claim.cjs');
const {loadMigratedContext}=require('./migration-gate.cjs');
const {requireReviewedActivation}=require('./reviewed-activation-proof.cjs');
function fail(code){throw Object.assign(new Error(code),{code});}
const validId=value=>typeof value==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(value);
const trusted=(record,install)=>Array.isArray(record?.trustedInstallIds)&&
 record.trustedInstallIds.every(value=>typeof value==='string')&&record.trustedInstallIds.includes(install);
function dependencies(options){
 const {store,auth,idToken}=options;
 if(!store||typeof store.runTransaction!=='function'||typeof store.serverTimestamp!=='function'||typeof store.readOwnerSession!=='function'||
 !auth||typeof auth.verifyIdToken!=='function'||typeof idToken!=='string'||!idToken.length)fail('invalid-point-session-dependencies');
}
async function forOwnerSession(options,work){
 const {store,auth,idToken}=options;
 // Read-only routing hint, NOT authorization. It lets every financial worker
 // start its transaction at the same shared account document before UID-local
 // records, avoiding opposite lock acquisition paths across recovered UIDs.
 const routingToken=await auth.verifyIdToken(idToken,true);
 if(!routingToken||!validId(routingToken.uid)||routingToken.firebase?.sign_in_provider!=='anonymous')fail('point-session-owner-sign-in-required');
 const hint=await store.readOwnerSession(routingToken.uid);
 if(!hint||hint.uid!==routingToken.uid||typeof hint.accountKey!=='string'||!/^[0-9]+$/.test(hint.accountKey))fail('point-session-owner-proof-required');
 return store.runTransaction(async tx=>{
  // On EVERY SDK transaction retry, repeat token validation/revocation and
  // all owner proof reads. Never accept account/UID/install/name from request.
  const token=await auth.verifyIdToken(idToken,true);
  if(!token||!validId(token.uid)||token.uid!==routingToken.uid||token.firebase?.sign_in_provider!=='anonymous')fail('point-session-owner-sign-in-required');
  // This read orders locks; its data grants no authority and is not cached.
  await tx.get(`deda_progress_migrations/${hint.accountKey}`);
  const session=await tx.get(`deda_sessions/${token.uid}`);
  if(!session||session.uid!==token.uid||typeof session.accountKey!=='string'||
   !/^[0-9]+$/.test(session.accountKey)||session.accountKey!==hint.accountKey||!validId(session.installId))fail('point-session-owner-proof-required');
  const accountKey=session.accountKey,install=session.installId;
  const user=await tx.get(`users/${token.uid}`);
  const profile=await tx.get(`deda_account_profiles/${accountKey}`);
  const directory=await tx.get(`deda_account_directory/${accountKey}`);
  const credential=await tx.get(`deda_credentials/${accountKey}`);
  if(!user||user.accountKey!==accountKey||user.authMethod!=='deda_pin_firestore_v1'||!trusted(user,install)||
   !profile||profile.accountKey!==accountKey||!trusted(profile,install)||
   !directory||directory.accountKey!==accountKey||directory.active!==true||
   !credential||credential.accountKey!==accountKey||credential.active!==true)fail('point-session-owner-proof-required');
  return work(tx,accountKey,{uid:token.uid});
 });
}
async function claimPointTierForOwnerSession(options){
 if(!options||typeof options!=='object'||Array.isArray(options)||Object.keys(options).length!==4||
 !['store','auth','idToken','threshold'].every(key=>Object.hasOwn(options,key)))fail('invalid-point-session-request');
 dependencies(options);
 const {store,threshold}=options;
 if(![5000,10000,15000,20000].includes(threshold))fail('point-tier-return-ineligible');
 return forOwnerSession(options,(tx,accountKey)=>{
  // Reuse the EXACT owner-verifying transaction for claim reads and writes.
  const transactionStore={serverTimestamp:()=>store.serverTimestamp(),runTransaction:action=>action(tx)};
  return claimMigratedPointTier({store:transactionStore,accountKey,threshold});
 });
}
async function readMigratedProgressForOwnerSession(options){
 if(!options||typeof options!=='object'||Array.isArray(options)||Object.keys(options).length!==3||
 !['store','auth','idToken'].every(key=>Object.hasOwn(options,key)))fail('invalid-progress-read-request');
 dependencies(options);
 return forOwnerSession(options,async(tx,accountKey)=>{
  const context=await loadMigratedContext(tx,accountKey);
  await requireReviewedActivation(tx,context);
  // No claim, local overwrite, initialization, preferences or reward call.
  return Object.freeze({state:context.state});
 });
}
async function claimReviewedPointTierForOwnerSession(options){
 if(!options||typeof options!=='object'||Array.isArray(options)||Object.keys(options).length!==4||
 !['store','auth','idToken','threshold'].every(key=>Object.hasOwn(options,key)))fail('invalid-point-session-request');
 dependencies(options);
 const {store,threshold}=options;
 if(![5000,10000,15000,20000].includes(threshold))fail('point-tier-return-ineligible');
 return forOwnerSession(options,async(tx,accountKey)=>{
  await requireReviewedActivation(tx,await loadMigratedContext(tx,accountKey));
  const transactionStore={serverTimestamp:()=>store.serverTimestamp(),runTransaction:work=>work(tx)};
  return claimMigratedPointTier({store:transactionStore,accountKey,threshold});
 });
}
module.exports={claimPointTierForOwnerSession,readMigratedProgressForOwnerSession,claimReviewedPointTierForOwnerSession,
 withVerifiedOwnerSession:forOwnerSession};
