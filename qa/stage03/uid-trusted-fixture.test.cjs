'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {build,apply,base,project}=require('./uid-trusted-fixture.cjs');
class Store{
  constructor(){this.rows=new Map();this.writes=0;}
  serverTimestamp(){return {toMillis:()=>1};}
  async runTransaction(f){
    const staged=new Map();const r=await f({get:async p=>this.rows.get(p)??null,set:(p,d)=>staged.set(p,d)});
    for(const [p,d]of staged){this.rows.set(p,d);this.writes++;}return r;
  }
}
test('fixed fixture uses existing core and protected UID projection, no gift credit',()=>{
  const d=build();
  assert.equal(Object.keys(d).length,12);
  assert.deepEqual(d[base].balances,{points:5,coins:10,xp:20,earnedDiamonds:200});
  assert.equal(d[base].version,4);
  assert.equal(d[base+'/inventory/current'].frames[0].receipt.cost,1000);
  assert.equal(d[base+'/inventory/current'].diamondGifts[0].status,'pending');
  assert.equal(d[base+'/inventory/current'].idGifts[0].acceptance,null);
  assert.ok(Object.keys(d).every(p=>p===base||p.startsWith(base+'/')));
});
test('wrong project never writes',async()=>{const store=new Store();await assert.rejects(apply({store,projectId:'other'}),/wrong-lab-project/);assert.equal(store.writes,0)});
test('create exact fixture once, then replay without duplicate credit',async()=>{
  const store=new Store();assert.deepEqual(await apply({store,projectId:project}),{replayed:false,count:12});
  assert.deepEqual(await apply({store,projectId:project}),{replayed:true,count:12});assert.equal(store.writes,12);
});
test('unknown or partial data blocks all writes',async()=>{
  const store=new Store();store.rows.set(base,{unknown:true});
  await assert.rejects(apply({store,projectId:project}),/unknown-or-partial/);assert.equal(store.writes,0);
});
test('existing changed receipt or inventory never overwritten',async()=>{
  const store=new Store();await apply({store,projectId:project});const before=store.writes;
  store.rows.set(base+'/inventory/current',{revision:2});
  await assert.rejects(apply({store,projectId:project}),/unknown-or-partial/);assert.equal(store.writes,before);
});
