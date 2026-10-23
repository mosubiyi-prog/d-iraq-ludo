'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const core = require('./reconcile-core.cjs');
const {reconcileVerifiedReceipt} = require('./reconcile-store.cjs');
const {parseMigration, reconcileMigratedReceipt} = require('./migration-gate.cjs');
const account = '07700000000', root = `deda_progress_migrations/${account}`;
const statePath = `deda_verified_progress/${account}`;
const baselineId = 'baseline_receipt_00000001', awardId = 'award_receipt_0000000001';
const baseline = {format:1,accountKey:account,source:'legacy-baseline-v1',sourceId:'approved-review',kind:'baseline',delta:{points:100,coins:30,xp:20,earnedDiamonds:9}};
const award = {format:1,accountKey:account,source:'task-claim-v1',sourceId:'day|task',kind:'award',delta:{points:5,coins:10,xp:20,earnedDiamonds:0}};
const key = core.eventKey(award), baselineKey = core.eventKey(baseline);
const migration = () => ({format:1,accountKey:account,migrationId:'migration_review_00000001',phase:'cutover-complete',evidenceDigest:'a'.repeat(64),baselineEventKey:baselineKey,settlementId:'settlement_review_0000001'});
const settlement = () => ({format:1,accountKey:account,migrationId:migration().migrationId,evidenceDigest:migration().evidenceDigest,baselineEventKey:baselineKey,legacyFenceId:'legacy_writer_fence_00001',pendingPurchases:0,pendingReservations:0});
const classification = disposition => ({format:1,accountKey:account,migrationId:migration().migrationId,evidenceDigest:migration().evidenceDigest,disposition,receipt:structuredClone(award)});
const classificationPath = `${root}/classifications/${key}`;
const settlementPath = `${root}/settlements/${migration().settlementId}`;
class Store {
  constructor() { this.docs = new Map(); this.writes = 0; this.retry = false; this.fail = false; }
  serverTimestamp() { return 'fixture-time'; }
  async runTransaction(action) {
    const run = async () => {
      const staged = new Map();
      const result = await action({get:async path => {
        if (staged.size) throw Error('read-after-write');
        return structuredClone(this.docs.get(path) ?? null);
      },set:(path,data) => staged.set(path,structuredClone(data))});
      return {result,staged};
    };
    let out = await run();
    if (this.retry) { this.retry = false; this.docs.set(root,{...migration(),phase:'baseline-approved'}); out = await run(); }
    if (this.fail) throw Error('fixture-commit-failure');
    for (const [path,data] of out.staged) { this.docs.set(path,data); this.writes++; }
    return out.result;
  }
}
async function fixture(disposition = 'included-in-baseline') {
  const store = new Store();
  store.docs.set(`deda_progress_receipts/${account}/events/${baselineId}`,structuredClone(baseline));
  store.docs.set(`deda_progress_receipts/${account}/events/${awardId}`,structuredClone(award));
  await reconcileVerifiedReceipt({store,accountKey:account,receiptId:baselineId});
  store.docs.set(root,migration()); store.docs.set(settlementPath,settlement());
  store.docs.set(classificationPath,classification(disposition));
  store.writes = 0;
  return store;
}
const apply = (store,id=awardId) => reconcileMigratedReceipt({store,accountKey:account,receiptId:id});
const reject = async (store,code) => {
  const before = structuredClone([...store.docs]);
  await assert.rejects(apply(store),e => e.code === code);
  assert.equal(store.writes,0); assert.deepEqual([...store.docs],before);
};
test('included old event returns current baseline without awarding or advancing version',async()=>{
  const store = await fixture(); const result = await apply(store);
  assert.equal(result.includedInBaseline,true); assert.deepEqual(result.state.balances,baseline.delta);
  assert.equal(result.state.version,1); assert.equal(store.writes,0);
});
test('included event through a second receipt ID is also suppressed',async()=>{
  const store = await fixture();const id = 'different_wrapper_0000001';
  store.docs.set(`deda_progress_receipts/${account}/events/${id}`,award);
  assert.equal((await apply(store,id)).includedInBaseline,true);assert.equal(store.writes,0);
});
test('post-cutover event applies exactly once through the original transaction',async()=>{
  const store = await fixture('after-cutover');const result = await apply(store);
  assert.equal(result.state.balances.coins,40);assert.equal(result.state.version,2);assert.equal(store.writes,2);
  store.writes = 0;const replay = await apply(store);assert.equal(replay.replayed,true);assert.equal(replay.state.version,2);assert.equal(store.writes,0);
});
test('included replay after later spend returns CURRENT balances',async()=>{
  const store = await fixture();const id = 'post_cutover_spend_000001';
  const debit = {...award,source:'cosmetic-debit-v1',kind:'spend',sourceId:'purchase-one',delta:{points:0,coins:-20,xp:0,earnedDiamonds:0}};
  store.docs.set(`deda_progress_receipts/${account}/events/${id}`,debit);
  store.docs.set(`${root}/classifications/${core.eventKey(debit)}`,{...classification('after-cutover'),receipt:debit});
  await apply(store,id);store.writes = 0;
  const result = await apply(store);assert.equal(result.state.balances.coins,10);assert.equal(result.state.version,2);assert.equal(store.writes,0);
});
for (const phase of ['pending','evidence-saved','baseline-approved']) test(`${phase} cannot mint an event`,async()=>{
  const store = await fixture();store.docs.set(root,{...migration(),phase,
    evidenceDigest:phase === 'pending' ? null : migration().evidenceDigest,
    baselineEventKey:phase === 'baseline-approved' ? baselineKey : null,
    settlementId:phase === 'baseline-approved' ? migration().settlementId : null});
  await reject(store,'migration-pending');
});
test('missing migration does not assume a new zero account',async()=>{
  const store = await fixture();store.docs.delete(root);await reject(store,'migration-required');
});
for (const [field,value] of [['accountKey','07700000001'],['format',2],['phase','approved'],['migrationId','../escape'],['evidenceDigest','bad']]) test(`invalid migration ${field} rejected`,async()=>{
  const store = await fixture();store.docs.set(root,{...migration(),[field]:value});await reject(store,'invalid-migration');
});
test('extra client approval field does not grant permission',()=>{
  assert.throws(()=>parseMigration({...migration(),verified:true},account),e=>e.code === 'migration-required');
});
test('settlement must exist independently of a completed flag',async()=>{
  const store = await fixture();store.docs.delete(settlementPath);await reject(store,'migration-settlement-required');
});
for (const [field,value] of [['pendingPurchases',1],['pendingReservations',1],['migrationId','other_migration_00000001'],['evidenceDigest','b'.repeat(64)],['legacyFenceId','']]) test(`unsettled ${field} blocks all writes`,async()=>{
  const store = await fixture();store.docs.set(settlementPath,{...settlement(),[field]:value});await reject(store,'migration-not-settled');
});
test('baseline must be the actual initialization event',async()=>{
  const store = await fixture();store.docs.set(statePath,{...store.docs.get(statePath),initializedBy:'b'.repeat(64)});await reject(store,'migration-baseline-conflict');
});
test('missing baseline applied marker blocks cutover',async()=>{
  const store = await fixture();store.docs.delete(`${statePath}/events/${baselineKey}`);await reject(store,'migration-baseline-missing');
});
test('unclassified event is held instead of guessed from time or arrival',async()=>{
  const store = await fixture();store.docs.delete(classificationPath);await reject(store,'migration-classification-required');
});
for (const field of ['migrationId','evidenceDigest','disposition']) test(`classification ${field} must bind current migration`,async()=>{
  const store = await fixture();store.docs.set(classificationPath,{...classification('after-cutover'),[field]:'other'});await reject(store,'migration-classification-conflict');
});
test('same source event with changed amount cannot reuse its classification',async()=>{
  const store = await fixture('after-cutover');store.docs.set(`deda_progress_receipts/${account}/events/${awardId}`,{...award,delta:{...award.delta,coins:999}});
  await reject(store,'migration-classification-conflict');
});
test('already-applied event cannot later be labelled included in baseline',async()=>{
  const store = await fixture('after-cutover');await apply(store);store.writes = 0;
  store.docs.set(classificationPath,classification('included-in-baseline'));await reject(store,'migration-event-already-applied');
});
test('a second baseline cannot pass the migration API',async()=>{
  const store = await fixture();await assert.rejects(apply(store,baselineId),e=>e.code === 'migration-baseline-already-sealed');assert.equal(store.writes,0);
});
test('SDK transaction retry rereads migration approval and refuses a revoked cutover',async()=>{
  const store = await fixture('after-cutover');store.retry = true;
  await assert.rejects(apply(store),e=>e.code === 'migration-pending');assert.equal(store.writes,0);assert.equal(store.docs.get(statePath).version,1);
});
test('commit failure leaves neither a debit nor marker',async()=>{
  const store = await fixture('after-cutover');const before = structuredClone([...store.docs]);store.fail = true;
  await assert.rejects(apply(store),/fixture-commit-failure/);assert.deepEqual([...store.docs],before);assert.equal(store.writes,0);
});
for (const [field,value] of [['format',2],['accountKey','07700000001'],['appliedVersion',2]]) test(`baseline marker ${field} must match initialization`,async()=>{
  const store = await fixture();const path = `${statePath}/events/${baselineKey}`;
  store.docs.set(path,{...store.docs.get(path),[field]:value});await reject(store,'migration-baseline-missing');
});
test('baseline receipt must be legacy review rather than a new-account bootstrap',async()=>{
  const store = await fixture();const path = `${statePath}/events/${baselineKey}`;
  store.docs.set(path,{...store.docs.get(path),receipt:{...baseline,source:'account-bootstrap-v1',delta:{points:0,coins:0,xp:0,earnedDiamonds:0}}});
  await reject(store,'migration-baseline-conflict');
});
test('a debit already included in baseline cannot be charged again',async()=>{
  const store = await fixture();const id = 'included_old_debit_000001';
  const debit = {...award,source:'cosmetic-debit-v1',kind:'spend',sourceId:'old-purchase',delta:{points:0,coins:-20,xp:0,earnedDiamonds:0}};
  store.docs.set(`deda_progress_receipts/${account}/events/${id}`,debit);
  store.docs.set(`${root}/classifications/${core.eventKey(debit)}`,{...classification('included-in-baseline'),receipt:debit});
  const result = await apply(store,id);assert.equal(result.includedInBaseline,true);
  assert.equal(result.state.balances.coins,30);assert.equal(store.writes,0);
});
