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
const {project,projectAccount}=require('./uid-ownership-projection.cjs');
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

const acctSource=base+'/accountSources/current',acctView=base+'/account/current';
const other='synthetic-peer-001', original='@DEDA-QA1234',peerId='@DEDA-QA5678';
const claimMs=Date.UTC(2026,10,1,10),claimKey='2026-11-01|open_map';
const accountFixture=(revision=1)=>({format:1,uid,revision,complete:true,
  profile:{displayName:'Synthetic QA',originalId:original,activeId:original,fixedColor:null},
  friends:[{pairKey:[uid,other].sort().join('__'),members:[uid,other],requesterUid:uid,recipientUid:other,
    requesterPublicId:original,recipientPublicId:peerId,requesterName:'Synthetic QA',recipientName:'Synthetic peer',status:'accepted'}],
  tasks:[{claimKey,dayId:'2026-11-01',taskId:'open_map',completedMs:claimMs,claimedMs:claimMs+1}],
  league:[{weekId,claimedKeys:[claimKey],completedTasks:1,weeklyXp:20}]});
const accountSeed=v=>db.doc(acctSource).set(v);
const accountApply=()=>projectAccount({store,uid});
test('complete protected account projection retains actual relationships, task claims and week history under same UID',async()=>{
  await accountSeed(accountFixture());const a=await accountApply();
  assert.equal(a.view.friends[0].recipientUid,other);
  assert.equal(a.view.tasks[0].claimKey,claimKey);
  assert.equal(a.view.league[0].weeklyXp,20);
  assert.deepEqual((await db.doc(acctView).get()).data(),a.view);
  assert.equal((await accountApply()).replayed,true);
  assert.equal((await db.doc(base).get()).exists,false);
  // Candidate only: independent authenticated owner clients restore exact data.
  // This does NOT prove that these rules are published in the live lab.
  for(const c of [client(),client()]){
    assert.deepEqual((await assertSucceeds(getDocFromServer(doc(c,acctView)))).data(),a.view);
    await assertFails(getDocs(collection(c,base,'account')));
    await assertFails(getDocFromServer(doc(c,acctSource)));
    await assertFails(getDocFromServer(doc(c,base+'/accountHistory/1')));
    await assertFails(getDocFromServer(doc(c,'deda_lab_uid_authority/'+other+'/account/current')));
  }
  const unsigned=env.unauthenticatedContext().firestore();
  for(const c of [client(other),client(uid,'anonymous'),unsigned]){
    await assertFails(getDocFromServer(doc(c,acctView)));
  }
  for(const c of [client(),client(other),client(uid,'anonymous'),unsigned]){
    for(const path of [acctSource,acctView,base+'/accountHistory/1']){
      await assertFails(setDoc(doc(c,path),accountFixture()));
      await assertFails(deleteDoc(doc(c,path)));
    }
  }
});
test('missing/foreign/duplicate or unsupported account sources fail closed',async()=>{
  await assert.rejects(accountApply());
  for(const mutate of [v=>v.complete=false,v=>v.uid=other,v=>v.friends[0].members=[other,'alien-uid'],
    v=>v.tasks.push(v.tasks[0]),v=>v.tasks[0].dayId='2026-02-30',
    v=>v.league[0].weeklyXp=200,v=>v.league[0].claimedKeys=['unknown']]){
    const v=accountFixture();mutate(v);await accountSeed(v);await assert.rejects(accountApply());
    assert.equal((await db.doc(acctView).get()).exists,false);
  }
});
test('active premium ID requires matching accepted protected inventory grant',async()=>{
  const v=accountFixture();v.profile.activeId=identifier;v.profile.fixedColor='gold';
  await accountSeed(v);await assert.rejects(accountApply(),{code:'account-active-id-unproven'});
  const inv=fixture();await seed(inv);await apply();await assert.rejects(accountApply(),{code:'account-active-id-unproven'});
  inv.revision=2;inv.idGifts[0].acceptance={uid,identifier,group:'001',receivedMs:ms+1};
  await seed(inv);await apply();assert.equal((await accountApply()).view.profile.activeId,identifier);
});
test('task claim history and weekly history cannot regress or reassign original ID',async()=>{
  await accountSeed(accountFixture());await accountApply();
  for(const mutate of [v=>{v.tasks=[];v.league=[];},v=>v.league=[],
    v=>{v.tasks[0].claimedMs=null;v.league=[];},
    v=>{v.profile.originalId='@DEDA-OTHER1';v.profile.activeId=v.profile.originalId;v.friends=[];}]){
    const v=accountFixture(2);mutate(v);await accountSeed(v);await assert.rejects(accountApply());
    assert.equal((await db.doc(acctView).get()).data().revision,1);
  }
});

test('separate exact live account candidate only permits atomic fixed synthetic snapshot',async()=>{
  const {generateAccount}=require('./uid-spark-fixture-rules.cjs');
  const {buildAccount,build}=require('./uid-trusted-fixture.cjs');
  const {writeBatch}=require('firebase/firestore');
  const local=await initializeTestEnvironment({projectId,firestore:{rules:generateAccount(readFileSync('firestore.rules','utf8'))}});
  try{
    await local.clearFirestore();
    const owner=local.authenticatedContext(uid,{firebase:{sign_in_provider:'password'}}).firestore();
    const foreign=local.authenticatedContext(other,{firebase:{sign_in_provider:'password'}}).firestore();
    const docs=buildAccount();
    const save=(db,rows)=>{const batch=writeBatch(db);for(const [p,v] of Object.entries(rows))batch.set(doc(db,p),v);return batch.commit();};
    await assertFails(save(owner,{[acctView]:docs[acctView]}));
    const bad=structuredClone(docs);bad[acctView].league[0].weeklyXp=200;
    await assertFails(save(owner,bad));await assertFails(save(foreign,docs));
    await assertFails(save(owner,build()));
    await assertSucceeds(save(owner,docs));
    const second=local.authenticatedContext(uid,{firebase:{sign_in_provider:'password'}}).firestore();
    assert.deepEqual((await assertSucceeds(getDocFromServer(doc(second,acctView)))).data(),docs[acctView]);
    await assertFails(save(owner,docs));
    await assertFails(deleteDoc(doc(owner,acctView)));
    await assertFails(getDocFromServer(doc(owner,acctSource)));
    await assertFails(getDocFromServer(doc(owner,base+'/accountHistory/1')));
    await assertFails(getDocFromServer(doc(foreign,acctView)));
  }finally{await local.cleanup();}
});

test('exact account candidate preserves locked progress and inventory and contains no update/delete grant',()=>{
  const {generateAccount}=require('./uid-spark-fixture-rules.cjs');
  const original=require('node:fs').readFileSync('firestore.rules','utf8');
  const rules=generateAccount(original);
  const start=original.indexOf('      match /account/current');
  assert.ok(start>0);assert.equal(rules.slice(0,start),original.slice(0,start));
  assert.equal((rules.match(/allow create: if owner\(uid\) && request.resource.data ==/g)||[]).length,3);
  assert.equal((rules.slice(start).match(/allow list, update, delete: if false;/g)||[]).length,3);
  assert.ok(!rules.includes('DEDA_STAGE03_SYNTHETIC_ONLY'));
  require('node:fs').writeFileSync('account-fixed-candidate.rules',rules);
});
