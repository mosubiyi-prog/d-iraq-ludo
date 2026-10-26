'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {activateReviewedBaseline,deploymentPath}=require('./activate-reviewed-baseline.cjs');
const {approveLegacyBaseline,policyPath}=require('./baseline-review.cjs');
const {saveMigrationAssessment}=require('./migration-assessment-store.cjs');
const {savePointTierCarryover}=require('./point-tier-carryover.cjs');
const {saveLegacyOperationReview}=require('./legacy-operation-review.cjs');
const {reviewLegacySettlement}=require('./review-legacy-settlement.cjs');
const {frames}=require('./purchase-frames.cjs');
const {reconcileMigratedReceipt}=require('./migration-gate.cjs');
const {claimMigratedPointTier}=require('./point-tier-claim.cjs');
const core=require('./reconcile-core.cjs');
const A='07700000000',original='@DEDA-ABC234',captureId='activate_capture_00000001';
const migrationId='activate_migration_000001',settlementId='activate_settlement_00001';
const policyRevision='owner_review_policy_00001',deploymentRevision='verified_deployment_000001',fenceId='enforced_writer_fence_00001';
const root=`deda_progress_migrations/${A}`,statePath=`deda_verified_progress/${A}`;
const resolutionPath=`${root}/settlementReviews/${settlementId}`,fencePath=`${root}/fences/${fenceId}`;
const capturePath=`deda_progress_evidence/${A}/captures/${captureId}`;
class Store{
 constructor(){this.docs=new Map();this.writes=[];this.retry=null;this.fail=false;}
 serverTimestamp(){return {seconds:10,nanoseconds:0};}
 async readOwnerSession(uid){return structuredClone(this.docs.get(`deda_sessions/${uid}`)??null);}
 async runTransaction(action){
  const run=async()=>{const writes=new Map();const result=await action({
   get:async p=>{assert.equal(writes.size,0,'all reads precede all writes');return structuredClone(this.docs.get(p)??null);},
   set:(p,d)=>writes.set(p,structuredClone(d)),
  });return {writes,result};};
  let out=await run();if(this.retry){const f=this.retry;this.retry=null;f(this.docs);out=await run();}
  if(this.fail)throw Error('fixture-commit-failure');
  for(const [p,d]of out.writes){this.docs.set(p,d);this.writes.push(p);}return out.result;
 }
}
async function fixture(){
 const store=new Store();
 store.docs.set(capturePath,{format:1,kind:'legacy-local-evidence',accountKey:A,captureId,
  sourceUid:'old-device',installId:'old-install',createdAt:{seconds:1,nanoseconds:0},records:{
   taskPoints:JSON.stringify({version:1,completions:{},awards:{income:{points:10000},
    'point_tier_reserve|5000':{points:-5000,id:'point_tier_reserve|5000',threshold:5000,
     reservedPoints:5000,bonusPoints:50,type:'point_tier_reserve'}},ledger:[]}),
   socialCoinsAndXp:'{"coins":30,"xp":20,"taskClaims":[]}',
   earnedDiamonds:'{"balance":9,"day":"2026-10-26","viewsToday":1}',
  }});
 await saveMigrationAssessment({store,accountKey:A,captureId,migrationId});
 store.docs.set(policyPath,{format:1,enabled:true,revision:policyRevision,
  decisionBasis:'owner-reviewed-grandfathering',acceptedIssues:['local-values-not-server-attested',
   'legacy-writer-fence-not-established','pending-operations-not-reviewed','taskPoints:reservations-require-review']});
 store.docs.set('admins/reviewer',{active:true,status:'active',role:'general_manager',email:'reviewer@example.test'});
 let authCalls=0;
 const auth={verifyIdToken:async(token,revoked)=>{assert.equal(token,'signed-fixture-only');assert.equal(revoked,true);authCalls++;
  return {uid:'reviewer',email:'reviewer@example.test',firebase:{sign_in_provider:'password'}};}};
 await approveLegacyBaseline({store,auth,idToken:'signed-fixture-only',accountKey:A,migrationId,
  expectedEvidenceDigest:store.docs.get(root).evidenceDigest,policyRevision});
 await savePointTierCarryover({store,accountKey:A,migrationId});
 store.docs.set('users/old-device',{accountKey:A,sharePersonalId:original});
 store.docs.set(`deda_share_ids/${original}`,{publicId:original,kind:'personal',active:true,ownerUid:'old-device'});
 store.docs.set(`deda_native_account_cosmetics/${original}`,{originalId:original,ownedFrames:[],pendingFrames:[]});
 const operations=await saveLegacyOperationReview({store,accountKey:A,migrationId,originalId:original});
 const migration=store.docs.get(root);
 // Explicit protected deployment/fence/settlement TEST FIXTURES. Neither this
 // suite nor the worker claims that an old APK was actually fenced or that
 // production deployment, manual settlement or UI integration has occurred.
 store.docs.set(deploymentPath,{format:1,enabled:true,revision:deploymentRevision,
  protocol:'deda-verified-progress-v1',enforcementRevision:'e'.repeat(64),
  clientBound:true,providersReady:true,atomicPurchasesReady:true});
 store.docs.set(fencePath,{format:1,accountKey:A,migrationId,evidenceDigest:migration.evidenceDigest,
  originalId:original,legacyFenceId:fenceId,protocol:'deda-verified-progress-v1',
  deploymentRevision,enforcementRevision:'e'.repeat(64),status:'enforced',createdAt:store.serverTimestamp()});
 store.docs.set(resolutionPath,{format:1,accountKey:A,migrationId,evidenceDigest:migration.evidenceDigest,
  baselineEventKey:migration.baselineEventKey,settlementId,originalId:original,
  operationReviewDigest:operations.report.inputDigest,purchaseCaptureId:null,legacyFenceId:fenceId,
  policyRevision,reviewerUid:'reviewer',reviewerEmail:'reviewer@example.test',status:'resolved',
  decision:'preserve-reviewed-balances-and-carried-rights',pendingPurchases:0,pendingReservations:0,
  createdAt:store.serverTimestamp()});
 store.writes=[];authCalls=0;
 return {store,request:{store,auth,idToken:'signed-fixture-only',accountKey:A,migrationId,settlementId},authCalls:()=>authCalls};
}
const activate=f=>activateReviewedBaseline(f.request);
async function reject(f,code){const before=structuredClone([...f.store.docs]);
 await assert.rejects(activate(f),e=>e.code===code);
 assert.deepEqual([...f.store.docs],before);assert.deepEqual(f.store.writes,[]);}
test('actual six-record activation is atomic and uses only reviewed raw local units',async()=>{
 const f=await fixture();f.store.docs.set(`deda_gm_personal_diamond_wallets/${A}`,{balance:1000000});
 const prior=structuredClone([...f.store.docs]);const result=await activate(f);
 assert.equal(result.replayed,false);assert.equal(result.state.version,1);
 assert.deepEqual(result.state.balances,{points:5000,coins:30,xp:20,earnedDiamonds:9});
 assert.equal(f.store.docs.get(root).phase,'cutover-complete');assert.equal(f.store.writes.length,6);
 assert(f.store.writes.every(p=>p===root||p.startsWith(`${root}/settlements/`)||p.startsWith(`${root}/activations/`)||
  p===statePath||p.startsWith(`${statePath}/events/`)||p.startsWith(`deda_progress_receipts/${A}/events/`)));
 for(const [p,d]of prior)if(p!==root)assert.deepEqual(f.store.docs.get(p),d,p);
 assert.equal(f.store.docs.get(`${root}/pointTierEntitlements/5000`).futureReturnPoints,5050);
});
test('repeat activation preserves timestamps and returns current state after later trusted award',async()=>{
 const f=await fixture();await activate(f);const initial=structuredClone([...f.store.docs]);
 const receipt={format:1,accountKey:A,source:'task-claim-v1',sourceId:'later|task',kind:'award',
  delta:{points:5,coins:10,xp:20,earnedDiamonds:0}};
 const key=core.eventKey(receipt),m=f.store.docs.get(root),receiptId='later_verified_receipt_00001';
 f.store.docs.set(`deda_progress_receipts/${A}/events/${receiptId}`,receipt);
 f.store.docs.set(`${root}/classifications/${key}`,{format:1,accountKey:A,migrationId,
  evidenceDigest:m.evidenceDigest,disposition:'after-cutover',receipt});
 await reconcileMigratedReceipt({store:f.store,accountKey:A,receiptId});f.store.writes=[];
 // Post-cutover ownership may legitimately change; replay does not demand an
 // obsolete live inventory snapshot or reset the current projection.
 f.store.docs.get(`deda_native_account_cosmetics/${original}`).ownedFrames.push('FRAME_03');
 const result=await activate(f);assert.equal(result.replayed,true);assert.equal(result.state.version,2);
 assert.equal(result.state.balances.points,5005);assert.deepEqual(f.store.writes,[]);
 for(const [p,d]of initial)if(p!==statePath&&p!==`deda_native_account_cosmetics/${original}`)assert.deepEqual(f.store.docs.get(p),d,p);
});
test('carried open reserve can be claimed exactly once after real activation',async()=>{
 const f=await fixture();await activate(f);
 const a=await claimMigratedPointTier({store:f.store,accountKey:A,threshold:5000});
 const b=await claimMigratedPointTier({store:f.store,accountKey:A,threshold:5000});
 assert.equal(a.state.balances.points,10050);assert.equal(b.replayed,true);assert.equal(b.state.balances.points,10050);
});
for(const field of ['missing','disabled','clientBound','providersReady','atomicPurchasesReady'])test(`deployment ${field} cannot release reviewed money`,async()=>{
 const f=await fixture();if(field==='missing')f.store.docs.delete(deploymentPath);
 else f.store.docs.get(deploymentPath)[field==='disabled'?'enabled':field]=false;
 await reject(f,['missing','disabled'].includes(field)?'cutover-deployment-not-approved':'cutover-integration-not-ready');
});
for(const field of ['missing','status','enforcementRevision','migrationId'])test(`fence ${field} blocks initialization`,async()=>{
 const f=await fixture();if(field==='missing')f.store.docs.delete(fencePath);
 else f.store.docs.get(fencePath)[field]=field==='status'?'prepared':field==='enforcementRevision'?'a'.repeat(64):'other_migration_00000001';
 await reject(f,field==='missing'?'cutover-enforced-fence-required':'cutover-fence-conflict');
});
for(const field of ['pendingPurchases','pendingReservations','status','evidenceDigest','baselineEventKey'])test(`unsettled/changed ${field} blocks initialization`,async()=>{
 const f=await fixture();f.store.docs.get(resolutionPath)[field]=field.startsWith('pending')?1:
  field==='status'?'requires-review':'a'.repeat(64);await reject(f,'cutover-operations-unresolved');
});
test('missing settlement review cannot be replaced by a naked zero counter',async()=>{
 const f=await fixture();f.store.docs.delete(resolutionPath);await reject(f,'cutover-reviewed-settlement-required');
});
test('a changed live pending purchase after review forces a new review instead of cutover',async()=>{
 const f=await fixture();f.store.docs.get(`deda_native_account_cosmetics/${original}`).pendingFrames.push('FRAME_03');
 await reject(f,'cutover-operation-review-changed');
});
test('changed approved raw balances cannot mint a bigger baseline',async()=>{
 const f=await fixture();f.store.docs.get(`${root}/approvals/${migrationId}`).receipt.delta.points++;
 await reject(f,'migration-baseline-evidence-conflict');
});
for(const field of ['amount','verified','reviewerUid','legacyFenceId','pendingPurchases'])test(`caller ${field} is not accepted as server proof`,async()=>{
 const f=await fixture();f.request[field]=true;await reject(f,'invalid-cutover-request');assert.equal(f.authCalls(),0);
});
for(const field of ['role','active','email','mustChangePassword'])test(`current manager ${field} is verified before release`,async()=>{
 const f=await fixture();f.store.docs.get('admins/reviewer')[field]=field==='role'?'admin':field==='active'?false:
  field==='email'?'other@example.test':true;await reject(f,'cutover-general-manager-required');
});
test('invalid or revoked server ID token is not bypassed by existing approval',async()=>{
 const f=await fixture();f.request.auth={verifyIdToken:async()=>{throw Object.assign(Error('revoked'),{code:'auth/id-token-revoked'});}};
 await reject(f,'auth/id-token-revoked');
});
test('anonymous token cannot perform a general manager activation',async()=>{
 const f=await fixture();f.request.auth={verifyIdToken:async()=>({uid:'reviewer',email:'reviewer@example.test',firebase:{sign_in_provider:'anonymous'}})};
 await reject(f,'cutover-manager-sign-in-required');
});
test('SDK retry rechecks revoked role and discards all six first-attempt writes',async()=>{
 const f=await fixture();f.store.retry=docs=>docs.get('admins/reviewer').role='admin';
 await assert.rejects(activate(f),e=>e.code==='cutover-general-manager-required');
 assert.equal(f.authCalls(),2);assert.deepEqual(f.store.writes,[]);assert.equal(f.store.docs.get(statePath),undefined);
});
test('SDK retry catches a new pending purchase before any baseline commits',async()=>{
 const f=await fixture();f.store.retry=docs=>docs.get(`deda_native_account_cosmetics/${original}`).pendingFrames.push('FRAME_03');
 await assert.rejects(activate(f),e=>e.code==='cutover-operation-review-changed');
 assert.deepEqual(f.store.writes,[]);assert.equal(f.store.docs.get(statePath),undefined);
});
test('failed atomic commit leaves root, source, rights and every wallet unchanged',async()=>{
 const f=await fixture(),before=structuredClone([...f.store.docs]);f.store.fail=true;
 await assert.rejects(activate(f),/fixture-commit-failure/);assert.deepEqual([...f.store.docs],before);
});
for(const path of [statePath,`${root}/settlements/${settlementId}`,`${root}/activations/${migrationId}`])test(`partial existing ${path} is never overwritten`,async()=>{
 const f=await fixture();f.store.docs.set(path,{preserve:'existing'});await reject(f,'cutover-partial-or-existing-state');
});
test('a damaged prior activation cannot reset or reissue the baseline',async()=>{
 const f=await fixture();await activate(f);f.store.writes=[];
 f.store.docs.get(`${root}/activations/${migrationId}`).enforcementRevision='a'.repeat(64);
 await reject(f,'cutover-existing-activation-conflict');
});

const {readMigratedProgressForOwnerSession,claimReviewedPointTierForOwnerSession}=require('./point-tier-session.cjs');
async function ownersFixture(){
 const f=await fixture();await activate(f);
 for(const [u,install]of [['old-owner','install-old'],['new-owner','install-new']]){
  f.store.docs.set(`deda_sessions/${u}`,{uid:u,accountKey:A,installId:install});
  f.store.docs.set(`users/${u}`,{accountKey:A,authMethod:'deda_pin_firestore_v1',trustedInstallIds:[install]});
 }
 f.store.docs.set(`deda_account_profiles/${A}`,{accountKey:A,trustedInstallIds:['install-old','install-new']});
 f.store.docs.set(`deda_account_directory/${A}`,{accountKey:A,active:true});
 f.store.docs.set(`deda_credentials/${A}`,{accountKey:A,active:true});
 f.store.writes=[];return f;
}
const ownerAuth=(uid='new-owner')=>({verifyIdToken:async(token,revoked)=>{
 assert.equal(token,'owner-fixture-only');assert.equal(revoked,true);
 return {uid,firebase:{sign_in_provider:'anonymous'}};
}});
const readOwner=(f,uid='new-owner',extra={})=>readMigratedProgressForOwnerSession({store:f.store,
 auth:ownerAuth(uid),idToken:'owner-fixture-only',...extra});
test('new proven UID reads actually activated balances without claiming a pending right',async()=>{
 const f=await ownersFixture(),before=structuredClone([...f.store.docs]);
 const a=await readOwner(f,'old-owner'),b=await readOwner(f);
 assert.deepEqual(a.state,b.state);assert.deepEqual(b.state.balances,{points:5000,coins:30,xp:20,earnedDiamonds:9});
 assert.deepEqual([...f.store.docs],before);assert.deepEqual(f.store.writes,[]);
 assert.equal(f.store.docs.get(`${root}/pointTierClaims/5000`),undefined);
});
for(const kind of ['missing-session','wrong-account','untrusted-install','inactive-directory','inactive-credential'])test(`read refuses ${kind} instead of a zero/default balance`,async()=>{
 const f=await ownersFixture();
 if(kind==='missing-session')f.store.docs.delete('deda_sessions/new-owner');
 if(kind==='wrong-account')f.store.docs.get('users/new-owner').accountKey='07700000001';
 if(kind==='untrusted-install')f.store.docs.get('users/new-owner').trustedInstallIds=[];
 if(kind==='inactive-directory')f.store.docs.get(`deda_account_directory/${A}`).active=false;
 if(kind==='inactive-credential')f.store.docs.get(`deda_credentials/${A}`).active=false;
 const before=structuredClone([...f.store.docs]);
 await assert.rejects(readOwner(f),e=>e.code==='point-session-owner-proof-required');
 assert.deepEqual([...f.store.docs],before);assert.deepEqual(f.store.writes,[]);
});
test('unmigrated account cannot treat an old server projection as a completed restore',async()=>{
 const f=await ownersFixture();const m=f.store.docs.get(root);m.phase='baseline-approved';m.settlementId=null;
 await assert.rejects(readOwner(f),e=>e.code==='migration-pending');assert.deepEqual(f.store.writes,[]);
});
for(const field of ['accountKey','uid','installId','verified','balance'])test(`read never accepts caller ${field} as identity or money`,async()=>{
 const f=await ownersFixture();await assert.rejects(readOwner(f,'new-owner',{[field]:true}),e=>e.code==='invalid-progress-read-request');
 assert.deepEqual(f.store.writes,[]);
});
test('a session change during SDK transaction retry prevents returning another account state',async()=>{
 const f=await ownersFixture();let checks=0;const base=ownerAuth();
 const auth={verifyIdToken:async(...args)=>{checks++;return base.verifyIdToken(...args);}};
 f.store.retry=docs=>docs.get('deda_sessions/new-owner').accountKey='07700000001';
 await assert.rejects(readMigratedProgressForOwnerSession({store:f.store,auth,idToken:'owner-fixture-only'}),
  e=>e.code==='point-session-owner-proof-required');
 assert.equal(checks,3);assert.deepEqual(f.store.writes,[]);
});
for(const proof of ['activation','fence','settlement-review'])test(`owner restore and claim require actual ${proof} evidence`,async()=>{
 const f=await ownersFixture();f.store.docs.delete(proof==='activation'?`${root}/activations/${migrationId}`:
  proof==='fence'?fencePath:resolutionPath);
 const before=structuredClone([...f.store.docs]);
 await assert.rejects(readOwner(f),e=>e.code==='reviewed-activation-proof-required');
 await assert.rejects(claimReviewedPointTierForOwnerSession({store:f.store,auth:ownerAuth(),idToken:'owner-fixture-only',threshold:5000}),
  e=>e.code==='reviewed-activation-proof-required');
 assert.deepEqual([...f.store.docs],before);assert.deepEqual(f.store.writes,[]);
});
test('reviewed owner claim shares the exact verified activation transaction and deduplicates',async()=>{
 const f=await ownersFixture();
 const request={store:f.store,auth:ownerAuth(),idToken:'owner-fixture-only',threshold:5000};
 const a=await claimReviewedPointTierForOwnerSession(request),b=await claimReviewedPointTierForOwnerSession(request);
 assert.equal(a.state.balances.points,10050);assert.equal(b.replayed,true);assert.equal(b.state.balances.points,10050);
});

const purchaseCaptureId='settlement_purchase_capture_01';
const purchasePath=`deda_purchase_evidence/${A}/captures/${purchaseCaptureId}`;
async function settlementFixture(change=()=>{}){
 const f=await fixture();f.store.docs.delete(resolutionPath);
 const snapshot={format:1,accountKey:A,originalId:original,inventory:null,
  frameJournals:Object.fromEntries(frames.map(frame=>[frame,null]))};
 change(snapshot,f);
 f.store.docs.set(purchasePath,{format:1,kind:'legacy-purchase-evidence',accountKey:A,
  sourceUid:'old-device',installId:'old-install',captureId:purchaseCaptureId,
  records:{originalId:original,progressCaptureId:captureId,localSnapshot:JSON.stringify(snapshot)},
  createdAt:f.store.serverTimestamp()});
 const {report}=await saveLegacyOperationReview({store:f.store,accountKey:A,migrationId,originalId:original,purchaseCaptureId});
 f.settlementRequest={store:f.store,auth:f.request.auth,idToken:f.request.idToken,accountKey:A,migrationId,
  settlementId,expectedOperationReviewDigest:report.inputDigest,purchaseCaptureId,originalId:original,legacyFenceId:fenceId};
 f.store.writes=[];return f;
}
const settle=f=>reviewLegacySettlement(f.settlementRequest);
async function settlementRejected(f,code){
 const before=structuredClone([...f.store.docs]);
 await assert.rejects(settle(f),e=>e.code===code);
 assert.deepEqual([...f.store.docs],before);assert.deepEqual(f.store.writes,[]);
}
test('settlement producer consumes real captured absence and carryover, writes only immutable resolution',async()=>{
 const f=await settlementFixture(),before=structuredClone([...f.store.docs]);
 const result=await settle(f);assert.equal(result.replayed,false);assert.equal(result.canReleaseBalance,false);
 assert.deepEqual(f.store.writes,[resolutionPath]);
 for(const [p,d]of before)assert.deepEqual(f.store.docs.get(p),d,p);
 const resolution=f.store.docs.get(resolutionPath);
 assert.equal(resolution.purchaseCaptureId,purchaseCaptureId);assert.equal(resolution.pendingPurchases,0);
 assert.equal(resolution.pendingReservations,0);assert.equal(f.store.docs.has(statePath),false);
 f.store.writes=[];const stored=structuredClone(resolution);
 assert.equal((await settle(f)).replayed,true);assert.deepEqual(f.store.docs.get(resolutionPath),stored);
 assert.deepEqual(f.store.writes,[]);
});
test('actual produced settlement permits six-record activation then replays without resetting later inventory',async()=>{
 const f=await settlementFixture();await settle(f);f.store.writes=[];
 assert.equal((await activate(f)).state.balances.points,5000);
 f.store.docs.get(`deda_native_account_cosmetics/${original}`).pendingFrames.push('FRAME_03');
 f.store.writes=[];assert.equal((await settle(f)).replayed,true);assert.deepEqual(f.store.writes,[]);
 assert.equal((await activate(f)).replayed,true);
});
for(const value of ['charging','paid',false,1,['paid']])test(`settlement cannot erase uncertain payment ${JSON.stringify(value)}`,async()=>{
 const f=await settlementFixture(snapshot=>{snapshot.frameJournals.FRAME_03=value;});
 await settlementRejected(f,'settlement-payment-journal-needs-review');
});
for(const value of ['{"owned":["badge_gold"]}',false,1,[]])test(`settlement cannot assume style history settled ${JSON.stringify(value)}`,async()=>{
 const f=await settlementFixture(snapshot=>{snapshot.inventory=value;});
 await settlementRejected(f,'settlement-style-history-needs-review');
});
for(const kind of ['pending','missing-pending','unknown-owned','partial-receipt'])test(`settlement blocks ${kind} without changing native sources`,async()=>{
 const f=await settlementFixture((_snapshot,f)=>{
  const native=f.store.docs.get(`deda_native_account_cosmetics/${original}`);
  if(kind==='pending')native.pendingFrames=['FRAME_03'];
  if(kind==='missing-pending')delete native.pendingFrames;
  if(kind==='unknown-owned')native.ownedFrames=['FRAME_FUTURE'];
  if(kind==='partial-receipt')f.store.docs.set(`deda_lab_frame_receipts/${original}/frames/FRAME_03`,{kind:'lab_frame'});
 });await settlementRejected(f,'settlement-native-purchases-needs-review');
});
test('stale review is recomputed within the settlement transaction, not trusted from counters',async()=>{
 const f=await settlementFixture();f.store.docs.get(`deda_native_account_cosmetics/${original}`).pendingFrames=['FRAME_03'];
 await settlementRejected(f,'settlement-operation-review-changed');
});
test('settlement retry rechecks changed inventory and commits no resolution',async()=>{
 const f=await settlementFixture();f.store.retry=docs=>docs.get(`deda_native_account_cosmetics/${original}`).pendingFrames.push('FRAME_03');
 await assert.rejects(settle(f),e=>e.code==='settlement-operation-review-changed');
 assert.equal(f.store.docs.has(resolutionPath),false);assert.deepEqual(f.store.writes,[]);
});
test('settlement retry revalidates manager identity and revocation',async()=>{
 const f=await settlementFixture();let calls=0;
 f.settlementRequest.auth={verifyIdToken:async()=>{calls++;if(calls===2)throw Object.assign(Error('revoked'),{code:'auth/id-token-revoked'});
  return {uid:'reviewer',email:'reviewer@example.test',firebase:{sign_in_provider:'password'}};}};
 f.store.retry=()=>{};await settlementRejected(f,'auth/id-token-revoked');assert.equal(calls,2);
});
test('settlement rejects caller amounts, zero counters and absent source capture',async()=>{
 for(const extra of [{pendingPurchases:0},{amount:0},{approved:true}]){
  const f=await settlementFixture();Object.assign(f.settlementRequest,extra);await settlementRejected(f,'invalid-settlement-review-request');
 }
 const f=await settlementFixture();f.store.docs.delete(purchasePath);await settlementRejected(f,'purchase-evidence-missing');
});
for(const missing of ['fence','deployment','approval','carryover'])test(`settlement requires ${missing} before writing resolution`,async()=>{
 const f=await settlementFixture();
 f.store.docs.delete(missing==='fence'?fencePath:missing==='deployment'?deploymentPath:
  missing==='approval'?`${root}/approvals/${migrationId}`:`${root}/pointTierCarryovers/${migrationId}`);
 await settlementRejected(f,{fence:'cutover-enforced-fence-required',deployment:'cutover-deployment-not-approved',
  approval:'settlement-baseline-approval-required',carryover:'migration-point-carryover-required'}[missing]);
});
test('failed settlement commit changes no source, carryover, approval, balance or resolution',async()=>{
 const f=await settlementFixture();f.store.fail=true;const before=structuredClone([...f.store.docs]);
 await assert.rejects(settle(f),/fixture-commit-failure/);assert.deepEqual([...f.store.docs],before);
});
