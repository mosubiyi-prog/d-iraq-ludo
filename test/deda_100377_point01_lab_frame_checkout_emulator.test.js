'use strict';
// Point01: LOCAL FIRESTORE EMULATOR ONLY, synthetic account and gift wallet.
// Verifies atomic 1000 frame debit, receipt, ownership and replay protection.
// NEVER read/write production DEDA accounts.
const test = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');
const {createRequire} = require('node:module');
const req = createRequire(resolve(__dirname, '../functions/package.json'));
const {initializeTestEnvironment, assertFails, assertSucceeds} =
  req('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, writeBatch, serverTimestamp} =
  req('firebase/firestore');
const PROJECT = 'demo-deda-100377-frames';
assert.equal(process.env.GCLOUD_PROJECT, PROJECT);
assert.match(process.env.FIRESTORE_EMULATOR_HOST || '',
  /^(127\.0\.0\.1|localhost):[0-9]{2,5}$/);
const rules = readFileSync('/tmp/deda-point01-frame-candidate.rules', 'utf8');
assert.match(rules,/DEDA_100377_POINT01_LAB_FRAME_1000_RULES_OFFLINE_NO_DEPLOY/);
const user={uid:'frame_owner_A',key:'9647700001111',id:'@DEDA-AX7H9P'};
const stranger={uid:'frame_user_B',key:'9647800002222',id:'@DEDA-BY8J3Q'};
let env;
const wallet=(db,id=user.id)=>doc(db,'deda_diamond_gift_balances',id);
const receipt=(db,frame='FRAME_03',id=user.id)=>
  doc(db,'deda_lab_frame_receipts',id,'frames',frame);
const owned=(db,frame='FRAME_03',id=user.id)=>
  doc(db,'deda_lab_owned_frames',id,'frames',frame);
const client=(uid=user.uid)=>env.authenticatedContext(uid).firestore();
async function reset(balance=2500){
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    for(const a of [user,stranger]){
      await setDoc(doc(db,'deda_sessions',a.uid),{uid:a.uid,accountKey:a.key});
      await setDoc(doc(db,'users',a.uid),
        {accountKey:a.key,sharePersonalId:a.id});
      await setDoc(doc(db,'deda_share_ids',a.id),
        {ownerUid:a.uid,kind:'personal',active:true,publicId:a.id});
    }
    await setDoc(wallet(db),{
      publicId:user.id,balance,createdAt:new Date(),updatedAt:new Date(),
      lastClaimGiftId:'synthetic-original-gift'});
  });
}
function checkout(db,frame='FRAME_03',price=1000,balanceAfter=1500){
  const batch=writeBatch(db), id=user.id+'_'+frame;
  batch.update(wallet(db),{
    balance:balanceAfter,lastLabFrameId:frame,
    lastLabFrameReceiptId:id,updatedAt:serverTimestamp()});
  batch.set(receipt(db,frame),{
    publicId:user.id,frameId:frame,kind:'lab_frame',
    cost:price,createdAt:serverTimestamp()});
  batch.set(owned(db,frame),{
    publicId:user.id,frameId:frame,receiptId:id,
    createdAt:serverTimestamp()});
  return batch.commit();
}
test.before(async()=>{
  env=await initializeTestEnvironment({
    projectId:PROJECT,firestore:{host:'127.0.0.1',port:8080,rules}});
});
test.after(async()=>{if(env)await env.cleanup()});
test('atomic 1000 checkout creates immutable receipt and ownership',async()=>{
  await reset();
  const db=client();
  await assertSucceeds(checkout(db));
  assert.equal((await getDoc(wallet(db))).data().balance,1500);
  assert.equal((await getDoc(receipt(db))).data().cost,1000);
  assert.equal((await getDoc(owned(db))).data().receiptId,
    user.id+'_FRAME_03');
  await assertFails(checkout(db,'FRAME_03',1000,500));
  assert.equal((await getDoc(wallet(db))).data().balance,1500);
});
test('genuine existing admin gift claim survives 1000-frame checkout rules',async()=>{
  await reset(2500);
  const giftId='point01_real_gift_preservation_100';
  await env.withSecurityRulesDisabled(async ctx=>{
    await setDoc(doc(ctx.firestore(),'deda_diamond_gifts',giftId),{
      giftId,targetPublicId:user.id,amount:100,status:'pending',
      sourceType:'admin',adminUid:'synthetic_manager',
      createdAt:new Date(2026,9,1)});
  });
  const db=client();
  const gift=writeBatch(db);
  gift.update(doc(db,'deda_diamond_gifts',giftId),{
    status:'received',claimedAt:serverTimestamp()});
  gift.update(wallet(db),{
    balance:2600,lastClaimGiftId:giftId,updatedAt:serverTimestamp()});
  await assertSucceeds(gift.commit());
  assert.equal((await getDoc(wallet(db))).data().balance,2600);
  const replay=writeBatch(db);
  replay.update(doc(db,'deda_diamond_gifts',giftId),{
    status:'received',claimedAt:serverTimestamp()});
  replay.update(wallet(db),{
    balance:2700,lastClaimGiftId:giftId,updatedAt:serverTimestamp()});
  await assertFails(replay.commit());
  assert.equal((await getDoc(wallet(db))).data().balance,2600);
});

test('two concurrent taps cannot both own or debit the same frame',async()=>{
  await reset(2500);
  const db=client();
  const outcomes=await Promise.allSettled([
    checkout(db,'FRAME_03',1000,1500),
    checkout(db,'FRAME_03',1000,1500),
  ]);
  assert.equal(outcomes.filter(x=>x.status==='fulfilled').length,1);
  assert.equal(outcomes.filter(x=>x.status==='rejected').length,1);
  assert.equal((await getDoc(wallet(db))).data().balance,1500);
  assert.equal((await getDoc(receipt(db))).data().cost,1000);
});

test('wallet-only debit and standalone owned frame are denied',async()=>{
  await reset();
  const db=client();
  const b=writeBatch(db);
  b.update(wallet(db),{balance:1500,updatedAt:serverTimestamp()});
  await assertFails(b.commit());
  await assertFails(setDoc(owned(db),{
    publicId:user.id,frameId:'FRAME_03',
    receiptId:user.id+'_FRAME_03',createdAt:serverTimestamp()}));
  assert.equal((await getDoc(wallet(db))).data().balance,2500);
});
test('wrong cost or premium catalog exclusion is denied',async()=>{
  await reset();
  const db=client();
  await assertFails(checkout(db,'FRAME_03',900,1500));
  await assertFails(checkout(db,'FRAME_01',1000,1500)); // free royal
  await assertFails(checkout(db,'FRAME_17',1000,1500));
  assert.equal((await getDoc(wallet(db))).data().balance,2500);
});
test('insufficient server-verified funds deny any ownership',async()=>{
  await reset(999);
  const db=client();
  await assertFails(checkout(db,'FRAME_03',1000,-1));
  assert.equal((await getDoc(wallet(db))).data().balance,999);
});
test('stranger cannot buy from or change owner wallet',async()=>{
  await reset();
  const db=client(stranger.uid);
  await assertFails(checkout(db));
  let amount;
  await env.withSecurityRulesDisabled(async ctx=>{
    amount=(await getDoc(wallet(ctx.firestore()))).data().balance;
  });
  assert.equal(amount,2500);
});
test('unauthenticated cannot create ownership or debit funds',async()=>{
  await reset();
  const db=env.unauthenticatedContext().firestore();
  await assertFails(checkout(db));
});
