import {readFileSync} from 'node:fs';
import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {initializeTestEnvironment,assertSucceeds,assertFails}
  from '@firebase/rules-unit-testing';
import {doc,getDoc,setDoc,writeBatch,serverTimestamp,Timestamp}
  from 'firebase/firestore';

const PROJECT='demo-deda-100426-spark-recovery';
const source=readFileSync(process.env.DEDA_DIRECT_RULES_PATH,'utf8');
const KEY='07702223333',ALT='07802223333',PIN='538249';
const ORIGINAL='@DEDA-AB3C5D';
const SRC='creator-uid-100426',NEW='replacement-uid-100426',BAD='untrusted-uid-100426';
let env,origin,newphone,attacker;
const accountDoc=(db,path)=>doc(db,path);
const pinProof=(db,uid,accountKey=KEY,pin=PIN)=>setDoc(
  accountDoc(db,'deda_auth_attempts/'+uid),{
    uid,accountKey,pin,createdAt:serverTimestamp()
  });
const anchor=(db,key=KEY)=>accountDoc(db,'deda_recovery_original_anchors/'+key);
const lock=(db,id=ORIGINAL)=>accountDoc(db,'deda_recovery_original_locks/'+id);
const hold=(db,uid=NEW)=>accountDoc(db,'deda_recovery_identity_holds/'+uid);
const aPayload=(key=KEY,original=ORIGINAL,uid=SRC)=>({
  accountKey:key,originalId:original,sourceUid:uid,createdAt:serverTimestamp()
});
const hPayload=(uid=NEW,key=KEY,original=ORIGINAL,src=SRC)=>({
  uid,accountKey:key,originalId:original,sourceUid:src,
  status:'PIN_PROVED_HOLD',createdAt:serverTimestamp(),
  canRestoreAssets:false,canMigrate:false,canCreditXp:false,
  canCreditDiamonds:false,canIssueGift:false
});
before(async()=>{
  env=await initializeTestEnvironment({projectId:PROJECT,firestore:{rules:source}});
  origin=env.authenticatedContext(SRC).firestore();
  newphone=env.authenticatedContext(NEW).firestore();
  attacker=env.authenticatedContext(BAD).firestore();
  await env.withSecurityRulesDisabled(async x=>{
    const db=x.firestore();
    await setDoc(accountDoc(db,'deda_credentials/'+KEY),
      {accountKey:KEY,pin:PIN,active:true,createdUid:SRC});
    await setDoc(accountDoc(db,'deda_account_directory/'+KEY),
      {accountKey:KEY,active:true,createdUid:SRC});
    await setDoc(accountDoc(db,'deda_account_profiles/'+KEY),
      {accountKey:KEY, trustedInstallIds:['copied-install']});
    await setDoc(accountDoc(db,'users/'+SRC),
      {accountKey:KEY,sharePersonalId:ORIGINAL,name:'original owner'});
    await setDoc(accountDoc(db,'deda_share_ids/'+ORIGINAL),
      {publicId:ORIGINAL,ownerUid:SRC,kind:'personal',active:true,
       displayName:'original owner'});
    await setDoc(accountDoc(db,'deda_sessions/'+BAD),
      {uid:BAD,accountKey:KEY,installId:'copied-install'});
  });
});
after(async()=>{if(env)await env.cleanup();});

test('Spark PIN proof is accepted by original owner, but bad PIN is denied',async()=>{
  await assertFails(pinProof(attacker,BAD,KEY,'000000'));
  await assertSucceeds(pinProof(origin,SRC));
});
test('source device atomically enrolls exactly one original ID anchor + lock',async()=>{
  const batch=writeBatch(origin);
  batch.set(anchor(origin),aPayload());
  batch.set(lock(origin),aPayload());
  await assertSucceeds(batch.commit());
  assert.equal((await assertSucceeds(getDoc(anchor(origin)))).data().originalId,ORIGINAL);
  await assertFails(getDoc(lock(origin)));
});
test('copied install ID and legacy session do not grant original ID lookup',async()=>{
  await assertFails(getDoc(anchor(attacker)));
  await assertFails(setDoc(hold(attacker,BAD),hPayload(BAD)));
});
test('second device uses fresh correct PIN to read original ID automatically',async()=>{
  await assertSucceeds(pinProof(newphone,NEW));
  const a=await assertSucceeds(getDoc(anchor(newphone)));
  assert.equal(a.data().sourceUid,SRC);
  assert.equal(a.data().originalId,ORIGINAL);
});
test('second device writes HOLD only, no source ID transfer',async()=>{
  await assertSucceeds(setDoc(hold(newphone),hPayload()));
  const r=(await assertSucceeds(getDoc(hold(newphone)))).data();
  assert.equal(r.status,'PIN_PROVED_HOLD');
  for(const k of ['canRestoreAssets','canMigrate','canCreditXp',
                  'canCreditDiamonds','canIssueGift'])assert.equal(r[k],false);
  await assertFails(getDoc(hold(origin,NEW)));
  await assertFails(setDoc(hold(newphone),{...hPayload(),canRestoreAssets:true}));
});
test('a new UID cannot invent sourceUid, originalId or enable any asset operation',async()=>{
  await assertSucceeds(pinProof(attacker,BAD));
  await assertFails(setDoc(hold(attacker,BAD),hPayload(BAD,KEY,'@DEDA-ZZ9999')));
  await assertFails(setDoc(hold(attacker,BAD),hPayload(BAD,KEY,ORIGINAL,'another-owner')));
  await assertFails(setDoc(hold(attacker,BAD),{...hPayload(BAD),canCreditDiamonds:true}));
  await assertSucceeds(setDoc(hold(attacker,BAD),hPayload(BAD)));
});
test('owner cannot modify an original ID or overwrite existing anchor / lock',async()=>{
  await assertFails(setDoc(anchor(origin),aPayload(KEY,'@DEDA-ZZ9999')));
  await assertFails(setDoc(lock(origin),aPayload(KEY,'@DEDA-ZZ9999')));
});
test('different account cannot enroll an already locked original ID',async()=>{
  await env.withSecurityRulesDisabled(async x=>{
    const db=x.firestore();
    await setDoc(accountDoc(db,'deda_credentials/'+ALT),
      {accountKey:ALT,pin:PIN,active:true,createdUid:SRC});
    await setDoc(accountDoc(db,'deda_account_directory/'+ALT),
      {accountKey:ALT,active:true,createdUid:SRC});
    await setDoc(accountDoc(db,'users/'+SRC),
      {accountKey:ALT,sharePersonalId:ORIGINAL});
  });
  try {
    await assertSucceeds(pinProof(origin,SRC,ALT,PIN));
    const batch=writeBatch(origin);
    batch.set(anchor(origin,ALT),aPayload(ALT));
    batch.set(lock(origin),aPayload(ALT));
    await assertFails(batch.commit());
  } finally {
    await env.withSecurityRulesDisabled(async x=>{
      const db=x.firestore();
      await setDoc(accountDoc(db,'users/'+SRC),
        {accountKey:KEY,sharePersonalId:ORIGINAL});
    });
  }
});
test('stale proof cannot read an immutable anchor from another device',async()=>{
  const stale=Timestamp.fromMillis(Date.now()-30*60*1000);
  await env.withSecurityRulesDisabled(async x=>{
    await setDoc(accountDoc(x.firestore(),'deda_auth_attempts/'+NEW),
      {uid:NEW,accountKey:KEY,pin:PIN,createdAt:stale});
  });
  await assertFails(getDoc(anchor(newphone)));
  await assertSucceeds(pinProof(newphone,NEW));
  await assertSucceeds(getDoc(anchor(newphone)));
});
test('no untrusted list/read of another device proof or original ID lock',async()=>{
  const outsider=env.unauthenticatedContext().firestore();
  await assertFails(getDoc(anchor(outsider)));
  await assertFails(getDoc(lock(attacker)));
  await assertFails(getDoc(hold(attacker,NEW)));
});
