'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {initializeTestEnvironment,assertFails,assertSucceeds}
 =require('@firebase/rules-unit-testing');
const {doc,getDoc,getDocs,setDoc,updateDoc,collection,serverTimestamp,Timestamp}
 =require('firebase/firestore');
const old='@DEDA-AB12CD', alias='@DEDA-IRAQI', normal='@DEDA-ZZABCD';
const owner='owner-340', stranger='viewer-414';
let env;
test.before(async()=>{
  env=await initializeTestEnvironment({projectId:'demo-deda-100418-legacy340',
    firestore:{rules:fs.readFileSync('/tmp/deda100418-current-rule-candidate.rules','utf8')}});
});
test.after(async()=>{if(env)await env.cleanup()});
async function setup(){
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    for(const [id,u] of [[old,owner],[normal,'owner-normal']]){
      await setDoc(doc(db,'deda_share_ids',id),{publicId:id,ownerUid:u,kind:'personal',active:true});
      await setDoc(doc(db,'users',u),{accountKey:'acct-'+u,sharePersonalId:id});
      await setDoc(doc(db,'deda_sessions',u),{accountKey:'acct-'+u});
    }
    // Previous canonical user activated a premium; legacy 340 device
    // has never published deda_public_active_aliases.
    await setDoc(doc(db,'deda_stage71_active_identifier',old),{
      originalId:old,activeId:alias,updatedAt:Timestamp.now()});
    await setDoc(doc(db,'deda_stage71_granted_registry',alias),{
      identifier:alias,recipientOriginalId:old,baseColor:'gold',
      kind:'self_used',group:'001'});
  });
}
test.beforeEach(setup);
test('100340 OLD user with no public alias exposes active PREM id, never retired original',async()=>{
  const viewer=env.authenticatedContext(stranger).firestore();
  const missing=await assertSucceeds(getDoc(doc(viewer,'deda_public_active_aliases',old)));
  assert.equal(missing.exists(),false);
  const active=await assertSucceeds(getDoc(doc(viewer,'deda_stage71_active_identifier',old)));
  assert.equal(active.data().activeId,alias);
  assert.notEqual(active.data().activeId,old);
});
test('legacy user without Stage71 row is a confirmed NORMAL selection after route proof',async()=>{
  const viewer=env.authenticatedContext(stranger).firestore();
  const route=await assertSucceeds(getDoc(doc(viewer,'deda_share_ids',normal)));
  assert.equal(route.data().kind,'personal');
  assert.equal(route.data().active,true);
  const active=await assertSucceeds(getDoc(doc(viewer,'deda_stage71_active_identifier',normal)));
  assert.equal(active.exists(),false);
});
test('anonymous, missing route and list never disclose active selections',async()=>{
  const anonymous=env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anonymous,'deda_stage71_active_identifier',old)));
  const viewer=env.authenticatedContext(stranger).firestore();
  await assertFails(getDocs(collection(viewer,'deda_stage71_active_identifier')));
  await assertFails(getDoc(doc(viewer,'deda_stage71_active_identifier','@DEDA-NOOWNR')));
  await assertFails(getDoc(doc(viewer,'deda_stage71_granted_registry',alias)));
});
test('public active GET does NOT enable creating or changing someone else selection',async()=>{
  const viewer=env.authenticatedContext(stranger).firestore();
  await assertFails(updateDoc(doc(viewer,'deda_stage71_active_identifier',old),
      {activeId:old,updatedAt:serverTimestamp()}));
  await assertFails(setDoc(doc(viewer,'deda_stage71_active_identifier',normal),{
    originalId:normal,activeId:normal,updatedAt:serverTimestamp()}));
  const still=await assertSucceeds(getDoc(doc(viewer,'deda_stage71_active_identifier',old)));
  assert.equal(still.data().activeId,alias);
});
test('legitimate original owner retains ability to update own active selection',async()=>{
  const db=env.authenticatedContext(owner).firestore();
  await assertSucceeds(updateDoc(doc(db,'deda_stage71_active_identifier',old),{
    activeId:old,updatedAt:serverTimestamp()}));
  const verifier=env.authenticatedContext(stranger).firestore();
  assert.equal((await assertSucceeds(getDoc(
      doc(verifier,'deda_stage71_active_identifier',old)))).data().activeId,old);
});
test('malformed legacy record with additional private fields is never exposed',async()=>{
  await env.withSecurityRulesDisabled(async ctx=>{
    await setDoc(doc(ctx.firestore(),'deda_stage71_active_identifier',old),{
      originalId:old,activeId:alias,privateClaim:'confidential',updatedAt:Timestamp.now()});
  });
  const viewer=env.authenticatedContext(stranger).firestore();
  await assertFails(getDoc(doc(viewer,'deda_stage71_active_identifier',old)));
});
