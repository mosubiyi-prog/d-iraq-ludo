'use strict';
const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDocFromServer,deleteDoc,collection,getDocs,serverTimestamp}=require('firebase/firestore');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getAuth}=require('firebase-admin/auth');
const {savePointTierCarryover}=require('./point-tier-carryover.cjs');
const {saveLegacyOperationReview}=require('./legacy-operation-review.cjs');
const {approveLegacyBaseline,policyPath}=require('./baseline-review.cjs');
const {getFirestore,FieldValue,Timestamp}=require('firebase-admin/firestore');
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

const operationsOriginal='@DEDA-ABC123';
const nativeCosmeticPath=`deda_native_account_cosmetics/${operationsOriginal}`;
const oldReceiptPath=`deda_lab_frame_receipts/${operationsOriginal}/frames/FRAME_03`;
const oldOwnershipPath=`deda_lab_owned_frames/${operationsOriginal}/frames/FRAME_03`;
async function operationsFixture(){
 await archiveAssessment();await assessArchive();
 await db.doc('users/old-device').update({sharePersonalId:operationsOriginal});
 await db.doc(`deda_share_ids/${operationsOriginal}`).set({publicId:operationsOriginal,kind:'personal',active:true,ownerUid:'old-device'});
 await db.doc(nativeCosmeticPath).set({originalId:operationsOriginal,pendingFrames:['FRAME_03'],ownedFrames:['FRAME_05'],
  ownedStyles:['badge_gold'],avatar:2,customField:'preserve',updatedAt:FieldValue.serverTimestamp()});
}
const reviewOperations=(extra={})=>saveLegacyOperationReview({store,accountKey:account,migrationId:assessmentMigrationId,originalId:operationsOriginal,...extra});
async function receiptPair(){
 await db.doc(oldReceiptPath).set({kind:'lab_frame',publicId:operationsOriginal,frameId:'FRAME_03',cost:1000,createdAt:FieldValue.serverTimestamp()});
 await db.doc(oldOwnershipPath).set({publicId:operationsOriginal,frameId:'FRAME_03',receiptId:`${operationsOriginal}_FRAME_03`,createdAt:FieldValue.serverTimestamp()});
}
test('operation review preserves actual Firestore pending markers, all cosmetics, GM wallet and raw evidence',async()=>{
 await operationsFixture();const wallet=db.doc('deda_gm_personal_diamond_wallets/keep');await wallet.set({balance:1000000});
 const native=(await db.doc(nativeCosmeticPath).get()).data(),source=(await db.doc(assessmentSource).get()).data(),root=(await db.doc(assessmentRoot).get()).data();
 const result=await reviewOperations();assert.equal(result.report.pendingPurchases,'unknown');assert.equal(result.report.canAutoSettle,false);
 assert.equal(result.report.pointTiers.observedUnclaimedReturns,1);
 assert.deepEqual((await db.doc(nativeCosmeticPath).get()).data(),native);
 assert.deepEqual((await db.doc(assessmentSource).get()).data(),source);assert.deepEqual((await db.doc(assessmentRoot).get()).data(),root);
 assert.deepEqual((await wallet.get()).data(),{balance:1000000});assert.equal((await db.doc(statePath).get()).exists,false);
 assert.equal((await db.collection(`${assessmentRoot}/operationReviews`).get()).size,1);
});
test('concurrent operation reviews create one immutable report with a stable timestamp',async()=>{
 await operationsFixture();const results=await Promise.all([reviewOperations(),reviewOperations()]);
 assert.equal(results.filter(r=>r.replayed).length,1);const before=(await db.doc(results[0].path).get()).data();
 assert.equal((await reviewOperations()).replayed,true);assert.deepEqual((await db.doc(results[0].path).get()).data(),before);
});
test('receipt pair confirms item only and never clears ambiguous native pending charge or refunds funds',async()=>{
 await operationsFixture();await receiptPair();const before=(await db.doc(nativeCosmeticPath).get()).data();
 const r=await reviewOperations();assert.equal(r.report.frames[0].receiptConfirmed,true);assert.equal(r.report.frames[0].nativePending,true);
 assert.equal(r.report.frames[0].canAutoRefund,false);assert.equal(r.report.pendingPurchases,'unknown');
 assert.deepEqual((await db.doc(nativeCosmeticPath).get()).data(),before);assert.equal((await db.doc(statePath).get()).exists,false);
});
for(const field of ['receipt-only','wrong-cost','wrong-receipt-id'])test(`operation review ${field} cannot confirm ownership`,async()=>{
 await operationsFixture();await receiptPair();
 if(field==='receipt-only')await db.doc(oldOwnershipPath).delete();
 if(field==='wrong-cost')await db.doc(oldReceiptPath).update({cost:1});
 if(field==='wrong-receipt-id')await db.doc(oldOwnershipPath).update({receiptId:'forged'});
 const r=await reviewOperations();assert.equal(r.report.frames[0].receiptConfirmed,false);assert.ok(r.report.issues.some(v=>v.includes('partial-or-invalid')));
});
test('changing a native pending list produces a new review and keeps original unresolved evidence',async()=>{
 await operationsFixture();const first=await reviewOperations();
 await db.doc(nativeCosmeticPath).update({pendingFrames:['FRAME_03','FRAME_06']});const second=await reviewOperations();
 assert.notEqual(first.path,second.path);assert.deepEqual((await db.doc(first.path).get()).data().nativePendingFrames,['FRAME_03']);
 assert.equal((await db.collection(`${assessmentRoot}/operationReviews`).get()).size,2);
});
for(const field of ['foreign-route-owner','changed-archive'])test(`operation ${field} cannot attach an inconsistent review`,async()=>{
 await operationsFixture();
 if(field==='foreign-route-owner')await db.doc(`deda_share_ids/${operationsOriginal}`).update({ownerUid:'other-device'});
 else await db.doc(assessmentSource).update({'records.socialCoinsAndXp':'{"coins":999,"xp":20,"taskClaims":[]}'});
 await assert.rejects(reviewOperations(),e=>e.code===(field==='foreign-route-owner'?'operation-review-owner-not-proven':'migration-reviewed-evidence-conflict'));
 assert.equal((await db.collection(`${assessmentRoot}/operationReviews`).get()).size,0);
});
test('missing server cosmetic record stays unknown instead of becoming no pending purchases',async()=>{
 await operationsFixture();await db.doc(nativeCosmeticPath).delete();const r=await reviewOperations();
 assert.equal(r.report.nativePendingFrames,null);assert.equal(r.report.pendingPurchases,'unknown');assert.equal(r.report.canReleaseBalance,false);
});
test('owners/new-device/manager client cannot read, forge or delete operation review snapshots',async()=>{
 await operationsFixture();const r=await reviewOperations();
 for(const uid of ['old-device','new-device','other-device',reviewManager.uid]){
  const ref=doc(client(uid),r.path);await assertFails(getDocFromServer(ref));
  await assertFails(setDoc(ref,{canAutoSettle:true},{merge:true}));await assertFails(deleteDoc(ref));
 }
});
test('operation review failed atomic write leaves original pending purchase available for later recovery',async()=>{
 await operationsFixture();const before=(await db.doc(nativeCosmeticPath).get()).data();
 const badStore=new DedaTrustedProgressTransactionStore({db,serverTimestamp:()=>undefined});await assert.rejects(reviewOperations({store:badStore}));
 assert.equal((await db.collection(`${assessmentRoot}/operationReviews`).get()).size,0);
 assert.deepEqual((await db.doc(nativeCosmeticPath).get()).data(),before);
});
const localPurchaseCaptureId='purchase_capture_origin_00001';
const localPurchaseSource=`deda_purchase_evidence/${account}/captures/${localPurchaseCaptureId}`;
async function localPurchaseArchive(){
 const frames=['FRAME_03','FRAME_05','FRAME_06','FRAME_07','FRAME_08','FRAME_09','FRAME_10','FRAME_11','FRAME_12','FRAME_13','FRAME_14','FRAME_15','FRAME_16'];
 const values=Object.fromEntries(frames.map(id=>[id,null]));values.FRAME_03='paid';values.FRAME_05='charging';
 await assertSucceeds(setDoc(doc(client('old-device'),localPurchaseSource),{format:1,kind:'legacy-purchase-evidence',accountKey:account,
  sourceUid:'old-device',installId:'old-install',captureId:localPurchaseCaptureId,createdAt:serverTimestamp(),records:{
   originalId:operationsOriginal,progressCaptureId:assessmentCaptureId,localSnapshot:JSON.stringify({format:1,accountKey:account,
    originalId:operationsOriginal,inventory:' {"owned":["frame_3"]} ',frameJournals:values})}}));
}
test('real client purchase sidecar links into private operation review without charge/refund/pending cleanup',async()=>{
 await operationsFixture();await localPurchaseArchive();const before=(await db.doc(nativeCosmeticPath).get()).data();
 const r=await reviewOperations({purchaseCaptureId:localPurchaseCaptureId});
 assert.equal(r.report.frames[0].localJournal.state,'paid-recorded');assert.equal(r.report.frames[1].localJournal.state,'charging-recorded');
 assert.equal(r.report.purchaseJournalEvidence.sourceUid,'old-device');assert.equal(r.report.purchaseJournalEvidence.canProvePayment,false);
 assert.equal(r.report.pendingPurchases,'unknown');assert.deepEqual((await db.doc(nativeCosmeticPath).get()).data(),before);
 assert.equal((await db.doc(statePath).get()).exists,false);
 const read=await assertSucceeds(getDocFromServer(doc(client('new-device'),localPurchaseSource)));
 assert.equal(read.data().sourceUid,'old-device');assert.equal(read.data().installId,'old-install');
 await assertFails(getDocFromServer(doc(client('new-device'),r.path)));
});
for(const field of ['sourceUid','installId','progressCaptureId'])test(`worker purchase ${field} mismatch cannot create a settlement review`,async()=>{
 await operationsFixture();await localPurchaseArchive();
 if(field==='progressCaptureId')await db.doc(localPurchaseSource).update({'records.progressCaptureId':'different_capture_000001'});
 else await db.doc(localPurchaseSource).update({[field]:'new-device'});
 await assert.rejects(reviewOperations({purchaseCaptureId:localPurchaseCaptureId}),e=>e.code===(field==='progressCaptureId'?'purchase-evidence-parent-conflict':'purchase-evidence-origin-conflict'));
 assert.equal((await db.collection(`${assessmentRoot}/operationReviews`).get()).size,0);
});
test('missing requested local payment evidence never becomes no pending purchases',async()=>{
 await operationsFixture();await assert.rejects(reviewOperations({purchaseCaptureId:localPurchaseCaptureId}),e=>e.code==='purchase-evidence-missing');
 assert.equal((await db.collection(`${assessmentRoot}/operationReviews`).get()).size,0);
});

const carryoverSummary=`${assessmentRoot}/pointTierCarryovers/${assessmentMigrationId}`;
const carriedStage=t=>`${assessmentRoot}/pointTierEntitlements/${t}`;
async function approvedCarryoverFixture(awards){
 await reviewFixture();
 if(awards!==undefined){
  await db.doc(assessmentSource).update({'records.taskPoints':JSON.stringify({version:1,
   awards:{income:{points:100000},...awards},completions:{},ledger:[]})});
  await db.doc(assessmentRoot).delete();await db.doc(assessmentPath).delete();await assessArchive();
 }
 await approveArchive();
}
const carryover=(extra={})=>savePointTierCarryover({store,accountKey:account,migrationId:assessmentMigrationId,...extra});
test('real approved carryover preserves original reservations, wallets and baseline proposal without releasing funds',async()=>{
 await approvedCarryoverFixture();await db.doc('deda_gm_personal_diamond_wallets/keep').set({balance:1000000});
 const before=(await db.doc(assessmentSource).get()).data(),rootBefore=(await db.doc(assessmentRoot).get()).data();
 const r=await carryover();assert.equal(r.summary.canReleaseBalance,false);assert.equal(r.summary.observedUnclaimedReturns,1);
 const stage=(await db.doc(carriedStage(5000)).get()).data();assert.equal(stage.status,'reserved-awaiting-cutover');
 assert.equal(stage.futureReturnPoints,5050);assert.equal(stage.canClaimNow,false);assert.equal(stage.recordedReservePoints,-5000);
 assert.equal((await db.collection(`${assessmentRoot}/pointTierEntitlements`).get()).size,5);
 assert.equal((await db.doc(statePath).get()).exists,false);
 assert.deepEqual((await db.doc(assessmentSource).get()).data(),before);assert.deepEqual((await db.doc(assessmentRoot).get()).data(),rootBefore);
 assert.deepEqual((await db.doc('deda_gm_personal_diamond_wallets/keep').get()).data(),{balance:1000000});
 assert.equal((await db.collection(`deda_progress_receipts/${account}/events`).get()).size,0);
});
test('concurrent carryover workers create one summary/five stages and retain initial timestamp on replay',async()=>{
 await approvedCarryoverFixture();const result=await Promise.all([carryover(),carryover()]);assert.equal(result.filter(v=>v.replayed).length,1);
 const before=(await db.doc(carryoverSummary).get()).data();const first=(await db.doc(carriedStage(5000)).get()).data();
 assert.equal((await carryover()).replayed,true);assert.deepEqual((await db.doc(carryoverSummary).get()).data(),before);
 assert.deepEqual((await db.doc(carriedStage(5000)).get()).data(),first);
 assert.equal((await db.collection(`${assessmentRoot}/pointTierCarryovers`).get()).size,1);
});
test('actual claimed raw pair is carried as already included with no second return amount',async()=>{
 await approvedCarryoverFixture({'point_tier_reserve|5000':{points:-5000},'point_tier_claim|5000':{points:5050}});
 await carryover();const stage=(await db.doc(carriedStage(5000)).get()).data();
 assert.equal(stage.status,'claimed-in-baseline');assert.equal(stage.futureReturnPoints,null);assert.equal(stage.recordedClaimPoints,5050);
});
test('terminal 25000 native stage stays spent in private carryover and cannot be refunded',async()=>{
 const awards={};for(const t of [5000,10000,15000,20000,25000]){
  awards[`point_tier_reserve|${t}`]={points:-t};if(t!==25000)awards[`point_tier_claim|${t}`]={points:t+t/100};
 }
 await approvedCarryoverFixture(awards);await carryover();const last=(await db.doc(carriedStage(25000)).get()).data();
 assert.equal(last.status,'terminal-prize-spent');assert.equal(last.futureReturnPoints,null);assert.equal(last.canRefundNow,false);
 assert.equal((await db.doc(carryoverSummary).get()).data().terminalPrizeReserved,true);
 assert.equal((await db.doc(statePath).get()).exists,false);
});
test('inconsistent later reserve without previous claim is retained without importing any rights',async()=>{
 await approvedCarryoverFixture({'point_tier_reserve|10000':{points:-10000}});
 const before=(await db.doc(assessmentSource).get()).data();
 await assert.rejects(carryover(),e=>e.code==='point-carryover-history-needs-review');
 assert.equal((await db.doc(carryoverSummary).get()).exists,false);assert.deepEqual((await db.doc(assessmentSource).get()).data(),before);
});
for(const change of ['policy-off','reviewer-demoted'])test(`carryover rechecks ${change} after actual SDK review approval`,async()=>{
 await approvedCarryoverFixture();
 if(change==='policy-off')await db.doc(policyPath).update({enabled:false});
 else await db.doc(`admins/${reviewManager.uid}`).update({role:'admin'});
 await assert.rejects(carryover(),e=>e.code===(change==='policy-off'?'baseline-review-policy-disabled':'point-carryover-reviewer-inactive'));
 assert.equal((await db.doc(carryoverSummary).get()).exists,false);
});
test('changed raw evidence cannot rebase approved carryover inside a real transaction',async()=>{
 await approvedCarryoverFixture();const raw=(await db.doc(assessmentSource).get()).data();
 await db.doc(assessmentSource).update({'records.taskPoints':raw.records.taskPoints+' '});
 await assert.rejects(carryover(),e=>e.code==='migration-reviewed-evidence-conflict');
 assert.equal((await db.doc(carryoverSummary).get()).exists,false);
});
test('existing financial state is preserved instead of importing a replacement entitlement basis',async()=>{
 await approvedCarryoverFixture();const existing={balances:{points:1000000},tag:'preserve'};await db.doc(statePath).set(existing);
 await assert.rejects(carryover(),e=>e.code==='point-carryover-already-activated');assert.deepEqual((await db.doc(statePath).get()).data(),existing);
});
test('clients including original/new/other UID and manager cannot read, forge or delete carried rights',async()=>{
 await approvedCarryoverFixture();await carryover();
 for(const uid of ['old-device','new-device','other-device',reviewManager.uid])for(const path of [carryoverSummary,carriedStage(5000)]){
  const ref=doc(client(uid),path);await assertFails(getDocFromServer(ref));
  await assertFails(setDoc(ref,{canClaimNow:true},{merge:true}));await assertFails(deleteDoc(ref));
 }
});
test('atomic write validation failure leaves neither a carryover summary nor partial stages',async()=>{
 await approvedCarryoverFixture();const badStore=new DedaTrustedProgressTransactionStore({db,serverTimestamp:()=>undefined});
 await assert.rejects(carryover({store:badStore}));assert.equal((await db.doc(carryoverSummary).get()).exists,false);
 assert.equal((await db.collection(`${assessmentRoot}/pointTierEntitlements`).get()).size,0);
});
test('tampered carried amount cannot be corrected silently by replaying original import',async()=>{
 await approvedCarryoverFixture();await carryover();await db.doc(carriedStage(5000)).update({futureReturnPoints:999999});
 await assert.rejects(carryover(),e=>e.code==='point-carryover-conflict');assert.equal((await db.doc(carriedStage(5000)).get()).data().futureReturnPoints,999999);
 assert.equal((await db.doc(statePath).get()).exists,false);
});
test('partial stage records are held rather than overwritten without their atomic summary',async()=>{
 await approvedCarryoverFixture();await db.doc(carriedStage(5000)).set({tag:'preserve'});
 await assert.rejects(carryover(),e=>e.code==='point-carryover-conflict');
 assert.deepEqual((await db.doc(carriedStage(5000)).get()).data(),{tag:'preserve'});
});
test('closed migration cannot reimport legacy rights or reset a later claim history',async()=>{
 await approvedCarryoverFixture();await db.doc(assessmentRoot).update({phase:'cutover-complete',settlementId:'settlement_review_0000001'});
 await assert.rejects(carryover(),e=>e.code==='point-carryover-reviewed-baseline-required');
 assert.equal((await db.doc(carryoverSummary).get()).exists,false);
});

// Gated follow-up events consume a real SDK-approved and saved carryover.
// Settlement, fence and cutover remain privileged synthetic fixtures; this
// does not implement or attest any production cutover or old-writer fence.
async function activatedCarryoverFixture(awards){
 await approvedCarryoverFixture(awards);await carryover();
 const approval=(await db.doc(approvalPath).get()).data();
 await seed(baselineId,approval.receipt);await apply(baselineId);
 const migration=(await db.doc(assessmentRoot).get()).data();
 const settlementId='carried_settlement_000001';
 await db.doc(assessmentRoot).update({phase:'cutover-complete',settlementId});
 await db.doc(`${assessmentRoot}/settlements/${settlementId}`).set({format:1,accountKey:account,
 migrationId:assessmentMigrationId,evidenceDigest:migration.evidenceDigest,baselineEventKey:migration.baselineEventKey,
 legacyFenceId:'writer_fence_fixture_00001',pendingPurchases:0,pendingReservations:0});
 await seed(awardId,award());
 await db.doc(`${assessmentRoot}/classifications/${core.eventKey(award())}`).set({format:1,accountKey:account,
 migrationId:assessmentMigrationId,evidenceDigest:migration.evidenceDigest,disposition:'after-cutover',receipt:award()});
 return approval.receipt.delta;
}
test('real gated award consumes carried proof atomically without claiming the reserved return',async()=>{
 const initial=await activatedCarryoverFixture(),rights=(await db.doc(carriedStage(5000)).get()).data();
 const second='carried_award_wrapper_00001';await seed(second,award());
 const results=await Promise.all([applyMigrated(awardId),applyMigrated(second)]);
 assert.equal(results.filter(r=>r.replayed).length,1);assert.equal((await state()).balances.points,initial.points+5);
 assert.equal((await state()).version,2);assert.equal((await events()).length,2);
 assert.deepEqual((await db.doc(carriedStage(5000)).get()).data(),rights);assert.equal(rights.canClaimNow,false);
});
for(const change of ['missing-summary','missing-5000','missing-25000','inflated-return','early-claim','changed-summary','changed-approval','changed-time'])
 test(`real financial transaction blocks ${change} without changing wallet, markers or raw source`,async()=>{
 await activatedCarryoverFixture();
 if(change==='missing-summary')await db.doc(carryoverSummary).delete();
 if(change==='missing-5000')await db.doc(carriedStage(5000)).delete();
 if(change==='missing-25000')await db.doc(carriedStage(25000)).delete();
 if(change==='inflated-return')await db.doc(carriedStage(5000)).update({futureReturnPoints:999999});
 if(change==='early-claim')await db.doc(carriedStage(5000)).update({canClaimNow:true});
 if(change==='changed-summary')await db.doc(carryoverSummary).update({observedUnclaimedReturns:0});
 if(change==='changed-approval')await db.doc(approvalPath).update({policyRevision:'different_policy_0000001'});
 if(change==='changed-time')await db.doc(carriedStage(25000)).update({createdAt:Timestamp.fromMillis(0)});
 const before=await state(),source=(await db.doc(assessmentSource).get()).data();
 await assert.rejects(applyMigrated(awardId),e=>e.code===(change==='missing-summary'?'migration-point-carryover-required':'migration-point-carryover-conflict'));
 assert.deepEqual(await state(),before);assert.equal((await events()).length,1);
 assert.deepEqual((await db.doc(assessmentSource).get()).data(),source);
});
test('historical manager demotion and review-policy disable do not freeze already-cutover rewards',async()=>{
 await activatedCarryoverFixture();await db.doc(policyPath).update({enabled:false});
 await db.doc(`admins/${reviewManager.uid}`).update({active:false});
 assert.equal((await applyMigrated(awardId)).state.version,2);
});
test('real final-stage carried proof never refunds terminal prize or previously claimed tiers',async()=>{
 const awards={};for(const t of [5000,10000,15000,20000,25000]){
 awards[`point_tier_reserve|${t}`]={points:-t};if(t!==25000)awards[`point_tier_claim|${t}`]={points:t+t/100};}
 const initial=await activatedCarryoverFixture(awards),terminal=(await db.doc(carriedStage(25000)).get()).data();
 assert.equal((await applyMigrated(awardId)).state.balances.points,initial.points+5);
 assert.deepEqual((await db.doc(carriedStage(25000)).get()).data(),terminal);assert.equal(terminal.futureReturnPoints,null);
});

const {claimMigratedPointTier}=require('./point-tier-claim.cjs');
const claimCarried=(threshold=5000,claimStore=store)=>claimMigratedPointTier({store:claimStore,accountKey:account,threshold});
const carriedClaim=t=>`${assessmentRoot}/pointTierClaims/${t}`;
test('real concurrent migrated point claims create one return and five atomic records without changing archived rights',async()=>{
 const initial=await activatedCarryoverFixture(),proof=(await db.doc(carriedStage(5000)).get()).data();
 const results=await Promise.all([claimCarried(),claimCarried()]);
 assert.equal(results.filter(r=>r.replayed).length,1);assert.equal((await state()).balances.points,initial.points+5050);
 assert.equal((await state()).version,2);assert.equal((await events()).length,2);
 const r=results[0],receipt=(await db.doc(`deda_progress_receipts/${account}/events/${r.eventKey}`).get()).data();
 assert.equal(receipt.source,'point-tier-return-v1');assert.equal(receipt.delta.points,5050);
 assert.equal((await db.doc(carriedClaim(5000)).get()).data().status,'claimed');
 assert.deepEqual((await db.doc(carriedStage(5000)).get()).data(),proof);
});
test('lost claim response is recovered without another return and new UID reads the same account balance',async()=>{
 const initial=await activatedCarryoverFixture();
 await assert.rejects((async()=>{await claimCarried();throw Error('injected-lost-response');})(),/injected-lost-response/);
 const second=await claimCarried();assert.equal(second.replayed,true);
 assert.equal(second.state.balances.points,initial.points+5050);assert.equal((await events()).length,2);
 const recovered=await assertSucceeds(getDocFromServer(doc(client('new-device'),statePath)));
 assert.equal(recovered.data().balances.points,initial.points+5050);
 await assertFails(getDocFromServer(doc(client('other-device'),statePath)));
});
test('original gated receipt replay cannot re-award a generated point return',async()=>{
 await activatedCarryoverFixture();const first=await claimCarried(),before=await state();
 const replay=await applyMigrated(first.eventKey);assert.equal(replay.replayed,true);assert.deepEqual(replay.state,before);
 assert.equal((await events()).length,2);
});
test('claim replay after later point spending returns current balances and preserves all other wallets',async()=>{
 const initial=await activatedCarryoverFixture();await claimCarried();
 const spend={format:1,accountKey:account,source:'point-reservation-v1',sourceId:'later-spend-fixture',kind:'spend',
 delta:{points:-100,coins:0,xp:0,earnedDiamonds:0}};
 const migration=(await db.doc(assessmentRoot).get()).data();
 await seed(debitId,spend);await db.doc(`${assessmentRoot}/classifications/${core.eventKey(spend)}`).set({format:1,
 accountKey:account,migrationId:assessmentMigrationId,evidenceDigest:migration.evidenceDigest,disposition:'after-cutover',receipt:spend});
 await db.doc(`deda_gm_personal_diamond_wallets/${account}`).set({balance:1000000});
 await applyMigrated(debitId);const replay=await claimCarried();
 assert.equal(replay.state.balances.points,initial.points+5050-100);assert.equal(replay.state.version,3);
 assert.equal(replay.state.balances.xp,initial.xp);assert.equal(replay.state.balances.earnedDiamonds,initial.earnedDiamonds);
 assert.deepEqual((await db.doc(`deda_gm_personal_diamond_wallets/${account}`).get()).data(),{balance:1000000});
});
for(const threshold of [10000,15000,20000])test(`real stage ${threshold} returns its fixed original amount once`,async()=>{
 const awards={};for(const t of [5000,10000,15000,20000]){
 if(t>threshold)break;awards[`point_tier_reserve|${t}`]={points:-t};if(t<threshold)awards[`point_tier_claim|${t}`]={points:t+t/100};}
 const initial=await activatedCarryoverFixture(awards),r=await claimCarried(threshold);
 assert.equal(r.returnedPoints,threshold+threshold/100);assert.equal(r.state.balances.points,initial.points+r.returnedPoints);
 assert.equal((await claimCarried(threshold)).replayed,true);assert.equal((await events()).length,2);
});
for(const condition of ['already-claimed','not-observed','terminal'])test(`real ${condition} stage cannot create a return receipt`,async()=>{
 if(condition==='already-claimed')await activatedCarryoverFixture({'point_tier_reserve|5000':{points:-5000},'point_tier_claim|5000':{points:5050}});
 else await activatedCarryoverFixture();
 const threshold=condition==='terminal'?25000:condition==='not-observed'?10000:5000,before=await state();
 await assert.rejects(claimCarried(threshold),e=>e.code==='point-tier-return-ineligible');
 assert.deepEqual(await state(),before);assert.equal((await events()).length,1);
 assert.equal((await db.doc(carriedClaim(threshold)).get()).exists,false);
});
for(const condition of ['pending-cutover','unsettled-purchase','missing-stage'])test(`real ${condition} blocks the claim producer before any of its five writes`,async()=>{
 await activatedCarryoverFixture();
 if(condition==='pending-cutover')await db.doc(assessmentRoot).update({phase:'baseline-approved'});
 if(condition==='unsettled-purchase')await db.doc(`${assessmentRoot}/settlements/carried_settlement_000001`).update({pendingPurchases:1});
 if(condition==='missing-stage')await db.doc(carriedStage(25000)).delete();
 const before=await state(),code=condition==='pending-cutover'?'migration-pending':condition==='unsettled-purchase'?'migration-not-settled':'migration-point-carryover-conflict';
 await assert.rejects(claimCarried(),e=>e.code===code);assert.deepEqual(await state(),before);
 assert.equal((await events()).length,1);assert.equal((await db.doc(carriedClaim(5000)).get()).exists,false);
});
test('real claim serialization failure rolls back receipt, classification, applied event, wallet and claim together',async()=>{
 await activatedCarryoverFixture();const before=await state(),proof=(await db.doc(carriedStage(5000)).get()).data();
 const receiptsBefore=(await db.collection(`deda_progress_receipts/${account}/events`).get()).size;
 const classesBefore=(await db.collection(`${assessmentRoot}/classifications`).get()).size;
 const badStore=new DedaTrustedProgressTransactionStore({db,serverTimestamp:()=>undefined});
 await assert.rejects(claimCarried(5000,badStore));assert.deepEqual(await state(),before);assert.equal((await events()).length,1);
 assert.equal((await db.doc(carriedClaim(5000)).get()).exists,false);
 assert.equal((await db.collection(`deda_progress_receipts/${account}/events`).get()).size,receiptsBefore);
 assert.equal((await db.collection(`${assessmentRoot}/classifications`).get()).size,classesBefore);
 assert.deepEqual((await db.doc(carriedStage(5000)).get()).data(),proof);
});
for(const condition of ['tampered-claim','orphan-receipt','missing-event'])test(`real ${condition} does not cause a replacement or second return`,async()=>{
 await activatedCarryoverFixture();const first=await claimCarried();
 if(condition==='tampered-claim')await db.doc(carriedClaim(5000)).update({returnedPoints:999999});
 if(condition==='orphan-receipt')await db.doc(carriedClaim(5000)).delete();
 if(condition==='missing-event')await db.doc(`${statePath}/events/${first.eventKey}`).delete();
 const before=await state();await assert.rejects(claimCarried(),e=>e.code==='point-tier-claim-conflict');
 assert.deepEqual(await state(),before);
});
test('clients including manager and recovered UID cannot read, forge or delete the private once-only claim record',async()=>{
 await activatedCarryoverFixture();await claimCarried();
 for(const uid of ['old-device','new-device','other-device',reviewManager.uid]){
 const ref=doc(client(uid),carriedClaim(5000));await assertFails(getDocFromServer(ref));
 await assertFails(setDoc(ref,{status:'pending',returnedPoints:999999},{merge:true}));await assertFails(deleteDoc(ref));}
});

const {claimPointTierForOwnerSession}=require('./point-tier-session.cjs');
async function authenticatedClaimFixture(){
 await activatedCarryoverFixture();
 const old=await authFixture(null),next=await authFixture(null);
 for(const [owner,install]of [[old,'old-install'],[next,'new-install']]){
  await db.doc(`deda_sessions/${owner.uid}`).set({uid:owner.uid,accountKey:account,installId:install});
  await db.doc(`users/${owner.uid}`).set({accountKey:account,authMethod:'deda_pin_firestore_v1',trustedInstallIds:[install]});
 }
 await db.doc(`deda_account_profiles/${account}`).set({accountKey:account,trustedInstallIds:['old-install','new-install']});
 await db.doc(`deda_account_directory/${account}`).set({accountKey:account,active:true});
 await db.doc(`deda_credentials/${account}`).set({accountKey:account,active:true});
 return {old,next};
}
const sessionReturn=owner=>claimPointTierForOwnerSession({store,auth:adminAuth,idToken:owner.idToken,threshold:5000});
test('actual Admin SDK token verification authorizes the atomic claim from derived server owner proof',async()=>{
 const {old}=await authenticatedClaimFixture(),before=await state();
 const r=await sessionReturn(old);assert.equal(r.state.accountKey,account);assert.equal(r.state.balances.points,before.balances.points+5050);
 assert.equal((await events()).length,2);assert.equal((await db.doc(carriedClaim(5000)).get()).data().status,'claimed');
});
test('two actual anonymous Auth UIDs proven for one account share one concurrent once-only claim',async()=>{
 const {old,next}=await authenticatedClaimFixture(),before=await state();
 const result=await Promise.all([sessionReturn(old),sessionReturn(next)]);
 assert.equal(result.filter(r=>r.replayed).length,1);assert.equal(result[0].eventKey,result[1].eventKey);
 assert.equal((await state()).balances.points,before.balances.points+5050);assert.equal((await events()).length,2);
});
test('actual recovered owner token replays current state after an older UID has already claimed',async()=>{
 const {old,next}=await authenticatedClaimFixture();const first=await sessionReturn(old);
 const replay=await sessionReturn(next);assert.equal(replay.replayed,true);assert.equal(replay.eventKey,first.eventKey);
 assert.equal(replay.state.version,2);assert.deepEqual(replay.state.balances,first.state.balances);
});
for(const condition of ['missing-session','wrong-session-uid','different-account','untrusted-user-install','untrusted-profile-install','inactive-directory','inactive-credential'])
 test(`real SDK token cannot bypass ${condition} owner proof`,async()=>{
 const {old}=await authenticatedClaimFixture();
 if(condition==='missing-session')await db.doc(`deda_sessions/${old.uid}`).delete();
 if(condition==='wrong-session-uid')await db.doc(`deda_sessions/${old.uid}`).update({uid:'other-device'});
 if(condition==='different-account')await db.doc(`users/${old.uid}`).update({accountKey:otherAccount});
 if(condition==='untrusted-user-install')await db.doc(`users/${old.uid}`).update({trustedInstallIds:[]});
 if(condition==='untrusted-profile-install')await db.doc(`deda_account_profiles/${account}`).update({trustedInstallIds:['new-install']});
 if(condition==='inactive-directory')await db.doc(`deda_account_directory/${account}`).update({active:false});
 if(condition==='inactive-credential')await db.doc(`deda_credentials/${account}`).update({active:false});
 const before=await state();await assert.rejects(sessionReturn(old),e=>e.code==='point-session-owner-proof-required');
 assert.deepEqual(await state(),before);assert.equal((await events()).length,1);assert.equal((await db.doc(carriedClaim(5000)).get()).exists,false);
});
test('actual password-manager token cannot substitute for an anonymous owner account session',async()=>{
 await authenticatedClaimFixture();const before=await state();
 await assert.rejects(sessionReturn(reviewManager),e=>e.code==='point-session-owner-sign-in-required');
 assert.deepEqual(await state(),before);assert.equal((await events()).length,1);
});
test('actual disabled Auth user is refused by Admin SDK before replay or a financial write',async()=>{
 const {old}=await authenticatedClaimFixture();await sessionReturn(old);const before=await state();
 await adminAuth.updateUser(old.uid,{disabled:true});
 await assert.rejects(sessionReturn(old),e=>e.code==='auth/user-disabled');
 assert.deepEqual(await state(),before);assert.equal((await events()).length,2);
});
test('invalid token is rejected by the actual Admin SDK without a claim or wallet write',async()=>{
 await authenticatedClaimFixture();const before=await state();
 await assert.rejects(sessionReturn({idToken:'invalid-synthetic-token'}),e=>typeof e.code==='string'&&e.code.startsWith('auth/'));
 assert.deepEqual(await state(),before);assert.equal((await events()).length,1);
});
