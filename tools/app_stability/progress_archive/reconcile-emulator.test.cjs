'use strict';
const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDocFromServer,deleteDoc,collection,getDocs,serverTimestamp}=require('firebase/firestore');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getAuth}=require('firebase-admin/auth');
const {approveLegacyBaseline,policyPath}=require('./baseline-review.cjs');
const {getFirestore,FieldValue}=require('firebase-admin/firestore');
const {reconcileVerifiedReceipt,DedaTrustedProgressTransactionStore}=require('./reconcile-store.cjs');
const core=require('./reconcile-core.cjs');
const {reconcileMigratedReceipt}=require('./migration-gate.cjs');
const {assessLegacyEvidence}=require('./legacy-assessment.cjs');
const {saveMigrationAssessment}=require('./migration-assessment-store.cjs');
const account='07700000000',otherAccount='07700000001';
const zero=()=>({points:0,coins:0,xp:0,earnedDiamonds:0});
const baselineId='baseline_receipt_00000001',awardId='award_receipt_0000000001',debitId='debit_receipt_0000000001';
const baseline=()=>({format:1,accountKey:account,source:'legacy-baseline-v1',sourceId:'approved-legacy-fixture',kind:'baseline',delta:{points:5000,coins:30,xp:3020,earnedDiamonds:9}});
const award=(sourceId='day|task')=>({format:1,accountKey:account,source:'task-claim-v1',sourceId,kind:'award',delta:{points:5,coins:10,xp:20,earnedDiamonds:0}});
const debit=(sourceId='fixture-debit')=>({format:1,accountKey:account,source:'cosmetic-debit-v1',sourceId,kind:'spend',delta:{...zero(),coins:-20}});
const statePath=`deda_verified_progress/${account}`;
let env,app,db,store,adminAuth,reviewManager,reviewOrdinary,reviewAnonymous;
async function authFixture(email){
 const host=process.env.FIREBASE_AUTH_EMULATOR_HOST;
 assert.match(host||'',/^(127\.0\.0\.1|localhost):[0-9]+$/);
 const response=await fetch(`http://${host}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=isolated-demo-key`,{
 method:'POST',headers:{'content-type':'application/json'},
 body:JSON.stringify(email?{email,password:'emulator-only-password-9!',returnSecureToken:true}:{returnSecureToken:true})});
 const data=await response.json();assert.equal(response.ok,true,JSON.stringify(data));
 assert.equal(typeof data.idToken,'string');return {uid:data.localId,idToken:data.idToken,email};
}
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
  adminAuth=getAuth(app);
  reviewManager=await authFixture('review-manager@example.test');
  reviewOrdinary=await authFixture('ordinary-user@example.test');
  reviewAnonymous=await authFixture(null);
});
test.after(async()=>{if(db)await db.terminate();if(app)await deleteApp(app);if(env)await env.cleanup();});
test.beforeEach(async()=>{
  await env.clearFirestore();
  for(const [uid,key,install]of [['old-device',account,'old-install'],['new-device',account,'new-install'],['other-device',otherAccount,'other-install']]){
    await db.doc(`deda_sessions/${uid}`).set({uid,accountKey:key,installId:install});
    await db.doc(`users/${uid}`).set({accountKey:key});
  }
});
const assessmentCaptureId='legacy_capture_review_00001',assessmentMigrationId='migration_review_00000001';
const assessmentSource=`deda_progress_evidence/${account}/captures/${assessmentCaptureId}`;
const assessmentRoot=`deda_progress_migrations/${account}`;
const assessmentPath=`${assessmentRoot}/reviews/${assessmentMigrationId}`;
const assessmentRecords=()=>({
 taskPoints:JSON.stringify({version:1,completions:{},awards:{income:{points:6000},'point_tier_reserve|5000':{points:-5000}},ledger:[]}),
 socialCoinsAndXp:'{"coins":30,"xp":3020,"taskClaims":[]}',
 earnedDiamonds:'{"balance":9,"day":"2026-10-24","viewsToday":1}',
});
async function archiveAssessment(records=assessmentRecords()){
 await assertSucceeds(setDoc(doc(client('old-device'),assessmentSource),{
  format:1,kind:'legacy-local-evidence',accountKey:account,captureId:assessmentCaptureId,
  sourceUid:'old-device',installId:'old-install',records,createdAt:serverTimestamp(),
 }));
}
const assessArchive=(extra={})=>saveMigrationAssessment({store,accountKey:account,
 captureId:assessmentCaptureId,migrationId:assessmentMigrationId,...extra});
test('assessment worker commits only private evidence-saved inputs and preserves source and original wallets',async()=>{
 await archiveAssessment();
 const wallet=db.doc(`deda_gm_personal_diamond_wallets/${account}`);
 await wallet.set({balance:1000000,tag:'existing-unchanged'});
 const before=(await db.doc(assessmentSource).get()).data();
 const result=await assessArchive();
 assert.equal(result.phase,'evidence-saved');assert.equal(result.assessment.canAutoApprove,false);
 assert.deepEqual(result.assessment.observedBalances,{points:1000,coins:30,xp:3020,earnedDiamonds:9});
 assert.deepEqual((await db.doc(assessmentSource).get()).data(),before);
 assert.deepEqual((await wallet.get()).data(),{balance:1000000,tag:'existing-unchanged'});
 assert.equal((await db.doc(assessmentRoot).get()).data().baselineEventKey,null);
 assert.equal((await db.doc(assessmentPath).get()).data().status,'requires-verification');
 assert.equal((await db.doc(statePath).get()).exists,false);assert.equal((await events()).length,0);
 assert.equal((await db.collection(`deda_progress_receipts/${account}/events`).get()).size,0);
});
test('concurrent assessment workers create one review and replay without changing timestamps',async()=>{
 await archiveAssessment();const results=await Promise.all([assessArchive(),assessArchive()]);
 assert.equal(results.filter(r=>r.replayed).length,1);
 const before=(await db.doc(assessmentPath).get()).data();
 assert.equal((await assessArchive()).replayed,true);
 assert.deepEqual((await db.doc(assessmentPath).get()).data(),before);
 assert.equal((await db.collection(`${assessmentRoot}/reviews`).get()).size,1);
});
test('assessment replay cannot downgrade a later approval phase',async()=>{
 await archiveAssessment();await assessArchive();
 await db.doc(assessmentRoot).update({phase:'baseline-approved',baselineEventKey:'a'.repeat(64),settlementId:'settlement_review_0000001'});
 const before=(await db.doc(assessmentRoot).get()).data();
 assert.equal((await assessArchive()).phase,'baseline-approved');
 assert.deepEqual((await db.doc(assessmentRoot).get()).data(),before);
 assert.equal((await db.doc(statePath).get()).exists,false);
});
test('missing archived progress never becomes a zero balance or empty migration',async()=>{
 await assert.rejects(assessArchive(),e=>e.code==='migration-evidence-missing');
 assert.equal((await db.doc(assessmentRoot).get()).exists,false);
 assert.equal((await db.doc(assessmentPath).get()).exists,false);
 assert.equal((await db.doc(statePath).get()).exists,false);
});
test('capture from another account cannot be relabelled by worker lookup',async()=>{
 await archiveAssessment();await assert.rejects(assessArchive({accountKey:otherAccount}),e=>e.code==='migration-evidence-missing');
 assert.equal((await db.doc(`deda_progress_migrations/${otherAccount}`).get()).exists,false);
 assert.equal((await db.doc(assessmentRoot).get()).exists,false);
});
test('malformed archived text is retained with unknown balances rather than zero defaults',async()=>{
 const records={taskPoints:'{broken',socialCoinsAndXp:null,earnedDiamonds:'[]'};
 await archiveAssessment(records);const r=await assessArchive();
 assert.deepEqual(r.assessment.observedBalances,{points:null,coins:null,xp:null,earnedDiamonds:null});
 assert.equal(r.assessment.canAutoApprove,false);
 assert.deepEqual((await db.doc(assessmentSource).get()).data().records,records);
 assert.equal((await db.doc(statePath).get()).exists,false);
});
test('new same-account UID reads original archive but not private assessment or approval inputs',async()=>{
 await archiveAssessment();await assessArchive();
 const old=await assertSucceeds(getDocFromServer(doc(client('new-device'),assessmentSource)));
 assert.equal(old.data().sourceUid,'old-device');assert.equal(old.data().installId,'old-install');
 await assertFails(getDocFromServer(doc(client('new-device'),assessmentPath)));
 await assertFails(getDocFromServer(doc(client('new-device'),assessmentRoot)));
});
test('neither owner nor other account can forge or edit private assessment and migration phase',async()=>{
 await archiveAssessment();await assessArchive();
 for(const uid of ['old-device','new-device','other-device']){
  await assertFails(setDoc(doc(client(uid),assessmentPath),{canAutoApprove:true},{merge:true}));
  await assertFails(setDoc(doc(client(uid),assessmentRoot),{phase:'cutover-complete'},{merge:true}));
  await assertFails(deleteDoc(doc(client(uid),assessmentPath)));
 }
 await assertFails(getDocFromServer(doc(client('other-device'),assessmentSource)));
 assert.equal((await db.doc(assessmentRoot).get()).data().phase,'evidence-saved');
});
test('competing migration IDs cannot overwrite each other in real transactions',async()=>{
 await archiveAssessment();const second='competing_migration_00001';
 const results=await Promise.allSettled([assessArchive(),assessArchive({migrationId:second})]);
 assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
 assert.equal(results.filter(r=>r.status==='rejected'&&r.reason.code==='migration-review-conflict').length,1);
 assert.equal((await db.collection(`${assessmentRoot}/reviews`).get()).size,1);
});
test('failed server write validation commits neither migration nor private review',async()=>{
 await archiveAssessment();const badStore=new DedaTrustedProgressTransactionStore({db,serverTimestamp:()=>undefined});
 await assert.rejects(assessArchive({store:badStore}));
 assert.equal((await db.doc(assessmentRoot).get()).exists,false);
 assert.equal((await db.doc(assessmentPath).get()).exists,false);
 assert.equal((await db.doc(assessmentSource).get()).exists,true);
});
test('changed archived bytes cannot overwrite an existing reviewed digest',async()=>{
 await archiveAssessment();await assessArchive();const before=(await db.doc(assessmentPath).get()).data();
 const records=(await db.doc(assessmentSource).get()).data().records;records.taskPoints+=' ';
 await db.doc(assessmentSource).update({records});
 await assert.rejects(assessArchive(),e=>e.code==='migration-review-conflict');
 assert.deepEqual((await db.doc(assessmentPath).get()).data(),before);
});
test('an existing pending migration attaches evidence without approving or bootstrapping',async()=>{
 await archiveAssessment();await db.doc(assessmentRoot).set({format:1,accountKey:account,migrationId:assessmentMigrationId,
  phase:'pending',evidenceDigest:null,baselineEventKey:null,settlementId:null});
 const r=await assessArchive();assert.equal(r.phase,'evidence-saved');
 assert.equal((await db.doc(statePath).get()).exists,false);
 assert.equal((await db.doc(assessmentRoot).get()).data().settlementId,null);
});
test('new-device higher snapshot is retained without sum/max or replacing the prior evidence choice',async()=>{
 await archiveAssessment();await assessArchive();const secondId='second_device_capture_0001';
 const path=`deda_progress_evidence/${account}/captures/${secondId}`,records=assessmentRecords();
 records.socialCoinsAndXp='{"coins":99999,"xp":99999,"taskClaims":[]}';
 await assertSucceeds(setDoc(doc(client('new-device'),path),{format:1,kind:'legacy-local-evidence',
  accountKey:account,captureId:secondId,sourceUid:'new-device',installId:'new-install',records,createdAt:serverTimestamp()}));
 await assert.rejects(assessArchive({captureId:secondId}),e=>e.code==='migration-review-conflict');
 assert.equal((await db.doc(assessmentPath).get()).data().observedBalances.coins,30);
 assert.deepEqual((await db.doc(path).get()).data().records,records);
 assert.equal((await db.doc(statePath).get()).exists,false);
});
test('produced assessment is not a verified receipt and cannot pass the financial cutover gate',async()=>{
 await archiveAssessment();await assessArchive();
 await assert.rejects(apply(assessmentCaptureId),e=>e.code==='verified-receipt-missing');
 await assert.rejects(reconcileMigratedReceipt({store,accountKey:account,receiptId:awardId}),e=>e.code==='migration-pending');
 assert.equal((await db.doc(statePath).get()).exists,false);assert.equal((await events()).length,0);
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
  const captureId='baseline_capture_00000001',sourcePath=`deda_progress_evidence/${account}/captures/${captureId}`;
  const records=assessmentRecords();records.taskPoints='{"version":1,"completions":{},"awards":{"old":{"points":5000}},"ledger":[]}';
  const raw={format:1,kind:'legacy-local-evidence',accountKey:account,captureId,sourceUid:'old-device',installId:'old-install',records,createdAt:FieldValue.serverTimestamp()};
  await db.doc(sourcePath).set(raw);
  const review=assessLegacyEvidence((await db.doc(sourcePath).get()).data(),account,captureId);
  await db.doc(`${migrationRoot}/reviews/migration_fixture_000001`).set({...review,migrationId:'migration_fixture_000001',sourcePath,createdAt:FieldValue.serverTimestamp()});
  const migration={format:1,accountKey:account,migrationId:'migration_fixture_000001',phase:'cutover-complete',
    evidenceDigest:review.evidenceDigest,baselineEventKey:core.eventKey(baseline()),settlementId:'settlement_fixture_000001'};
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
    format:1,accountKey:account,migrationId:'migration_fixture_000001',evidenceDigest:(await db.doc(migrationRoot).get()).data().evidenceDigest,
    disposition:'included-in-baseline',receipt:debit('already-settled-purchase')});
  assert.equal((await applyMigrated(debitId)).includedInBaseline,true);
  assert.equal((await state()).balances.coins,30);assert.equal((await state()).version,1);
});
test('new device reads the current balance after migrated award and spending',async()=>{
  await migrationFixture('after-cutover');await applyMigrated(awardId);await seed(debitId,debit());
  await db.doc(`${migrationRoot}/classifications/${core.eventKey(debit())}`).set({
    format:1,accountKey:account,migrationId:'migration_fixture_000001',evidenceDigest:(await db.doc(migrationRoot).get()).data().evidenceDigest,
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

for(const kind of ['missing-review','missing-archive','changed-bytes','changed-origin','changed-review','inflated-baseline'])test(`real transaction rejects ${kind} without money or marker changes`,async()=>{
 await migrationFixture('after-cutover');
 const source=`deda_progress_evidence/${account}/captures/baseline_capture_00000001`;
 const review=`${migrationRoot}/reviews/migration_fixture_000001`;
 const codes={'missing-review':'migration-reviewed-evidence-required','missing-archive':'migration-evidence-missing',
  'changed-bytes':'migration-reviewed-evidence-conflict','changed-origin':'migration-reviewed-evidence-conflict',
  'changed-review':'migration-reviewed-evidence-conflict','inflated-baseline':'migration-baseline-evidence-conflict'};
 if(kind==='missing-review')await db.doc(review).delete();
 if(kind==='missing-archive')await db.doc(source).delete();
 if(kind==='changed-bytes'){const raw=(await db.doc(source).get()).data();raw.records.socialCoinsAndXp+=' ';await db.doc(source).set(raw);}
 if(kind==='changed-origin')await db.doc(source).update({installId:'different-install'});
 if(kind==='changed-review')await db.doc(review).update({canAutoApprove:true});
 if(kind==='inflated-baseline')await db.doc(`${statePath}/events/${core.eventKey(baseline())}`).update({'receipt.delta.coins':9999});
 const before=await state(),markers=(await events()).length;
 await assert.rejects(applyMigrated(awardId),e=>e.code===codes[kind]);
 assert.deepEqual(await state(),before);assert.equal((await events()).length,markers);
});

// Tokens below are issued by the localhost Auth emulator and verified by the
// actual Admin SDK with checkRevoked=true, NOT authenticatedContext claims.
const reviewPolicyRevision='owner_review_policy_00001';
const approvalPath=`${assessmentRoot}/approvals/${assessmentMigrationId}`;
async function reviewFixture(){
 await adminAuth.updateUser(reviewManager.uid,{disabled:false});
 await archiveAssessment();await assessArchive();
 await db.doc(`admins/${reviewManager.uid}`).set({active:true,status:'active',role:'general_manager',
  email:reviewManager.email,mustChangePassword:false});
 await db.doc(policyPath).set({format:1,enabled:true,revision:reviewPolicyRevision,
  decisionBasis:'owner-reviewed-grandfathering',acceptedIssues:[
   'local-values-not-server-attested','legacy-writer-fence-not-established','pending-operations-not-reviewed',
   'taskPoints:reservations-require-review']});
}
async function approveArchive(overrides={}){
 return approveLegacyBaseline({store,auth:adminAuth,idToken:reviewManager.idToken,accountKey:account,
  migrationId:assessmentMigrationId,expectedEvidenceDigest:(await db.doc(assessmentRoot).get()).data().evidenceDigest,
  policyRevision:reviewPolicyRevision,...overrides});
}
test('real Auth SDK manager review writes only private approval and no financial state or receipt',async()=>{
 await reviewFixture();const before=(await db.doc(assessmentSource).get()).data();const r=await approveArchive();
 assert.equal(r.phase,'baseline-approved');assert.equal(r.canReleaseBalance,false);
 const approval=(await db.doc(approvalPath).get()).data();
 assert.equal(approval.reviewerUid,reviewManager.uid);assert.equal(approval.receipt.delta.points,1000);
 assert.equal(approval.status,'approved-awaiting-settlement');assert.equal(approval.createdAt.constructor.name,'Timestamp');
 assert.equal((await db.doc(assessmentRoot).get()).data().settlementId,null);
 assert.deepEqual((await db.doc(assessmentSource).get()).data(),before);
 assert.equal((await db.doc(statePath).get()).exists,false);
 assert.equal((await db.collection(`deda_progress_receipts/${account}/events`).get()).size,0);
 await assert.rejects(applyMigrated(awardId),e=>e.code==='migration-pending');
});
test('concurrent real-token reviews produce one approval with stable original timestamp',async()=>{
 await reviewFixture();const results=await Promise.all([approveArchive(),approveArchive()]);
 assert.equal(results.filter(r=>r.replayed).length,1);const before=(await db.doc(approvalPath).get()).data();
 assert.equal((await approveArchive()).replayed,true);assert.deepEqual((await db.doc(approvalPath).get()).data(),before);
 assert.equal((await db.collection(`${assessmentRoot}/approvals`).get()).size,1);
});
for(const kind of ['ordinary','anonymous','invalid','disabled-manager'])test(`real Auth SDK rejects ${kind} approval without private or wallet writes`,async()=>{
 await reviewFixture();let idToken=reviewManager.idToken;
 if(kind==='ordinary')idToken=reviewOrdinary.idToken;
 if(kind==='anonymous')idToken=reviewAnonymous.idToken;
 if(kind==='invalid')idToken='not-a-firebase-token';
 if(kind==='disabled-manager')await adminAuth.updateUser(reviewManager.uid,{disabled:true});
 await assert.rejects(approveArchive({idToken}),e=>kind==='ordinary'?e.code==='baseline-review-general-manager-required':
  kind==='anonymous'?e.code==='baseline-review-admin-sign-in-required':/^auth\//.test(e.code||''));
 assert.equal((await db.doc(approvalPath).get()).exists,false);
 assert.equal((await db.doc(assessmentRoot).get()).data().phase,'evidence-saved');
 assert.equal((await db.doc(statePath).get()).exists,false);
});
for(const kind of ['missing-policy','disabled-policy','stopped-manager','demoted-manager','email-mismatch','stale-digest','changed-archive'])test(`real review ${kind} fails closed`,async()=>{
 await reviewFixture();const extra={};
 if(kind==='missing-policy')await db.doc(policyPath).delete();
 if(kind==='disabled-policy')await db.doc(policyPath).update({enabled:false});
 if(kind==='stopped-manager')await db.doc(`admins/${reviewManager.uid}`).update({active:false});
 if(kind==='demoted-manager')await db.doc(`admins/${reviewManager.uid}`).update({role:'admin'});
 if(kind==='email-mismatch')await db.doc(`admins/${reviewManager.uid}`).update({email:'different@example.test'});
 if(kind==='stale-digest')extra.expectedEvidenceDigest='f'.repeat(64);
 if(kind==='changed-archive')await db.doc(assessmentSource).update({'records.socialCoinsAndXp':'{"coins":999,"xp":20,"taskClaims":[]}'});
 const expected={'missing-policy':'baseline-review-policy-disabled','disabled-policy':'baseline-review-policy-disabled',
  'stopped-manager':'baseline-review-general-manager-required','demoted-manager':'baseline-review-general-manager-required',
  'email-mismatch':'baseline-review-general-manager-required','stale-digest':'baseline-review-migration-conflict',
  'changed-archive':'migration-reviewed-evidence-conflict'};
 await assert.rejects(approveArchive(extra),e=>e.code===expected[kind]);
 assert.equal((await db.doc(approvalPath).get()).exists,false);assert.equal((await db.doc(statePath).get()).exists,false);
});
test('valid emulator manager client still cannot read/create private approval or enable review policy',async()=>{
 await reviewFixture();await approveArchive();
 for(const c of [client('new-device'),env.authenticatedContext(reviewManager.uid,{email:reviewManager.email}).firestore()]){
  for(const path of [approvalPath,policyPath]){
   await assertFails(getDocFromServer(doc(c,path)));await assertFails(setDoc(doc(c,path),{enabled:true},{merge:true}));
   await assertFails(deleteDoc(doc(c,path)));
  }
 }
});
test('approval atomic commit failure preserves evidence-saved state and creates no partial approval',async()=>{
 await reviewFixture();const badStore=new DedaTrustedProgressTransactionStore({db,serverTimestamp:()=>undefined});
 await assert.rejects(approveArchive({store:badStore}));
 assert.equal((await db.doc(approvalPath).get()).exists,false);
 assert.equal((await db.doc(assessmentRoot).get()).data().phase,'evidence-saved');
});
test('assessment retry after approval does not erase reviewer decision or advance money',async()=>{
 await reviewFixture();await approveArchive();const before=(await db.doc(approvalPath).get()).data();
 assert.equal((await assessArchive()).phase,'baseline-approved');
 assert.deepEqual((await db.doc(approvalPath).get()).data(),before);
 assert.equal((await db.doc(statePath).get()).exists,false);
});
