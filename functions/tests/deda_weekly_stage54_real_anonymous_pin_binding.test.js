'use strict';
/* Private real HTTP integration: Auth Emulator → Functions v2 → Firestore.
 * All fixtures synthetic. Never reads a real account, app, or production data.
 * Emulator-issued Auth tokens are UNSIGNED, App Check not tested.
 */
const test=require('node:test');
const assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const PROJECT='demo-deda-stage54-pin-binding';
if(process.env.GCLOUD_PROJECT!==PROJECT||
  process.env.STAGE54_EMULATOR_ONLY!=='true'||
  !process.env.FIREBASE_AUTH_EMULATOR_HOST||
  !process.env.FIREBASE_FUNCTIONS_EMULATOR_HOST||
  !process.env.FIRESTORE_EMULATOR_HOST)
 throw Error('STAGE54_REFUSE_NO_EMULATORS');
const AUTH='http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:';
const FUNC='http://127.0.0.1:5001/'+PROJECT+'/us-central1/dedaStage54LegacyPinPreflight';
const FIRST='07701234567',SECOND='07702223334',LOCK='07703334445';
const PIN_A='417263',PIN_B='508172',PIN_LOCK='936251',INVALID='000000';
const app=initializeApp({projectId:PROJECT},'stage54-integration-test');
const db=getFirestore(app);
const ids=[];
async function signup(){
 const result=await fetch(AUTH+'signUp?key=stage54-disposable-only',{
   method:'POST',headers:{'Content-Type':'application/json'},
   body:JSON.stringify({returnSecureToken:true})
 });
 const body=await result.json();
 if(!result.ok)throw Error('LOCAL_AUTH_EMULATOR_SIGNUP_FAILED_'+result.status);
 assert.equal(typeof body.idToken,'string');
 assert.equal(typeof body.localId,'string');
 ids.push(body);
 return body;
}
async function call(id,accountKey,pin,extras,rawAuth){
 const headers={'Content-Type':'application/json'};
 if(id)headers.Authorization='Bearer '+id.idToken;
 if(rawAuth)headers.Authorization=rawAuth;
 const data={accountKey,pin,...extras};
 const response=await fetch(FUNC,{method:'POST',headers,
   body:JSON.stringify({data})});
 return {status:response.status,body:await response.json()};
}
function hold(result,accountKey,pin){
 assert.equal(result.status,200,JSON.stringify(result).slice(0,180));
 const v=result.body?.result;
 assert.equal(v?.emulatorOnly,true);
 assert.equal(v?.serverOwnedBinding,true);
 assert.equal(v?.awardState,'HOLD_NO_GRANTS');
 for(const k of ['canCreditTaskPoints','canCreditLifetimeXp',
   'canCreditSocialCoins','canCreditLeagueXp','canCreditDiamonds',
   'canIssueWinnerGift','appCheckVerified','productionReady',
   'migrationApproved','legacyWriterCutover'])
   assert.equal(v[k],false,k);
 const text=JSON.stringify(result);
 assert.equal(text.includes(accountKey),false);
 assert.equal(text.includes(pin),false);
 assert.equal(text.includes('originalInstallId'),false);
}
function reject(result){
 assert.notEqual(result.status,200,JSON.stringify(result).slice(0,240));
 assert.equal(result.body?.result,undefined);
 const response=JSON.stringify(result.body);
 for(const secret of [FIRST,SECOND,LOCK,PIN_A,PIN_B,PIN_LOCK])
   assert.equal(response.includes(secret),false,'must not leak private account or PIN');
}
async function seed(account,pin){
 const batch=db.batch();
 batch.set(db.doc('deda_credentials/'+account),{
   accountKey:account,pin,active:true,createdUid:'STAGE54_SYNTHETIC'});
 batch.set(db.doc('deda_account_directory/'+account),{
   accountKey:account,active:true,createdUid:'STAGE54_SYNTHETIC'});
 batch.set(db.doc('deda_account_profiles/'+account),{
   accountKey:account,name:'Stage54 synthetic',trustedInstallIds:['local-old-device']});
 await batch.commit();
}
let one,two,third,attacker,outsider;
test.before(async()=>{
 [one,two,third,attacker,outsider]=await Promise.all([
   signup(),signup(),signup(),signup(),signup()
 ]);
 await seed(FIRST,PIN_A);
 await seed(SECOND,PIN_B);
 await seed(LOCK,PIN_LOCK);
 const batch=db.batch();
 batch.set(db.doc('users/'+one.localId),{
   accountKey:FIRST,diamonds:111,xp:765,coins:22,
   frames:['original-bought'],originalId:'@DEDA-STAGE54'});
 batch.set(db.doc('users/'+one.localId+'/wallet/original'),{
   diamonds:111,xp:765,coins:22,frames:['original-bought']});
 batch.set(db.doc('deda_admin_diamond_wallets/gm'),{diamonds:1000000});
 await batch.commit();
});
test.after(async()=>deleteApp(app));

test('1: registered anonymous Auth UID + correct original PIN creates server-owned HOLD binding',async()=>{
 const r=await call(one,FIRST,PIN_A);
 hold(r,FIRST,PIN_A);
 const b=(await db.doc('deda_stage54_private_account_bindings/'+one.localId).get()).data();
 assert.equal(b.uid,one.localId);
 assert.equal(b.accountKey,FIRST);
 assert.equal(b.canGrant,false);
 assert.equal(b.canMigrate,false);
 assert.equal(b.authProvider,'anonymous');
});

test('2: second independent anonymous phone can bind same canonical account with original PIN',async()=>{
 hold(await call(two,FIRST,PIN_A),FIRST,PIN_A);
 const a=(await db.doc('deda_stage54_private_account_bindings/'+one.localId).get()).data();
 const b=(await db.doc('deda_stage54_private_account_bindings/'+two.localId).get()).data();
 assert.equal(a.accountKey,b.accountKey);
 assert.notEqual(a.uid,b.uid);
});

test('3: no Firebase Auth token cannot create identity binding',async()=>{
 reject(await call(null,FIRST,PIN_A));
});

test('4: client-forged XP, diamonds, UID, install or rank fields are rejected before any binding',async()=>{
 for(const extra of [
   {uid:one.localId},{installId:'local-old-device'},
   {trustedInstallIds:['local-old-device']},{xp:20},
   {diamonds:150},{rank:1},{coins:10},{winner:'top1'},
   {proof:'signed-by-client'},{accountKey:SECOND}
 ]){
  const r=await call(outsider,FIRST,PIN_A,extra);
  // A forged accountKey overwrites the request account, so it might be valid
  // by itself. Specifically use a wrong PIN to ensure no cross-account proof.
  reject(r);
 }
 assert.equal((await db.doc('deda_stage54_private_account_bindings/'+outsider.localId).get()).exists,false);
});

test('5: wrong original PIN rejected with no account secret echoed',async()=>{
 reject(await call(third,SECOND,INVALID));
 assert.equal((await db.doc('deda_stage54_private_account_bindings/'+third.localId).get()).exists,false);
});

test('6: a correct PIN can still bind before reaching the independent backend lock threshold',async()=>{
 hold(await call(third,SECOND,PIN_B),SECOND,PIN_B);
});

test('7: copied old install ID cannot replace the required PIN',async()=>{
 reject(await call(attacker,SECOND,INVALID,{installId:'local-old-device'}));
 reject(await call(attacker,SECOND,INVALID));
 assert.equal((await db.doc('deda_stage54_private_account_bindings/'+attacker.localId).get()).exists,false);
});

test('8: 5 wrong attempts lock account on backend, then correct PIN is temporarily rejected',async()=>{
 const responses=[];
 for(let i=0;i<5;i++)responses.push(await call(attacker,LOCK,INVALID));
 responses.forEach(reject);
 reject(await call(attacker,LOCK,PIN_LOCK));
 assert.equal((await db.doc('deda_stage54_private_account_bindings/'+attacker.localId).get()).exists,false);
});

test('9: account-level lock also denies second caller UID (not a local device counter)',async()=>{
 reject(await call(outsider,LOCK,PIN_LOCK));
});

test('10: a locked account does not stop a separate account from authenticating',async()=>{
 hold(await call(attacker,SECOND,PIN_B),SECOND,PIN_B);
});

test('11: original UID cannot silently switch from its already-bound account to another one',async()=>{
 reject(await call(one,SECOND,PIN_B));
 const b=(await db.doc('deda_stage54_private_account_bindings/'+one.localId).get()).data();
 assert.equal(b.accountKey,FIRST);
});

test('12: repeat correct PIN for same UID is idempotent, not a new identity or reward grant',async()=>{
 const before=(await db.doc('deda_stage54_private_account_bindings/'+one.localId).get()).data();
 hold(await call(one,FIRST,PIN_A),FIRST,PIN_A);
 const after=(await db.doc('deda_stage54_private_account_bindings/'+one.localId).get()).data();
 assert.equal(before.accountKey,after.accountKey);
 assert.equal(before.createdAt.toMillis(),after.createdAt.toMillis());
 assert.equal(after.canGrant,false);
});

test('13: concurrent same-UID valid PIN requests do not create duplicate records',async()=>{
 const results=await Promise.all([call(two,FIRST,PIN_A),call(two,FIRST,PIN_A)]);
 results.forEach(x=>hold(x,FIRST,PIN_A));
 const bindings=await db.collection('deda_stage54_private_account_bindings').get();
 assert.equal(bindings.docs.filter(x=>x.id===two.localId).length,1);
});

test('14: invalid/malformed Authorization header is not a credential',async()=>{
 for(const header of ['Bearer broken','Basic not-a-firebase-token']){
   reject(await call(null,FIRST,PIN_A,{},header));
 }
});

test('15: server binding does not alter original user progress, wallets, gems, admin wallet or private gift inbox',async()=>{
 assert.deepEqual((await db.doc('users/'+one.localId+'/wallet/original').get()).data(),{
   diamonds:111,xp:765,coins:22,frames:['original-bought']
 });
 const u=(await db.doc('users/'+one.localId).get()).data();
 assert.equal(u.xp,765);assert.equal(u.diamonds,111);assert.equal(u.coins,22);
 assert.equal((await db.doc('deda_admin_diamond_wallets/gm').get()).data().diamonds,1000000);
 assert.equal((await db.collection('deda_weekly_stage45_private_gift_inbox').get()).size,0);
 assert.equal((await db.collection('deda_verified_progress').get()).size,0);
 assert.equal((await db.collection('deda_stage54_private_account_bindings').get()).size,4);
});
