'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const core=require('../../tools/app_stability/progress_archive/reconcile-core.cjs');
const {inspectClassifiedReceipt,previewReviewedReceiptForOwner}=
  require('../deda_step2_verified_receipt_replay_audit_NOT_EXPORTED.js');
const account='07700000000',other='07700000001';
const receiptId='task_receipt_2026_000001',duplicateId='different_document_00001';
const baselineKey='a'.repeat(64),migrationId='migration_2026_00000001',digest='b'.repeat(64);
const award=()=>({format:1,accountKey:account,source:'task-claim-v1',
 sourceId:'2026-10-21|open_map',kind:'award',
 delta:{points:5,coins:0,xp:20,earnedDiamonds:0}});
const key=()=>core.eventKey(award());
const context=()=>({migration:{format:1,accountKey:account,migrationId,
 phase:'cutover-complete',baselineEventKey:baselineKey,evidenceDigest:digest},
 state:{format:1,accountKey:account,initializedBy:baselineKey,version:3,
 balances:{points:125,coins:30,xp:60,earnedDiamonds:80}}});
const classification=(disposition='after-cutover')=>({format:1,accountKey:account,
 migrationId,evidenceDigest:digest,disposition,receipt:award()});
const marker=()=>({format:1,accountKey:account,eventKey:key(),receipt:award(),
 receiptId,appliedVersion:2,afterBalances:{points:105,coins:30,xp:40,earnedDiamonds:80},
 createdAt:'fixture-time'});
function fixture(disposition='after-cutover',exists=true){
 const docs=new Map([
 ['deda_progress_receipts/'+account+'/events/'+receiptId,award()],
 ['deda_progress_migrations/'+account+'/classifications/'+key(),classification(disposition)]]);
 if(exists)docs.set('deda_verified_progress/'+account+'/events/'+key(),marker());
 const observed=[];
 const tx={
  async get(path){observed.push(path);return structuredClone(docs.get(path)??null);},
  set(){throw Error('audit-must-never-write');},
  update(){throw Error('audit-must-never-update');},
  delete(){throw Error('audit-must-never-delete');}
 };
 return {docs,tx,observed,ctx:context()};
}
const run=(f,id=receiptId)=>inspectClassifiedReceipt({tx:f.tx,accountKey:account,
 context:f.ctx,receiptId:id});
const reject=(f,code)=>assert.rejects(run(f),e=>e.code===code);
test('verified award is observed as already applied; no credit or cutover',async()=>{
 const f=fixture(),r=await run(f);
 assert.equal(r.status,'already-applied-once');assert.equal(r.eventKey,key());
 for(const field of ['canCreateReceipt','canCreditDiamonds','canCreditPoints',
   'canReapplySpend','canReissuePrizes','allowPhoneCutover'])assert.equal(r[field],false);
 assert.equal(f.observed.length,3);
});
test('same source wrapped in another receipt doc cannot give another award',async()=>{
 const f=fixture();f.docs.set('deda_progress_receipts/'+account+'/events/'+duplicateId,award());
 const first=await run(f),second=await run(f,duplicateId);
 assert.equal(first.eventKey,second.eventKey);assert.equal(second.status,'already-applied-once');
});
test('old included-in-baseline event is not reapplied',async()=>{
 const f=fixture('included-in-baseline',false);
 assert.equal((await run(f)).status,'already-in-reviewed-baseline');
});
test('classified but unapplied does not authorize points',async()=>{
 const r=await run(fixture('after-cutover',false));
 assert.equal(r.status,'classified-but-not-applied');
 assert.equal(r.canCreditPoints,false);assert.equal(r.canCreditDiamonds,false);
});
test('included event with applied marker is rejected',async()=>{
 await reject(fixture('included-in-baseline'),'step2-included-receipt-was-applied-again');
});
test('absent receipt means HOLD, not zero',async()=>{
 const f=fixture();f.docs.delete('deda_progress_receipts/'+account+'/events/'+receiptId);
 await reject(f,'step2-verified-receipt-missing');
});
test('missing classification means HOLD',async()=>{
 const f=fixture();f.docs.delete('deda_progress_migrations/'+account+'/classifications/'+key());
 await reject(f,'step2-receipt-classification-missing');
});
test('changed amount with same event key cannot be replayed',async()=>{
 const f=fixture();f.docs.set('deda_progress_receipts/'+account+'/events/'+receiptId,
  {...award(),delta:{points:999,coins:0,xp:20,earnedDiamonds:0}});
 await reject(f,'step2-receipt-classification-conflict');
});
test('classification from another migration is refused',async()=>{
 const f=fixture(),path='deda_progress_migrations/'+account+'/classifications/'+key();
 f.docs.set(path,{...classification(),migrationId:'migration_foreign_000001'});
 await reject(f,'step2-receipt-classification-conflict');
});
test('corrupt applied markers cannot count as already applied',async()=>{
 const path='deda_verified_progress/'+account+'/events/'+key();
 for(const mutation of [
  {eventKey:'f'.repeat(64)},{receipt:{...award(),sourceId:'fake'}},
  {appliedVersion:4},{receiptId:'bad/id'},
  {afterBalances:{points:-1,coins:30,xp:20,earnedDiamonds:80}},
 ]){
  const f=fixture();f.docs.set(path,{...marker(),...mutation});
  await assert.rejects(run(f));
 }
});
test('latest applied marker must equal trusted state balance',async()=>{
 const f=fixture(),path='deda_verified_progress/'+account+'/events/'+key();
 f.docs.set(path,{...marker(),appliedVersion:3});
 await reject(f,'step2-applied-state-conflict');
});
test('wrong account, pending migration and baseline mismatch fail before read',async()=>{
 const f=fixture();
 for(const ctx of [
  {...context(),migration:{...context().migration,accountKey:other}},
  {...context(),migration:{...context().migration,phase:'pending'}},
  {...context(),state:{...context().state,initializedBy:'f'.repeat(64)}},
 ]){
  await assert.rejects(inspectClassifiedReceipt({tx:f.tx,
   accountKey:account,context:ctx,receiptId}));
 }
 assert.equal(f.observed.length,0);
});
test('baseline itself cannot be replayed',async()=>{
 const f=fixture();
 f.docs.set('deda_progress_receipts/'+account+'/events/'+receiptId,
  {...award(),source:'legacy-baseline-v1',kind:'baseline'});
 await reject(f,'step2-baseline-receipt-not-replayable');
});
test('owner API refuses missing trusted server session dependencies',async()=>{
 await assert.rejects(previewReviewedReceiptForOwner({
  store:{},auth:{verifyIdToken:async()=>({uid:'untrusted',firebase:{sign_in_provider:'password'}})},
  idToken:'mock',receiptId}),e=>e.code==='point-session-owner-sign-in-required');
});
