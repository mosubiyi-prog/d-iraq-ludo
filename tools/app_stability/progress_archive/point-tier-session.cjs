'use strict';
// INTERNAL, UNDEPLOYED session adapter; no HTTP/callable export or activation.
// Auth is the trusted Admin SDK, not a caller-supplied decoded-token payload.
const {claimMigratedPointTier}=require('./point-tier-claim.cjs');
function fail(code){throw Object.assign(new Error(code),{code});}
const validId=value=>typeof value==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(value);
const trusted=(record,install)=>Array.isArray(record?.trustedInstallIds)&&
 record.trustedInstallIds.every(value=>typeof value==='string')&&record.trustedInstallIds.includes(install);
async function claimPointTierForOwnerSession(options){
 if(!options||typeof options!=='object'||Array.isArray(options)||Object.keys(options).length!==4||
 !['store','auth','idToken','threshold'].every(key=>Object.hasOwn(options,key)))fail('invalid-point-session-request');
 const {store,auth,idToken,threshold}=options;
 if(!store||typeof store.runTransaction!=='function'||typeof store.serverTimestamp!=='function'||typeof store.readOwnerSession!=='function'||
 !auth||typeof auth.verifyIdToken!=='function'||typeof idToken!=='string'||!idToken.length)fail('invalid-point-session-dependencies');
 if(![5000,10000,15000,20000].includes(threshold))fail('point-tier-return-ineligible');
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
  // Reuse this EXACT transaction for claim proof, reads and five writes.
  // There is no preliminary committed authorization or nested SDK transaction.
  const transactionStore={serverTimestamp:()=>store.serverTimestamp(),runTransaction:action=>action(tx)};
  return claimMigratedPointTier({store:transactionStore,accountKey,threshold});
 });
}
module.exports={claimPointTierForOwnerSession};
