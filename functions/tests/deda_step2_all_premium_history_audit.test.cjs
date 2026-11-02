'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {validatePages,inspectOriginalPremiumHistory,previewOriginalPremiumHistory}=
 require('../deda_step2_all_premium_history_audit_NOT_EXPORTED.js');
const originalId='@DEDA-ABC123',giftId='@DEDA-GOLD01',other='@DEDA-ROYAL1';
const stamp=n=>({toMillis:()=>n});
const grant=(id=giftId,kind='gifted',original=originalId)=>({
 id,data:{identifier:id,recipientOriginalId:original,group:'001',
 baseColor:'gold',kind,grantedAt:stamp(1000)}
});
const receipt=(id=giftId,original=originalId)=>({
 id,data:{identifier:id,originalId:original,group:'001',receivedAt:stamp(2000)}
});
const run=(gs=[],rs=[])=>validatePages(gs,rs,originalId);
test('empty stage71 lists do not pretend old premium aliases do not exist',()=>{
 const r=run();assert.equal(r.stage71And74ServerSourcesScanned,true);
 assert.equal(r.legacyPaidAndUnscopedGiftsUnknown,true);
 assert.equal(r.allPremiumIdsRecovered,false);
 assert.equal(r.allowPhoneCutover,false);
});
test('independently gifted, received, self-used inactive IDs all preserved',()=>{
 const r=run([grant(),grant(other,'self_used')],[receipt()]);
 assert.equal(r.stage71GrantRows,2);
 assert.equal(r.receivedGiftCount,1);assert.equal(r.selfUsed,1);
 assert.equal(r.pendingGiftCount,0);
 assert.deepEqual(r.states.map(x=>x.identifier),[giftId,other].sort());
 for(const k of ['canGrantPremium','canActivatePremium','canReceiveGift',
  'canReissueGift','canCreditDiamonds','allowPhoneCutover'])
   assert.equal(r[k],false);
});
test('pending premium gift is not credited or treated received',()=>{
 const r=run([grant()],[]);assert.equal(r.pendingGiftCount,1);
 assert.equal(r.receivedGiftCount,0);
 assert.equal(r.states[0].state,'gift-awaits-receipt');
});
test('double grant document ID never duplicates ownership',()=>{
 assert.throws(()=>run([grant(),grant()]),e=>e.code==='step2-premium-history-grant-conflict');
});
test('duplicate receiver receipt is blocked even with same bytes',()=>{
 assert.throws(()=>run([grant()],[receipt(),receipt()]),
   e=>e.code==='step2-premium-history-receipt-conflict');
});
test('a gift receipt without recipient grant is never trusted',()=>{
 assert.throws(()=>run([],[receipt()]),
  e=>e.code==='step2-premium-history-orphan-receipt');
});
test('different original ID on grant/receipt is refused',()=>{
 assert.throws(()=>run([grant(giftId,'gifted','@DEDA-FOREIG')]),
  e=>e.code==='step2-premium-history-grant-conflict');
 assert.throws(()=>run([grant()],[receipt(giftId,'@DEDA-FOREIG')]),
  e=>e.code==='step2-premium-history-receipt-conflict');
});
test('self-used grants cannot be forged into received gifts',()=>{
 assert.throws(()=>run([grant(giftId,'self_used')],[receipt()]),
   e=>e.code==='step2-premium-history-self-gift-conflict');
});
test('mismatched group or receipt before grant is not proof',()=>{
 const wrong=receipt();wrong.data.group='002';
 assert.throws(()=>run([grant()],[wrong]),
  e=>e.code==='step2-premium-history-receipt-grant-conflict');
 const old=receipt();old.data.receivedAt=stamp(500);
 assert.throws(()=>run([grant()],[old]),
  e=>e.code==='step2-premium-history-receipt-grant-conflict');
});
test('invalid grant timestamp and malformed rows fail closed',()=>{
 const wrong=grant();wrong.data.grantedAt='yesterday';
 assert.throws(()=>run([wrong]),e=>e.code==='step2-premium-history-grant-conflict');
 assert.throws(()=>run([null]),e=>e.code==='step2-premium-history-grant-conflict');
});
test('invalid receipt timestamp or doc id fail closed',()=>{
 const wrong=receipt();wrong.data.receivedAt=null;
 assert.throws(()=>run([grant()],[wrong]),e=>e.code==='step2-premium-history-receipt-conflict');
});
test('over 200 results always HOLD before any accounting',()=>{
 assert.throws(()=>run(Array(201).fill(grant())),e=>e.code==='step2-premium-history-unbounded');
});
test('same-owner reader queries both pages, never mutates',async()=>{
 const requested=[];
 const r=await inspectOriginalPremiumHistory({originalId,reader:{
  async listPremiumHistory(kind){requested.push(kind);
   return kind==='grants'?[grant()]:[receipt()];},
 }});
 assert.deepEqual(requested,['grants','receipts']);
 assert.equal(r.receivedGiftCount,1);assert.equal(r.canReissueGift,false);
});
test('missing independent server query refuses a fabricated empty history',async()=>{
 await assert.rejects(inspectOriginalPremiumHistory({
  originalId,reader:{}
 }),e=>e.code==='step2-premium-history-owner-unverified');
});
test('linked-session rejects unauthenticated history request before any read',async()=>{
 await assert.rejects(previewOriginalPremiumHistory({
  store:{},auth:{},idToken:'fake'
 }),e=>e.code==='step2-linked-session-dependencies-missing');
});
test('a valid original owner session binds the queries to original ID only',async()=>{
 const uid='original-linked-uid',key='07712345678',lookups=[],paths=[];
 const docs=new Map([
  ['deda_sessions/'+uid,{uid,accountKey:key}],
  ['deda_account_directory/'+key,{accountKey:key,active:true,createdUid:uid}],
  ['deda_credentials/'+key,{accountKey:key,active:true,createdUid:uid}],
  ['deda_account_profiles/'+key,{accountKey:key,name:'Original User',accountType:'user'}],
  ['users/'+uid,{accountKey:key,sharePersonalId:originalId}],
  ['deda_share_ids/'+originalId,{publicId:originalId,ownerUid:uid,kind:'personal',active:true}]
 ]);
 const auth={async verifyIdToken(_t,revoke){
  assert.equal(revoke,true);
  return {uid,email:key+'@deda-login.invalid',firebase:{sign_in_provider:'password'}};
 }};
 const store={
  async readOwnerSession(){return {uid,accountKey:key};},
  makeReadOnlyQuery(coll,field,equals,limit){
   lookups.push([coll,field,equals,limit]);
   return {coll,field,equals,limit};
  },
  async runTransaction(work){
   return work({async get(x){
    if(typeof x==='string'){paths.push(x);return docs.get(x)??null;}
    assert.equal(x.equals,originalId);
    const rows=x.coll==='deda_stage71_granted_registry'?[grant()]:[receipt()];
    return {size:rows.length,docs:rows.map(r=>({id:r.id,data:()=>r.data}))};
   }});
  }
 };
 const r=await previewOriginalPremiumHistory({store,auth,idToken:'private-test-token'});
 assert.equal(r.receivedGiftCount,1);
 assert.deepEqual(lookups,[
  ['deda_stage71_granted_registry','recipientOriginalId',originalId,201],
  ['deda_stage74_id_gift_receipts','originalId',originalId,201]
 ]);
 assert.equal(paths.includes('deda_share_ids/'+originalId),true);
});
test('server query overflow at 201 rows fails closed',async()=>{
 const uid='original-linked-uid',key='07712345678';
 const docs=new Map([
  ['deda_sessions/'+uid,{uid,accountKey:key}],
  ['deda_account_directory/'+key,{accountKey:key,active:true,createdUid:uid}],
  ['deda_credentials/'+key,{accountKey:key,active:true,createdUid:uid}],
  ['deda_account_profiles/'+key,{accountKey:key,name:'Original User',accountType:'user'}],
  ['users/'+uid,{accountKey:key,sharePersonalId:originalId}],
  ['deda_share_ids/'+originalId,{publicId:originalId,ownerUid:uid,kind:'personal',active:true}]
 ]);
 const store={
  async readOwnerSession(){return {uid,accountKey:key};},
  makeReadOnlyQuery(coll,field,equals,limit){
   assert.equal(limit,201);return {coll,field,equals};
  },
  async runTransaction(work){return work({async get(x){
   if(typeof x==='string')return docs.get(x)??null;
   return {size:201,docs:Array.from({length:201},(_,i)=>({
     id:'@DEDA-ABC'+String(i).padStart(3,'0'),data:()=>grant().data
   }))};
  }});}
 };
 const auth={async verifyIdToken(){return {uid,
  email:key+'@deda-login.invalid',firebase:{sign_in_provider:'password'}};}};
 await assert.rejects(previewOriginalPremiumHistory({
  store,auth,idToken:'token'
 }),e=>e.code==='step2-linked-history-unbounded-or-incomplete');
});
