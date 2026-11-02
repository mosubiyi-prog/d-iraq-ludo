'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {withLinkedOwnerReadSession}=
 require('../deda_step2_linked_owner_read_session_NOT_EXPORTED.js');
const {previewReviewedReceiptForLinkedOwner}=
 require('../deda_step2_verified_receipt_replay_audit_NOT_EXPORTED.js');
const key='07712345678',uid='original-uid-100340',originalId='@DEDA-ABC123';
const email=key+'@deda-login.invalid';
const token=()=>({uid,email,firebase:{sign_in_provider:'password'}});
function fixture(){
 const docs=new Map([
  ['deda_sessions/'+uid,{uid,accountKey:key,installId:'original-install'}],
  ['deda_account_directory/'+key,{accountKey:key,active:true,createdUid:uid}],
  ['deda_credentials/'+key,{accountKey:key,active:true,createdUid:uid}],
  ['deda_account_profiles/'+key,{accountKey:key,name:'Original Profile',accountType:'user'}],
  ['users/'+uid,{accountKey:key,sharePersonalId:originalId}],
  ['deda_share_ids/'+originalId,{publicId:originalId,ownerUid:uid,kind:'personal',active:true}],
 ]);
 const calls={token:0,hint:0,reads:[],writes:0};
 let tokens=[token(),token()];
 const auth={async verifyIdToken(_id,revoke){
   assert.equal(revoke,true);calls.token++;
   const next=tokens[Math.min(calls.token-1,tokens.length-1)];
   if(next instanceof Error)throw next;
   return structuredClone(next);
 }};
 const store={
  async readOwnerSession(userUid){calls.hint++;assert.equal(userUid,uid);return structuredClone(docs.get('deda_sessions/'+uid));},
  async runTransaction(action){
   return action({
    async get(path){calls.reads.push(path);return structuredClone(docs.get(path)??null);},
    set(){calls.writes++;throw Error('NO-WRITE');},
    update(){calls.writes++;throw Error('NO-WRITE');},
    delete(){calls.writes++;throw Error('NO-WRITE');}
   });
  }
 };
 const run=work=>withLinkedOwnerReadSession({store,auth,idToken:'signed-test-token'},work);
 return {docs,calls,store,auth,run,setTokens:x=>{tokens=x;}};
}
test('confirmed original UID can read; no write methods are exposed',async()=>{
 const f=fixture();
 const answer=await f.run(async(tx,account,owner)=>{
  assert.equal(account,key);assert.equal(owner.uid,uid);assert.equal(owner.originalId,originalId);
  assert.equal(tx.set,undefined);assert.equal(tx.update,undefined);assert.equal(tx.delete,undefined);
  return await tx.get('deda_account_profiles/'+key);
 });
 assert.equal(answer.name,'Original Profile');
 assert.equal(f.calls.token,2);assert.equal(f.calls.writes,0);
});
test('same UID can read twice without duplicate marker or writer',async()=>{
 const f=fixture();
 const values=await Promise.all([f.run(async()=>originalId),f.run(async()=>originalId)]);
 assert.deepEqual(values,[originalId,originalId]);assert.equal(f.calls.writes,0);
});
test('anonymous or mismatched provider rejected before any database reads',async()=>{
 for(const provider of ['anonymous','google.com','custom']){
  const f=fixture();
  f.setTokens([{...token(),firebase:{sign_in_provider:provider}}]);
  await assert.rejects(f.run(async()=>true));
  assert.equal(f.calls.reads.length,0);
 }
});
test('different signed-in UID cannot substitute existing owner',async()=>{
 const f=fixture();f.setTokens([{...token(),uid:'other-uid'}]);
 await assert.rejects(f.run(async()=>true));
 assert.equal(f.calls.reads.length,0);
});
test('email must be canonical, not caller-controlled account',async()=>{
 const f=fixture();f.setTokens([{...token(),email:'other@example.com'}]);
 await assert.rejects(f.run(async()=>true));
 assert.equal(f.calls.reads.length,0);
});
test('revocation or account switch at transaction retry rejects work',async()=>{
 for(const changed of [{...token(),uid:'foreign-uid'},new Error('revoked'),{...token(),email:'different@deda-login.invalid'}]){
  const f=fixture();f.setTokens([token(),changed]);
  let ran=false;
  await assert.rejects(f.run(async()=>{ran=true;}));
  assert.equal(ran,false);assert.equal(f.calls.writes,0);
 }
});
test('missing owner routing hint never gives inferred account',async()=>{
 const f=fixture();f.docs.delete('deda_sessions/'+uid);
 await assert.rejects(f.run(async()=>true),e=>e.code==='step2-linked-owner-routing-missing');
 assert.equal(f.calls.reads.length,0);
});
test('active directory and original createdUid are required',async()=>{
 for(const value of [false,null,'other']){
  const f=fixture(),p='deda_account_directory/'+key;
  f.docs.set(p,value===null?null:{accountKey:key,active:value===false?false:true,
    createdUid:value==='other'?'foreign':uid});
  await assert.rejects(f.run(async()=>true));
  assert.equal(f.calls.writes,0);
 }
});
test('stored credentials and profile must match original account',async()=>{
 for(const path of ['deda_credentials/'+key,'deda_account_profiles/'+key]){
  const f=fixture();f.docs.delete(path);
  await assert.rejects(f.run(async()=>true));
  assert.equal(f.calls.writes,0);
 }
});
test('same UID session cannot switch account after routing hint',async()=>{
 const f=fixture();f.docs.set('deda_sessions/'+uid,{uid,accountKey:'07700000000'});
 await assert.rejects(f.run(async()=>true),e=>e.code==='step2-linked-owner-documents-conflict');
 assert.equal(f.calls.writes,0);
});
test('personal ID must remain immutable, not active premium ID',async()=>{
 const f=fixture();f.docs.set('users/'+uid,{accountKey:key,sharePersonalId:'@DEDA-VIP123'});
 await assert.rejects(f.run(async()=>true),e=>e.code==='step2-linked-original-route-mismatch');
 assert.equal(f.calls.writes,0);
});
test('other owner on original route is rejected',async()=>{
 const f=fixture();f.docs.set('deda_share_ids/'+originalId,{
  publicId:originalId,ownerUid:'different-owner',kind:'personal',active:true});
 await assert.rejects(f.run(async()=>true),e=>e.code==='step2-linked-original-route-mismatch');
 assert.equal(f.calls.writes,0);
});
test('after verified read, missing reviewed migration keeps receipts on HOLD',async()=>{
 const f=fixture();
 await assert.rejects(previewReviewedReceiptForLinkedOwner({
  store:f.store,auth:f.auth,idToken:'signed-test-token',
  receiptId:'receipt_missing_2026_00001'
 }),e=>e.code==='migration-required');
 assert.equal(f.calls.writes,0);
});
test('invalid receipt ID is rejected before token or database',async()=>{
 const f=fixture();
 await assert.rejects(previewReviewedReceiptForLinkedOwner({
  store:f.store,auth:f.auth,idToken:'signed-test-token',receiptId:'../../escape'
 }),e=>e.code==='step2-invalid-receipt-id');
 assert.equal(f.calls.token,0);assert.equal(f.calls.reads.length,0);
});
