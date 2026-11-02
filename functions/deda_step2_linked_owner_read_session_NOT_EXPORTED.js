'use strict';
// STEP2 / PRIVATE QA ONLY. Same-original UID, password-linked owner read gate.
// No client callable, token creation, PIN checking, restore or wallet writes.
// The 6-digit credential and legacy 100340 writer fence remain release blockers.
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const account=v=>typeof v==='string'&&/^[0-9]{10,16}$/.test(v);
const original=v=>typeof v==='string'&&/^@DEDA-[A-Z0-9]{6}$/.test(v);
const fail=code=>{throw Object.assign(new Error(code),{code});};
const email=accountKey=>accountKey+'@deda-login.invalid';

function linkedToken(token, uid, accountKey){
 return token&&id(token.uid)&&token.uid===uid&&
   token.firebase?.sign_in_provider==='password'&&
   token.email===email(accountKey);
}
/**
 * Restrict to fresh, server-verified same-original UID; never use client
 * accountKey, originalId, name, last-used phone or premium display ID.
 * All reads and downstream work share one Admin transaction and are retried
 * together. Pass ONLY tx.get into the callback to prevent mutations.
 */
async function withLinkedOwnerReadSession({store,auth,idToken},work){
 if(!store||typeof store.readOwnerSession!=='function'||
    typeof store.runTransaction!=='function'||
    !auth||typeof auth.verifyIdToken!=='function'||
    typeof idToken!=='string'||idToken.length<1||
    typeof work!=='function')fail('step2-linked-session-dependencies-missing');
 // Read-only route HINT from server (not authorization). No client account.
 const before=await auth.verifyIdToken(idToken,true);
 if(!before||!id(before.uid)||before.firebase?.sign_in_provider!=='password')
   fail('step2-linked-password-provider-required');
 const hint=await store.readOwnerSession(before.uid);
 const key=hint?.accountKey;
 if(!account(key)||hint.uid!==before.uid||!linkedToken(before,before.uid,key))
   fail('step2-linked-owner-routing-missing');
 return store.runTransaction(async tx=>{
   if(typeof tx?.get!=='function')fail('step2-linked-transaction-required');
   // Recheck the token on each transaction attempt, including revocation.
   const token=await auth.verifyIdToken(idToken,true);
   if(!linkedToken(token,before.uid,key))
     fail('step2-linked-session-changed-or-revoked');
   // Shared lock/read order with financial migration workers.
   await tx.get('deda_progress_migrations/'+key);
   const session=await tx.get('deda_sessions/'+token.uid);
   const directory=await tx.get('deda_account_directory/'+key);
   const credential=await tx.get('deda_credentials/'+key);
   const profile=await tx.get('deda_account_profiles/'+key);
   const user=await tx.get('users/'+token.uid);
   const originalId=user?.sharePersonalId;
   if(!session||session.uid!==token.uid||session.accountKey!==key||
      !directory||directory.accountKey!==key||directory.active!==true||
      directory.createdUid!==token.uid||
      !credential||credential.accountKey!==key||credential.active!==true||
      credential.createdUid!==token.uid||
      !profile||profile.accountKey!==key||
      !['user','placeOwner'].includes(profile.accountType)||
      typeof profile.name!=='string'||profile.name.trim().length<2||
      !user||user.accountKey!==key||!original(originalId))
     fail('step2-linked-owner-documents-conflict');
   const route=await tx.get('deda_share_ids/'+originalId);
   if(!route||route.publicId!==originalId||route.ownerUid!==token.uid||
      route.kind!=='personal'||route.active!==true)
     fail('step2-linked-original-route-mismatch');
   // Sensitive read callback receives no tx.set/update/delete methods.
   // Two fixed owner-scoped Admin queries. The private adapter must construct
   // a Firestore Query with where(field,'==',originalId).limit(201).
   // No client-provided collection/field/owner/limit; no write capability.
   const premiumQueries=Object.freeze({
     grants:Object.freeze(['deda_stage71_granted_registry','recipientOriginalId']),
     receipts:Object.freeze(['deda_stage74_id_gift_receipts','originalId']),
   });
   const listPremiumHistory=async kind=>{
     const spec=premiumQueries[kind];
     if(!spec||typeof store.makeReadOnlyQuery!=='function')
       fail('step2-linked-history-query-unavailable');
     const query=store.makeReadOnlyQuery(spec[0],spec[1],originalId,201);
     if(!query)fail('step2-linked-history-query-unavailable');
     const snap=await tx.get(query);
     if(!snap||!Array.isArray(snap.docs)||
        snap.size!==snap.docs.length||snap.docs.length>200)
       fail('step2-linked-history-unbounded-or-incomplete');
     return Object.freeze(snap.docs.map(doc=>{
       if(!doc||typeof doc.id!=='string'||!id(doc.id)||
          typeof doc.data!=='function')
         fail('step2-linked-history-doc-invalid');
       return Object.freeze({id:doc.id,data:doc.data()});
     }));
   };
   const reader=Object.freeze({get:path=>tx.get(path),listPremiumHistory});
   return work(reader,key,Object.freeze({uid:token.uid,originalId}));
 });
}
module.exports={withLinkedOwnerReadSession};
