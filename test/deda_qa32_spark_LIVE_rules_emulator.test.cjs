'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs=require('node:fs');
const {initializeTestEnvironment,assertFails,assertSucceeds}
  =require('@firebase/rules-unit-testing');
const {doc,getDoc,setDoc,writeBatch,serverTimestamp,Timestamp,
  collection,getDocs}=require('firebase/firestore');

const owner='deda-owner',other='deda-stranger',
      original='@DEDA-AQPYXJ',alias='@DEDA-IRAQI',bad='@DEDA-WRONG';
let env;
async function seed() {
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    const entries=[
      ['users/'+owner,{accountKey:'one-account',sharePersonalId:original}],
      ['deda_sessions/'+owner,{accountKey:'one-account'}],
      ['deda_share_ids/'+original,
        {publicId:original,kind:'personal',active:true,ownerUid:owner}],
      ['deda_stage71_active_identifier/'+original,
        {originalId:original,activeId:alias,updatedAt:Timestamp.now()}],
      ['deda_stage71_granted_registry/'+alias,
        {identifier:alias,recipientOriginalId:original,kind:'gifted',
          group:'001',baseColor:'gold'}],
      ['deda_stage74_id_gift_receipts/'+alias,
        {identifier:alias,originalId:original,group:'001',
          receivedAt:Timestamp.now()}],
    ];
    for(const [id,data] of entries)await setDoc(doc(db,id),data);
  });
}
function batchDocs(db,color='gold') {
  const batch=writeBatch(db);
  batch.set(doc(db,'deda_public_active_aliases',original),
    {originalId:original,activeId:alias,baseColor:color,
      updatedAt:serverTimestamp()});
  batch.set(doc(db,'deda_public_alias_routes',alias),
    {aliasId:alias,originalId:original,baseColor:color,
      updatedAt:serverTimestamp()});
  return batch;
}

test.before(async()=>{
  const rules=fs.readFileSync('/tmp/deda_spark_emulator_rules.rules','utf8');
  env=await initializeTestEnvironment({
    projectId:'deda-spark-qa32-emulator',
    firestore:{rules},
  });
});
test.after(async()=>{if(env)await env.cleanup();});
test.beforeEach(async()=>{
  await env.clearFirestore();
  await seed();
});

test('only the original ID owner can atomically publish a gifted+received premium alias',async()=>{
  const ownerDb=env.authenticatedContext(owner).firestore();
  await assertSucceeds(batchDocs(ownerDb).commit());
  const stranger=env.authenticatedContext(other).firestore();
  const route=await assertSucceeds(getDoc(
    doc(stranger,'deda_public_alias_routes',alias)));
  const active=await assertSucceeds(getDoc(
    doc(stranger,'deda_public_active_aliases',original)));
  assert.equal(route.data().originalId,original);
  assert.equal(active.data().activeId,alias);
  assert.equal(active.data().baseColor,'gold');
  await assertFails(setDoc(doc(stranger,'deda_public_alias_routes',alias),
    {aliasId:alias,originalId:bad,baseColor:'pink',
      updatedAt:serverTimestamp()}));
});

test('same-account forged color, UID or grant without receipt fails closed',async()=>{
  const db=env.authenticatedContext(owner).firestore();
  await assertFails(batchDocs(db,'pink').commit());
  await env.withSecurityRulesDisabled(async ctx=>{
    await setDoc(doc(ctx.firestore(),'deda_stage74_id_gift_receipts',alias),
      {identifier:alias,originalId:bad,group:'001',
        receivedAt:Timestamp.now()});
  });
  await assertFails(batchDocs(db).commit());
});

test('unauthenticated user has no access; authenticated query-list forbidden',async()=>{
  const visitor=env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(visitor,'deda_public_alias_routes',alias)));
  const stranger=env.authenticatedContext(other).firestore();
  await assertFails(getDocs(collection(stranger,'deda_public_alias_routes')));
});

test('owner cannot publish never-selected alias or alias assigned to someone else',async()=>{
  const ownerDb=env.authenticatedContext(owner).firestore();
  await env.withSecurityRulesDisabled(async ctx=>{
    await setDoc(doc(ctx.firestore(),'deda_stage71_active_identifier',original),
      {originalId:original,activeId:bad});
  });
  await assertFails(batchDocs(ownerDb).commit());
});

test('original ID restores safely without fraudulently attributing foil',async()=>{
  await env.withSecurityRulesDisabled(async ctx=>{
    await setDoc(doc(ctx.firestore(),'deda_stage71_active_identifier',original),
      {originalId:original,activeId:original});
  });
  const db=env.authenticatedContext(owner).firestore();
  await assertSucceeds(setDoc(doc(db,'deda_public_active_aliases',original),
    {originalId:original,activeId:original,baseColor:null,
      updatedAt:serverTimestamp()}));
  const docRef=await assertSucceeds(getDoc(
    doc(env.authenticatedContext(other).firestore(),
      'deda_public_active_aliases',original)));
  assert.equal(docRef.data().activeId,original);
  assert.equal(docRef.data().baseColor,null);
});


test('FUTURE self-used ID from group 002 works without special rule per ID',async()=>{
  const future='@DEDA-NEW88', futureOriginal='@DEDA-AB12CD', futureUser='future-owner';
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    await setDoc(doc(db,'users',futureUser),
      {accountKey:'future-account',sharePersonalId:futureOriginal});
    await setDoc(doc(db,'deda_sessions',futureUser),
      {accountKey:'future-account'});
    await setDoc(doc(db,'deda_share_ids',futureOriginal),
      {publicId:futureOriginal,kind:'personal',active:true,ownerUid:futureUser});
    await setDoc(doc(db,'deda_stage71_active_identifier',futureOriginal),
      {originalId:futureOriginal,activeId:future});
    await setDoc(doc(db,'deda_stage71_granted_registry',future),
      {identifier:future,recipientOriginalId:futureOriginal,kind:'self_used',
        group:'002',baseColor:'royal'});
  });
  const db=env.authenticatedContext(futureUser).firestore();
  const tx=writeBatch(db);
  tx.set(doc(db,'deda_public_active_aliases',futureOriginal),
    {originalId:futureOriginal,activeId:future,baseColor:'royal',
      updatedAt:serverTimestamp()});
  tx.set(doc(db,'deda_public_alias_routes',future),
    {aliasId:future,originalId:futureOriginal,baseColor:'royal',
      updatedAt:serverTimestamp()});
  await assertSucceeds(tx.commit());
  const receiver=env.authenticatedContext(other).firestore();
  assert.equal((await assertSucceeds(getDoc(
    doc(receiver,'deda_public_alias_routes',future)))).data().originalId,futureOriginal);
});
