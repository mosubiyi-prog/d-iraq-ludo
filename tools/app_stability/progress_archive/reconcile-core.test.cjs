'use strict';
const test=require('node:test');const assert=require('node:assert/strict');
const core=require('./reconcile-core.cjs');
const {reconcileVerifiedReceipt,DedaTrustedProgressTransactionStore}=require('./reconcile-store.cjs');
const account='07700000000';
const zero=()=>({points:0,coins:0,xp:0,earnedDiamonds:0});
const receipt=(changes={})=>({format:1,accountKey:account,source:'legacy-baseline-v1',sourceId:'fixture-legacy-approved',kind:'baseline',delta:{points:5000,coins:30,xp:3020,earnedDiamonds:9},...changes});
const parsed=changes=>core.parseReceipt(receipt(changes),account);
const initial=()=>core.applyEvent(null,parsed());
const award=()=>parsed({source:'task-claim-v1',sourceId:'day|task',kind:'award',delta:{points:5,coins:10,xp:20,earnedDiamonds:0}});
const spend=()=>parsed({source:'cosmetic-debit-v1',sourceId:'fixture-checkout',kind:'spend',delta:{...zero(),coins:-20}});
const rejects=(action,code)=>assert.throws(action,e=>e.code===code);

test('legacy baseline preserves approved progress without combining external wallets',()=>{
  const state=initial();assert.deepEqual(state.balances,receipt().delta);assert.equal(state.version,1);
  assert.equal(state.initializedBy,core.eventKey(parsed()));
});
test('explicit trusted bootstrap permits a genuinely new zero state',()=>{
  const state=core.applyEvent(null,parsed({source:'account-bootstrap-v1',delta:zero()}));
  assert.deepEqual(state.balances,zero());assert.equal(state.version,1);
});
test('missing state plus ordinary award does not silently create zero history',()=>{
  rejects(()=>core.applyEvent(null,award()),'progress-initialization-required');
});
test('later baseline cannot reset or add legacy amounts after initialization',()=>{
  rejects(()=>core.applyEvent(initial(),parsed()),'baseline-already-initialized');
});
test('direct core entry still rejects an unparsed award with a negative delta',()=>{
  rejects(()=>core.applyEvent(initial(),{...award(),delta:{...zero(),coins:-1}}),'invalid-award');
});
test('server event changes only its delta and advances one causal version',()=>{
  const start=initial();const next=core.applyEvent(start,award());
  assert.deepEqual(next.balances,{points:5005,coins:40,xp:3040,earnedDiamonds:9});
  assert.equal(next.version,2);assert.equal(next.initializedBy,start.initializedBy);
  assert.equal(start.balances.coins,30);
});
test('spending decreases coins while preserving XP and history initialization',()=>{
  const next=core.applyEvent(initial(),spend());
  assert.equal(next.balances.coins,10);assert.equal(next.balances.xp,3020);
});
test('source event key ignores receipt document IDs, SDK UID and arrival time',()=>{
  const event=award();assert.equal(core.eventKey(event),core.eventKey({...event,uid:'new-device',clientTime:0,receiptId:'new-wrapper'}));
});
test('same source identity with altered amount keeps key but conflicts semantically',()=>{
  const event=award();const changed=parsed({...event,delta:{...event.delta,coins:11}});
  assert.equal(core.eventKey(event),core.eventKey(changed));assert.equal(core.sameEvent(event,changed),false);
});
test('source IDs cannot collide through delimiter tricks',()=>{
  const a=award(),b=parsed({...a,sourceId:'day|task|other'});
  assert.notEqual(core.eventKey(a),core.eventKey(b));
});
for(const [field,value,code] of [
  ['format',2,'receipt-account-or-format'],['accountKey','other','receipt-account-or-format'],
  ['source','client-snapshot','unsupported-event-source'],['sourceId','','invalid-source-id'],
  ['sourceId','x'.repeat(257),'invalid-source-id'],['kind','spend','unsupported-event-source'],
])test(`invalid receipt ${field}/${String(value).slice(0,16)} is rejected`,()=>rejects(()=>parsed({[field]:value}),code));
for(const amount of [NaN,Infinity,1.5,Number.MAX_SAFE_INTEGER+1,'100'])test(`unsafe amount ${amount} rejected`,()=>{
  rejects(()=>parsed({delta:{...zero(),coins:amount}}),'invalid-amount');
});
for(const missing of ['points','xp'])test(`missing unit ${missing} cannot become an implicit zero`,()=>{
  const delta=zero();delete delta[missing];rejects(()=>parsed({delta}),'invalid-units');
});
test('unknown currency field is not imported into the progress vector',()=>{
  rejects(()=>parsed({delta:{...zero(),giftedDiamonds:1000}}),'invalid-units');
});
for(const kind of ['baseline','award','spend'])test(`sign policy enforced for ${kind}`,()=>{
  const changes=kind==='baseline'?{delta:{...zero(),coins:-1}}:kind==='award'?
    {source:'task-claim-v1',kind,delta:{...zero(),coins:-1}}:
    {source:'cosmetic-debit-v1',kind,delta:{...zero(),coins:1}};
  rejects(()=>parsed(changes),'invalid-'+kind);
});
test('new-account zero bootstrap cannot smuggle a legacy or arbitrary credit',()=>{
  rejects(()=>parsed({source:'account-bootstrap-v1'}),'new-account-bootstrap-must-be-zero');
});
test('spending cannot reduce earned XP',()=>{
  rejects(()=>parsed({source:'cosmetic-debit-v1',kind:'spend',delta:{...zero(),xp:-1}}),'invalid-spend');
});
test('rewarded ad receipt cannot award another currency',()=>{
  rejects(()=>parsed({source:'rewarded-ad-v1',kind:'award',delta:{...zero(),coins:10}}),'invalid-rewarded-ad-units');
});
test('point reservation cannot debit coins or XP',()=>{
  rejects(()=>parsed({source:'point-reservation-v1',kind:'spend',delta:{...zero(),coins:-1}}),'invalid-point-units');
});
test('multi-unit overspend rejects the entire transition without mutating prior amounts',()=>{
  const state=initial(),before=JSON.stringify(state);
  const event=parsed({source:'cosmetic-debit-v1',kind:'spend',delta:{...zero(),coins:-20,earnedDiamonds:-10}});
  rejects(()=>core.applyEvent(state,event),'insufficient-earnedDiamonds');assert.equal(JSON.stringify(state),before);
});
test('safe integer overflow fails without wrapping or clamping',()=>{
  const state={...initial(),balances:{...initial().balances,coins:Number.MAX_SAFE_INTEGER}};
  rejects(()=>core.applyEvent(state,award()),'progress-overflow');
});
test('corrupt state version is rejected without reconstructing a zero projection',()=>{
  rejects(()=>core.applyEvent({...initial(),version:0},award()),'invalid-state');
});
test('corrupt negative server balance is rejected before applying an award',()=>{
  rejects(()=>core.applyEvent({...initial(),balances:{...zero(),coins:-1}},award()),'invalid-amount');
});
test('projection is immutable to callers',()=>{
  const state=initial();assert.throws(()=>{state.balances.coins=999;},TypeError);assert.equal(state.balances.coins,30);
});
class MemoryStore{
  constructor(){this.docs=new Map();this.writes=0;this.failAt=null;}
  serverTimestamp(){return 'fixture-server-time';}
  async runTransaction(action){
    const staged=new Map();
    const out=await action({get:async path=>structuredClone(this.docs.get(path)??null),
      set:(path,data)=>{if(path===this.failAt)throw new Error('fixture-commit-error');staged.set(path,structuredClone(data));}});
    for(const [path,data]of staged){this.docs.set(path,data);this.writes++;}return out;
  }
  seed(id,data){this.docs.set(`deda_progress_receipts/${account}/events/${id}`,data);}
}
const baselineId='baseline_receipt_00000001',awardId='award_receipt_0000000001',spendId='spend_receipt_0000000001';
const apply=(store,id)=>reconcileVerifiedReceipt({store,accountKey:account,receiptId:id});
test('missing protected receipt does not authorize local legacy evidence',async()=>{
  const store=new MemoryStore();store.docs.set(`deda_progress_evidence/${account}/captures/${baselineId}`,receipt());
  await assert.rejects(apply(store,baselineId),e=>e.code==='verified-receipt-missing');assert.equal(store.writes,0);
});
test('replay after later spending returns current balance instead of historical award balance',async()=>{
  const store=new MemoryStore();store.seed(baselineId,receipt());store.seed(awardId,award());store.seed(spendId,spend());
  await apply(store,baselineId);await apply(store,awardId);await apply(store,spendId);
  const before=store.writes,out=await apply(store,awardId);
  assert.equal(out.replayed,true);assert.equal(out.state.balances.coins,20);assert.equal(out.state.version,3);assert.equal(store.writes,before);
});
test('two receipt wrappers for same source event do not duplicate the award',async()=>{
  const store=new MemoryStore();store.seed(baselineId,receipt());store.seed(awardId,award());store.seed('different_wrapper_0000001',award());
  await apply(store,baselineId);await apply(store,awardId);
  const out=await apply(store,'different_wrapper_0000001');assert.equal(out.replayed,true);assert.equal(out.state.version,2);
});
test('same event source with conflicting receipt cannot overwrite earlier evidence',async()=>{
  const store=new MemoryStore();store.seed(baselineId,receipt());store.seed(awardId,award());
  await apply(store,baselineId);await apply(store,awardId);const before=store.writes;
  store.seed('different_wrapper_0000001',{...award(),delta:{...award().delta,coins:999}});
  await assert.rejects(apply(store,'different_wrapper_0000001'),e=>e.code==='source-event-conflict');assert.equal(store.writes,before);
});
test('transaction failure rolls back marker and projection together',async()=>{
  const store=new MemoryStore();store.seed(baselineId,receipt());store.failAt=`deda_verified_progress/${account}`;
  await assert.rejects(apply(store,baselineId),/fixture-commit-error/);assert.equal(store.writes,0);assert.equal(store.docs.size,1);
});
test('Admin transport composition uses the original transaction and server snapshot exists flag',async()=>{
  const calls=[];const db={doc:path=>({path}),runTransaction:async action=>action({
    get:async ref=>({exists:true,data:()=>({path:ref.path})}),set:(ref,data)=>calls.push([ref.path,data])})};
  const store=new DedaTrustedProgressTransactionStore({db,serverTimestamp:()=>123});
  const result=await store.runTransaction(async tx=>{const data=await tx.get('fixture/path');tx.set('fixture/result',data);return data;});
  assert.deepEqual(result,{path:'fixture/path'});assert.deepEqual(calls,[['fixture/result',result]]);
});

function closedTransactionError(){return Object.assign(Error('3 INVALID_ARGUMENT: Transaction is invalid or closed.'),
 {code:3,details:'Transaction is invalid or closed.'});}
function retryDatabase({failure,commitBeforeError=false,alwaysFail=false}={}){
 const db={docs:new Map(),calls:0,writes:0,doc:path=>({path}),async runTransaction(action){
  this.calls++;const staged=new Map();
  const result=await action({get:async ref=>({exists:this.docs.has(ref.path),data:()=>structuredClone(this.docs.get(ref.path))}),
   set:(ref,value)=>staged.set(ref.path,structuredClone(value))});
  const fails=failure&&(this.calls===1||alwaysFail);
  if(!fails||commitBeforeError)for(const [path,value]of staged){this.docs.set(path,value);this.writes++;}
  if(fails)throw failure;return result;
 }};
 return db;
}
test('closed transaction before commit is recreated in full without partial writes',async()=>{
 const db=retryDatabase({failure:closedTransactionError()});const store=new DedaTrustedProgressTransactionStore({db,serverTimestamp:()=>({seconds:1,nanoseconds:0})});
 const id='closed_baseline_receipt_001';db.docs.set(`deda_progress_receipts/${account}/events/${id}`,receipt());
 const result=await reconcileVerifiedReceipt({store,accountKey:account,receiptId:id});
 assert.equal(db.calls,2);assert.equal(db.writes,2);assert.equal(result.state.version,1);
 assert.equal(result.state.balances.points,5000);
});
test('closed response after atomic commit is reconciled from marker and never credits baseline twice',async()=>{
 const db=retryDatabase({failure:closedTransactionError(),commitBeforeError:true});
 const store=new DedaTrustedProgressTransactionStore({db,serverTimestamp:()=>({seconds:1,nanoseconds:0})});
 const id='closed_baseline_receipt_001';db.docs.set(`deda_progress_receipts/${account}/events/${id}`,receipt());
 const result=await reconcileVerifiedReceipt({store,accountKey:account,receiptId:id});
 assert.equal(result.replayed,true);assert.equal(db.calls,2);assert.equal(db.writes,2);
 assert.equal(result.state.version,1);assert.equal(result.state.balances.points,5000);
});
test('closed transaction recreation is bounded to one extra full transaction',async()=>{
 const db=retryDatabase({failure:closedTransactionError(),alwaysFail:true});
 const store=new DedaTrustedProgressTransactionStore({db,serverTimestamp:()=>0});
 await assert.rejects(store.runTransaction(async tx=>{await tx.get('private/proof');tx.set('private/result',{ok:true});}),e=>e.code===3);
 assert.equal(db.calls,2);assert.equal(db.writes,0);
});
for(const error of [Object.assign(Error('invalid field'),{code:3}),Object.assign(Error('denied'),{code:7}),
 Object.assign(Error('unavailable'),{code:14}),Error('application-failure')])test(`non-closed status ${String(error.code??'application')} never triggers the extra transaction`,async()=>{
 const db=retryDatabase({failure:error});const store=new DedaTrustedProgressTransactionStore({db,serverTimestamp:()=>0});
 await assert.rejects(store.runTransaction(async tx=>{await tx.get('private/proof');tx.set('private/result',{ok:true});}),e=>e===error);
 assert.equal(db.calls,1);assert.equal(db.writes,0);
});
test('whole-transaction recreation repeats verification and refuses changed authority before writing',async()=>{
 const db=retryDatabase({failure:closedTransactionError()});let checks=0;
 const store=new DedaTrustedProgressTransactionStore({db,serverTimestamp:()=>0});
 await assert.rejects(store.runTransaction(async tx=>{
  checks++;if(checks===2)throw Object.assign(Error('revoked'),{code:'auth/id-token-revoked'});
  await tx.get('private/proof');tx.set('private/result',{ok:true});
 }),e=>e.code==='auth/id-token-revoked');assert.equal(checks,2);assert.equal(db.calls,2);assert.equal(db.writes,0);
});
