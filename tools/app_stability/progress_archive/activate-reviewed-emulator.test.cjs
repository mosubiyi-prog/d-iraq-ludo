'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDocFromServer,serverTimestamp}=require('firebase/firestore');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getAuth}=require('firebase-admin/auth');
const {getFirestore,FieldValue}=require('firebase-admin/firestore');
const {DedaTrustedProgressTransactionStore}=require('./reconcile-store.cjs');
const {saveMigrationAssessment}=require('./migration-assessment-store.cjs');
const {approveLegacyBaseline,policyPath}=require('./baseline-review.cjs');
const {savePointTierCarryover}=require('./point-tier-carryover.cjs');
const {saveLegacyOperationReview}=require('./legacy-operation-review.cjs');
const {activateReviewedBaseline,deploymentPath}=require('./activate-reviewed-baseline.cjs');
const {reviewLegacySettlement}=require('./review-legacy-settlement.cjs');
const {frames}=require('./purchase-frames.cjs');
const {purchaseReviewedFrameForOwnerSession}=require('./purchase-reviewed-frame.cjs');
const {readMigratedProgressForOwnerSession,claimReviewedPointTierForOwnerSession}=require('./point-tier-session.cjs');
const A='07700000000',original='@DEDA-ABC234',captureId='sdk_activation_capture_0001';
const migrationId='sdk_activation_migration_01',settlementId='sdk_activation_settlement_1';
const revision='sdk_owner_review_policy_01',deploymentRevision='sdk_deployment_fixture_01',fenceId='sdk_enforced_fence_fixture_1';
const root=`deda_progress_migrations/${A}`,statePath=`deda_verified_progress/${A}`;
let env,app,db,auth,store,manager,owner,next;
async function createAuth(email){
 const host=process.env.FIREBASE_AUTH_EMULATOR_HOST;
 assert.match(host||'',/^(localhost|127\.0\.0\.1):[0-9]+$/);
 const response=await fetch(`http://${host}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=isolated-demo-only`,{
  method:'POST',headers:{'content-type':'application/json'},
  body:JSON.stringify(email?{email,password:'demo-only-password-9!',returnSecureToken:true}:{returnSecureToken:true})});
 const result=await response.json();assert.equal(response.ok,true);
 return {uid:result.localId,idToken:result.idToken,email};
}
test.before(async()=>{
 assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^(localhost|127\.0\.0\.1):[0-9]+$/);
 const projectId='demo-deda-progress-archive';
 env=await initializeTestEnvironment({projectId,firestore:{rules:fs.readFileSync(path.join(__dirname,'firestore.rules'),'utf8')}});
 app=initializeApp({projectId},'reviewed-activation-sdk-only');db=getFirestore(app);auth=getAuth(app);
 store=new DedaTrustedProgressTransactionStore({db,serverTimestamp:()=>FieldValue.serverTimestamp()});
 manager=await createAuth('cutover-manager@example.test');owner=await createAuth(null);next=await createAuth(null);
});
test.after(async()=>{if(db)await db.terminate();if(app)await deleteApp(app);if(env)await env.cleanup();});
test.beforeEach(async()=>{
 await env.clearFirestore();await auth.updateUser(manager.uid,{disabled:false});
 await auth.updateUser(owner.uid,{disabled:false});await auth.updateUser(next.uid,{disabled:false});
 for(const [user,install]of [[owner,'old-install'],[next,'new-install']]){
  await db.doc(`deda_sessions/${user.uid}`).set({uid:user.uid,accountKey:A,installId:install});
  await db.doc(`users/${user.uid}`).set({accountKey:A,sharePersonalId:original,
   authMethod:'deda_pin_firestore_v1',trustedInstallIds:[install]});
 }
 await db.doc(`deda_account_profiles/${A}`).set({accountKey:A,trustedInstallIds:['old-install','new-install']});
 await db.doc(`deda_account_directory/${A}`).set({accountKey:A,active:true});
 await db.doc(`deda_credentials/${A}`).set({accountKey:A,active:true});
 await db.doc(`deda_share_ids/${original}`).set({publicId:original,kind:'personal',active:true,ownerUid:owner.uid});
 await db.doc(`deda_native_account_cosmetics/${original}`).set({originalId:original,ownedFrames:[],pendingFrames:[]});
 await db.doc(`admins/${manager.uid}`).set({active:true,status:'active',role:'general_manager',email:manager.email});
 await db.doc(`deda_gm_personal_diamond_wallets/${A}`).set({balance:1000000,fixture:'unchanged'});
});
async function reviewedFixture(journalValue=null){
 const client=env.authenticatedContext(owner.uid).firestore();
 await assertSucceeds(setDoc(doc(client,`deda_progress_evidence/${A}/captures/${captureId}`),{
  format:1,kind:'legacy-local-evidence',accountKey:A,captureId,sourceUid:owner.uid,installId:'old-install',
  createdAt:serverTimestamp(),records:{
   taskPoints:JSON.stringify({version:1,completions:{},awards:{income:{points:6000},
    'point_tier_reserve|5000':{points:-5000}},ledger:[]}),
   socialCoinsAndXp:'{"coins":30,"xp":20,"taskClaims":[]}',
   earnedDiamonds:'{"balance":9,"day":"2026-10-26","viewsToday":1}',
  }}));
 await saveMigrationAssessment({store,accountKey:A,captureId,migrationId});
 await db.doc(policyPath).set({format:1,enabled:true,revision,decisionBasis:'owner-reviewed-grandfathering',
  acceptedIssues:['local-values-not-server-attested','legacy-writer-fence-not-established',
   'pending-operations-not-reviewed','taskPoints:reservations-require-review']});
 const migration=(await db.doc(root).get()).data();
 await approveLegacyBaseline({store,auth,idToken:manager.idToken,accountKey:A,migrationId,
  expectedEvidenceDigest:migration.evidenceDigest,policyRevision:revision});
 await savePointTierCarryover({store,accountKey:A,migrationId});
 const reviewed=(await db.doc(root).get()).data();
 const purchaseCaptureId='sdk_purchase_settlement_001';
 await assertSucceeds(setDoc(doc(client,`deda_purchase_evidence/${A}/captures/${purchaseCaptureId}`),{
  format:1,kind:'legacy-purchase-evidence',accountKey:A,captureId:purchaseCaptureId,sourceUid:owner.uid,
  installId:'old-install',createdAt:serverTimestamp(),records:{originalId:original,progressCaptureId:captureId,
   localSnapshot:JSON.stringify({format:1,accountKey:A,originalId:original,inventory:null,
    frameJournals:Object.fromEntries(frames.map((frame,index)=>[frame,index===0?journalValue:null]))})}}));
 const operations=await saveLegacyOperationReview({store,accountKey:A,migrationId,originalId:original,purchaseCaptureId});
 // Deployment/fence remain deliberate private TEST inputs, not published
 // protection, production settlement, actual PIN UI or provider attestation.
 await db.doc(deploymentPath).set({format:1,enabled:true,revision:deploymentRevision,
  protocol:'deda-verified-progress-v1',enforcementRevision:'e'.repeat(64),clientBound:true,
  providersReady:true,atomicPurchasesReady:true});
 await db.doc(`${root}/fences/${fenceId}`).set({format:1,accountKey:A,migrationId,
  evidenceDigest:reviewed.evidenceDigest,originalId:original,legacyFenceId:fenceId,
  protocol:'deda-verified-progress-v1',deploymentRevision,enforcementRevision:'e'.repeat(64),
  status:'enforced',createdAt:FieldValue.serverTimestamp()});
 const settlementRequest={store,auth,idToken:manager.idToken,accountKey:A,migrationId,settlementId,
  originalId:original,expectedOperationReviewDigest:operations.report.inputDigest,purchaseCaptureId,legacyFenceId:fenceId};
 if(journalValue===null)await reviewLegacySettlement(settlementRequest);
 return settlementRequest;
}
const activate=(overrides={})=>activateReviewedBaseline({store,auth,idToken:manager.idToken,
 accountKey:A,migrationId,settlementId,...overrides});
const read=user=>readMigratedProgressForOwnerSession({store,auth,idToken:user.idToken});
const current=async()=>{const snap=await db.doc(statePath).get();return snap.exists?snap.data():null;};
test('real SDK activation creates the baseline and a recovered owner reads all four units without a grant',async()=>{
 await reviewedFixture();const source=(await db.doc(`deda_progress_evidence/${A}/captures/${captureId}`).get()).data();
 const result=await activate();assert.equal(result.replayed,false);
 assert.deepEqual(result.state.balances,{points:1000,coins:30,xp:20,earnedDiamonds:9});
 const recovered=await read(next);assert.deepEqual(recovered.state,await current());
 assert.equal((await db.collection(`${statePath}/events`).get()).size,1);
 assert.equal((await db.doc(`${root}/pointTierClaims/5000`).get()).exists,false);
 assert.deepEqual((await db.doc(`deda_gm_personal_diamond_wallets/${A}`).get()).data(),{balance:1000000,fixture:'unchanged'});
 assert.deepEqual((await db.doc(`deda_progress_evidence/${A}/captures/${captureId}`).get()).data(),source);
});
test('concurrent real SDK activation creates one baseline with one replay',async()=>{
 await reviewedFixture();const results=await Promise.all([activate(),activate()]);
 assert.equal(results.filter(r=>r.replayed).length,1);assert.equal((await current()).version,1);
 assert.equal((await db.collection(`${statePath}/events`).get()).size,1);
 assert.equal((await db.collection(`${root}/activations`).get()).size,1);
 assert.equal((await db.collection(`deda_progress_receipts/${A}/events`).get()).size,1);
});
test('once-only claim after actual activation is shared by recovered and original owner tokens',async()=>{
 await reviewedFixture();await activate();
 const claim=user=>claimReviewedPointTierForOwnerSession({store,auth,idToken:user.idToken,threshold:5000});
 const results=await Promise.all([claim(owner),claim(next)]);
 assert.equal(results.filter(r=>r.replayed).length,1);assert.equal((await current()).balances.points,6050);
 const replay=await activate();assert.equal(replay.replayed,true);assert.equal(replay.state.balances.points,6050);
});
for(const proof of ['deployment','fence','settlement'])test(`real SDK missing ${proof} leaves every balance absent`,async()=>{
 await reviewedFixture();await db.doc(proof==='deployment'?deploymentPath:
  proof==='fence'?`${root}/fences/${fenceId}`:`${root}/settlementReviews/${settlementId}`).delete();
 await assert.rejects(activate());assert.equal(await current(),null);
 assert.equal((await db.doc(root).get()).data().phase,'baseline-approved');
 assert.equal((await db.collection(`${statePath}/events`).get()).size,0);
});
test('real SDK transaction abort after staging six writes commits none',async()=>{
 await reviewedFixture();const before=(await db.doc(root).get()).data();
 const aborting={serverTimestamp:()=>store.serverTimestamp(),runTransaction:work=>store.runTransaction(async tx=>{
  await work(tx);throw Error('deliberate-sdk-abort');
 })};
 await assert.rejects(activate({store:aborting}),/deliberate-sdk-abort/);
 assert.equal(await current(),null);assert.deepEqual((await db.doc(root).get()).data(),before);
 assert.equal((await db.collection(`${root}/activations`).get()).size,0);
});
test('closed transaction after actual commit replays without another baseline',async()=>{
 await reviewedFixture();let calls=0;
 const wrapped=new DedaTrustedProgressTransactionStore({db:{doc:p=>db.doc(p),runTransaction:async work=>{
  calls++;const result=await db.runTransaction(work);
  if(calls===1)throw Object.assign(Error('3 INVALID_ARGUMENT: Transaction is invalid or closed.'),
   {code:3,details:'Transaction is invalid or closed.'});
  return result;
 }},serverTimestamp:()=>FieldValue.serverTimestamp()});
 const result=await activate({store:wrapped});assert.equal(result.replayed,true);assert.equal(calls,2);
 assert.equal((await current()).version,1);assert.equal((await db.collection(`${statePath}/events`).get()).size,1);
});
test('actual disabled manager token cannot activate the private approval',async()=>{
 await reviewedFixture();await auth.updateUser(manager.uid,{disabled:true});
 await assert.rejects(activate(),e=>e.code==='auth/user-disabled');assert.equal(await current(),null);
});
test('actual recovered owner without trusted install cannot read a manufactured zero balance',async()=>{
 await reviewedFixture();await activate();const before=await current();
 await db.doc(`users/${next.uid}`).update({trustedInstallIds:[]});
 await assert.rejects(read(next),e=>e.code==='point-session-owner-proof-required');
 assert.deepEqual(await current(),before);
});
test('clients including the manager cannot forge activation, settlement review or fence records',async()=>{
 await reviewedFixture();
 for(const user of [manager,owner,next]){
  const dbClient=env.authenticatedContext(user.uid).firestore();
  for(const p of [`${root}/activations/${migrationId}`,`${root}/settlementReviews/${settlementId}`,`${root}/fences/${fenceId}`]){
   await assertFails(getDocFromServer(doc(dbClient,p)));
   await assertFails(setDoc(doc(dbClient,p),{status:'resolved',pendingPurchases:0}));
  }
 }
 assert.equal(await current(),null);
});
test('real captured charging journal prevents settlement and leaves all source records untouched',async()=>{
 const request=await reviewedFixture('charging');
 const before=(await db.doc(`deda_purchase_evidence/${A}/captures/${request.purchaseCaptureId}`).get()).data();
 await assert.rejects(reviewLegacySettlement(request),e=>e.code==='settlement-payment-journal-needs-review');
 assert.equal((await db.doc(`${root}/settlementReviews/${settlementId}`).get()).exists,false);
 assert.equal(await current(),null);
 assert.deepEqual((await db.doc(`deda_purchase_evidence/${A}/captures/${request.purchaseCaptureId}`).get()).data(),before);
});
test('concurrent real settlement review writes one immutable resolution and does not release balances',async()=>{
 const request=await reviewedFixture();await db.doc(`${root}/settlementReviews/${settlementId}`).delete();
 const result=await Promise.all([reviewLegacySettlement(request),reviewLegacySettlement(request)]);
 assert.equal(result.filter(r=>r.replayed).length,1);assert.equal(await current(),null);
 assert.equal((await db.collection(`${root}/settlementReviews`).get()).size,1);
});
const purchase=(user,frameId='FRAME_03')=>purchaseReviewedFrameForOwnerSession({store,auth,idToken:user.idToken,frameId});
async function fundedPurchase(){
 await reviewedFixture();await activate();
 await db.doc(`deda_diamond_gift_balances/${original}`).set({publicId:original,balance:1991,lastClaimGiftId:'fixture-only'});
}
test('actual concurrent recovered-UID purchases create one payment and one receipt/ownership pair',async()=>{
 await fundedPurchase();const results=await Promise.all([purchase(owner),purchase(next)]);
 assert.equal(results.filter(r=>r.replayed).length,1);
 assert.deepEqual((await current()).balances,{points:1000,coins:30,xp:20,earnedDiamonds:0});
 assert.equal((await current()).version,2);
 assert.equal((await db.doc(`deda_diamond_gift_balances/${original}`).get()).data().balance,1000);
 assert.equal((await db.collection(`${root}/framePurchases`).get()).size,1);
 assert.equal((await db.collection(`deda_lab_frame_receipts/${original}/frames`).get()).size,1);
 assert.equal((await db.collection(`deda_lab_owned_frames/${original}/frames`).get()).size,1);
 assert.equal((await db.doc(`deda_gm_personal_diamond_wallets/${A}`).get()).data().balance,1000000);
});
test('actual different frame transactions share the same balance and cannot overspend it',async()=>{
 await fundedPurchase();
 const results=await Promise.all([purchase(owner,'FRAME_03'),purchase(next,'FRAME_05')]);
 assert.equal(results.every(r=>r.replayed===false),true);
 assert.equal((await db.doc(`deda_diamond_gift_balances/${original}`).get()).data().balance,0);
 assert.equal((await current()).balances.earnedDiamonds,0);assert.equal((await current()).version,2);
 await assert.rejects(purchase(owner,'FRAME_06'),e=>e.code==='frame-insufficient-diamonds');
 assert.equal((await db.doc(`deda_lab_owned_frames/${original}/frames/FRAME_06`).get()).exists,false);
});
test('actual GM purchase uses only protected personal wallet and leaves both ordinary sources intact',async()=>{
 await fundedPurchase();
 await db.doc(`admin_entry_access/${A}`).set({accountKey:A,active:true,status:'active',
  accessType:'general_manager_gateway',allowedRole:'general_manager'});
 await db.doc(`deda_gm_personal_diamond_wallets/${A}`).set({accountKey:A,initialBalance:1000000,balance:1000000});
 const before=await current(),result=await purchase(owner);
 assert.equal(result.managerBalance,999000);assert.deepEqual(await current(),before);
 assert.equal((await db.doc(`deda_diamond_gift_balances/${original}`).get()).data().balance,1991);
});
test('actual aborted atomic purchase writes neither debit, payment, receipt nor native ownership',async()=>{
 await fundedPurchase();const before=await current();
 const aborting={readOwnerSession:uid=>store.readOwnerSession(uid),serverTimestamp:()=>store.serverTimestamp(),
  runTransaction:work=>store.runTransaction(async tx=>{await work(tx);throw Error('atomic-purchase-abort');})};
 await assert.rejects(purchaseReviewedFrameForOwnerSession({store:aborting,auth,idToken:owner.idToken,frameId:'FRAME_03'}),/atomic-purchase-abort/);
 assert.deepEqual(await current(),before);
 assert.equal((await db.doc(`deda_diamond_gift_balances/${original}`).get()).data().balance,1991);
 assert.equal((await db.collection(`${root}/framePurchases`).get()).size,0);
 assert.equal((await db.doc(`deda_lab_frame_receipts/${original}/frames/FRAME_03`).get()).exists,false);
 assert.deepEqual((await db.doc(`deda_native_account_cosmetics/${original}`).get()).data().ownedFrames,[]);
});
