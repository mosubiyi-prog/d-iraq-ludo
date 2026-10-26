'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path');
const {initializeTestEnvironment,assertSucceeds,assertFails}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDocFromServer,getDocs,collection,deleteDoc,writeBatch,serverTimestamp}=require('firebase/firestore');
const account='07700000000',other='07700000001',original='@DEDA-ABC123';
const uid='private-old',fresh='private-new',foreign='private-other';let env;
const hex=n=>n.toString(16).padStart(48,'0');
const target=`deda_private_account_data/${account}`;
const dbFor=u=>env.authenticatedContext(u).firestore();
const data=(u=uid,v=1,payload='{"favorites":["raw damaged entry"]}')=>({format:1,accountKey:account,
  originalId:original,version:v,mutationId:hex(v),payload,sourceUid:u,updatedAt:serverTimestamp()});
async function write(db,d){const b=writeBatch(db);b.set(doc(db,target),d);
  b.set(doc(db,`${target}/versions/${d.mutationId}`),d);return b.commit();}
test.before(async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^(127\.0\.0\.1|localhost):[0-9]+$/);
  env=await initializeTestEnvironment({projectId:'demo-deda-progress-archive',
    firestore:{rules:fs.readFileSync(path.join(__dirname,'firestore.rules'),'utf8')}});
});
test.after(async()=>{if(env)await env.cleanup();});
test.beforeEach(async()=>{
  await env.clearFirestore();await env.withSecurityRulesDisabled(async c=>{
    const db=c.firestore();
    for(const [u,a] of [[uid,account],[fresh,account],[foreign,other]]){
      await setDoc(doc(db,`users/${u}`),{accountKey:a,sharePersonalId:original});
      await setDoc(doc(db,`deda_sessions/${u}`),{uid:u,accountKey:a,installId:`fixture-${u}`});
    }
    await setDoc(doc(db,`deda_share_ids/${original}`),{publicId:original,kind:'personal',active:true,ownerUid:uid});
  });
});
test('same account with a new UID reads native private records and immutable history',async()=>{
  await assertSucceeds(write(dbFor(uid),data()));
  const read=await assertSucceeds(getDocFromServer(doc(dbFor(fresh),target)));
  assert.equal(read.data().payload,'{"favorites":["raw damaged entry"]}');
  await assertSucceeds(getDocFromServer(doc(dbFor(fresh),`${target}/versions/${hex(1)}`)));
});
test('absent backup is readable as absence by its owner',async()=>{
  assert.equal((await assertSucceeds(getDocFromServer(doc(dbFor(fresh),target)))).exists(),false);
});
test('deletion payload and second handset revision preserve prior history',async()=>{
  await assertSucceeds(write(dbFor(uid),data()));
  await assertSucceeds(write(dbFor(fresh),data(fresh,2,'{"favorites":[],"personalPlaces":null}')));
  const old=await getDocFromServer(doc(dbFor(uid),`${target}/versions/${hex(1)}`));
  assert.equal(old.data().version,1);
  assert.equal((await getDocFromServer(doc(dbFor(uid),target))).data().version,2);
});
for(const u of [foreign,null])test(`${u||'unauthenticated'} cannot read, enumerate or replace another account`,async()=>{
  await write(dbFor(uid),data());const db=u?dbFor(u):env.unauthenticatedContext().firestore();
  await assertFails(getDocFromServer(doc(db,target)));
  await assertFails(getDocs(collection(db,'deda_private_account_data')));
  await assertFails(write(db,data(u||uid,2)));
});
test('head cannot advance without its exact immutable history entry',async()=>{
  const db=dbFor(uid);
  await assertFails(setDoc(doc(db,target),data()));
  const b=writeBatch(db);b.set(doc(db,target),data());
  b.set(doc(db,`${target}/versions/${hex(1)}`),{...data(),payload:'different'});
  await assertFails(b.commit());
});
test('history cannot be created without matching the account head',async()=>{
  await assertFails(setDoc(doc(dbFor(uid),`${target}/versions/${hex(1)}`),data()));
});
test('old handset version cannot overwrite a newer head',async()=>{
  await write(dbFor(uid),data());await write(dbFor(fresh),data(fresh,2));
  await assertFails(write(dbFor(uid),{...data(uid,2),mutationId:hex(9)}));
  assert.equal((await getDocFromServer(doc(dbFor(uid),target))).data().version,2);
});
for(const change of ['version','accountKey','originalId','sourceUid','extra','oversize'])test(`invalid ${change} rejects the whole batch`,async()=>{
  const d=data();
  if(change==='version')d.version=8;if(change==='accountKey')d.accountKey=other;
  if(change==='originalId')d.originalId='@DEDA-2020';if(change==='sourceUid')d.sourceUid=fresh;
  if(change==='extra')d.balance=1000000;if(change==='oversize')d.payload='x'.repeat(200001);
  await assertFails(write(dbFor(uid),d));
});
test('history and head cannot be deleted or history rewritten',async()=>{
  await write(dbFor(uid),data());
  await assertFails(deleteDoc(doc(dbFor(uid),target)));
  await assertFails(deleteDoc(doc(dbFor(uid),`${target}/versions/${hex(1)}`)));
  await assertFails(setDoc(doc(dbFor(uid),`${target}/versions/${hex(1)}`),data()));
  await assertFails(getDocs(collection(dbFor(uid),`${target}/versions`)));
});
