'use strict';
// Point01: NEW frames + EXISTING badge purchase and gift claiming compatibility.
// Uses synthetic accounts and temporary published-rules-derived candidate ONLY.
const test=require('node:test');
const assert=require('node:assert/strict');
const {readFileSync}=require('node:fs');
const {resolve}=require('node:path');
const {createRequire}=require('node:module');
const req=createRequire(resolve(__dirname,'../functions/package.json'));
const {initializeTestEnvironment,assertFails,assertSucceeds}=
  req('@firebase/rules-unit-testing');
const {doc,setDoc,getDoc,writeBatch,serverTimestamp}=
  req('firebase/firestore');
const PROJECT='demo-deda-100377-legacy-compatible';
assert.equal(process.env.GCLOUD_PROJECT, PROJECT);
assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^(127\.0\.0\.1|localhost):[0-9]{2,5}$/);
const rules=readFileSync('/tmp/deda-point01-legacy-compatible.rules','utf8');
assert.match(rules,/DEDA_100377_POINT01_LEGACY_SHOP_COMPATIBLE_NO_DEPLOY/);
const A={uid:'legacy_buy_owner',key:'9647700001111',id:'@DEDA-AB3C5D'};
const B={uid:'legacy_buy_stranger',key:'9647800002222',id:'@DEDA-ZX4W6V'};
const giftId='point01_legacy_pending_gift';
let env;
const client=(uid=A.uid)=>env.authenticatedContext(uid).firestore();
const wallet=(db,id=A.id)=>doc(db,'deda_diamond_gift_balances',id);
const receipt=(db,frame='FRAME_03',id=A.id)=>
  doc(db,'deda_lab_frame_receipts',id,'frames',frame);
const owned=(db,frame='FRAME_03',id=A.id)=>
  doc(db,'deda_lab_owned_frames',id,'frames',frame);
async function reset(balance=2500){
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    for(const u of [A,B]){
      await setDoc(doc(db,'users',u.uid),{accountKey:u.key,sharePersonalId:u.id});
      await setDoc(doc(db,'deda_sessions',u.uid),{uid:u.uid,accountKey:u.key});
      await setDoc(doc(db,'deda_share_ids',u.id),{
        ownerUid:u.uid,publicId:u.id,kind:'personal',active:true});
    }
    await setDoc(wallet(db),{
      publicId:A.id,balance,createdAt:new Date(),updatedAt:new Date(),
      lastClaimGiftId:'prior_real_claim'});
    await setDoc(doc(db,'deda_diamond_gifts',giftId),{
      giftId,targetPublicId:A.id,amount:100,status:'pending',
      sourceType:'admin',adminUid:'gm_synthetic_owner',
      createdAt:new Date(2026,9,22)});
  });
}
function newFramePurchase(db,frame='FRAME_03',price=1000,after=1500){
  const tx=writeBatch(db);
  const id=A.id+'_'+frame;
  tx.update(wallet(db),{
    balance:after,lastLabFrameId:frame,
    lastLabFrameReceiptId:id,updatedAt:serverTimestamp()});
  tx.set(receipt(db,frame),{
    publicId:A.id,frameId:frame,kind:'lab_frame',cost:price,
    createdAt:serverTimestamp()});
  tx.set(owned(db,frame),{
    publicId:A.id,frameId:frame,receiptId:id,
    createdAt:serverTimestamp()});
  return tx.commit();
}
test.before(async()=>{env=await initializeTestEnvironment({
  projectId:PROJECT,firestore:{host:'127.0.0.1',port:8080,rules},
})});
test.after(async()=>{if(env)await env.cleanup()});
test('original gift-funded badge debit stays accepted, frame purchase still works',async()=>{
  await reset();
  const db=client();
  const old=writeBatch(db);
  old.update(wallet(db),{balance:2300,updatedAt:serverTimestamp()});
  await assertSucceeds(old.commit());
  assert.equal((await getDoc(wallet(db))).data().balance,2300);
  await assertSucceeds(newFramePurchase(db,'FRAME_03',1000,1300));
  assert.equal((await getDoc(wallet(db))).data().balance,1300);
  assert.equal((await getDoc(receipt(db))).data().cost,1000);
  assert.equal((await getDoc(owned(db))).data().receiptId,A.id+'_FRAME_03');
});
test('existing user gift claim remains atomic and cannot claim twice',async()=>{
  await reset();
  const db=client();
  const tx=writeBatch(db);
  tx.update(doc(db,'deda_diamond_gifts',giftId),{
    status:'received',claimedAt:serverTimestamp()});
  tx.update(wallet(db),{
    balance:2600,lastClaimGiftId:giftId,updatedAt:serverTimestamp()});
  await assertSucceeds(tx.commit());
  assert.equal((await getDoc(wallet(db))).data().balance,2600);
  const replay=writeBatch(db);
  replay.update(doc(db,'deda_diamond_gifts',giftId),{
    status:'received',claimedAt:serverTimestamp()});
  replay.update(wallet(db),{
    balance:2700,lastClaimGiftId:giftId,updatedAt:serverTimestamp()});
  await assertFails(replay.commit());
  assert.equal((await getDoc(wallet(db))).data().balance,2600);
});
test('new frame receipt is immutable; duplicate purchase never debits twice',async()=>{
  await reset();
  const db=client();
  await assertSucceeds(newFramePurchase(db));
  await assertFails(newFramePurchase(db,'FRAME_03',1000,500));
  assert.equal((await getDoc(wallet(db))).data().balance,1500);
});
test('simultaneous duplicate requests produce exactly one purchase',async()=>{
  await reset();
  const db=client();
  const results=await Promise.allSettled([
    newFramePurchase(db),newFramePurchase(db)
  ]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
  assert.equal(results.filter(r=>r.status==='rejected').length,1);
  assert.equal((await getDoc(wallet(db))).data().balance,1500);
});
test('two different paid frames each charge 1000 once without overwriting ownership',async()=>{
  await reset(2500);
  const db=client();
  await assertSucceeds(newFramePurchase(db,'FRAME_03',1000,1500));
  await assertSucceeds(newFramePurchase(db,'FRAME_05',1000,500));
  assert.equal((await getDoc(wallet(db))).data().balance,500);
  assert.equal((await getDoc(owned(db,'FRAME_03'))).data().frameId,'FRAME_03');
  assert.equal((await getDoc(owned(db,'FRAME_05'))).data().frameId,'FRAME_05');
  await assertFails(newFramePurchase(db,'FRAME_03',1000,-500));
  assert.equal((await getDoc(wallet(db))).data().balance,500);
});
test('fake LAB wallet markers without a receipt cannot bypass original store permission',async()=>{
  await reset(2500);
  const db=client();
  const b=writeBatch(db);
  b.update(wallet(db),{
    balance:1500,lastLabFrameId:'FRAME_03',
    lastLabFrameReceiptId:A.id+'_FRAME_03',updatedAt:serverTimestamp()});
  await assertFails(b.commit());
  assert.equal((await getDoc(wallet(db))).data().balance,2500);
});
test('price 900, free royalty frame and unknown frame cannot be purchased',async()=>{
  await reset();
  const db=client();
  await assertFails(newFramePurchase(db,'FRAME_03',900,1500));
  await assertFails(newFramePurchase(db,'FRAME_01',1000,1500));
  await assertFails(newFramePurchase(db,'FRAME_17',1000,1500));
  assert.equal((await getDoc(wallet(db))).data().balance,2500);
});
test('owner with only 999 verified gift diamonds cannot buy 1000 frame',async()=>{
  await reset(999);
  const db=client();
  await assertFails(newFramePurchase(db,'FRAME_03',1000,-1));
  assert.equal((await getDoc(wallet(db))).data().balance,999);
});
test('forged ownership or standalone receipt without matching debit denied',async()=>{
  await reset();
  const db=client();
  await assertFails(setDoc(owned(db),{
    publicId:A.id,frameId:'FRAME_03',
    receiptId:A.id+'_FRAME_03',createdAt:serverTimestamp()}));
  await assertFails(setDoc(receipt(db),{
    publicId:A.id,frameId:'FRAME_03',kind:'lab_frame',
    cost:1000,createdAt:serverTimestamp()}));
  assert.equal((await getDoc(wallet(db))).data().balance,2500);
});
test('different user cannot buy, claim, alter, or read owner wallet',async()=>{
  await reset();
  const db=client(B.uid);
  await assertFails(newFramePurchase(db));
  await assertFails(getDoc(wallet(db)));
  const b=writeBatch(db);
  b.update(wallet(db),{balance:2300,updatedAt:serverTimestamp()});
  await assertFails(b.commit());
});
test('unauthenticated user cannot buy a frame',async()=>{
  await reset();
  const db=env.unauthenticatedContext().firestore();
  await assertFails(newFramePurchase(db));
});
