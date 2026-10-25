'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {savePointTierCarryover}=require('./point-tier-carryover.cjs');
const {approveLegacyBaseline,policyPath}=require('./baseline-review.cjs');
const {saveMigrationAssessment}=require('./migration-assessment-store.cjs');
const A='07700000000',captureId='carryover_capture_0000001',migrationId='carryover_migration_000001';
const root=`deda_progress_migrations/${A}`,source=`deda_progress_evidence/${A}/captures/${captureId}`;
const summaryPath=`${root}/pointTierCarryovers/${migrationId}`,stage=t=>`${root}/pointTierEntitlements/${t}`;
const revision='owner_review_policy_00001';
class Store{
 constructor(){this.docs=new Map();this.writes=[];this.retry=null;this.fail=false;}
 serverTimestamp(){return {seconds:10,nanoseconds:0};}
 async runTransaction(action){
  const run=async()=>{const writes=new Map();const result=await action({get:async path=>{assert.equal(writes.size,0);return structuredClone(this.docs.get(path)??null);},set:(path,data)=>writes.set(path,structuredClone(data))});return {writes,result};};
  let out=await run();if(this.retry){const retry=this.retry;this.retry=null;retry(this.docs);out=await run();}
  if(this.fail)throw Error('fixture-commit-failure');for(const [path,data]of out.writes){this.docs.set(path,data);this.writes.push(path);}return out.result;
 }
}
const reserve=t=>({points:-t,id:`point_tier_reserve|${t}`,threshold:t,reservedPoints:t,bonusPoints:t/100,type:'point_tier_reserve'});
const claim=t=>({points:t+t/100,id:`point_tier_claim|${t}`,threshold:t,reservedPoints:t,bonusPoints:t/100,type:'point_tier_claim'});
async function fixture(awards={'point_tier_reserve|5000':reserve(5000)}){
 const store=new Store();store.docs.set(source,{format:1,kind:'legacy-local-evidence',accountKey:A,captureId,
 sourceUid:'old-device',installId:'old-install',createdAt:{seconds:1,nanoseconds:0},records:{
 taskPoints:JSON.stringify({version:1,awards:{income:{points:100000},...awards},completions:{},ledger:[]}),
 socialCoinsAndXp:'{"coins":30,"xp":20,"taskClaims":[]}',earnedDiamonds:'{"balance":9,"day":"2026-10-25","viewsToday":1}'}});
 await saveMigrationAssessment({store,accountKey:A,captureId,migrationId});
 store.docs.set(policyPath,{format:1,enabled:true,revision,decisionBasis:'owner-reviewed-grandfathering',acceptedIssues:[
 'local-values-not-server-attested','legacy-writer-fence-not-established','pending-operations-not-reviewed','taskPoints:reservations-require-review']});
 store.docs.set('admins/reviewer',{active:true,status:'active',role:'general_manager',email:'reviewer@example.test'});
 const auth={verifyIdToken:async()=>({uid:'reviewer',email:'reviewer@example.test',firebase:{sign_in_provider:'password'}})};
 await approveLegacyBaseline({store,auth,idToken:'fixture-only',accountKey:A,migrationId,policyRevision:revision,expectedEvidenceDigest:store.docs.get(root).evidenceDigest});
 store.writes=[];return {store,request:{store,accountKey:A,migrationId}};
}
const carry=f=>savePointTierCarryover(f.request);
async function reject(f,code){const before=structuredClone([...f.store.docs]);await assert.rejects(carry(f),e=>e.code===code);assert.deepEqual([...f.store.docs],before);assert.deepEqual(f.store.writes,[]);}
test('approved open reserve becomes a protected future right without refund, zeroing, or balance writes',async()=>{
 const f=await fixture();f.store.docs.set('existing-manager-wallet',{balance:1000000});const before=structuredClone([...f.store.docs]);
 const r=await carry(f);assert.equal(r.summary.observedUnclaimedReturns,1);assert.equal(r.summary.canReleaseBalance,false);
 assert.equal(f.store.docs.get(stage(5000)).status,'reserved-awaiting-cutover');assert.equal(f.store.docs.get(stage(5000)).futureReturnPoints,5050);
 assert.equal(f.store.docs.get(stage(5000)).canClaimNow,false);assert.equal(f.store.docs.get(stage(5000)).recordedReservePoints,-5000);
 assert.equal(f.store.docs.get(stage(10000)).status,'not-observed');assert.equal(f.store.docs.get(stage(10000)).futureReturnPoints,null);
 assert.equal(f.store.writes.length,6);for(const [path,value]of before)assert.deepEqual(f.store.docs.get(path),value);
 assert.ok(f.store.writes.every(path=>path.includes('/pointTier')));assert.equal(f.store.docs.get(root).settlementId,null);
});
test('claim already included in the approved raw baseline cannot get a second return',async()=>{
 const f=await fixture({'point_tier_reserve|5000':reserve(5000),'point_tier_claim|5000':claim(5000)});await carry(f);
 const record=f.store.docs.get(stage(5000));assert.equal(record.status,'claimed-in-baseline');assert.equal(record.futureReturnPoints,null);
 assert.equal(record.recordedClaimPoints,5050);assert.equal(f.store.docs.get(summaryPath).observedUnclaimedReturns,0);
});
test('final 25000 prize reserve remains spent with no future return or invented bonus',async()=>{
 const awards={};for(const t of [5000,10000,15000,20000,25000]){
 awards[`point_tier_reserve|${t}`]=reserve(t);if(t!==25000)awards[`point_tier_claim|${t}`]=claim(t);}
 const f=await fixture(awards);await carry(f);const last=f.store.docs.get(stage(25000));
 assert.equal(last.status,'terminal-prize-spent');assert.equal(last.recordedReservePoints,-25000);assert.equal(last.futureReturnPoints,null);
 assert.equal(last.canRefundNow,false);assert.equal(f.store.docs.get(summaryPath).terminalPrizeReserved,true);
});
test('replay preserves all original timestamps and every source instead of writing stages again',async()=>{
 const f=await fixture();await carry(f);const before=structuredClone([...f.store.docs]);f.store.writes=[];
 assert.equal((await carry(f)).replayed,true);assert.deepEqual([...f.store.docs],before);assert.deepEqual(f.store.writes,[]);
});
test('Firestore map order changes in private approval do not change deterministic carryover identity',async()=>{
 const f=await fixture();await carry(f);f.store.writes=[];
 const a=f.store.docs.get(`${root}/approvals/${migrationId}`);a.receipt.delta=Object.fromEntries(Object.entries(a.receipt.delta).reverse());
 assert.equal((await carry(f)).replayed,true);assert.deepEqual(f.store.writes,[]);
});
for(const phase of ['evidence-saved','cutover-complete'])test(`${phase} does not authorize import or resetting later rights`,async()=>{
 const f=await fixture();const m=f.store.docs.get(root);m.phase=phase;
 if(phase==='evidence-saved'){m.baselineEventKey=null;m.settlementId=null;}else m.settlementId='settlement_review_0000001';
 await reject(f,'point-carryover-reviewed-baseline-required');
});
for(const kind of ['missing','disabled','changed-revision'])test(`${kind} protected policy refuses private carryover`,async()=>{
 const f=await fixture();if(kind==='missing')f.store.docs.delete(policyPath);else if(kind==='disabled')f.store.docs.get(policyPath).enabled=false;
 else f.store.docs.get(policyPath).revision='different_policy_0000001';
 await reject(f,kind==='changed-revision'?'invalid-baseline-review-policy':'baseline-review-policy-disabled');
});
for(const [field,value]of [['active',false],['role','admin'],['status','paused'],['email','other@example.test'],['mustChangePassword',true]])test(`reviewer's ${field} is rechecked before any stage transfer`,async()=>{
 const f=await fixture();f.store.docs.get('admins/reviewer')[field]=value;await reject(f,'point-carryover-reviewer-inactive');
});
test('changing original archived bytes after approval does not silently rebase pending rights',async()=>{
 const f=await fixture();f.store.docs.get(source).records.taskPoints+=' ';await reject(f,'migration-reviewed-evidence-conflict');
});
test('missing approval cannot be replaced by phase baseline-approved alone',async()=>{
 const f=await fixture();f.store.docs.delete(`${root}/approvals/${migrationId}`);await reject(f,'point-carryover-approval-required');
});
test('inflated approved baseline amount is rejected against the original raw assessment',async()=>{
 const f=await fixture();f.store.docs.get(`${root}/approvals/${migrationId}`).receipt.delta.points++;
 await reject(f,'point-carryover-baseline-conflict');
});
for(const awards of [
 {'point_tier_claim|5000':claim(5000)},
 {'point_tier_reserve|5000':{points:-1}},
 {'point_tier_reserve|10000':reserve(10000)},
 {'point_tier|5000':{points:50}},
 {'point_tier_reserve|25000':reserve(25000),'point_tier_claim|25000':claim(25000)},
])test(`ambiguous/history-correction case stays untouched: ${Object.keys(awards).join(',')}`,async()=>{
 const f=await fixture(awards);await reject(f,'point-carryover-history-needs-review');
});
test('partial prior stage without a summary cannot be overwritten by a fresh import',async()=>{
 const f=await fixture();f.store.docs.set(stage(5000),{status:'preserve-existing'});await reject(f,'point-carryover-conflict');
});
test('changed previously imported future return amount refuses replay instead of restoring/re-awarding it',async()=>{
 const f=await fixture();await carry(f);f.store.writes=[];f.store.docs.get(stage(5000)).futureReturnPoints=999999;
 await reject(f,'point-carryover-conflict');
});
test('already initialized financial state is never reset or augmented by carrying historical rights',async()=>{
 const f=await fixture();f.store.docs.set(`deda_verified_progress/${A}`,{balances:{points:1000000}});
 await reject(f,'point-carryover-already-activated');
});
for(const field of ['amount','threshold','verified','reviewerUid'])test(`caller ${field} cannot supply a right or bypass the approved basis`,async()=>{
 const f=await fixture();f.request[field]=true;await reject(f,'invalid-point-carryover-request');
});
test('transaction retry rereads a revoked role and discards all first-attempt stage writes',async()=>{
 const f=await fixture();f.store.retry=docs=>docs.get('admins/reviewer').role='admin';
 await assert.rejects(carry(f),e=>e.code==='point-carryover-reviewer-inactive');assert.deepEqual(f.store.writes,[]);assert.equal(f.store.docs.get(summaryPath),undefined);
});
test('atomic commit failure retains all old reservations and writes no private stage or summary',async()=>{
 const f=await fixture();f.store.fail=true;const before=structuredClone([...f.store.docs]);
 await assert.rejects(carry(f),/fixture-commit-failure/);assert.deepEqual([...f.store.docs],before);
});

// The real migration gate consumes the writer's output in the SAME financial
// transaction. Cutover and settlement here remain explicit test fixtures.
const {reconcileMigratedReceipt}=require('./migration-gate.cjs');
const {reconcileVerifiedReceipt}=require('./reconcile-store.cjs');
const core=require('./reconcile-core.cjs');
const nextReceiptId='after_cutover_award_000001';
const nextReceipt={format:1,accountKey:A,source:'task-claim-v1',sourceId:'day|new-task',kind:'award',
 delta:{points:5,coins:10,xp:20,earnedDiamonds:0}};
const gate=f=>reconcileMigratedReceipt({store:f.store,accountKey:A,receiptId:nextReceiptId});
async function activatedFixture(awards){
 const f=await fixture(awards);await carry(f);
 const approval=f.store.docs.get(`${root}/approvals/${migrationId}`);
 const baselineReceiptId='approved_baseline_0000001';
 f.store.docs.set(`deda_progress_receipts/${A}/events/${baselineReceiptId}`,approval.receipt);
 await reconcileVerifiedReceipt({store:f.store,accountKey:A,receiptId:baselineReceiptId});
 const migration=f.store.docs.get(root);migration.phase='cutover-complete';migration.settlementId='settlement_fixture_000001';
 f.store.docs.set(`${root}/settlements/${migration.settlementId}`,{format:1,accountKey:A,migrationId,
 evidenceDigest:migration.evidenceDigest,baselineEventKey:migration.baselineEventKey,
 legacyFenceId:'writer_fence_fixture_00001',pendingPurchases:0,pendingReservations:0});
 f.store.docs.set(`deda_progress_receipts/${A}/events/${nextReceiptId}`,structuredClone(nextReceipt));
 f.store.docs.set(`${root}/classifications/${core.eventKey(nextReceipt)}`,{format:1,accountKey:A,migrationId,
 evidenceDigest:migration.evidenceDigest,disposition:'after-cutover',receipt:structuredClone(nextReceipt)});
 f.store.writes=[];return f;
}
async function rejectGate(f,code){
 const before=structuredClone([...f.store.docs]);await assert.rejects(gate(f),e=>e.code===code);
 assert.deepEqual([...f.store.docs],before);assert.deepEqual(f.store.writes,[]);
}
test('gated award validates the real saved five-stage proof without releasing a reserved return',async()=>{
 const f=await activatedFixture(),before=structuredClone(f.store.docs.get(stage(5000)));
 const result=await gate(f);assert.equal(result.state.balances.points,95005);assert.equal(result.state.version,2);
 assert.deepEqual(f.store.docs.get(stage(5000)),before);assert.equal(before.futureReturnPoints,5050);
 f.store.writes=[];assert.equal((await gate(f)).replayed,true);assert.deepEqual(f.store.writes,[]);
});
test('completed root and zero pending counters cannot replace missing carried rights',async()=>{
 const f=await activatedFixture();f.store.docs.delete(summaryPath);await rejectGate(f,'migration-point-carryover-required');
});
for(const threshold of [5000,10000,15000,20000,25000])test(`missing stage ${threshold} blocks financial write even when not observed locally`,async()=>{
 const f=await activatedFixture();f.store.docs.delete(stage(threshold));await rejectGate(f,'migration-point-carryover-conflict');
});
for(const [field,value]of [['futureReturnPoints',999999],['status','claimed-in-baseline'],['canClaimNow',true],
 ['canRefundNow',true],['recordedReservePoints',0],['sourceReserveKey','other-key'],['evidenceDigest','f'.repeat(64)],
 ['migrationId','different_migration_000001'],['basisDigest','a'.repeat(64)]])test(`changed carried ${field} cannot cross the financial gate`,async()=>{
 const f=await activatedFixture();f.store.docs.get(stage(5000))[field]=value;await rejectGate(f,'migration-point-carryover-conflict');
});
for(const [field,value]of [['observedUnclaimedReturns',0],['canReleaseBalance',true],['stageCount',4],['canAutoSettle',true]])test(`changed summary ${field} blocks even a verified award`,async()=>{
 const f=await activatedFixture();f.store.docs.get(summaryPath)[field]=value;await rejectGate(f,'migration-point-carryover-conflict');
});
test('missing historical approval cannot be replaced by carried stages and a completed flag',async()=>{
 const f=await activatedFixture();f.store.docs.delete(`${root}/approvals/${migrationId}`);await rejectGate(f,'point-carryover-approval-required');
});
test('changed historical policy revision does not silently rebase approved stage rights',async()=>{
 const f=await activatedFixture();f.store.docs.get(`${root}/approvals/${migrationId}`).policyRevision='different_policy_0000001';
 await rejectGate(f,'migration-point-carryover-conflict');
});
test('different stage timestamp rejects a mixed or partial carryover commit',async()=>{
 const f=await activatedFixture();f.store.docs.get(stage(10000)).createdAt.seconds++;
 await rejectGate(f,'migration-point-carryover-conflict');
});
test('malformed proof timestamp is rejected instead of ignored',async()=>{
 const f=await activatedFixture();f.store.docs.get(summaryPath).createdAt='fixture-time';
 await rejectGate(f,'point-carryover-invalid-approval-time');
});
test('transaction retry rechecks rights and cannot credit after a carryover changed',async()=>{
 const f=await activatedFixture();f.store.retry=docs=>docs.get(stage(5000)).futureReturnPoints++;
 await assert.rejects(gate(f),e=>e.code==='migration-point-carryover-conflict');
 assert.deepEqual(f.store.writes,[]);assert.equal(f.store.docs.get(`deda_verified_progress/${A}`).version,1);
});
test('post-cutover rewards do not depend on a historical reviewer remaining a manager or a review policy staying enabled',async()=>{
 const f=await activatedFixture();f.store.docs.get(policyPath).enabled=false;f.store.docs.get('admins/reviewer').active=false;
 assert.equal((await gate(f)).state.version,2);
});
test('final prize stays spent and previous claimed stages receive no second returns through the gate',async()=>{
 const awards={};for(const t of [5000,10000,15000,20000,25000]){
 awards[`point_tier_reserve|${t}`]=reserve(t);if(t!==25000)awards[`point_tier_claim|${t}`]=claim(t);}
 const f=await activatedFixture(awards),before=structuredClone([...f.store.docs].filter(([path])=>path.includes('/pointTier')));
 const balance=f.store.docs.get(`deda_verified_progress/${A}`).balances.points;
 assert.equal((await gate(f)).state.balances.points,balance+5);
 assert.deepEqual([...f.store.docs].filter(([path])=>path.includes('/pointTier')),before);
});
test('no observed stage history needs no invented zero entitlements, but orphan records block it',async()=>{
 const f=await activatedFixture({});f.store.docs.delete(summaryPath);
 for(const t of [5000,10000,15000,20000,25000])f.store.docs.delete(stage(t));
 assert.equal((await gate(f)).state.version,2);f.store.writes=[];
 f.store.docs.set(stage(5000),{canClaimNow:true});await rejectGate(f,'migration-point-carryover-conflict');
});
test('an existing empty-history summary must be checked rather than skipped',async()=>{
 const f=await activatedFixture({});f.store.docs.get(summaryPath).canReleaseBalance=true;
 await rejectGate(f,'migration-point-carryover-conflict');
});

const {claimMigratedPointTier}=require('./point-tier-claim.cjs');
const claimRight=(f,threshold=5000)=>claimMigratedPointTier({store:f.store,accountKey:A,threshold});
const claimRecord=t=>`${root}/pointTierClaims/${t}`;
async function rejectClaim(f,code,threshold=5000){
 const before=structuredClone([...f.store.docs]);await assert.rejects(claimRight(f,threshold),e=>e.code===code);
 assert.deepEqual([...f.store.docs],before);assert.deepEqual(f.store.writes,[]);
}
test('first migrated claim atomically credits exact reserved return with receipt, classification, event and claim marker',async()=>{
 const f=await activatedFixture(),before=structuredClone([...f.store.docs]),result=await claimRight(f);
 assert.equal(result.replayed,false);assert.equal(result.returnedPoints,5050);assert.equal(result.state.balances.points,100050);
 assert.deepEqual(result.state.balances,{points:100050,coins:30,xp:20,earnedDiamonds:9});assert.equal(result.state.version,2);
 assert.equal(f.store.writes.length,5);const marker=f.store.docs.get(claimRecord(5000));assert.equal(marker.status,'claimed');
 const receipt=f.store.docs.get(`deda_progress_receipts/${A}/events/${result.eventKey}`);
 assert.equal(receipt.source,'point-tier-return-v1');assert.equal(receipt.delta.points,5050);
 for(const [path,value]of before)if(path!==`deda_verified_progress/${A}`)assert.deepEqual(f.store.docs.get(path),value);
 assert.equal(f.store.docs.get(stage(5000)).status,'reserved-awaiting-cutover');
});
test('lost successful claim response and repeated request preserve proof and do not award again',async()=>{
 const f=await activatedFixture();await claimRight(f);const before=structuredClone([...f.store.docs]);f.store.writes=[];
 const replay=await claimRight(f);assert.equal(replay.replayed,true);assert.equal(replay.state.balances.points,100050);
 assert.deepEqual([...f.store.docs],before);assert.deepEqual(f.store.writes,[]);
});
test('claim retry after a later award returns current balances rather than restoring old after-balance',async()=>{
 const f=await activatedFixture();await claimRight(f);await gate(f);f.store.writes=[];
 const replay=await claimRight(f);assert.equal(replay.state.balances.points,100055);assert.equal(replay.state.version,3);
 assert.deepEqual(f.store.writes,[]);
});
test('generic gated receipt replay cannot credit a claim produced by the atomic worker again',async()=>{
 const f=await activatedFixture(),first=await claimRight(f);f.store.writes=[];
 const r=await reconcileMigratedReceipt({store:f.store,accountKey:A,receiptId:first.eventKey});
 assert.equal(r.replayed,true);assert.equal(r.state.version,2);assert.equal(r.state.balances.points,100050);
 assert.deepEqual(f.store.writes,[]);
});
for(const threshold of [10000,15000,20000])test(`stage ${threshold} uses its original fixed return after previous stages were claimed in raw evidence`,async()=>{
 const awards={};for(const t of [5000,10000,15000,20000]){
 if(t>threshold)break;awards[`point_tier_reserve|${t}`]=reserve(t);if(t<threshold)awards[`point_tier_claim|${t}`]=claim(t);}
 const f=await activatedFixture(awards),prior=f.store.docs.get(`deda_verified_progress/${A}`).balances.points;
 const r=await claimRight(f,threshold);assert.equal(r.returnedPoints,threshold+threshold/100);
 assert.equal(r.state.balances.points,prior+threshold+threshold/100);
});
for(const threshold of [25000,0,-5000,5000.5,'5000',100000])test(`invalid or terminal stage ${JSON.stringify(threshold)} never grants points`,async()=>{
 const f=await activatedFixture();await rejectClaim(f,'point-tier-return-ineligible',threshold);
});
for(const field of ['amount','verified','reviewerUid','sourceId','migrationId'])test(`client ${field} cannot control a claim receipt`,async()=>{
 const f=await activatedFixture();await assert.rejects(claimMigratedPointTier({store:f.store,accountKey:A,threshold:5000,[field]:true}),e=>e.code==='invalid-point-tier-claim-request');
 assert.deepEqual(f.store.writes,[]);
});
test('a return already included in the baseline cannot be claimed a second time',async()=>{
 const f=await activatedFixture({'point_tier_reserve|5000':reserve(5000),'point_tier_claim|5000':claim(5000)});
 await rejectClaim(f,'point-tier-return-ineligible');
});
test('an unobserved local stage cannot be claimed as an implicit empty entitlement',async()=>{
 const f=await activatedFixture({});await rejectClaim(f,'point-tier-return-ineligible');
});
for(const phase of ['baseline-approved','evidence-saved'])test(`${phase} prevents a reserved right from being released early`,async()=>{
 const f=await activatedFixture();const m=f.store.docs.get(root);m.phase=phase;
 if(phase==='evidence-saved'){m.baselineEventKey=null;m.settlementId=null;}
 await rejectClaim(f,'migration-pending');
});
for(const field of ['pendingPurchases','pendingReservations'])test(`${field} stops claims without partial receipt or wallet write`,async()=>{
 const f=await activatedFixture();f.store.docs.get(`${root}/settlements/settlement_fixture_000001`)[field]=1;
 await rejectClaim(f,'migration-not-settled');
});
test('missing immutable stage proof blocks the claim producer as well as ordinary financial events',async()=>{
 const f=await activatedFixture();f.store.docs.delete(stage(25000));await rejectClaim(f,'migration-point-carryover-conflict');
});
test('failed transaction leaves all five claim writes and original archived rights untouched',async()=>{
 const f=await activatedFixture(),before=structuredClone([...f.store.docs]);f.store.fail=true;
 await assert.rejects(claimRight(f),/fixture-commit-failure/);assert.deepEqual([...f.store.docs],before);assert.deepEqual(f.store.writes,[]);
});
test('retry rechecks pending settlement and cannot release a right after it changes',async()=>{
 const f=await activatedFixture();f.store.retry=docs=>docs.get(`${root}/settlements/settlement_fixture_000001`).pendingPurchases=1;
 await assert.rejects(claimRight(f),e=>e.code==='migration-not-settled');assert.deepEqual(f.store.writes,[]);
 assert.equal(f.store.docs.get(`deda_verified_progress/${A}`).version,1);
});
for(const partial of ['claim','receipt','event','classification'])test(`orphan ${partial} cannot be overwritten to grant a second return`,async()=>{
 const f=await activatedFixture(),r=await claimRight(f),paths={claim:claimRecord(5000),receipt:`deda_progress_receipts/${A}/events/${r.eventKey}`,
 event:`deda_verified_progress/${A}/events/${r.eventKey}`,classification:`${root}/classifications/${r.eventKey}`};
 if(partial==='claim'){for(const key of ['receipt','event','classification'])f.store.docs.delete(paths[key]);}
 else{f.store.docs.delete(paths.claim);for(const key of ['receipt','event','classification'])if(key!==partial)f.store.docs.delete(paths[key]);}
 f.store.writes=[];await rejectClaim(f,'point-tier-claim-conflict');
});
for(const [field,value]of [['returnedPoints',999999],['basisDigest','f'.repeat(64)],['migrationId','different_migration_000001'],
 ['threshold',10000],['appliedVersion',99],['status','pending'],['receiptId','other_receipt_00000001']])test(`tampered claim ${field} cannot authorize replay or another award`,async()=>{
 const f=await activatedFixture();await claimRight(f);f.store.docs.get(claimRecord(5000))[field]=value;f.store.writes=[];
 await rejectClaim(f,'point-tier-claim-conflict');
});
test('claim after current manager demotion consumes the historical protected right without requiring a new review',async()=>{
 const f=await activatedFixture();f.store.docs.get('admins/reviewer').active=false;f.store.docs.get(policyPath).enabled=false;
 assert.equal((await claimRight(f)).returnedPoints,5050);
});
for(const points of [1,5000,5051,25250])test(`point-return receipt amount ${points} cannot masquerade as a valid original stage`,()=>{
 assert.throws(()=>core.parseReceipt({format:1,accountKey:A,source:'point-tier-return-v1',sourceId:`${migrationId}|5000|${'a'.repeat(64)}`,
 kind:'award',delta:{points,coins:0,xp:0,earnedDiamonds:0}},A),e=>e.code==='invalid-point-tier-return');
});
for(const unit of ['coins','xp','earnedDiamonds'])test(`point-return receipt cannot add unrelated ${unit}`,()=>{
 assert.throws(()=>core.parseReceipt({format:1,accountKey:A,source:'point-tier-return-v1',sourceId:`${migrationId}|5000|${'a'.repeat(64)}`,
 kind:'award',delta:{points:5050,coins:0,xp:0,earnedDiamonds:0,[unit]:1}},A),e=>e.code==='invalid-point-tier-return');
});
for(const sourceId of ['arbitrary',`${migrationId}|25000|${'a'.repeat(64)}`,`${migrationId}|5000|not-a-basis`])test(`malformed or terminal source ID is not a return authority: ${sourceId.slice(0,40)}`,()=>{
 assert.throws(()=>core.parseReceipt({format:1,accountKey:A,source:'point-tier-return-v1',sourceId,kind:'award',
 delta:{points:5050,coins:0,xp:0,earnedDiamonds:0}},A),e=>e.code==='invalid-point-tier-return');
});

const {claimPointTierForOwnerSession}=require('./point-tier-session.cjs');
function ownerSession(f,uid='owner-old',install='old-install'){
 f.store.docs.set(`deda_sessions/${uid}`,{uid,accountKey:A,installId:install});
 f.store.docs.set(`users/${uid}`,{accountKey:A,authMethod:'deda_pin_firestore_v1',trustedInstallIds:[install]});
 f.store.docs.set(`deda_account_profiles/${A}`,{accountKey:A,trustedInstallIds:['old-install','new-install']});
 f.store.docs.set(`deda_account_directory/${A}`,{accountKey:A,active:true});
 f.store.docs.set(`deda_credentials/${A}`,{accountKey:A,active:true});
 const calls=[];const auth={verifyIdToken:async(value,revoked)=>{calls.push([value,revoked]);return {uid,firebase:{sign_in_provider:'anonymous'}};}};
 return {store:f.store,auth,idToken:'synthetic-owner-token',threshold:5000,calls};
}
const sessionRequest=s=>({store:s.store,auth:s.auth,idToken:s.idToken,threshold:s.threshold});
const sessionClaim=s=>claimPointTierForOwnerSession(sessionRequest(s));
async function rejectSession(f,s,code){
 const before=structuredClone([...f.store.docs]);await assert.rejects(sessionClaim(s),e=>e.code===code);
 assert.deepEqual([...f.store.docs],before);assert.deepEqual(f.store.writes,[]);
}
test('session adapter derives account from server proof and commits the original five-write claim in one transaction',async()=>{
 const f=await activatedFixture(),s=ownerSession(f);let transactions=0;const run=f.store.runTransaction.bind(f.store);
 f.store.runTransaction=async action=>{transactions++;return run(action);};
 const r=await sessionClaim(s);assert.equal(r.returnedPoints,5050);assert.equal(r.state.accountKey,A);
 assert.equal(transactions,1);assert.equal(f.store.writes.length,5);assert.deepEqual(s.calls,[[s.idToken,true]]);
});
test('new verified UID/install for the same account replays the original claim without a second return',async()=>{
 const f=await activatedFixture(),old=ownerSession(f);const first=await sessionClaim(old);f.store.writes=[];
 const next=ownerSession(f,'owner-new','new-install'),replay=await sessionClaim(next);
 assert.equal(replay.replayed,true);assert.equal(replay.eventKey,first.eventKey);assert.equal(replay.state.balances.points,100050);
 assert.deepEqual(f.store.writes,[]);
});
for(const field of ['accountKey','uid','installId','name','verified','amount','decodedToken'])test(`session adapter refuses caller authority field ${field}`,async()=>{
 const f=await activatedFixture(),s=ownerSession(f);
 await assert.rejects(claimPointTierForOwnerSession({...sessionRequest(s),[field]:A}),e=>e.code==='invalid-point-session-request');
 assert.deepEqual(s.calls,[]);assert.deepEqual(f.store.writes,[]);
});
for(const provider of ['password','custom','phone',undefined])test(`provider ${provider} cannot substitute for the original anonymous owner session`,async()=>{
 const f=await activatedFixture(),s=ownerSession(f);s.auth.verifyIdToken=async()=>({uid:'owner-old',firebase:{sign_in_provider:provider}});
 await rejectSession(f,s,'point-session-owner-sign-in-required');
});
for(const token of [null,{}, {uid:'../escape',firebase:{sign_in_provider:'anonymous'}}])test('invalid verified-token identity fails before owner or financial writes',async()=>{
 const f=await activatedFixture(),s=ownerSession(f);s.auth.verifyIdToken=async()=>token;await rejectSession(f,s,'point-session-owner-sign-in-required');
});
for(const path of ['deda_sessions/owner-old','users/owner-old',`deda_account_profiles/${A}`,`deda_account_directory/${A}`,`deda_credentials/${A}`])test(`missing owner proof ${path.split('/')[0]} cannot release a migrated right`,async()=>{
 const f=await activatedFixture(),s=ownerSession(f);f.store.docs.delete(path);await rejectSession(f,s,'point-session-owner-proof-required');
});
for(const [path,field,value]of [
 ['deda_sessions/owner-old','uid','another-user'],['deda_sessions/owner-old','accountKey','../escape'],['deda_sessions/owner-old','installId','../escape'],
 ['users/owner-old','accountKey','07700000001'],['users/owner-old','authMethod','local'],['users/owner-old','trustedInstallIds',[]],
 [`deda_account_profiles/${A}`,'accountKey','07700000001'],[`deda_account_profiles/${A}`,'trustedInstallIds',['unrelated-install']],
 [`deda_account_directory/${A}`,'active',false],[`deda_credentials/${A}`,'active',false],
 [`deda_account_directory/${A}`,'accountKey','07700000001'],[`deda_credentials/${A}`,'accountKey','07700000001'],
])test(`mismatched or inactive ${path.split('/')[0]}.${field} cannot authorize a claim`,async()=>{
 const f=await activatedFixture(),s=ownerSession(f);f.store.docs.get(path)[field]=value;await rejectSession(f,s,'point-session-owner-proof-required');
});
test('retry revalidates token revocation before accepting staged financial writes',async()=>{
 const f=await activatedFixture(),s=ownerSession(f);f.store.retry=()=>{};
 s.auth.verifyIdToken=async(token,checkRevoked)=>{s.calls.push([token,checkRevoked]);if(s.calls.length===2)throw Object.assign(Error('revoked'),{code:'auth/id-token-revoked'});return {uid:'owner-old',firebase:{sign_in_provider:'anonymous'}};};
 await assert.rejects(sessionClaim(s),e=>e.code==='auth/id-token-revoked');assert.deepEqual(s.calls,[[s.idToken,true],[s.idToken,true]]);
 assert.deepEqual(f.store.writes,[]);assert.equal(f.store.docs.get(`deda_verified_progress/${A}`).version,1);
});
test('retry rereads server owner proof instead of reusing authorization across transaction attempts',async()=>{
 const f=await activatedFixture(),s=ownerSession(f);f.store.retry=docs=>docs.get(`deda_account_profiles/${A}`).trustedInstallIds=[];
 await assert.rejects(sessionClaim(s),e=>e.code==='point-session-owner-proof-required');assert.equal(s.calls.length,2);assert.deepEqual(f.store.writes,[]);
});
test('wrong-account session cannot consume another account carried right or fall back to its old identity',async()=>{
 const f=await activatedFixture(),s=ownerSession(f);f.store.docs.get('deda_sessions/owner-old').accountKey='07700000001';
 await rejectSession(f,s,'point-session-owner-proof-required');
});
