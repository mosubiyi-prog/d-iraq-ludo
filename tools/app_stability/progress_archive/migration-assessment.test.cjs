'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {assessLegacyEvidence}=require('./legacy-assessment.cjs');
const {saveMigrationAssessment}=require('./migration-assessment-store.cjs');
const A='07700000000',B='07700000001',captureId='legacy_capture_review_00001',migrationId='migration_review_00000001';
const source=`deda_progress_evidence/${A}/captures/${captureId}`,root=`deda_progress_migrations/${A}`;
const reviewPath=`${root}/reviews/${migrationId}`;
function evidence(){return {format:1,kind:'legacy-local-evidence',accountKey:A,captureId,
 sourceUid:'original-old-device',installId:'original-install',createdAt:{seconds:1792800000,nanoseconds:123},
 records:{taskPoints:JSON.stringify({version:1,completions:{},awards:{
  'task|2026-10-24|map_opened':{points:5,type:'task'},'legacy-income':{points:5995},
  'point_tier_reserve|5000':{points:-5000}},ledger:[]}),
  socialCoinsAndXp:JSON.stringify({coins:30,xp:3020,taskClaims:['2026-10-24|map_opened']}),
  earnedDiamonds:JSON.stringify({balance:9,day:'2026-10-24',viewsToday:1})}};}
const assess=raw=>assessLegacyEvidence(raw,A,captureId);
class Store{
 constructor(){this.docs=new Map([[source,evidence()]]);this.writes=[];this.retry=null;this.fail=false;}
 serverTimestamp(){return {seconds:1792800001,nanoseconds:0};}
 async runTransaction(action){
  const run=async()=>{
   const staged=new Map();
   const result=await action({get:async path=>{
    if(staged.size)throw Error('read-after-write');return structuredClone(this.docs.get(path)??null);
   },set:(path,data)=>staged.set(path,structuredClone(data))});
   return {staged,result};
  };
  let out=await run();
  if(this.retry){const mutate=this.retry;this.retry=null;mutate(this.docs);out=await run();}
  if(this.fail)throw Error('fixture-commit-failure');
  for(const [path,data]of out.staged){this.docs.set(path,data);this.writes.push(path);}
  return out.result;
 }
}
const save=(store,extra={})=>saveMigrationAssessment({store,accountKey:A,captureId,migrationId,...extra});
test('observes the net award balance including old debits; never adds manager or gifted components',()=>{
 const raw=evidence(),before=structuredClone(raw),r=assess(raw);
 assert.deepEqual(r.observedBalances,{points:1000,coins:30,xp:3020,earnedDiamonds:9});
 assert.equal(r.status,'requires-verification');assert.equal(r.canAutoApprove,false);
 assert.equal(r.history.reservationRecords,1);assert.equal(r.settlement.purchases,'unknown');
 assert.equal(r.settlement.pointReservations,'unknown');assert.deepEqual(raw,before);
 assert.ok(r.excludedComponents.includes('general-manager-personal-wallet'));
});
test('negative task balance is retained as evidence rather than clamped to zero',()=>{
 const raw=evidence();raw.records.taskPoints=JSON.stringify({version:1,awards:{reserve:{points:-5000}},completions:{},ledger:[]});
 assert.equal(assess(raw).observedBalances.points,-5000);
});
test('explicit zero records differ from missing records; neither authorizes bootstrap',()=>{
 const raw=evidence();raw.records={taskPoints:JSON.stringify({version:1,awards:{},completions:{},ledger:[]}),
  socialCoinsAndXp:'{"coins":0,"xp":0,"taskClaims":[]}',earnedDiamonds:'{"balance":0,"day":"2026-10-24","viewsToday":0}'};
 assert.deepEqual(assess(raw).observedBalances,{points:0,coins:0,xp:0,earnedDiamonds:0});
 raw.records={taskPoints:null,socialCoinsAndXp:null,earnedDiamonds:null};
 assert.deepEqual(assess(raw).observedBalances,{points:null,coins:null,xp:null,earnedDiamonds:null});
 assert.equal(assess(raw).canAutoApprove,false);
});
for(const text of ['{broken','[]','null','"wrong"',''])test(`malformed/non-object payload is preserved and never zeroed: ${text}`,()=>{
 const raw=evidence();raw.records.socialCoinsAndXp=text;const before=structuredClone(raw);
 const r=assess(raw);assert.equal(r.observedBalances.coins,null);assert.equal(r.observedBalances.xp,null);
 assert.deepEqual(raw,before);assert.ok(r.issues.some(x=>x.startsWith('socialCoinsAndXp:')));
});
for(const text of ['{"coins":1,"coins":999,"xp":20}',String.raw`{"coins":1,"\u0063oins":999,"xp":20}`,
 '{"coins":1,"xp":20,"nested":{"x":1,"x":2}}'])test('duplicate JSON keys including escaped/nested names are not interpreted as balances',()=>{
 const raw=evidence();raw.records.socialCoinsAndXp=text;const r=assess(raw);
 assert.equal(r.observedBalances.coins,null);assert.ok(r.issues.includes('socialCoinsAndXp:duplicate-json-key'));
});
test('braces/quotes/colon inside a JSON string do not create false duplicate keys',()=>{
 const raw=evidence();raw.records.socialCoinsAndXp=JSON.stringify({coins:1,xp:20,taskClaims:[],note:'{"x":1,"x":2}'});
 assert.equal(assess(raw).observedBalances.coins,1);
});
for(const value of [1.5,'30',-1,Number.MAX_SAFE_INTEGER+1])test(`invalid coins ${value} is not coerced or clamped`,()=>{
 const raw=evidence();raw.records.socialCoinsAndXp=JSON.stringify({coins:value,xp:20,taskClaims:[]});
 assert.equal(assess(raw).observedBalances.coins,null);
});
test('a large safe legacy value is observed without silent display clamping',()=>{
 const raw=evidence();raw.records.earnedDiamonds=JSON.stringify({balance:2**30+1,day:'2026-10-24',viewsToday:0});
 const r=assess(raw);assert.equal(r.observedBalances.earnedDiamonds,2**30+1);
 assert.ok(r.issues.includes('earnedDiamonds:balance-outside-legacy-display-range'));
});
test('unsafe/fractional award entries cannot manufacture a partial point total',()=>{
 const raw=evidence();raw.records.taskPoints=JSON.stringify({version:1,awards:{ok:{points:5},bad:{points:0.5}},completions:{},ledger:[]});
 assert.equal(assess(raw).observedBalances.points,null);
});
test('history disagreement is flagged without deriving coins or XP from point claims',()=>{
 const raw=evidence();raw.records.socialCoinsAndXp='{"coins":17,"xp":19,"taskClaims":["different|task"]}';
 const r=assess(raw);assert.equal(r.observedBalances.coins,17);assert.equal(r.observedBalances.xp,19);
 assert.equal(r.history.taskAwardsWithoutSocialHistory,1);assert.equal(r.history.socialHistoryWithoutTaskAward,1);
 assert.ok(r.issues.includes('task-social-history:requires-reconciliation'));
});
test('bounded old histories cannot be assumed complete',()=>{
 const raw=evidence(),points=JSON.parse(raw.records.taskPoints),social=JSON.parse(raw.records.socialCoinsAndXp);
 points.ledger=Array(600).fill({id:'fixture'});social.taskClaims=Array.from({length:180},(_,i)=>`day|task${i}`);
 raw.records.taskPoints=JSON.stringify(points);raw.records.socialCoinsAndXp=JSON.stringify(social);
 const r=assess(raw);assert.ok(r.issues.includes('taskPoints:history-may-be-truncated'));
 assert.ok(r.issues.includes('socialCoinsAndXp:history-may-be-truncated'));
});
for(const mutate of [r=>r.records.taskPoints+='\n',r=>r.sourceUid='different-old-uid',r=>r.installId='different-install',
 r=>r.createdAt.nanoseconds++,r=>r.records.earnedDiamonds=null])test('digest binds exact bytes and original provenance, not just observed totals',()=>{
 const raw=evidence(),before=assess(raw).evidenceDigest;mutate(raw);assert.notEqual(assess(raw).evidenceDigest,before);
});
for(const [name,mutate,code]of [
 ['account',r=>r.accountKey=B,'invalid-migration-evidence'],
 ['capture',r=>r.captureId='other_capture_0000000001','invalid-migration-evidence'],
 ['extra',r=>r.verified=true,'invalid-migration-evidence'],
 ['record-type',r=>r.records.taskPoints=5,'invalid-migration-evidence-record'],
 ['record-size',r=>r.records.taskPoints='x'.repeat(200001),'invalid-migration-evidence-record'],
 ['time',r=>r.createdAt.nanoseconds=1e9,'invalid-migration-evidence-time'],
])test(`invalid archive ${name} fails without rewriting it`,()=>{
 const raw=evidence();mutate(raw);assert.throws(()=>assess(raw),e=>e.code===code);
});
test('creates only an evidence-saved migration and private review; no balance/receipt/identity writes',async()=>{
 const store=new Store(),raw=structuredClone(store.docs.get(source));const r=await save(store);
 assert.equal(r.phase,'evidence-saved');assert.equal(r.assessment.canAutoApprove,false);
 assert.deepEqual(new Set(store.writes),new Set([root,reviewPath]));
 assert.deepEqual(store.docs.get(source),raw);
 assert.equal(store.docs.get(root).baselineEventKey,null);assert.equal(store.docs.get(root).settlementId,null);
 assert.equal(store.docs.has(`deda_verified_progress/${A}`),false);
});
test('idempotent repeat retains original private review timestamp and never rewrites source',async()=>{
 const store=new Store();await save(store);const before=structuredClone([...store.docs]);store.writes=[];
 assert.equal((await save(store)).replayed,true);assert.deepEqual([...store.docs],before);assert.deepEqual(store.writes,[]);
});
test('Firestore-style reordered map keys do not create a false replay conflict',async()=>{
 const store=new Store();await save(store);const r=store.docs.get(reviewPath);
 r.observedBalances={xp:r.observedBalances.xp,points:r.observedBalances.points,earnedDiamonds:r.observedBalances.earnedDiamonds,coins:r.observedBalances.coins};
 store.writes=[];assert.equal((await save(store)).replayed,true);assert.deepEqual(store.writes,[]);
});
test('a later migration approval is never downgraded by assessment replay',async()=>{
 const store=new Store();await save(store);store.docs.set(root,{...store.docs.get(root),phase:'baseline-approved',
  baselineEventKey:'a'.repeat(64),settlementId:'settlement_review_0000001'});store.writes=[];
 assert.equal((await save(store)).phase,'baseline-approved');assert.deepEqual(store.writes,[]);
});
test('missing old capture cannot create a zero baseline or a review',async()=>{
 const store=new Store();store.docs.delete(source);
 await assert.rejects(save(store),e=>e.code==='migration-evidence-missing');assert.deepEqual(store.writes,[]);
});
test('conflicting capture or migration identity cannot overwrite the first review',async()=>{
 const store=new Store();await save(store);const before=structuredClone([...store.docs]);store.writes=[];
 await assert.rejects(save(store,{migrationId:'different_migration_00001'}),e=>e.code==='migration-review-conflict');
 store.docs.get(source).records.taskPoints+=' ';
 await assert.rejects(save(store),e=>e.code==='migration-review-conflict');assert.deepEqual(store.writes,[]);
 assert.deepEqual(store.docs.get(reviewPath),before.find(([p])=>p===reviewPath)[1]);
});
test('a higher second-device snapshot is retained but never max-merged into the first review',async()=>{
 const store=new Store();await save(store);const otherId='second_device_capture_0001',raw=evidence();
 raw.captureId=otherId;raw.sourceUid='new-device';raw.installId='new-install';
 raw.records.socialCoinsAndXp='{"coins":99999,"xp":99999,"taskClaims":[]}';
 const otherPath=`deda_progress_evidence/${A}/captures/${otherId}`;store.docs.set(otherPath,raw);store.writes=[];
 await assert.rejects(save(store,{captureId:otherId}),e=>e.code==='migration-review-conflict');
 assert.equal(store.docs.get(reviewPath).observedBalances.coins,30);assert.deepEqual(store.docs.get(otherPath),raw);
 assert.deepEqual(store.writes,[]);assert.equal(store.docs.has(`deda_verified_progress/${A}`),false);
});
test('tampered review amount or client approval flag cannot survive replay validation',async()=>{
 const store=new Store();await save(store);store.docs.get(reviewPath).canAutoApprove=true;store.writes=[];
 await assert.rejects(save(store),e=>e.code==='migration-review-conflict');assert.deepEqual(store.writes,[]);
});
test('SDK transaction retry rechecks the source and migration before writing',async()=>{
 const store=new Store();store.retry=docs=>docs.set(root,{format:1,accountKey:A,migrationId:'different_migration_00001',
  phase:'pending',evidenceDigest:null,baselineEventKey:null,settlementId:null});
 await assert.rejects(save(store),e=>e.code==='migration-review-conflict');assert.deepEqual(store.writes,[]);
});
test('commit failure leaves neither the migration phase nor a partial private review',async()=>{
 const store=new Store();store.fail=true;const before=structuredClone([...store.docs]);
 await assert.rejects(save(store),/fixture-commit-failure/);assert.deepEqual([...store.docs],before);assert.deepEqual(store.writes,[]);
});
test('client amount/approval input is rejected before any storage access',async()=>{
 const store=new Store();store.runTransaction=()=>{throw Error('must-not-read');};
 await assert.rejects(save(store,{verified:true,balances:{points:999}}),e=>e.code==='invalid-assessment-request');
});
