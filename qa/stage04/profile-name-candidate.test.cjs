'use strict';
const {test,before,after,beforeEach}=require('node:test');
const assert=require('node:assert/strict');
const {readFileSync}=require('node:fs');
const {initializeTestEnvironment,assertSucceeds,assertFails}=require('@firebase/rules-unit-testing');
const {doc,setDoc,deleteDoc,getDocFromServer,writeBatch}=require('firebase/firestore');
const {build,buildAccount,base,uid}=require('../stage03/uid-trusted-fixture.cjs');
const {generateProfileName}=require('./profile-name-candidate.cjs');
const projectId='demo-deda-stage03-uid';
const account=base+'/account/current',source=base+'/accountSources/current',history=base+'/accountHistory/';
const original=buildAccount()[account], rights=build();
let env;
const client=(id=uid,provider='password')=>env.authenticatedContext(id,{firebase:{sign_in_provider:provider}}).firestore();
const renamed=(old,name='Synthetic Name Two')=>({...structuredClone(old),revision:old.revision+1,profile:{...old.profile,displayName:name}});
const write=(db,next,paths=[account,source,history+next.revision])=>{
  const b=writeBatch(db);
  for(const path of paths)b.set(doc(db,path),next);
  return b.commit();
};
const read=async(path)=>{
  let value;
  await env.withSecurityRulesDisabled(async ctx=>{
    value=(await getDocFromServer(doc(ctx.firestore(),path))).data();
  });
  return value;
};
before(async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^127\.0\.0\.1:[0-9]+$/);
  assert.equal(process.env.GCLOUD_PROJECT,projectId);
  env=await initializeTestEnvironment({projectId,firestore:{rules:generateProfileName(readFileSync('original.rules','utf8'))}});
});
after(async()=>{if(env)await env.cleanup()});
beforeEach(async()=>{
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore(),batch=writeBatch(db);
    for(const [path,data] of Object.entries({...rights,...buildAccount()}))batch.set(doc(db,path),data);
    await batch.commit();
  });
});
test('owner name only updates same UID atomically, keeps two revisions and every protected right',async()=>{
  const second=renamed(original,'اسم تجريبي جديد');
  await assertSucceeds(write(client(),second));
  assert.deepEqual((await assertSucceeds(getDocFromServer(doc(client(),account)))).data(),second);
  assert.deepEqual(await read(source),second);
  assert.deepEqual(await read(history+'1'),original);
  assert.deepEqual(await read(history+'2'),second);
  const third=renamed(second,'Synthetic Name Three');
  await assertSucceeds(write(client(),third));
  assert.deepEqual(await read(history+'2'),second);
  assert.deepEqual(await read(history+'3'),third);
  for(const [path,data] of Object.entries(rights))assert.deepEqual(await read(path),data);
  await assertFails(write(client(),second)); // stale client cannot revert
  await assertFails(getDocFromServer(doc(client(),source)));
  await assertFails(getDocFromServer(doc(client(),history+'3')));
});
test('partial, foreign, anonymous, no-op, invalid name and unrelated protected changes are denied',async()=>{
  const c=client(),next=renamed(original);
  for(const paths of [[account],[source],[history+'2'],[account,source],[account,history+'2']])
    await assertFails(write(c,next,paths));
  for(const db of [client('foreign'),client(uid,'anonymous'),env.unauthenticatedContext().firestore()])
    await assertFails(write(db,next));
  for(const name of ['x','  test','test ','<test>','bad\nname','a'.repeat(97),original.profile.displayName])
    await assertFails(write(c,renamed(original,name)));
  const changes=[
    x=>x.uid='foreign',x=>x.profile.originalId='@DEDA-QA9999',
    x=>x.profile.activeId='@DEDA-QA9999',x=>x.profile.fixedColor='gold',
    x=>x.profile.role='admin',x=>x.tasks=[],x=>x.friends=[],x=>x.league=[],
    x=>x.revision=5,x=>x.complete=false,x=>x.wallet=1000000,
  ];
  for(const mutate of changes){const x=renamed(original);mutate(x);await assertFails(write(c,x));}
  await assertFails(write(c,next,[account,source,history+'99']));
  await assertFails(deleteDoc(doc(c,account)));
  await assertFails(setDoc(doc(c,history+'1'),next));
  await assertFails(setDoc(doc(c,base),{...rights[base],balances:{...rights[base].balances,earnedDiamonds:1000000}}));
  assert.deepEqual(await read(account),original);
  assert.deepEqual(await read(source),original);
  assert.equal(await read(history+'2'),undefined);
});
