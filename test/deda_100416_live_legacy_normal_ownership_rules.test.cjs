'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,getDoc,setDoc,updateDoc,runTransaction,serverTimestamp,Timestamp}
 =require('firebase/firestore');
const original='@DEDA-AB12CD', uid='legacy-user-100416',
      stranger='stranger-user-100416', premium='@DEDA-IRAKI';
let env;
const user=(db)=>doc(db,'users',uid);
const source=(db)=>doc(db,'deda_stage71_active_identifier',original);
const publicId=(db)=>doc(db,'deda_public_active_aliases',original);

async function seed(hasId=false,hasSelection=false) {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    await setDoc(user(db),{accountKey:'legacy-account', ...(hasId?{sharePersonalId:original}:{})});
    await setDoc(doc(db,'deda_sessions',uid),{accountKey:'legacy-account'});
    await setDoc(doc(db,'deda_share_ids',original),{
      publicId:original,kind:'personal',active:true,ownerUid:uid
    });
    if(hasSelection)await setDoc(source(db),{
      originalId:original,activeId:premium,updatedAt:Timestamp.now()
    });
  });
}
async function sameBatch(db){
  return runTransaction(db,async tx=>{
    const current=await tx.get(user(db));
    const active=await tx.get(source(db));
    if(!current.exists()) throw Error('missing user');
    if(!active.exists()) {
      tx.update(user(db),{sharePersonalId:original});
      tx.set(source(db),{originalId:original,activeId:original,
        updatedAt:serverTimestamp()});
    }
  });
}
async function ownerSafeTwoStep(db){
  // Phase 1: establish immutable owner's public ID field on users/{uid}.
  // All owner+session+route assertions are performed by client before this
  // call; the server's current owner rule independently checks the UID.
  await assertSucceeds(updateDoc(user(db),{sharePersonalId:original}));
  // Phase 2: only create a MISSING normal selection for this same owner.
  const selection=await assertSucceeds(getDoc(source(db)));
  if(!selection.exists()){
    await assertSucceeds(runTransaction(db,async tx=>{
      const snap=await tx.get(source(db));
      if(!snap.exists())tx.set(source(db),{
        originalId:original,activeId:original,
        updatedAt:serverTimestamp()
      });
    }));
  }
  // Phase 3: normal public proof only once server accepts selection.
  await assertSucceeds(setDoc(publicId(db),{
    originalId:original,activeId:original,
    baseColor:null,updatedAt:serverTimestamp()
  }));
}
test.before(async()=>{
  env=await initializeTestEnvironment({
    projectId:'demo-deda-100416-live-rules',
    firestore:{rules:fs.readFileSync(
      '/tmp/deda100416-exact-production.rules','utf8')}
  });
});
test.after(async()=>{if(env)await env.cleanup();});

test('current 100414 SAME transaction rejected on old missing-ID account',async()=>{
  await seed();
  const db=env.authenticatedContext(uid).firestore();
  await assertFails(sameBatch(db));
});
test('strict owner ordered repair allowed by ACTUAL live rules',async()=>{
  await seed();
  const owner=env.authenticatedContext(uid).firestore();
  await ownerSafeTwoStep(owner);
  assert.equal((await getDoc(user(owner))).data().sharePersonalId,original);
  assert.equal((await getDoc(source(owner))).data().activeId,original);
  const other=env.authenticatedContext(stranger).firestore();
  assert.equal((await getDoc(publicId(other))).data().activeId,original);
});
test('stranger cannot backfill profile or create normal active row',async()=>{
  await seed();
  const db=env.authenticatedContext(stranger).firestore();
  await assertFails(updateDoc(user(db),{sharePersonalId:original}));
  await assertFails(setDoc(source(db),{
    originalId:original,activeId:original,updatedAt:serverTimestamp()
  }));
});
test('premium existing selection survives owner normal proof backfill',async()=>{
  await seed(false,true);
  const db=env.authenticatedContext(uid).firestore();
  await assertSucceeds(updateDoc(user(db),{sharePersonalId:original}));
  const before=(await getDoc(source(db))).data();
  assert.equal(before.activeId,premium);
  // Code path must never overwrite an existing selection; the public alias
  // cannot be published as NORMAL unless the source has been reselected.
  await assertFails(setDoc(publicId(db),{
    originalId:original,activeId:original,
    baseColor:null,updatedAt:serverTimestamp()
  }));
  assert.equal((await getDoc(source(db))).data().activeId,premium);
});
