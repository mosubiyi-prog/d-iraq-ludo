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
