'use strict';
const {test,before,after,beforeEach}=require('node:test');
const assert=require('node:assert/strict');
const {readFileSync}=require('node:fs');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,getDocFromServer,setDoc,deleteDoc,serverTimestamp,collection,getDocs}=require('firebase/firestore');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore,FieldValue}=require('firebase-admin/firestore');
const core=require('./reconcile-core.cjs');
const {reconcileLabReceipt,DedaTrustedProgressTransactionStore}=require('./reconcile-store.cjs');
const uid=core.LAB_UID, projectId='demo-deda-stage03-uid', root='deda_lab_uid_authority/'+uid;
const zero=()=>({points:0,coins:0,xp:0,earnedDiamonds:0});
const baseline='baseline_fixture_000001', award='award_fixture_00000001', debit='debit_fixture_00000001';
const record=(source,sourceId,kind,delta)=>({format:1,accountKey:uid,source,sourceId,kind,delta});
const boot=()=>record('account-bootstrap-v1','synthetic-new-lab','baseline',zero());
const reward=()=>record('task-claim-v1','synthetic-task-one','award',{points:5,coins:10,xp:20,earnedDiamonds:0});
const diamond=()=>record('rewarded-ad-v1','synthetic-ad-one','award',{...zero(),earnedDiamonds:1200});
const spend=()=>record('cosmetic-debit-v1','synthetic-frame-one','spend',{...zero(),earnedDiamonds:-1000});
let env,app,db,store;
const client=(id=uid,provider='password')=>env.authenticatedContext(id,{firebase:{sign_in_provider:provider}}).firestore();
const seed=(id,r)=>db.doc(root+'/receipts/'+id).set(r);
const apply=(id)=>reconcileLabReceipt({store,accountKey:uid,receiptId:id});
const read=async()=> (await db.doc(root).get()).data();
const init=async()=>{await seed(baseline,boot());await apply(baseline)};
before(async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^127\.0\.0\.1:[0-9]+$/);
  assert.equal(process.env.GCLOUD_PROJECT,projectId);
  env=await initializeTestEnvironment({projectId,firestore:{rules:readFileSync('firestore.rules','utf8')}});
  app=initializeApp({projectId},'stage03-demo-authority');
  db=getFirestore(app);
  store=new DedaTrustedProgressTransactionStore({db,serverTimestamp:()=>FieldValue.serverTimestamp()});
});
after(async()=>{if(db)await db.terminate();if(app)await deleteApp(app);if(env)await env.cleanup()});
beforeEach(async()=>{await env.clearFirestore()});
test('legacy default still rejects UID and lab cannot use legacy baseline or a different UID',()=>{
  assert.throws(()=>core.account(uid),{code:'invalid-account'});
  assert.throws(()=>core.account('07700000000','lab-uid'),{code:'invalid-account'});
  assert.throws(()=>core.parseReceipt(record('legacy-baseline-v1','old','baseline',zero()),uid,'lab-uid'),{code:'lab-legacy-baseline-forbidden'});
});
test('missing protected source or missing baseline cannot initialize balances',async()=>{
  await assert.rejects(apply(award),{code:'verified-receipt-missing'});
  await seed(award,reward());
  await assert.rejects(apply(award),{code:'progress-initialization-required'});
  assert.equal(await read(),undefined);
});
test('trusted fixture writes atomic projection and one marker; replay returns current version after debit',async()=>{
  await init();await seed(award,reward());await apply(award);
  await seed('diamond_fixture_000001',diamond());await apply('diamond_fixture_000001');
  await seed(debit,spend());await apply(debit);
  const before=await read();
  assert.equal(before.version,4);assert.deepEqual(before.balances,{points:5,coins:10,xp:20,earnedDiamonds:200});
  const replay=await apply(award);assert.equal(replay.replayed,true);assert.deepEqual(replay.state,before);
  const fresh=await assertSucceeds(getDocFromServer(doc(client(),root)));
  assert.deepEqual(fresh.data(),before);assert.equal(fresh.metadata.fromCache,false);
  assert.equal((await db.collection(root+'/events').get()).size,4);
  assert.equal((await db.doc('deda_verified_progress/'+uid).get()).exists,false);
});
test('two different receipt wrappers cannot double-credit same source; altered amount conflicts',async()=>{
  await init();await seed(award,reward());await seed('other_wrapper_00000001',reward());
  const outcomes=await Promise.all([apply(award),apply('other_wrapper_00000001')]);
  assert.equal(outcomes.filter(x=>x.replayed).length,1);
  await seed('changed_wrapper_000001',record('task-claim-v1','synthetic-task-one','award',{points:500,coins:10,xp:20,earnedDiamonds:0}));
  await assert.rejects(apply('changed_wrapper_000001'),{code:'source-event-conflict'});
  assert.equal((await read()).balances.points,5);
});
test('insufficient debit fails without event or state changes; second baseline cannot reset',async()=>{
  await init();await seed(debit,spend());
  await assert.rejects(apply(debit),{code:'insufficient-earnedDiamonds'});
  await seed('second_baseline_000001',record('account-bootstrap-v1','second','baseline',zero()));
  await assert.rejects(apply('second_baseline_000001'),{code:'baseline-already-initialized'});
  assert.equal((await read()).version,1);assert.equal((await db.collection(root+'/events').get()).size,1);
});
test('client cannot create authority, submit a fake receipt, modify state, delete or read private events',async()=>{
  const owner=client();
  await assertFails(setDoc(doc(owner,root),{balances:{earnedDiamonds:999999}}));
  await assertFails(setDoc(doc(owner,root+'/receipts/'+award),reward()));
  await init();await seed(award,reward());await apply(award);
  for(const c of [owner,client('foreign'),client(uid,'anonymous'),env.unauthenticatedContext().firestore()]){
    await assertFails(setDoc(doc(c,root),{balances:{earnedDiamonds:999999}},{merge:true}));
    await assertFails(deleteDoc(doc(c,root)));
    await assertFails(setDoc(doc(c,root+'/receipts/'+debit),spend()));
    await assertFails(getDocFromServer(doc(c,root+'/receipts/'+award)));
    await assertFails(getDocs(collection(c,root,'events')));
  }
  for(const c of [client('foreign'),client(uid,'anonymous'),env.unauthenticatedContext().firestore()]){
    await assertFails(getDocFromServer(doc(c,root)));
  }
  await assertSucceeds(getDocFromServer(doc(owner,root)));
  assert.equal((await read()).balances.points,5);
});
test('client private payload cannot become a financial source even if it contains fabricated amounts',async()=>{
  await init();
  const id='a'.repeat(48),c=client();
  const data={format:1,uid,version:1,mutationId:id,payload:'{"earnedDiamonds":99999}',updatedAt:serverTimestamp()};
  const {writeBatch}=require('firebase/firestore');
  const b=writeBatch(c);const p='deda_lab_uid_private/'+uid;
  b.set(doc(c,p),data);b.set(doc(c,p+'/versions/'+id),data);await assertSucceeds(b.commit());
  await assert.rejects(apply(award),{code:'verified-receipt-missing'});
  assert.equal((await read()).balances.earnedDiamonds,0);
});
