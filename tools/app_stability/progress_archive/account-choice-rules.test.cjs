'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path');
const {initializeTestEnvironment,assertSucceeds,assertFails}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDocFromServer,getDocs,collection,deleteDoc,serverTimestamp,Timestamp,runTransaction}=require('firebase/firestore');
const account='07700000000',other='07700000001',original='@DEDA-ABC123',foreign='@DEDA-DEF456';
const uid='choice-old',fresh='choice-new',stranger='choice-other';let env;
const hex=n=>n.toString(16).padStart(48,'0');
const target=(a=account,o=original)=>`deda_free_card_choices/${a}/cards/${o}`;
const dbFor=u=>env.authenticatedContext(u).firestore();
const value=(u=uid,version=1,choice='gold')=>({format:1,accountKey:account,originalId:original,
  version,choice,mutationId:hex(version),sourceUid:u,updatedAt:serverTimestamp()});
test.before(async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^(127\.0\.0\.1|localhost):[0-9]+$/);
  env=await initializeTestEnvironment({projectId:'demo-deda-progress-archive',firestore:{rules:fs.readFileSync(path.join(__dirname,'firestore.rules'),'utf8')}});
});
test.after(async()=>{if(env)await env.cleanup();});
test.beforeEach(async()=>{
  await env.clearFirestore();await env.withSecurityRulesDisabled(async c=>{
    const db=c.firestore();
    for(const [u,a,o] of [[uid,account,original],[fresh,account,original],[stranger,other,foreign]]) {
      await setDoc(doc(db,`users/${u}`),{accountKey:a,sharePersonalId:o});
      await setDoc(doc(db,`deda_sessions/${u}`),{uid:u,accountKey:a,installId:`fixture-${u}`});
    }
    for(const [o,u] of [[original,uid],[foreign,stranger]]) {
      await setDoc(doc(db,`deda_share_ids/${o}`),{publicId:o,kind:'personal',active:true,ownerUid:u});
    }
  });
});
test('a second UID for the same PIN account reads the first handset choice',async()=>{
  await assertSucceeds(setDoc(doc(dbFor(uid),target()),value()));
  const saved=await assertSucceeds(getDocFromServer(doc(dbFor(fresh),target())));
  assert.equal(saved.data().choice,'gold');assert.equal(saved.data().sourceUid,uid);
  assert(saved.data().updatedAt instanceof Timestamp);
});
test('the second handset can update its OWN account without changing ownership',async()=>{
  await assertSucceeds(setDoc(doc(dbFor(uid),target()),value()));
  await assertSucceeds(setDoc(doc(dbFor(fresh),target()),value(fresh,2,'pink')));
  const saved=await getDocFromServer(doc(dbFor(uid),target()));assert.equal(saved.data().version,2);
});
test('missing account choice is readable as absence by its owner only',async()=>{
  assert.equal((await assertSucceeds(getDocFromServer(doc(dbFor(fresh),target())))).exists(),false);
  await assertFails(getDocFromServer(doc(dbFor(stranger),target())));
});
for(const action of ['get','create','update','list','delete']) {
  test(`foreign and unauthenticated ${action} are rejected`,async()=>{
    await assertSucceeds(setDoc(doc(dbFor(uid),target()),value()));
    for(const db of [dbFor(stranger),env.unauthenticatedContext().firestore()]) {
      if(action==='get')await assertFails(getDocFromServer(doc(db,target())));
      if(action==='create')await assertFails(setDoc(doc(db,target(account,'@DEDA-QQQ111')),value()));
      if(action==='update')await assertFails(setDoc(doc(db,target()),value(uid,2,'pink')));
      if(action==='list')await assertFails(getDocs(collection(db,`deda_free_card_choices/${account}/cards`)));
      if(action==='delete')await assertFails(deleteDoc(doc(db,target())));
    }
  });
}
for(const defect of ['no-session','wrong-session-uid','wrong-user-account','wrong-original','inactive-route','different-route-owner']) {
  test(`owner proof defect ${defect} prevents both read and write`,async()=>{
    await env.withSecurityRulesDisabled(async c=>{
      const db=c.firestore();
      if(defect==='no-session')await deleteDoc(doc(db,`deda_sessions/${uid}`));
      if(defect==='wrong-session-uid')await setDoc(doc(db,`deda_sessions/${uid}`),{uid:fresh,accountKey:account});
      if(defect==='wrong-user-account')await setDoc(doc(db,`users/${uid}`),{accountKey:other,sharePersonalId:original});
      if(defect==='wrong-original')await setDoc(doc(db,`users/${uid}`),{accountKey:account,sharePersonalId:foreign});
      if(defect==='inactive-route')await setDoc(doc(db,`deda_share_ids/${original}`),{publicId:original,kind:'personal',active:false,ownerUid:uid});
      if(defect==='different-route-owner')await setDoc(doc(db,`deda_share_ids/${original}`),{publicId:original,kind:'personal',active:true,ownerUid:stranger});
    });
    await assertFails(getDocFromServer(doc(dbFor(uid),target())));
    await assertFails(setDoc(doc(dbFor(uid),target()),value()));
  });
}
const invalid={
  financialField:d=>{d.balance=1000000;},ownershipField:d=>{d.ownedIds=['VIP'];},
  account:d=>{d.accountKey=other;},original:d=>{d.originalId=foreign;},
  uid:d=>{d.sourceUid=fresh;},time:d=>{d.updatedAt=Timestamp.fromMillis(0);},
  color:d=>{d.choice='paid';},version:d=>{d.version=0;},fraction:d=>{d.version=1.5;},
  mutation:d=>{d.mutationId='short';},missing:d=>{delete d.choice;},
};
for(const [name,change] of Object.entries(invalid))test(`invalid choice ${name} is refused`,async()=>{
  const d=value();change(d);await assertFails(setDoc(doc(dbFor(uid),target()),d));
});
test('owner cannot enumerate accounts or delete the version guard',async()=>{
  await assertSucceeds(setDoc(doc(dbFor(uid),target()),value()));
  await assertFails(getDocs(collection(dbFor(uid),`deda_free_card_choices/${account}/cards`)));
  await assertFails(deleteDoc(doc(dbFor(uid),target())));
});
test('old version, skipped version and repeated mutation ID cannot overwrite a newer choice',async()=>{
  const db=dbFor(uid),ref=doc(db,target());await assertSucceeds(setDoc(ref,value()));
  await assertSucceeds(setDoc(ref,value(uid,2,'royal')));
  for(const d of [value(uid,2,'pink'),value(uid,4,'pink'),{...value(uid,3,'pink'),mutationId:hex(2)}]) {
    await assertFails(setDoc(ref,d));
  }
  assert.equal((await getDocFromServer(ref)).data().choice,'royal');
});
test('real SDK compare-and-set accepts only one concurrent handset at the same version',async()=>{
  await setDoc(doc(dbFor(uid),target()),value());
  async function change(db,u,color,id) {
    return runTransaction(db,async tx=>{
      const ref=doc(db,target()),old=await tx.get(ref);
      if(old.data().version!==1)throw Error('choice-conflict');
      tx.set(ref,{...value(u,2,color),mutationId:hex(id)});
    });
  }
  const outcomes=await Promise.allSettled([change(dbFor(uid),uid,'pink',40),change(dbFor(fresh),fresh,'royal',41)]);
  assert.equal(outcomes.filter(r=>r.status==='fulfilled').length,1);
  const saved=await getDocFromServer(doc(dbFor(uid),target()));assert.equal(saved.data().version,2);
});
