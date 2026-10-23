'use strict';
const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDocFromServer,deleteDoc,collection,getDocs,serverTimestamp}=require('firebase/firestore');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore,FieldValue}=require('firebase-admin/firestore');
const {reconcileVerifiedReceipt,DedaTrustedProgressTransactionStore}=require('./reconcile-store.cjs');
const core=require('./reconcile-core.cjs');
const {reconcileMigratedReceipt}=require('./migration-gate.cjs');
const account='07700000000',otherAccount='07700000001';
const zero=()=>({points:0,coins:0,xp:0,earnedDiamonds:0});
const baselineId='baseline_receipt_00000001',awardId='award_receipt_0000000001',debitId='debit_receipt_0000000001';
const baseline=()=>({format:1,accountKey:account,source:'legacy-baseline-v1',sourceId:'approved-legacy-fixture',kind:'baseline',delta:{points:5000,coins:30,xp:3020,earnedDiamonds:9}});
const award=(sourceId='day|task')=>({format:1,accountKey:account,source:'task-claim-v1',sourceId,kind:'award',delta:{points:5,coins:10,xp:20,earnedDiamonds:0}});
const debit=(sourceId='fixture-debit')=>({format:1,accountKey:account,source:'cosmetic-debit-v1',sourceId,kind:'spend',delta:{...zero(),coins:-20}});
const statePath=`deda_verified_progress/${account}`;
let env,app,db,store;
const client=uid=>env.authenticatedContext(uid).firestore();
const seed=async(id,data)=>db.doc(`deda_progress_receipts/${account}/events/${id}`).set(data);
const apply=id=>reconcileVerifiedReceipt({store,accountKey:account,receiptId:id});
const state=async()=> (await db.doc(statePath).get()).data();
const events=async()=> (await db.collection(`${statePath}/events`).get()).docs;
async function initialize(){await seed(baselineId,baseline());await apply(baselineId);}
test.before(async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^(127\.0\.0\.1|localhost):[0-9]+$/);
  const projectId='demo-deda-progress-archive';
  env=await initializeTestEnvironment({projectId,firestore:{rules:fs.readFileSync(path.join(__dirname,'firestore.rules'),'utf8')}});
  app=initializeApp({projectId},'isolated-progress-reconcile');db=getFirestore(app);
  store=new DedaTrustedProgressTransactionStore({db,serverTimestamp:()=>FieldValue.serverTimestamp()});
});
test.after(async()=>{if(db)await db.terminate();if(app)await deleteApp(app);if(env)await env.cleanup();});
test.beforeEach(async()=>{
  await env.clearFirestore();
  for(const [uid,key,install]of [['old-device',account,'old-install'],['new-device',account,'new-install'],['other-device',otherAccount,'other-install']]){
    await db.doc(`deda_sessions/${uid}`).set({uid,accountKey:key,installId:install});
    await db.doc(`users/${uid}`).set({accountKey:key});
  }
});
test('trusted Admin transaction commits approved baseline and marker together',async()=>{
  await initialize();assert.deepEqual((await state()).balances,baseline().delta);
  assert.equal((await state()).version,1);assert.equal((await events()).length,1);
});
test('new UID and install read SAME verified progress and XP without resetting it',async()=>{
  await initialize();const snap=await assertSucceeds(getDocFromServer(doc(client('new-device'),statePath)));
  assert.equal(snap.data().balances.coins,30);assert.equal(snap.data().balances.xp,3020);
});
for(const who of ['unauthenticated','other-device'])test(`${who} cannot read the private progress projection`,async()=>{
  await initialize();const c=who==='unauthenticated'?env.unauthenticatedContext().firestore():client(who);
  await assertFails(getDocFromServer(doc(c,statePath)));
});
test('owner cannot enumerate the parent collection across account keys',async()=>{
  await initialize();await assertFails(getDocs(collection(client('old-device'),'deda_verified_progress')));
});
for(const operation of ['create','update','delete'])test(`owner cannot ${operation} server-authoritative projection`,async()=>{
  if(operation!=='create')await initialize();const ref=doc(client('old-device'),statePath);
  if(operation==='delete')await assertFails(deleteDoc(ref));else await assertFails(setDoc(ref,{format:1,accountKey:account,balances:{...zero(),coins:999999}}));
});
test('owner cannot manufacture a trusted receipt from local evidence',async()=>{
  await assertFails(setDoc(doc(client('old-device'),`deda_progress_receipts/${account}/events/${baselineId}`),baseline()));
  await assert.rejects(apply(baselineId),e=>e.code==='verified-receipt-missing');assert.equal(await state(),undefined);
});
test('raw archive can be kept without becoming a trusted receipt or balance',async()=>{
  const captureId='capture_evidence_00000001';
  await assertSucceeds(setDoc(doc(client('old-device'),`deda_progress_evidence/${account}/captures/${captureId}`),{
    format:1,kind:'legacy-local-evidence',accountKey:account,sourceUid:'old-device',installId:'old-install',captureId,
    records:{taskPoints:'{"balance":999999}',socialCoinsAndXp:'{"coins":999999}',earnedDiamonds:null},createdAt:serverTimestamp()}));
  await assert.rejects(apply(captureId),e=>e.code==='verified-receipt-missing');assert.equal(await state(),undefined);
});
test('trusted receipt details are not readable by clients',async()=>{
  await initialize();await assertFails(getDocFromServer(doc(client('old-device'),`deda_progress_receipts/${account}/events/${baselineId}`)));
});
for(const operation of ['set','delete'])test(`owner cannot ${operation} the applied event marker`,async()=>{
  await initialize();const key=core.eventKey(core.parseReceipt(baseline(),account));const ref=doc(client('old-device'),`${statePath}/events/${key}`);
  if(operation==='delete')await assertFails(deleteDoc(ref));else await assertFails(setDoc(ref,{appliedVersion:0}));
});
test('replaying an old award after a debit returns current state without resurrecting spent coins',async()=>{
  await initialize();await seed(awardId,award());await seed(debitId,debit());await apply(awardId);await apply(debitId);
  const replay=await apply(awardId);assert.equal(replay.replayed,true);assert.equal(replay.state.balances.coins,20);
  assert.equal(replay.state.version,3);assert.equal((await events()).length,3);
});
test('concurrent receipt wrappers for SAME source event award once',async()=>{
  await initialize();const wrapper='second_wrapper_00000001';await seed(awardId,award());await seed(wrapper,award());
  const results=await Promise.all([apply(awardId),apply(wrapper)]);
  assert.equal(results.filter(r=>r.replayed).length,1);assert.equal((await state()).balances.coins,40);
  assert.equal((await state()).version,2);assert.equal((await events()).length,2);
});
test('concurrent different awards preserve both changes and monotonic versions',async()=>{
  await initialize();const second='second_award_0000000001';await seed(awardId,award('task-one'));await seed(second,award('task-two'));
  await Promise.all([apply(awardId),apply(second)]);assert.equal((await state()).balances.coins,50);assert.equal((await state()).version,3);
});
test('two devices cannot both spend the same last coins',async()=>{
  await initialize();const second='second_debit_0000000001';await seed(debitId,debit('one'));await seed(second,debit('two'));
  const outcomes=await Promise.allSettled([apply(debitId),apply(second)]);
  assert.equal(outcomes.filter(r=>r.status==='fulfilled').length,1);
  assert.equal(outcomes.filter(r=>r.status==='rejected'&&r.reason.code==='insufficient-coins').length,1);
  assert.equal((await state()).balances.coins,10);assert.equal((await state()).version,2);assert.equal((await events()).length,2);
});
test('multi-currency insufficient spend changes neither balance nor applied marker',async()=>{
  await initialize();await seed(debitId,{...debit(),delta:{...zero(),coins:-20,earnedDiamonds:-10}});
  await assert.rejects(apply(debitId),e=>e.code==='insufficient-earnedDiamonds');
  assert.deepEqual((await state()).balances,baseline().delta);assert.equal((await events()).length,1);
});
test('conflicting amount under an already applied source identity fails closed',async()=>{
  await initialize();await seed(awardId,award());await apply(awardId);const duplicate='conflicting_wrapper_00001';
  await seed(duplicate,{...award(),delta:{...award().delta,coins:99999}});
  await assert.rejects(apply(duplicate),e=>e.code==='source-event-conflict');
  assert.equal((await state()).balances.coins,40);assert.equal((await events()).length,2);
});
test('award before explicit initialization does not invent an empty baseline',async()=>{
  await seed(awardId,award());await assert.rejects(apply(awardId),e=>e.code==='progress-initialization-required');
  assert.equal(await state(),undefined);assert.equal((await events()).length,0);
});
test('second legacy baseline cannot overwrite newer progress even with a new source ID',async()=>{
  await initialize();const second='second_baseline_00000001';await seed(second,{...baseline(),sourceId:'new-review',delta:{...baseline().delta,coins:99999}});
  await assert.rejects(apply(second),e=>e.code==='baseline-already-initialized');assert.equal((await state()).balances.coins,30);
});
test('corrupt server state is rejected without clamping or replacing it with zero',async()=>{
  await initialize();await db.doc(statePath).update({'balances.coins':-1});await seed(awardId,award());
  await assert.rejects(apply(awardId),e=>e.code==='invalid-amount');assert.equal((await state()).balances.coins,-1);
  assert.equal((await events()).length,1);
});
test('new projection never credits, debits or merges the existing wallet namespaces',async()=>{
  const wallets=['deda_diamond_gift_balances','deda_gm_personal_diamond_wallets','deda_admin_diamond_wallets'];
  for(const name of wallets)await db.doc(`${name}/${account}`).set({balance:12345});
  await initialize();await seed(awardId,award());await apply(awardId);
  for(const name of wallets)assert.deepEqual((await db.doc(`${name}/${account}`).get()).data(),{balance:12345});
});
test('event history belongs to the account on new device, never another account',async()=>{
  await initialize();const c=client('new-device');
  assert.equal((await assertSucceeds(getDocs(collection(c,`${statePath}/events`)))).size,1);
  await assertFails(getDocs(collection(client('other-device'),`${statePath}/events`)));
});

// Migration approvals below are ADMIN TEST FIXTURES, not real legacy audits,
// provider proofs or actual fencing of writers in older APKs.
const migrationRoot=`deda_progress_migrations/${account}`;
async function migrationFixture(disposition='included-in-baseline'){
  await initialize();await seed(awardId,award());
  const migration={format:1,accountKey:account,migrationId:'migration_fixture_000001',phase:'cutover-complete',
    evidenceDigest:'a'.repeat(64),baselineEventKey:core.eventKey(baseline()),settlementId:'settlement_fixture_000001'};
  await db.doc(migrationRoot).set(migration);
  await db.doc(`${migrationRoot}/settlements/${migration.settlementId}`).set({format:1,accountKey:account,
    migrationId:migration.migrationId,evidenceDigest:migration.evidenceDigest,baselineEventKey:migration.baselineEventKey,
    legacyFenceId:'legacy_fence_fixture_0001',pendingPurchases:0,pendingReservations:0});
  await db.doc(`${migrationRoot}/classifications/${core.eventKey(award())}`).set({format:1,accountKey:account,
    migrationId:migration.migrationId,evidenceDigest:migration.evidenceDigest,disposition,receipt:award()});
}
const applyMigrated=id=>reconcileMigratedReceipt({store,accountKey:account,receiptId:id});
test('migration included award is not credited twice through concurrent wrappers',async()=>{
  await migrationFixture();const second='migration_wrapper_0000001';await seed(second,award());
  const result=await Promise.all([applyMigrated(awardId),applyMigrated(second)]);
  assert.ok(result.every(r=>r.includedInBaseline));assert.deepEqual((await state()).balances,baseline().delta);
  assert.equal((await state()).version,1);assert.equal((await events()).length,1);
});
test('migration post-cutover award remains exactly once in real Admin transactions',async()=>{
  await migrationFixture('after-cutover');const second='migration_wrapper_0000001';await seed(second,award());
  const result=await Promise.all([applyMigrated(awardId),applyMigrated(second)]);
  assert.equal(result.filter(r=>r.replayed).length,1);assert.equal((await state()).balances.coins,40);
  assert.equal((await state()).version,2);assert.equal((await events()).length,2);
});
test('migration unknown classification leaves balances and history unchanged',async()=>{
  await migrationFixture();await db.doc(`${migrationRoot}/classifications/${core.eventKey(award())}`).delete();
  await assert.rejects(applyMigrated(awardId),e=>e.code==='migration-classification-required');
  assert.deepEqual((await state()).balances,baseline().delta);assert.equal((await events()).length,1);
});
test('migration pending cutover cannot credit even a verified fixture receipt',async()=>{
  await migrationFixture();await db.doc(migrationRoot).update({phase:'baseline-approved'});
  await assert.rejects(applyMigrated(awardId),e=>e.code==='migration-pending');assert.equal((await state()).version,1);
});
test('migration unsettled purchase blocks credit without any partial marker',async()=>{
  await migrationFixture();await db.doc(`${migrationRoot}/settlements/settlement_fixture_000001`).update({pendingPurchases:1});
  await assert.rejects(applyMigrated(awardId),e=>e.code==='migration-not-settled');assert.equal((await events()).length,1);
});
test('migration same event with different amount cannot reuse old review',async()=>{
  await migrationFixture('after-cutover');await seed(awardId,{...award(),delta:{...award().delta,coins:9999}});
  await assert.rejects(applyMigrated(awardId),e=>e.code==='migration-classification-conflict');assert.equal((await state()).version,1);
});
test('migration included historical debit is not deducted a second time',async()=>{
  await migrationFixture();await seed(debitId,debit('already-settled-purchase'));
  await db.doc(`${migrationRoot}/classifications/${core.eventKey(debit('already-settled-purchase'))}`).set({
    format:1,accountKey:account,migrationId:'migration_fixture_000001',evidenceDigest:'a'.repeat(64),
    disposition:'included-in-baseline',receipt:debit('already-settled-purchase')});
  assert.equal((await applyMigrated(debitId)).includedInBaseline,true);
  assert.equal((await state()).balances.coins,30);assert.equal((await state()).version,1);
});
test('new device reads the current balance after migrated award and spending',async()=>{
  await migrationFixture('after-cutover');await applyMigrated(awardId);await seed(debitId,debit());
  await db.doc(`${migrationRoot}/classifications/${core.eventKey(debit())}`).set({
    format:1,accountKey:account,migrationId:'migration_fixture_000001',evidenceDigest:'a'.repeat(64),
    disposition:'after-cutover',receipt:debit()});
  await applyMigrated(debitId);await applyMigrated(awardId);
  const snapshot=await assertSucceeds(getDocFromServer(doc(client('new-device'),statePath)));
  assert.equal(snapshot.data().balances.coins,20);assert.equal(snapshot.data().version,3);
});
for(const path of [migrationRoot,`${migrationRoot}/classifications/${core.eventKey(award())}`,`${migrationRoot}/settlements/settlement_fixture_000001`]){
  test(`client cannot read or manufacture protected migration document ${path.split('/').at(-1)}`,async()=>{
    await migrationFixture();const ref=doc(client('new-device'),path);
    await assertFails(getDocFromServer(ref));await assertFails(setDoc(ref,{verified:true,phase:'cutover-complete'}));
    await assertFails(deleteDoc(ref));
  });
}
