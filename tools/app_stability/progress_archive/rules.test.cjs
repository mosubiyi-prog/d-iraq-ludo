'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment,assertSucceeds,assertFails} = require('@firebase/rules-unit-testing');
const {doc,setDoc,getDocFromServer,deleteDoc,collection,getDocs,serverTimestamp,Timestamp,runTransaction} = require('firebase/firestore');
const account='07700000000',otherAccount='07700000001';
const oldUid='owner-old',newUid='owner-new',otherUid='owner-other';
const oldId='capture_old_intent_0001',newId='capture_new_intent_0001';
const evidencePath=(key=account,id=newId)=>`deda_progress_evidence/${key}/captures/${id}`;
const records=()=>({taskPoints:'{"awards":{"spent":{"points":-5000}}}',socialCoinsAndXp:'{"coins":17,"xp":3020,"taskClaims":["day|task"]}',earnedDiamonds:'{"balance":9}'});
function payload(id=newId) {return {format:1,kind:'legacy-local-evidence',accountKey:account,sourceUid:oldUid,
  installId:'fixture-old-install',captureId:id,records:records(),createdAt:serverTimestamp()};}
let env;
const dbFor=(uid)=>env.authenticatedContext(uid).firestore();
test.before(async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^(127\.0\.0\.1|localhost):[0-9]+$/,
    'requires localhost emulator; never use production credentials');
  env=await initializeTestEnvironment({projectId:'demo-deda-progress-archive',firestore:{
    rules:fs.readFileSync(path.join(__dirname,'firestore.rules'),'utf8')}});
});
test.after(async()=>{if(env)await env.cleanup();});
test.beforeEach(async()=>{
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    for(const [uid,key,install] of [[oldUid,account,'fixture-old-install'],[newUid,account,'fixture-new-install'],[otherUid,otherAccount,'fixture-other-install']]) {
      await setDoc(doc(db,'users',uid),{accountKey:key});
      await setDoc(doc(db,'deda_sessions',uid),{uid,accountKey:key,installId:install});
    }
    await setDoc(doc(db,evidencePath(account,oldId)),{...payload(oldId),createdAt:Timestamp.now()});
  });
});
test('verified original owner can create and read immutable raw evidence',async()=>{
  const db=dbFor(oldUid);
  await assertSucceeds(setDoc(doc(db,evidencePath()),payload()));
  const saved=await assertSucceeds(getDocFromServer(doc(db,evidencePath())));
  assert.deepEqual(saved.data().records,records());
  assert(saved.data().createdAt instanceof Timestamp);
});
test('native owner proof can read only its own users projection',async()=>{
  const own=await assertSucceeds(getDocFromServer(doc(dbFor(oldUid),'users',oldUid)));
  assert.equal(own.data().accountKey,account);
  await assertFails(getDocFromServer(doc(dbFor(oldUid),'users',newUid)));
  await assertFails(getDocs(collection(dbFor(oldUid),'users')));
});
test('own users projection remains read-only and unavailable without authentication',async()=>{
  const ref=doc(dbFor(oldUid),'users',oldUid);
  await assertFails(setDoc(ref,{accountKey:otherAccount}));
  await assertFails(deleteDoc(ref));
  await assertFails(getDocFromServer(doc(env.unauthenticatedContext().firestore(),'users',oldUid)));
});
test('new UID and new install for SAME proven account can read old-device evidence',async()=>{
  const saved=await assertSucceeds(getDocFromServer(doc(dbFor(newUid),evidencePath(account,oldId))));
  assert.equal(saved.data().sourceUid,oldUid);
  assert.equal(saved.data().installId,'fixture-old-install');
});
test('same account on new device can list its own evidence collection',async()=>{
  const rows=await assertSucceeds(getDocs(collection(dbFor(newUid),`deda_progress_evidence/${account}/captures`)));
  assert.equal(rows.size,1);
});
for(const operation of ['read','create','list']) {
  test(`unauthenticated ${operation} is rejected`,async()=>{
    const db=env.unauthenticatedContext().firestore();
    if(operation==='read')await assertFails(getDocFromServer(doc(db,evidencePath(account,oldId))));
    if(operation==='create')await assertFails(setDoc(doc(db,evidencePath()),payload()));
    if(operation==='list')await assertFails(getDocs(collection(db,`deda_progress_evidence/${account}/captures`)));
  });
  test(`different verified account cannot ${operation} the owner's archive`,async()=>{
    const db=dbFor(otherUid);
    if(operation==='read')await assertFails(getDocFromServer(doc(db,evidencePath(account,oldId))));
    if(operation==='create')await assertFails(setDoc(doc(db,evidencePath()),payload()));
    if(operation==='list')await assertFails(getDocs(collection(db,`deda_progress_evidence/${account}/captures`)));
  });
}
for(const defect of ['no-session','no-user-projection','wrong-session-uid','wrong-user-account']) {
  test(`incomplete ownership proof ${defect} is rejected`,async()=>{
    await env.withSecurityRulesDisabled(async ctx=>{
      const db=ctx.firestore();
      if(defect==='no-session')await deleteDoc(doc(db,'deda_sessions',oldUid));
      if(defect==='no-user-projection')await deleteDoc(doc(db,'users',oldUid));
      if(defect==='wrong-session-uid')await setDoc(doc(db,'deda_sessions',oldUid),{uid:'foreign',accountKey:account,installId:'fixture-old-install'});
      if(defect==='wrong-user-account')await setDoc(doc(db,'users',oldUid),{accountKey:otherAccount});
    });
    await assertFails(getDocFromServer(doc(dbFor(oldUid),evidencePath(account,oldId))));
    await assertFails(setDoc(doc(dbFor(oldUid),evidencePath()),payload()));
  });
}
const badCases={
  sourceUid:d=>{d.sourceUid=newUid;},
  accountKey:d=>{d.accountKey=otherAccount;},
  installId:d=>{d.installId='wrong-install';},
  kind:d=>{d.kind='verified-wallet';},
  format:d=>{d.format=2;},
  captureId:d=>{d.captureId=oldId;},
  clientTime:d=>{d.createdAt=Timestamp.fromMillis(1);},
  trustedFlag:d=>{d.trusted=true;},
  missingRecord:d=>{delete d.records.taskPoints;},
  extraRecord:d=>{d.records.balance=1000000;},
  numericRecord:d=>{d.records.earnedDiamonds=1000000;},
  oversizedRecord:d=>{d.records.taskPoints='x'.repeat(200001);},
};
for(const [name,mutate]of Object.entries(badCases)) {
  test(`invalid archive field ${name} cannot be created`,async()=>{
    const data=payload();mutate(data);
    await assertFails(setDoc(doc(dbFor(oldUid),evidencePath()),data));
  });
}
test('path ID must follow the fixed capture intent format',async()=>{
  await assertFails(setDoc(doc(dbFor(oldUid),evidencePath(account,'short')),{...payload(),captureId:'short'}));
});
test('null/empty/malformed local payloads are preserved without interpreting them as balances',async()=>{
  const data=payload();data.records={taskPoints:null,socialCoinsAndXp:'',earnedDiamonds:'{broken'};
  await assertSucceeds(setDoc(doc(dbFor(oldUid),evidencePath()),data));
  const saved=await assertSucceeds(getDocFromServer(doc(dbFor(newUid),evidencePath())));
  assert.deepEqual(saved.data().records,data.records);
});
for(const operation of ['update','delete']) {
  test(`even the original owner cannot ${operation} an existing snapshot`,async()=>{
    const ref=doc(dbFor(oldUid),evidencePath(account,oldId));
    if(operation==='delete')await assertFails(deleteDoc(ref));
    else await assertFails(setDoc(ref,{...payload(oldId),records:{...records(),earnedDiamonds:'{"balance":0}'}}));
  });
}
test('blind replay of identical set is denied rather than changing the server timestamp',async()=>{
  await assertFails(setDoc(doc(dbFor(oldUid),evidencePath(account,oldId)),payload(oldId)));
});
test('two concurrent transactions for the SAME intent preserve exactly one document',async()=>{
  async function saveOnce(db) {
    const ref=doc(db,evidencePath());
    return runTransaction(db,async tx=>{
      const prior=await tx.get(ref);
      if(prior.exists()) {
        assert.deepEqual(prior.data().records,records());
        assert.equal(prior.data().sourceUid,oldUid);
        return;
      }
      tx.set(ref,payload());
    });
  }
  await assertSucceeds(Promise.all([saveOnce(dbFor(oldUid)),saveOnce(dbFor(oldUid))]));
  const rows=await assertSucceeds(getDocs(collection(dbFor(newUid),`deda_progress_evidence/${account}/captures`)));
  assert.equal(rows.size,2); // one seeded old snapshot and exactly one new intent.
});
test('new UID cannot overwrite old history but can create a separate snapshot after valid login',async()=>{
  const data={...payload(),sourceUid:newUid,installId:'fixture-new-install'};
  await assertFails(setDoc(doc(dbFor(newUid),evidencePath(account,oldId)),{...data,captureId:oldId}));
  await assertSucceeds(setDoc(doc(dbFor(newUid),evidencePath()),data));
});
for(const wallet of ['deda_diamond_gift_balances','deda_gm_personal_diamond_wallets','deda_admin_diamond_wallets']) {
  test(`archive policy cannot credit or recreate ${wallet}`,async()=>{
    await assertFails(setDoc(doc(dbFor(oldUid),wallet,account),{balance:1000000}));
  });
}
test('claiming manager/custom-account tokens does not grant access to another account',async()=>{
  const db=env.authenticatedContext('fake-manager',{role:'general_manager',accountKey:account}).firestore();
  await assertFails(getDocFromServer(doc(db,evidencePath(account,oldId))));
});
test('cross-account parent collection listing is denied',async()=>{
  await assertFails(getDocs(collection(dbFor(oldUid),'deda_progress_evidence')));
});
const purchaseId='purchase_capture_origin_00001',purchaseOriginal='@DEDA-ABC123';
const purchasePath=(id=purchaseId)=>`deda_purchase_evidence/${account}/captures/${id}`;
const purchaseFrames=['FRAME_03','FRAME_05','FRAME_06','FRAME_07','FRAME_08','FRAME_09','FRAME_10','FRAME_11','FRAME_12','FRAME_13','FRAME_14','FRAME_15','FRAME_16'];
function purchasePayload(){return {format:1,kind:'legacy-purchase-evidence',accountKey:account,sourceUid:oldUid,
 installId:'fixture-old-install',captureId:purchaseId,createdAt:serverTimestamp(),records:{originalId:purchaseOriginal,
 progressCaptureId:oldId,localSnapshot:JSON.stringify({format:1,accountKey:account,originalId:purchaseOriginal,
 inventory:' {"owned":["frame_3"]} ',frameJournals:Object.fromEntries(purchaseFrames.map(id=>[id,id==='FRAME_03'?'paid':null]))})}};}
async function purchaseProof(){await env.withSecurityRulesDisabled(async ctx=>{
 const db=ctx.firestore();await setDoc(doc(db,'users',oldUid),{accountKey:account,sharePersonalId:purchaseOriginal});
 await setDoc(doc(db,'users',newUid),{accountKey:account,sharePersonalId:purchaseOriginal});
 await setDoc(doc(db,'deda_share_ids',purchaseOriginal),{publicId:purchaseOriginal,kind:'personal',active:true,ownerUid:oldUid});
});}
test('original device can create linked immutable purchase evidence without altering raw progress parent',async()=>{
 await purchaseProof();const db=dbFor(oldUid),before=(await getDocFromServer(doc(db,evidencePath(account,oldId)))).data();
 await assertSucceeds(setDoc(doc(db,purchasePath()),purchasePayload()));
 const saved=(await assertSucceeds(getDocFromServer(doc(db,purchasePath())))).data();
 assert.equal(saved.records.progressCaptureId,oldId);assert.equal(JSON.parse(saved.records.localSnapshot).frameJournals.FRAME_03,'paid');
 assert.deepEqual((await getDocFromServer(doc(db,evidencePath(account,oldId)))).data(),before);
});
test('new UID/install for same account reads and lists original payment journal with old provenance',async()=>{
 await purchaseProof();await assertSucceeds(setDoc(doc(dbFor(oldUid),purchasePath()),purchasePayload()));
 const saved=(await assertSucceeds(getDocFromServer(doc(dbFor(newUid),purchasePath())))).data();
 assert.equal(saved.sourceUid,oldUid);assert.equal(saved.installId,'fixture-old-install');
 assert.equal((await assertSucceeds(getDocs(collection(dbFor(newUid),`deda_purchase_evidence/${account}/captures`)))).size,1);
});
test('new UID can capture its own journal only alongside a parent captured under that new UID/install',async()=>{
 await purchaseProof();const db=dbFor(newUid);
 await assertSucceeds(setDoc(doc(db,evidencePath(account,newId)),{...payload(newId),sourceUid:newUid,installId:'fixture-new-install'}));
 const data=purchasePayload();data.sourceUid=newUid;data.installId='fixture-new-install';data.records.progressCaptureId=newId;
 await assertSucceeds(setDoc(doc(db,purchasePath()),data));
});
test('new UID cannot relabel original phone journal as its own by linking the older parent',async()=>{
 await purchaseProof();const data=purchasePayload();data.sourceUid=newUid;data.installId='fixture-new-install';
 await assertFails(setDoc(doc(dbFor(newUid),purchasePath()),data));
});
for(const who of ['unauthenticated','other-account'])test(`${who} cannot read, list or forge purchase sidecars`,async()=>{
 await purchaseProof();await assertSucceeds(setDoc(doc(dbFor(oldUid),purchasePath()),purchasePayload()));
 const db=who==='unauthenticated'?env.unauthenticatedContext().firestore():dbFor(otherUid);
 await assertFails(getDocFromServer(doc(db,purchasePath())));
 await assertFails(getDocs(collection(db,`deda_purchase_evidence/${account}/captures`)));
 const data=purchasePayload();data.captureId='other_purchase_capture_0001';
 await assertFails(setDoc(doc(db,purchasePath(data.captureId)),data));
});
for(const defect of ['foreign-source','wrong-install','missing-parent','inactive-route','wrong-user-original','foreign-route-owner','alias-route'])test(`purchase sidecar ${defect} blocked by server proof`,async()=>{
 await purchaseProof();const data=purchasePayload();
 if(defect==='foreign-source')data.sourceUid=newUid;
 if(defect==='wrong-install')data.installId='new-install';
 if(defect==='missing-parent')data.records.progressCaptureId='missing_parent_capture_001';
 await env.withSecurityRulesDisabled(async ctx=>{
  const db=ctx.firestore();
  if(defect==='inactive-route')await setDoc(doc(db,'deda_share_ids',purchaseOriginal),{active:false},{merge:true});
  if(defect==='wrong-user-original')await setDoc(doc(db,'users',oldUid),{sharePersonalId:'@DEDA-OTHER1'},{merge:true});
  if(defect==='foreign-route-owner')await setDoc(doc(db,'deda_share_ids',purchaseOriginal),{ownerUid:otherUid},{merge:true});
  if(defect==='alias-route')await setDoc(doc(db,'deda_share_ids',purchaseOriginal),{kind:'premium'},{merge:true});
 });
 await assertFails(setDoc(doc(dbFor(oldUid),purchasePath()),data));
});
for(const field of ['extra-field','client-time','wrong-kind','oversized-snapshot','missing-snapshot'])test(`invalid purchase ${field} rejected`,async()=>{
 await purchaseProof();const data=purchasePayload();
 if(field==='extra-field')data.verified=true;if(field==='client-time')data.createdAt=Timestamp.fromMillis(1);
 if(field==='wrong-kind')data.kind='verified-receipt';if(field==='oversized-snapshot')data.records.localSnapshot='x'.repeat(200001);
 if(field==='missing-snapshot')delete data.records.localSnapshot;
 await assertFails(setDoc(doc(dbFor(oldUid),purchasePath()),data));
});
test('purchase sidecars cannot be overwritten/deleted and add no routing collection read or write grant',async()=>{
 await purchaseProof();await assertSucceeds(setDoc(doc(dbFor(oldUid),purchasePath()),purchasePayload()));
 for(const uid of [oldUid,newUid]){
  await assertFails(setDoc(doc(dbFor(uid),purchasePath()),{records:{localSnapshot:'paid'}},{merge:true}));
  await assertFails(deleteDoc(doc(dbFor(uid),purchasePath())));
  await assertFails(getDocFromServer(doc(dbFor(uid),'deda_share_ids',purchaseOriginal)));
  await assertFails(setDoc(doc(dbFor(uid),'deda_share_ids',purchaseOriginal),{active:true},{merge:true}));
 }
});
