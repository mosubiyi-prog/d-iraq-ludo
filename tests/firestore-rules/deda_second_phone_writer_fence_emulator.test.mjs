import {before, beforeEach, after, test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {initializeTestEnvironment, assertFails, assertSucceeds}
  from '@firebase/rules-unit-testing';
import {doc, getDoc, setDoc, updateDoc, writeBatch, serverTimestamp}
  from 'firebase/firestore';

/**
 * REAL Firestore security-rules evaluation against throwaway emulator ONLY.
 * Synthetic owner/second/attacker users; NO live access or rules deployment.
 */
const PROJECT='demo-deda-second-phone-wallet-fence';
const source=process.env.DEDA_SECOND_PHONE_FENCE_RULES||'';
const emulator=process.env.FIRESTORE_EMULATOR_HOST||'';
assert.match(source,/^\/tmp\/deda-second-phone-fence-[A-Za-z0-9_-]+\.rules$/);
assert.equal(emulator,'127.0.0.1:8080');
assert.equal(process.env.GCLOUD_PROJECT,PROJECT);
const rules=fs.readFileSync(source,'utf8');
assert.match(rules,/DEDA_NEW_PHONE_WALLET_WRITER_CUTOVER_CANDIDATE/);
const ACCOUNT='07701234567',ORIGINAL='@DEDA-ABC123';
const OLD='first_disposable_owner_uid',NEW='second_disposable_owner_uid';
const OTHER='unrelated_disposable_uid';
const oldInstall='emulator-first-phone-install';
const newInstall='emulator-second-phone-install';
const giftWallet='deda_diamond_gift_balances/'+ORIGINAL;
const gmWallet='deda_gm_personal_diamond_wallets/'+ACCOUNT;
const accountFence='deda_migration_account_authority/'+ACCOUNT;
const idFence='deda_migration_spend_authority/'+ORIGINAL;
let env,first,second,outsider;

function originalData(uid){
 return {accountKey:ACCOUNT,sharePersonalId:ORIGINAL,uid,
   name:'emulator DEDA account'};
}
function session(uid,install){
 return {uid,accountKey:ACCOUNT,installId:install,
   signedInAt:new Date('2026-10-29T09:00:00Z'),
   lastSeenAt:new Date('2026-10-29T09:00:00Z')};
}
async function seed(path,data){
 await env.withSecurityRulesDisabled(async ctx=>
   setDoc(doc(ctx.firestore(),path),data));
}
async function activateServerFences(activeUid=NEW){
 // The mobile app CANNOT write these. Fake Admin SDK bypass only in emulator.
 await env.withSecurityRulesDisabled(async ctx=>{
   const admin=ctx.firestore(),ts=new Date('2026-10-29T09:20:00Z');
   await setDoc(doc(admin,idFence),{
     format:1,publicId:ORIGINAL,originalUid:OLD,activeUid,
     status:'new-device-exclusive',protocol:'deda-verified-progress-v1',
     migrationId:'synthetic_fence_migration_0001',
     deploymentRevision:'synthetic_revision_0001',createdAt:ts});
   await setDoc(doc(admin,accountFence),{
     format:1,accountKey:ACCOUNT,originalUid:OLD,activeUid,
     status:'new-device-exclusive',protocol:'deda-verified-progress-v1',
     migrationId:'synthetic_fence_migration_0001',
     deploymentRevision:'synthetic_revision_0001',createdAt:ts});
 });
}
before(async()=>{
 env=await initializeTestEnvironment({
   projectId:PROJECT,firestore:{host:'127.0.0.1',port:8080,rules},
 });
 first=env.authenticatedContext(OLD).firestore();
 second=env.authenticatedContext(NEW).firestore();
 outsider=env.authenticatedContext(OTHER).firestore();
});
beforeEach(async()=>{
 await env.clearFirestore();
 await env.withSecurityRulesDisabled(async ctx=>{
   const a=ctx.firestore();
   const entries=[
     ['users/'+OLD,originalData(OLD)],['users/'+NEW,originalData(NEW)],
     ['deda_sessions/'+OLD,session(OLD,oldInstall)],
     ['deda_sessions/'+NEW,session(NEW,newInstall)],
     ['deda_share_ids/'+ORIGINAL,{publicId:ORIGINAL,ownerUid:OLD,
       kind:'personal',active:true,displayName:'QA only'}],
     ['deda_account_profiles/'+ACCOUNT,{
       accountKey:ACCOUNT,name:'private QA only',phone:ACCOUNT,
       accountType:'user',trustedInstallIds:[oldInstall,newInstall],
       lastSeenAt:new Date('2026-10-29T09:00:00Z')}],
     [giftWallet,{publicId:ORIGINAL,balance:5000,lastClaimGiftId:'fixture',
       createdAt:new Date('2026-10-29T09:00:00Z'),
       updatedAt:new Date('2026-10-29T09:00:00Z')}],
     [gmWallet,{accountKey:ACCOUNT,balance:1000000,initialBalance:1000000,
       createdAt:new Date('2026-10-29T09:00:00Z'),
       updatedAt:new Date('2026-10-29T09:00:00Z')}],
     ['admin_entry_access/'+ACCOUNT,{
       accountKey:ACCOUNT,active:true,status:'active',
       accessType:'general_manager_gateway',allowedRole:'general_manager'}],
   ];
   for(const [path,data] of entries)
     await setDoc(doc(a,path),data);
 });
});
after(async()=>{if(env)await env.cleanup();});

test('01 without a server cutover marker the original legitimate wallet debit remains valid',async()=>{
 await assertSucceeds(updateDoc(doc(first,giftWallet),{
   balance:4900,updatedAt:serverTimestamp()}));
 const v=await assertSucceeds(getDoc(doc(first,giftWallet)));
 assert.equal(v.data().balance,4900);
});
test('02 after server cutover old phone cannot debit or claim and existing wallet remains intact',async()=>{
 await activateServerFences();
 await assertFails(updateDoc(doc(first,giftWallet),{
   balance:1,updatedAt:serverTimestamp()}));
 const v=await assertSucceeds(getDoc(doc(first,giftWallet)));
 assert.equal(v.data().balance,5000);
 await assertFails(updateDoc(doc(first,'deda_sessions/'+OLD),{
   lastSeenAt:serverTimestamp()}));
 await assertFails(updateDoc(doc(first,'users/'+OLD),{
   lastSeenAt:serverTimestamp()}));
});
test('03 verified NEW phone can use original receipt-backed wallet without creating another',async()=>{
 await activateServerFences();
 await assertSucceeds(updateDoc(doc(second,giftWallet),{
   balance:4900,updatedAt:serverTimestamp()}));
 const a=await assertSucceeds(getDoc(doc(second,giftWallet)));
 assert.equal(a.data().balance,4900);
 await assertSucceeds(updateDoc(doc(second,'deda_sessions/'+NEW),{
   lastSeenAt:serverTimestamp()}));
});
test('04 correct owner and wrong third phone are distinct: unrelated UID cannot spend',async()=>{
 await activateServerFences();
 await assertFails(updateDoc(doc(outsider,giftWallet),{
   balance:1,updatedAt:serverTimestamp()}));
 await assertFails(getDoc(doc(outsider,giftWallet)));
});
test('05 old phone cannot acquire the 1000-diamond frame in one atomic checkout',async()=>{
 await activateServerFences();
 const frame='FRAME_03';
 const receipt='deda_lab_frame_receipts/'+ORIGINAL+'/frames/'+frame;
 const owned='deda_lab_owned_frames/'+ORIGINAL+'/frames/'+frame;
 const batch=writeBatch(first);
 batch.set(doc(first,receipt),{
   publicId:ORIGINAL,frameId:frame,kind:'lab_frame',
   cost:1000,createdAt:serverTimestamp()});
 batch.set(doc(first,owned),{
   publicId:ORIGINAL,frameId:frame,
   receiptId:ORIGINAL+'_'+frame,createdAt:serverTimestamp()});
 batch.update(doc(first,giftWallet),{
   balance:4000,updatedAt:serverTimestamp()});
 await assertFails(batch.commit());
 await assertFails(getDoc(doc(first,receipt)));
 const v=await assertSucceeds(getDoc(doc(second,giftWallet)));
 assert.equal(v.data().balance,5000);
});
test('06 new phone CAN buy frame with exactly one wallet debit, receipt and ownership',async()=>{
 await activateServerFences();
 const frame='FRAME_03';
 const receipt='deda_lab_frame_receipts/'+ORIGINAL+'/frames/'+frame;
 const owned='deda_lab_owned_frames/'+ORIGINAL+'/frames/'+frame;
 const batch=writeBatch(second);
 batch.set(doc(second,receipt),{
   publicId:ORIGINAL,frameId:frame,kind:'lab_frame',
   cost:1000,createdAt:serverTimestamp()});
 batch.set(doc(second,owned),{
   publicId:ORIGINAL,frameId:frame,
   receiptId:ORIGINAL+'_'+frame,createdAt:serverTimestamp()});
 batch.update(doc(second,giftWallet),{
   balance:4000,updatedAt:serverTimestamp()});
 await assertSucceeds(batch.commit());
 assert.equal((await assertSucceeds(getDoc(doc(second,giftWallet)))).data().balance,4000);
 assert.equal((await assertSucceeds(getDoc(doc(second,owned)))).data().receiptId,
   ORIGINAL+'_'+frame);
});
test('07 mobile clients cannot forge or delete either server-owned fence record',async()=>{
 for(const db of [first,second,outsider]){
   for(const path of [idFence,accountFence]){
     await assertFails(setDoc(doc(db,path),{activeUid:OLD}));
     await assertFails(getDoc(doc(db,path)));
   }
 }
});
test('08 malformed or third-party fence fails closed rather than sending funds to old UID',async()=>{
 await activateServerFences(OTHER);
 for(const db of [first,second]){
   await assertFails(updateDoc(doc(db,giftWallet),{
     balance:3500,updatedAt:serverTimestamp()}));
 }
});
test('09 original personal GM wallet cannot be debited by old UID after cutover',async()=>{
 await activateServerFences();
 await assertFails(updateDoc(doc(first,gmWallet),{
   balance:999000,updatedAt:serverTimestamp()}));
});
