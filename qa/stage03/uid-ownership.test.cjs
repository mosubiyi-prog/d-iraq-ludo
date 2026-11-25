'use strict';
const {test,before,after,beforeEach}=require('node:test');
const assert=require('node:assert/strict');
const {readFileSync}=require('node:fs');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,getDocFromServer,setDoc,deleteDoc,collection,getDocs}=require('firebase/firestore');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore,FieldValue}=require('firebase-admin/firestore');
const {DedaTrustedProgressTransactionStore}=require('./reconcile-store.cjs');
const {LAB_UID:uid}=require('./reconcile-core.cjs');
const {project}=require('./uid-ownership-projection.cjs');
const projectId='demo-deda-stage03-uid',base='deda_lab_uid_authority/'+uid,source=base+'/inventorySources/current',view=base+'/inventory/current';
const weekId='2026-10-31',ms=Date.UTC(2026,10,7,3),identifier='@DEDA-QAFIXTURE';
let env,app,db,store;
const client=(id=uid,provider='password')=>env.authenticatedContext(id,{firebase:{sign_in_provider:provider}}).firestore();
const frame=()=>({frameId:'FRAME_03',receipt:{uid,frameId:'FRAME_03',kind:'lab_frame',cost:1000,createdMs:ms},ownership:{uid,frameId:'FRAME_03',receiptId:uid+'_FRAME_03',createdMs:ms}});
const gift=()=>({identifier,grant:{uid,identifier,group:'001',baseColor:'gold',kind:'gifted',grantedMs:ms},acceptance:null});
const prize=()=>({giftId:'deda-weekly-'+weekId+'-'+uid,uid,sourceType:'weekly_league',weekId,amount:250,status:'pending',createdMs:ms,receivedMs:null});
const admin=()=>({giftId:'synthetic-admin-gift',uid,sourceType:'admin',weekId:null,amount:30,status:'pending',createdMs:ms,receivedMs:null});
const fixture=(revision=1)=>({format:1,uid,revision,complete:true,frames:[frame()],idGifts:[gift()],diamondGifts:[prize(),admin()]});
const seed=v=>db.doc(source).set(v);
const apply=()=>project({store,uid});
const read=async()=> (await db.doc(view).get()).data();
before(async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^127\.0\.0\.1:[0-9]+$/);
  assert.equal(process.env.GCLOUD_PROJECT,projectId);
  env=await initializeTestEnvironment({projectId,firestore:{rules:readFileSync('firestore.rules','utf8')}});
  app=initializeApp({projectId},'stage03-ownership-demo');db=getFirestore(app);
  store=new DedaTrustedProgressTransactionStore({db,serverTimestamp:()=>FieldValue.serverTimestamp()});
});
after(async()=>{if(db)await db.terminate();if(app)await deleteApp(app);if(env)await env.cleanup()});
beforeEach(async()=>{await env.clearFirestore()});
test('missing or explicitly incomplete source never yields empty inventory',async()=>{
  await assert.rejects(apply(),{code:'ownership-source-missing'});
  await seed({...fixture(),complete:false});
  await assert.rejects(apply(),{code:'ownership-source-incomplete'});
  assert.equal(await read(),undefined);
});
test('paired frame, pending ID and diamond gifts restored by same UID, no financial credit',async()=>{
  await seed(fixture());const result=await apply();
  assert.equal(result.replayed,false);
  const restored=await assertSucceeds(getDocFromServer(doc(client(),view)));
  assert.deepEqual(restored.data(),result.view);
  assert.equal(restored.data().frames.length,1);assert.equal(restored.data().idGifts[0].acceptance,null);
  assert.equal(restored.data().diamondGifts.every(g=>g.status==='pending'),true);
  assert.equal((await db.doc(base).get()).exists,false);
  assert.equal((await db.doc('deda_verified_progress/'+uid).get()).exists,false);
});
test('wrong owner, unapproved frame and mismatched pair are rejected',async()=>{
  for(const mutate of [v=>v.frames[0].receipt.uid='foreign',v=>v.frames[0].frameId='FRAME_01',
    v=>v.frames[0].ownership.receiptId='bad',v=>v.frames[0].receipt.cost=1]){
    const v=fixture();mutate(v);await seed(v);await assert.rejects(apply());assert.equal(await read(),undefined);
  }
});
test('accepting already granted ID and already issued gifts updates history without payout',async()=>{
  await seed(fixture());await apply();
  const v=fixture(2);v.idGifts[0].acceptance={uid,identifier,group:'001',receivedMs:ms+1};
  for(const g of v.diamondGifts){g.status='received';g.receivedMs=ms+1;}
  await seed(v);await apply();const current=await read();assert.equal(current.idGifts[0].acceptance.receivedMs,ms+1);
  assert.equal(current.diamondGifts.every(g=>g.status==='received'),true);
  assert.equal((await db.doc(base).get()).exists,false);
  const replay=await apply();assert.equal(replay.replayed,true);
  assert.equal((await db.collection(base+'/inventoryHistory').get()).size,2);
  assert.deepEqual(await read(),current);
});
test('duplicate ID or weekly receipt, early prize, changed recipient and forged acceptance denied',async()=>{
  for(const mutate of [v=>v.idGifts.push(gift()),v=>v.diamondGifts.push(prize()),
    v=>v.diamondGifts[0].createdMs=ms-1,v=>v.diamondGifts[0].uid='foreign',
    v=>v.idGifts[0].acceptance={uid:'foreign',identifier,group:'001',receivedMs:ms+1}]){
    const v=fixture();mutate(v);await seed(v);await assert.rejects(apply());assert.equal(await read(),undefined);
  }
});
test('later source cannot remove purchased frames or erase grants, gifts, amounts or acceptance',async()=>{
  const first=fixture();first.idGifts[0].acceptance={uid,identifier,group:'001',receivedMs:ms+1};
  first.diamondGifts[0].status='received';first.diamondGifts[0].receivedMs=ms+1;
  await seed(first);await apply();const old=await read();
  for(const mutate of [v=>v.frames=[],v=>v.idGifts=[],v=>v.idGifts[0].acceptance=null,
    v=>v.diamondGifts=[],v=>v.diamondGifts[0].amount=500,
    v=>{v.diamondGifts[0].status='pending';v.diamondGifts[0].receivedMs=null}]){
    const v=structuredClone(first);v.revision=2;mutate(v);await seed(v);
    await assert.rejects(apply(),{code:'ownership-history-regression'});assert.deepEqual(await read(),old);
  }
});
test('same revision different content and skipped revision fail, competing replay commits once',async()=>{
  await seed(fixture());const a=await Promise.all([apply(),apply()]);assert.equal(a.filter(x=>x.replayed).length,1);
  const bad=fixture();bad.diamondGifts[0].amount=999;await seed(bad);
  await assert.rejects(apply(),{code:'ownership-revision-conflict'});
  await seed(fixture(3));await assert.rejects(apply(),{code:'ownership-revision-conflict'});
  assert.equal((await read()).revision,1);
});
test('client reads only own view and cannot write source, view, history or grant itself anything',async()=>{
  await seed(fixture());await apply();const owner=client();
  await assertSucceeds(getDocFromServer(doc(owner,view)));
  for(const c of [owner,client('foreign'),client(uid,'anonymous'),env.unauthenticatedContext().firestore()]){
    await assertFails(setDoc(doc(c,source),fixture(2)));
    await assertFails(setDoc(doc(c,view),fixture(2)));
    await assertFails(deleteDoc(doc(c,view)));
    await assertFails(setDoc(doc(c,base+'/inventoryHistory/2'),fixture(2)));
    await assertFails(getDocFromServer(doc(c,source)));
    await assertFails(getDocFromServer(doc(c,base+'/inventoryHistory/1')));
    await assertFails(getDocs(collection(c,base,'inventory')));
  }
  for(const c of [client('foreign'),client(uid,'anonymous'),env.unauthenticatedContext().firestore()])await assertFails(getDocFromServer(doc(c,view)));
  assert.equal((await read()).revision,1);
});
