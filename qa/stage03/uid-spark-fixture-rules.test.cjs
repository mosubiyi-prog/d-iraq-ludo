'use strict';
const {test,before,after,beforeEach}=require('node:test');
const assert=require('node:assert/strict');
const {readFileSync}=require('node:fs');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,setDoc,deleteDoc,getDocFromServer,writeBatch,serverTimestamp}=require('firebase/firestore');
const {build,base,uid}=require('./uid-trusted-fixture.cjs');
const {marker,markerPath}=require('./uid-spark-fixture-rules.cjs');
const projectId='demo-deda-stage03-uid',view=base+'/inventory/current',docs=build();
let env;
const client=(id=uid,provider='password')=>env.authenticatedContext(id,{firebase:{sign_in_provider:provider}}).firestore();
const seed=async(value=marker)=>env.withSecurityRulesDisabled(async c=>setDoc(doc(c.firestore(),markerPath),value));
const serverRead=async(path)=>{
  let snapshot;
  await env.withSecurityRulesDisabled(async c=>{snapshot=await getDocFromServer(doc(c.firestore(),path));});
  assert.ok(snapshot,'privileged emulator read must return a snapshot');
  return snapshot;
};
const batch=(db,entries=docs)=>{
  const b=writeBatch(db);
  for(const [p,d] of Object.entries(entries))b.set(doc(db,p),p.startsWith(base+'/events/')?{...d,createdAt:serverTimestamp()}:d);
  return b.commit();
};
before(async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^127\.0\.0\.1:[0-9]+$/);
  assert.equal(process.env.GCLOUD_PROJECT,projectId);
  env=await initializeTestEnvironment({projectId,firestore:{rules:readFileSync('firestore.rules','utf8')}});
});
after(async()=>{if(env)await env.cleanup()});
beforeEach(async()=>env.clearFirestore());
test('untrusted client cannot authorize or create any fixture without protected marker',async()=>{
  const c=client();await assertFails(setDoc(doc(c,markerPath),marker));
  await assertFails(batch(c));await assertFails(getDocFromServer(doc(c,markerPath)));
  assert.equal((await serverRead(base)).exists(),false);
  await seed({...marker,purpose:'wrong'});await assertFails(batch(c));
});
test('authorized exact atomic fixture restores both projections on independent sessions, no replay writes',async()=>{
  await seed();assert.equal((await serverRead(base)).exists(),false);
  await assertSucceeds(batch(client()));
  for(const [p,d] of Object.entries(docs)){
    const s=await serverRead(p);assert.equal(s.exists(),true);
    const value=s.data();
    if(p.startsWith(base+'/events/')){assert.equal(typeof value.createdAt.toMillis,'function');delete value.createdAt;}
    assert.deepEqual(value,d);
  }
  const c=client(),second=client();
  for(const p of [base,view]){
    assert.deepEqual((await assertSucceeds(getDocFromServer(doc(c,p)))).data(),docs[p]);
    assert.deepEqual((await assertSucceeds(getDocFromServer(doc(second,p)))).data(),docs[p]);
  }
  await assertFails(batch(second));
  await assertFails(deleteDoc(doc(c,base)));
  await assertFails(setDoc(doc(c,base),{...docs[base],version:5}));
  await assertFails(setDoc(doc(c,view),{...docs[view],revision:2}));
});
test('partial transaction, omitted receipt, altered amount or wrong user cannot write',async()=>{
  await seed();const c=client();
  await assertFails(batch(c,{[base]:docs[base]}));
  const missing={...docs};delete missing[Object.keys(missing).find(p=>p.includes('/receipts/'))];
  await assertFails(batch(c,missing));
  const changed=structuredClone(docs);changed[base].balances.earnedDiamonds+=1;
  await assertFails(batch(c,changed));
  const gift=structuredClone(docs);gift[view].diamondGifts[0].amount+=1;
  await assertFails(batch(c,gift));
  for(const other of [client('foreign'),client(uid,'anonymous'),env.unauthenticatedContext().firestore()])await assertFails(batch(other));
  for(const p of Object.keys(docs))assert.equal((await serverRead(p)).exists(),false);
});
test('authorization and protected source history stay inaccessible even to pinned user',async()=>{
  await seed();await assertSucceeds(batch(client()));const c=client();
  for(const p of [markerPath,...Object.keys(docs).filter(p=>p!==base&&p!==view)]){
    await assertFails(getDocFromServer(doc(c,p)));
    await assertFails(deleteDoc(doc(c,p)));
  }
  for(const other of [client('foreign'),client(uid,'anonymous'),env.unauthenticatedContext().firestore()]){
    await assertFails(getDocFromServer(doc(other,base)));
    await assertFails(getDocFromServer(doc(other,view)));
  }
});
