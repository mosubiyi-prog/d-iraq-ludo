'use strict';
const {test,before,after,beforeEach}=require('node:test');
const assert=require('node:assert/strict');
const {readFileSync}=require('node:fs');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,getDocFromServer,setDoc,deleteDoc,collection,getDocs,writeBatch}=require('firebase/firestore');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore,FieldValue}=require('firebase-admin/firestore');
const {DedaTrustedProgressTransactionStore}=require('./reconcile-store.cjs');
const {LAB_UID:uid}=require('./reconcile-core.cjs');
const {project,projectAccount,readWalletEvidence,refreshWallet,activateOwnedId,pointTier,generateWalletRead,mutateFriendCandidate,executeFriendCandidateCommand,generateFriendCandidateRules}=require('./uid-ownership-projection.cjs');
const projectId='demo-deda-stage03-uid',base='deda_lab_uid_authority/'+uid,source=base+'/inventorySources/current',view=base+'/inventory/current';
const weekId='2026-10-31',ms=Date.UTC(2026,10,7,3),identifier='@DEDA-QAFIXTURE';
let env,app,db,store;
const client=(id=uid,provider='password')=>env.authenticatedContext(id,{firebase:{sign_in_provider:provider}}).firestore();
const frame=()=>({frameId:'FRAME_03',receipt:{uid,frameId:'FRAME_03',kind:'lab_frame',cost:1000,createdMs:ms},ownership:{uid,frameId:'FRAME_03',receiptId:uid+'_FRAME_03',createdMs:ms}});
const gift=()=>({identifier,grant:{uid,identifier,group:'001',baseColor:'gold',kind:'gifted',grantedMs:ms},acceptance:null});
const prize=()=>({giftId:'deda-weekly-'+weekId+'-'+uid,uid,sourceType:'weekly_league',weekId,amount:250,status:'pending',createdMs:ms,receivedMs:null});
const admin=()=>({giftId:'synthetic-admin-gift',uid,sourceType:'admin',weekId:null,amount:30,status:'pending',createdMs:ms,receivedMs:null});
const fixture=(revision=1)=>({format:1,uid,revision,complete:true,frames:[frame()],idGifts:[gift()],diamondGifts:[prize(),admin()]});
const seed=v=>db.doc(source).set(v);
const apply=()=>project({store,uid});
const read=async()=> (await db.doc(view).get()).data();
before(async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^127\.0\.0\.1:[0-9]+$/);
  assert.equal(process.env.GCLOUD_PROJECT,projectId);
  env=await initializeTestEnvironment({projectId,firestore:{rules:readFileSync('firestore.rules','utf8')}});
  app=initializeApp({projectId},'stage03-ownership-demo');db=getFirestore(app);
  store=new DedaTrustedProgressTransactionStore({db,serverTimestamp:()=>FieldValue.serverTimestamp()});
});
after(async()=>{if(db)await db.terminate();if(app)await deleteApp(app);if(env)await env.cleanup()});
beforeEach(async()=>{await env.clearFirestore()});
test('missing or explicitly incomplete source never yields empty inventory',async()=>{
  await assert.rejects(apply(),{code:'ownership-source-missing'});
  await seed({...fixture(),complete:false});
  await assert.rejects(apply(),{code:'ownership-source-incomplete'});
  assert.equal(await read(),undefined);
});
test('paired frame, pending ID and diamond gifts restored by same UID, no financial credit',async()=>{
  await seed(fixture());const result=await apply();
  assert.equal(result.replayed,false);
  const restored=await assertSucceeds(getDocFromServer(doc(client(),view)));
  assert.deepEqual(restored.data(),result.view);
  assert.equal(restored.data().frames.length,1);assert.equal(restored.data().idGifts[0].acceptance,null);
  assert.equal(restored.data().diamondGifts.every(g=>g.status==='pending'),true);
  assert.equal((await db.doc(base).get()).exists,false);
  assert.equal((await db.doc('deda_verified_progress/'+uid).get()).exists,false);
});
test('wrong owner, unapproved frame and mismatched pair are rejected',async()=>{
  for(const mutate of [v=>v.frames[0].receipt.uid='foreign',v=>v.frames[0].frameId='FRAME_01',
    v=>v.frames[0].ownership.receiptId='bad',v=>v.frames[0].receipt.cost=1]){
    const v=fixture();mutate(v);await seed(v);await assert.rejects(apply());assert.equal(await read(),undefined);
  }
});
test('accepting already granted ID and already issued gifts updates history without payout',async()=>{
  await seed(fixture());await apply();
  const v=fixture(2);v.idGifts[0].acceptance={uid,identifier,group:'001',receivedMs:ms+1};
  for(const g of v.diamondGifts){g.status='received';g.receivedMs=ms+1;}
  await seed(v);await apply();const current=await read();assert.equal(current.idGifts[0].acceptance.receivedMs,ms+1);
  assert.equal(current.diamondGifts.every(g=>g.status==='received'),true);
  assert.equal((await db.doc(base).get()).exists,false);
  const replay=await apply();assert.equal(replay.replayed,true);
  assert.equal((await db.collection(base+'/inventoryHistory').get()).size,2);
  assert.deepEqual(await read(),current);
});
test('duplicate ID or weekly receipt, early prize, changed recipient and forged acceptance denied',async()=>{
  for(const mutate of [v=>v.idGifts.push(gift()),v=>v.diamondGifts.push(prize()),
    v=>v.diamondGifts[0].createdMs=ms-1,v=>v.diamondGifts[0].uid='foreign',
    v=>v.idGifts[0].acceptance={uid:'foreign',identifier,group:'001',receivedMs:ms+1}]){
    const v=fixture();mutate(v);await seed(v);await assert.rejects(apply());assert.equal(await read(),undefined);
  }
});
test('later source cannot remove purchased frames or erase grants, gifts, amounts or acceptance',async()=>{
  const first=fixture();first.idGifts[0].acceptance={uid,identifier,group:'001',receivedMs:ms+1};
  first.diamondGifts[0].status='received';first.diamondGifts[0].receivedMs=ms+1;
  await seed(first);await apply();const old=await read();
  for(const mutate of [v=>v.frames=[],v=>v.idGifts=[],v=>v.idGifts[0].acceptance=null,
    v=>v.diamondGifts=[],v=>v.diamondGifts[0].amount=500,
    v=>{v.diamondGifts[0].status='pending';v.diamondGifts[0].receivedMs=null}]){
    const v=structuredClone(first);v.revision=2;mutate(v);await seed(v);
    await assert.rejects(apply(),{code:'ownership-history-regression'});assert.deepEqual(await read(),old);
  }
});
test('same revision different content and skipped revision fail, competing replay commits once',async()=>{
  await seed(fixture());const a=await Promise.all([apply(),apply()]);assert.equal(a.filter(x=>x.replayed).length,1);
  const bad=fixture();bad.diamondGifts[0].amount=999;await seed(bad);
  await assert.rejects(apply(),{code:'ownership-revision-conflict'});
  await seed(fixture(3));await assert.rejects(apply(),{code:'ownership-revision-conflict'});
  assert.equal((await read()).revision,1);
});
test('client reads only own view and cannot write source, view, history or grant itself anything',async()=>{
  await seed(fixture());await apply();const owner=client();
  await assertSucceeds(getDocFromServer(doc(owner,view)));
  for(const c of [owner,client('foreign'),client(uid,'anonymous'),env.unauthenticatedContext().firestore()]){
    await assertFails(setDoc(doc(c,source),fixture(2)));
    await assertFails(setDoc(doc(c,view),fixture(2)));
    await assertFails(deleteDoc(doc(c,view)));
    await assertFails(setDoc(doc(c,base+'/inventoryHistory/2'),fixture(2)));
    await assertFails(getDocFromServer(doc(c,source)));
    await assertFails(getDocFromServer(doc(c,base+'/inventoryHistory/1')));
    await assertFails(getDocs(collection(c,base,'inventory')));
  }
  for(const c of [client('foreign'),client(uid,'anonymous'),env.unauthenticatedContext().firestore()])await assertFails(getDocFromServer(doc(c,view)));
  assert.equal((await read()).revision,1);
});

const acctSource=base+'/accountSources/current',acctView=base+'/account/current';
const other='synthetic-peer-001', original='@DEDA-QA1234',peerId='@DEDA-QA5678';
const claimMs=Date.UTC(2026,10,1,10),claimKey='2026-11-01|open_map';
const accountFixture=(revision=1)=>({format:1,uid,revision,complete:true,
  profile:{displayName:'Synthetic QA',originalId:original,activeId:original,fixedColor:null},
  friends:[{pairKey:[uid,other].sort().join('__'),members:[uid,other],requesterUid:uid,recipientUid:other,
    requesterPublicId:original,recipientPublicId:peerId,requesterName:'Synthetic QA',recipientName:'Synthetic peer',status:'accepted'}],
  tasks:[{claimKey,dayId:'2026-11-01',taskId:'open_map',completedMs:claimMs,claimedMs:claimMs+1}],
  league:[{weekId,claimedKeys:[claimKey],completedTasks:1,weeklyXp:20}]});
const accountSeed=v=>db.doc(acctSource).set(v);
const accountApply=()=>projectAccount({store,uid});
// Existing UID and trusted synthetic peer records only. No Auth enrolment.
const friendGraphPath='deda_friendships/'+[uid,other].sort().join('__');
async function seedFriendActionFixture(direction='accepted'){
  const a=accountFixture();
  if(direction==='incoming'){
    a.friends[0]={...a.friends[0],members:[other,uid],requesterUid:other,
      recipientUid:uid,requesterPublicId:peerId,recipientPublicId:original,
      requesterName:'Synthetic peer',recipientName:'Synthetic QA',status:'pending'};
  }
  await accountSeed(a);await accountApply();
  const seed={
    ['users/'+uid]:{accountKey:uid,sharePersonalId:original},
    ['deda_sessions/'+uid]:{uid,accountKey:uid},
    ['deda_share_ids/'+original]:{ownerUid:uid,publicId:original,kind:'personal',active:true},
    ['deda_share_ids/'+peerId]:{ownerUid:other,publicId:peerId,kind:'personal',active:true},
    ['deda_social_profiles/'+peerId]:{ownerUid:other,publicId:peerId,displayName:'Synthetic peer'},
    [friendGraphPath]:a.friends[0],
  };
  await Promise.all(Object.entries(seed).map(([p,v])=>db.doc(p).set(v)));
  return a;
}
const friendAction=(action,expectedRevision,peerUid=other)=>
  mutateFriendCandidate({store,uid,peerUid,action,expectedRevision});
test('04/02 trusted demo removes and sends exactly once, protects source and unrelated rights',async()=>{
  const old=await seedFriendActionFixture();
  const removed=await friendAction('remove',1);
  assert.equal(removed.friends.length,0);
  assert.equal((await db.doc(friendGraphPath).get()).exists,false);
  await assert.rejects(friendAction('send',1),{code:'friends-revision-conflict'});
  const sent=await friendAction('send',2);
  assert.equal(sent.friends[0].status,'pending');
  assert.equal(sent.friends[0].requesterUid,uid);
  assert.deepEqual((await db.doc(friendGraphPath).get()).data(),sent.friends[0]);
  await assert.rejects(friendAction('accept',3),{code:'friends-not-pending-recipient'});
  await assert.rejects(friendAction('send',3),{code:'friends-existing-request-or-relation'});
  await assert.rejects(friendAction('remove',3),{code:'friends-not-accepted'});
  await assert.rejects(friendAction('send',3,uid),{code:'friends-candidate-input'});
  assert.deepEqual(sent.profile,old.profile);assert.deepEqual(sent.tasks,old.tasks);
  assert.deepEqual(sent.league,old.league);
  assert.deepEqual((await db.doc(acctSource).get()).data(),sent);
  assert.deepEqual((await db.doc(base+'/accountHistory/3').get()).data(),sent);
  await assertFails(setDoc(doc(client(),friendGraphPath),{...sent.friends[0],status:'accepted'}));
  await assertFails(setDoc(doc(client(),acctView),{...sent,revision:4}));
});
test('04/02 incoming response requires recipient, matching canonical relationship and exact revision',async()=>{
  for(const action of ['accept','reject']){
    await env.clearFirestore();
    await seedFriendActionFixture('incoming');
    const row=(await db.doc(friendGraphPath).get()).data();
    await db.doc(friendGraphPath).set({...row,status:'accepted'});
    await assert.rejects(friendAction(action,1),{code:'friends-canonical-projection-conflict'});
    await db.doc(friendGraphPath).set(row);
    await db.doc('deda_share_ids/'+peerId).update({ownerUid:uid});
    await assert.rejects(friendAction(action,1),{code:'friends-directory-owner-unproven'});
    await db.doc('deda_share_ids/'+peerId).update({ownerUid:other});
    const result=await friendAction(action,1);
    assert.equal(result.friends[0].status,action==='accept'?'accepted':'rejected');
    assert.deepEqual((await db.doc(friendGraphPath).get()).data(),result.friends[0]);
    await assert.rejects(friendAction(action,1),{code:'friends-revision-conflict'});
    await assert.rejects(friendAction(action,2),{code:'friends-not-pending-recipient'});
  }
});
test('04/02 bilateral synthetic lifecycle uses one owner UID, canonical row and monotonic history',async()=>{
  const old=await seedFriendActionFixture();
  const peer=(action,expectedRevision)=>mutateFriendCandidate({
    store,uid,peerUid:other,action,expectedRevision,simulatePeer:true});
  await friendAction('remove',1);
  const sent=await friendAction('send',2);
  assert.equal(sent.friends[0].recipientUid,other);
  await assert.rejects(friendAction('accept',3),{code:'friends-not-pending-recipient'});
  const rejected=await peer('reject',3);
  assert.equal(rejected.friends[0].status,'rejected');
  const incoming=await peer('send',4);
  assert.equal(incoming.friends[0].requesterUid,other);
  assert.equal(incoming.friends[0].recipientUid,uid);
  assert.equal(sent.friends[0].requestRevision,3);
  assert.equal(rejected.friends[0].requestRevision,3);
  assert.equal(incoming.friends[0].requestRevision,5);
  await assert.rejects(peer('accept',5),{code:'friends-not-pending-recipient'});
  const accepted=await friendAction('accept',5);
  assert.equal(accepted.friends[0].status,'accepted');
  assert.equal(accepted.friends[0].requestRevision,5);
  assert.deepEqual((await db.doc(friendGraphPath).get()).data(),accepted.friends[0]);
  const gone=await peer('remove',6);
  assert.equal(gone.friends.length,0);
  assert.equal((await db.doc(friendGraphPath).get()).exists,false);
  const competing=await Promise.allSettled([friendAction('send',7),peer('send',7)]);
  assert.equal(competing.filter(x=>x.status==='fulfilled').length,1);
  assert.equal(competing.find(x=>x.status==='rejected').reason.code,'friends-revision-conflict');
  const next=competing.find(x=>x.status==='fulfilled').value;
  assert.equal(next.revision,8);
  assert.deepEqual((await db.doc(friendGraphPath).get()).data(),next.friends[0]);
  assert.deepEqual((await db.doc(acctView).get()).data(),next);
  assert.deepEqual((await db.doc(acctSource).get()).data(),next);
  assert.equal((await db.collection(base+'/accountHistory').get()).size,8);
  assert.deepEqual(next.profile,old.profile);
  assert.deepEqual(next.tasks,old.tasks);
  assert.deepEqual(next.league,old.league);
  assert.equal((await db.doc('users/'+other).get()).exists,false);
  assert.equal((await db.doc('deda_sessions/'+other).get()).exists,false);
  assert.equal((await db.doc('deda_lab_uid_authority/'+other+'/account/current').get()).exists,false);
  await assertFails(setDoc(doc(client(),friendGraphPath),{...next.friends[0],status:'accepted'}));
});
test('04/02 UI command boundary uses existing trusted worker and rejects forged peer or stale event',async()=>{
  await seedFriendActionFixture('incoming');
  const cmd={format:1,action:'accept',peerUid:other,peerPublicId:peerId,
    pairKey:[uid,other].sort().join('__'),expectedRevision:1,requestRevision:null};
  const run=command=>executeFriendCandidateCommand({store,uid,command});
  await assert.rejects(run({...cmd,simulatePeer:true}),{code:'ownership-schema'});
  await assert.rejects(run({...cmd,peerPublicId:original}),{code:'friends-command-invalid'});
  await assert.rejects(run({...cmd,requestRevision:1}),{code:'friends-command-stale-request'});
  const accepted=await run(cmd);
  assert.equal(accepted.friends[0].status,'accepted');
  await assert.rejects(run(cmd),{code:'friends-revision-conflict'});
  const removed=await run({...cmd,action:'remove',expectedRevision:2});
  assert.equal(removed.friends.length,0);
  const sent=await run({...cmd,action:'send',expectedRevision:3});
  assert.equal(sent.friends[0].status,'pending');
  assert.equal(sent.friends[0].requestRevision,4);
  await assert.rejects(run({...cmd,action:'reject',expectedRevision:4,requestRevision:4}),
    {code:'friends-not-pending-recipient'});
  await assertFails(setDoc(doc(client(),acctView),{...sent,revision:5}));
});
test('04/02 scoped Spark client candidate accepts only exact atomic friend transitions',async()=>{
  const initial=await seedFriendActionFixture('incoming');
  const p='deda_social_profiles/'+peerId;
  await db.doc(p).update({avatarStyle:1,frameStyle:0,backgroundStyle:0,level:1,badges:[]});
  const rules=generateFriendCandidateRules(readFileSync('firestore.rules','utf8'));
  const local=await initializeTestEnvironment({projectId,firestore:{rules}});
  try{
    const c=(id=uid,provider='password')=>local.authenticatedContext(id,{firebase:{sign_in_provider:provider}}).firestore();
    const owner=c();
    await assertSucceeds(getDocFromServer(doc(owner,p)));
    await assertFails(getDocFromServer(doc(c(other),p)));
    await assertFails(getDocs(collection(owner,'deda_social_profiles')));
    await assertFails(setDoc(doc(owner,p),{ownerUid:uid}));
    const commit=(client,next,omit='')=>{
      const batch=writeBatch(client);
      for(const path of [acctView,acctSource,base+'/accountHistory/'+next.revision])
        if(path!==omit)batch.set(doc(client,path),next);
      if(omit!==friendGraphPath){
        if(next.friends.length)batch.set(doc(client,friendGraphPath),next.friends[0]);
        else batch.delete(doc(client,friendGraphPath));
      }
      return batch.commit();
    };
    const accepted={...initial,revision:2,friends:[{...initial.friends[0],status:'accepted'}]};
    await assertFails(commit(owner,{...accepted,profile:{...initial.profile,displayName:'forged'}}));
    await assertFails(commit(owner,{...accepted,tasks:[]}));
    await assertFails(commit(owner,accepted,acctSource));
    await assertFails(commit(owner,accepted,friendGraphPath));
    await assertFails(commit(c(other),accepted));
    await assertFails(commit(c(uid,'anonymous'),accepted));
    await assertSucceeds(commit(owner,accepted));
    await assertFails(commit(owner,accepted));
    const removed={...accepted,revision:3,friends:[]};
    await assertSucceeds(commit(owner,removed));
    const pending={...removed,revision:4,friends:[{pairKey:[uid,other].sort().join('__'),
      members:[uid,other],requesterUid:uid,recipientUid:other,requesterPublicId:original,
      recipientPublicId:peerId,requesterName:initial.profile.displayName,
      recipientName:'Synthetic peer',status:'pending',requestRevision:4}]};
    await assertSucceeds(commit(owner,pending));
    await assertFails(commit(owner,{...pending,revision:5,friends:[{...pending.friends[0],status:'accepted'}]}));
    await assertFails(commit(owner,{...pending,revision:5,friends:[]}));
    assert.deepEqual((await assertSucceeds(getDocFromServer(doc(c(),acctView)))).data(),pending);
    assert.deepEqual((await db.doc(acctSource).get()).data(),pending);
    assert.equal((await db.doc('users/'+other).get()).exists,false);
    await assertFails(getDocFromServer(doc(owner,acctSource)));
  }finally{await local.cleanup();}
});
test('complete protected account projection retains actual relationships, task claims and week history under same UID',async()=>{
  await accountSeed(accountFixture());const a=await accountApply();
  assert.equal(a.view.friends[0].recipientUid,other);
  assert.equal(a.view.tasks[0].claimKey,claimKey);
  assert.equal(a.view.league[0].weeklyXp,20);
  assert.deepEqual((await db.doc(acctView).get()).data(),a.view);
  assert.equal((await accountApply()).replayed,true);
  assert.equal((await db.doc(base).get()).exists,false);
  // Candidate only: independent authenticated owner clients restore exact data.
  // This does NOT prove that these rules are published in the live lab.
  for(const c of [client(),client()]){
    assert.deepEqual((await assertSucceeds(getDocFromServer(doc(c,acctView)))).data(),a.view);
    await assertFails(getDocs(collection(c,base,'account')));
    await assertFails(getDocFromServer(doc(c,acctSource)));
    await assertFails(getDocFromServer(doc(c,base+'/accountHistory/1')));
    await assertFails(getDocFromServer(doc(c,'deda_lab_uid_authority/'+other+'/account/current')));
  }
  const unsigned=env.unauthenticatedContext().firestore();
  for(const c of [client(other),client(uid,'anonymous'),unsigned]){
    await assertFails(getDocFromServer(doc(c,acctView)));
  }
  for(const c of [client(),client(other),client(uid,'anonymous'),unsigned]){
    for(const path of [acctSource,acctView,base+'/accountHistory/1']){
      await assertFails(setDoc(doc(c,path),accountFixture()));
      await assertFails(deleteDoc(doc(c,path)));
    }
  }
});
test('missing/foreign/duplicate or unsupported account sources fail closed',async()=>{
  await assert.rejects(accountApply());
  for(const mutate of [v=>v.complete=false,v=>v.uid=other,v=>v.friends[0].members=[other,'alien-uid'],
    v=>v.tasks.push(v.tasks[0]),v=>v.tasks[0].dayId='2026-02-30',
    v=>v.league[0].weeklyXp=200,v=>v.league[0].claimedKeys=['unknown']]){
    const v=accountFixture();mutate(v);await accountSeed(v);await assert.rejects(accountApply());
    assert.equal((await db.doc(acctView).get()).exists,false);
  }
});
test('active premium ID requires matching accepted protected inventory grant',async()=>{
  const v=accountFixture();v.profile.activeId=identifier;v.profile.fixedColor='gold';
  await accountSeed(v);await assert.rejects(accountApply(),{code:'account-active-id-unproven'});
  const inv=fixture();await seed(inv);await apply();await assert.rejects(accountApply(),{code:'account-active-id-unproven'});
  inv.revision=2;inv.idGifts[0].acceptance={uid,identifier,group:'001',receivedMs:ms+1};
  await seed(inv);await apply();assert.equal((await accountApply()).view.profile.activeId,identifier);
});
test('task claim history and weekly history cannot regress or reassign original ID',async()=>{
  await accountSeed(accountFixture());await accountApply();
  for(const mutate of [v=>{v.tasks=[];v.league=[];},v=>v.league=[],
    v=>{v.tasks[0].claimedMs=null;v.league=[];},
    v=>{v.profile.originalId='@DEDA-OTHER1';v.profile.activeId=v.profile.originalId;v.friends=[];}]){
    const v=accountFixture(2);mutate(v);await accountSeed(v);await assert.rejects(accountApply());
    assert.equal((await db.doc(acctView).get()).data().revision,1);
  }
});

test('separate exact live account candidate only permits atomic fixed synthetic snapshot',async()=>{
  const {generateAccount}=require('./uid-spark-fixture-rules.cjs');
  const {buildAccount,build}=require('./uid-trusted-fixture.cjs');
  const {writeBatch}=require('firebase/firestore');
  const local=await initializeTestEnvironment({projectId,firestore:{rules:generateAccount(readFileSync('firestore.rules','utf8'))}});
  try{
    await local.clearFirestore();
    const owner=local.authenticatedContext(uid,{firebase:{sign_in_provider:'password'}}).firestore();
    const foreign=local.authenticatedContext(other,{firebase:{sign_in_provider:'password'}}).firestore();
    const docs=buildAccount();
    const save=(db,rows)=>{const batch=writeBatch(db);for(const [p,v] of Object.entries(rows))batch.set(doc(db,p),v);return batch.commit();};
    await assertFails(save(owner,{[acctView]:docs[acctView]}));
    const bad=structuredClone(docs);bad[acctView].league[0].weeklyXp=200;
    await assertFails(save(owner,bad));await assertFails(save(foreign,docs));
    await assertFails(save(owner,build()));
    await assertSucceeds(save(owner,docs));
    const second=local.authenticatedContext(uid,{firebase:{sign_in_provider:'password'}}).firestore();
    assert.deepEqual((await assertSucceeds(getDocFromServer(doc(second,acctView)))).data(),docs[acctView]);
    await assertFails(save(owner,docs));
    await assertFails(deleteDoc(doc(owner,acctView)));
    await assertFails(getDocFromServer(doc(owner,acctSource)));
    await assertFails(getDocFromServer(doc(owner,base+'/accountHistory/1')));
    await assertFails(getDocFromServer(doc(foreign,acctView)));
  }finally{await local.cleanup();}
});

test('exact account candidate preserves locked progress and inventory and contains no update/delete grant',()=>{
  const {generateAccount}=require('./uid-spark-fixture-rules.cjs');
  const original=require('node:fs').readFileSync('firestore.rules','utf8');
  const rules=generateAccount(original);
  const start=original.indexOf('      match /account/current');
  assert.ok(start>0);assert.equal(rules.slice(0,start),original.slice(0,start));
  assert.equal((rules.match(/allow create: if owner\(uid\) && request.resource.data ==/g)||[]).length,3);
  assert.equal((rules.slice(start).match(/allow list, update, delete: if false;/g)||[]).length,3);
  assert.ok(!rules.includes('DEDA_STAGE03_SYNTHETIC_ONLY'));
  require('node:fs').writeFileSync('account-fixed-candidate.rules',rules);
});

 
// Legacy-shaped synthetic records only. No production read or wallet mutation
// by readWalletEvidence; the pinned lab UID is the only account key.
const walletGiftPath='deda_diamond_gift_balances/'+original;
const walletPersonalPath='deda_gm_personal_diamond_wallets/'+uid;
const walletAdminPath='admins/'+uid, walletAccessPath='admin_entry_access/'+uid;
const walletRoutePath='deda_share_ids/'+original;
async function seedWalletEvidence(){
  const {build,buildAccount}=require('./uid-trusted-fixture.cjs');
  const docs={...build(),...buildAccount()};
  // The fixture's earned balance is already net of its verified frame debit.
  for(const p of [base,view,acctView])await db.doc(p).set(docs[p]);
  const rows={
    ['users/'+uid]:{accountKey:uid,sharePersonalId:original},
    ['deda_sessions/'+uid]:{accountKey:uid,uid},
    [walletRoutePath]:{publicId:original,ownerUid:uid,active:true,kind:'personal'},
    [walletGiftPath]:{publicId:original,balance:70},
  };
  for(const [p,v] of Object.entries(rows))await db.doc(p).set(v);
  return rows;
}
const readWallet=()=>readWalletEvidence({store,uid});
async function seedWalletManager(){
  await db.doc(walletAdminPath).set({role:'general_manager',active:true,status:'active'});
  await db.doc(walletAccessPath).set({accountKey:uid,active:true,status:'active',
    accessType:'general_manager_gateway',allowedRole:'general_manager'});
  await db.doc(walletPersonalPath).set({accountKey:uid,balance:1000000});
}
test('04/01 wallet reads residuals from original-shaped records, not gift receipts or admin gifting pool',async()=>{
  await seedWalletEvidence();
  const oldProgress=(await db.doc(base).get()).data(),oldInventory=await read();
  const result=await readWallet();
  assert.deepEqual(result,{format:1,uid,complete:true,sourceKind:'synthetic-lab-wallet-v1',
    progressVersion:4,inventoryRevision:1,accountRevision:1,originalId:original,
    giftResidual:70,managerPersonal:0,hasManagerPersonal:false});
  assert.equal(oldProgress.balances.earnedDiamonds+result.giftResidual,270);
  await db.doc(walletGiftPath).update({balance:0});
  assert.equal((await readWallet()).giftResidual,0);
  await seedWalletManager();
  const manager=await readWallet();
  assert.equal(manager.hasManagerPersonal,true);assert.equal(manager.managerPersonal,1000000);
  assert.equal(oldProgress.balances.earnedDiamonds+manager.giftResidual+manager.managerPersonal,1000200);
  assert.deepEqual((await db.doc(base).get()).data(),oldProgress);
  assert.deepEqual(await read(),oldInventory);
  assert.equal((await db.doc(walletPersonalPath).get()).data().balance,1000000);
  assert.equal((await db.doc(walletGiftPath).get()).data().balance,0);
});
test('04/01 missing gift, wrong route, foreign UID and inconsistent manager proof fail closed',async()=>{
  await seedWalletEvidence();
  await db.doc(walletGiftPath).delete();
  await assert.rejects(readWallet(),{code:'wallet-gift-source-unproven'});
  await db.doc(walletGiftPath).set({publicId:original,balance:70,ownerUid:other});
  await assert.rejects(readWallet(),{code:'wallet-gift-source-unproven'});
  await db.doc(walletGiftPath).set({publicId:original,balance:70});
  await db.doc(walletRoutePath).update({ownerUid:other});
  await assert.rejects(readWallet(),{code:'wallet-owner-unproven'});
  await db.doc(walletRoutePath).update({ownerUid:uid});
  await assert.rejects(readWalletEvidence({store,uid:other}),{code:'invalid-account'});
  await db.doc(walletPersonalPath).set({accountKey:uid,balance:1000000});
  await assert.rejects(readWallet(),{code:'wallet-role-unproven'});
  await seedWalletManager();
  await db.doc(walletPersonalPath).delete();
  await assert.rejects(readWallet(),{code:'wallet-manager-source-unproven'});
  await db.doc(walletPersonalPath).set({accountKey:uid,balance:9007199254740990});
  await assert.rejects(readWallet(),{code:'wallet-overflow'});
  await db.doc(walletPersonalPath).set({accountKey:other,balance:1});
  await assert.rejects(readWallet(),{code:'wallet-manager-source-unproven'});
  await assert.rejects(readWalletEvidence({store:{db:{projectId:'not-demo'}},uid}),{code:'wallet-emulator-only'});
});

 
test('04/01 static wallet projection read by same UID only, all client writes denied',async()=>{
  await seedWalletEvidence();
  const proof=await readWallet();
  const wallet=base+'/wallet/current';
  const originalRules=readFileSync('firestore.rules','utf8');
  const anchor='      match /account/current {';
  assert.equal(originalRules.split(anchor).length,2);
  // Temporary emulator rules only. Never export, generate a live candidate
  // from this test, or grant writes to the client.
  const candidate=generateWalletRead(originalRules);
  const local=await initializeTestEnvironment({projectId,firestore:{rules:candidate}});
  try{
    const c=(id=uid,provider='password')=>local.authenticatedContext(id,{firebase:{sign_in_provider:provider}}).firestore();
    await local.withSecurityRulesDisabled(ctx=>setDoc(doc(ctx.firestore(),wallet),proof));
    for(const owner of [c(),c()]){
      assert.deepEqual((await assertSucceeds(getDocFromServer(doc(owner,wallet)))).data(),proof);
      await assertFails(setDoc(doc(owner,wallet),{...proof,giftResidual:99999}));
      await assertFails(deleteDoc(doc(owner,wallet)));
      await assertFails(getDocs(collection(owner,base,'wallet')));
      await assertFails(setDoc(doc(owner,base+'/wallet/other'),proof));
      await assertFails(getDocFromServer(doc(owner,walletGiftPath)));
      await assertFails(getDocFromServer(doc(owner,walletPersonalPath)));
    }
    for(const denied of [c(other),c(uid,'anonymous'),local.unauthenticatedContext().firestore()]){
      await assertFails(getDocFromServer(doc(denied,wallet)));
      await assertFails(setDoc(doc(denied,wallet),proof));
    }
    assert.deepEqual((await db.doc(wallet).get()).data(),proof);
    await db.doc('deda_sessions/'+uid).update({accountKey:other});
    await assertFails(getDocFromServer(doc(c(),wallet)));
    await db.doc('deda_sessions/'+uid).update({accountKey:uid});
    await db.doc('users/'+uid).update({sharePersonalId:'@DEDA-QA9999'});
    await assertFails(getDocFromServer(doc(c(),wallet)));
    await db.doc('users/'+uid).update({sharePersonalId:original});
    await db.doc(walletGiftPath).update({balance:20});
    await assertFails(getDocFromServer(doc(c(),wallet)));
    const fresh=await readWallet();
    assert.equal(fresh.giftResidual,20);
    await local.withSecurityRulesDisabled(ctx=>setDoc(doc(ctx.firestore(),wallet),fresh));
    assert.deepEqual((await assertSucceeds(getDocFromServer(doc(c(),wallet)))).data(),fresh);
    await db.doc(acctView).update({revision:2});
    await assertFails(getDocFromServer(doc(c(),wallet)));
    await db.doc(acctView).update({revision:1});
    await seedWalletManager();
    await assertFails(getDocFromServer(doc(c(),wallet)));
    const manager=await readWallet();
    await local.withSecurityRulesDisabled(ctx=>setDoc(doc(ctx.firestore(),wallet),manager));
    assert.deepEqual((await assertSucceeds(getDocFromServer(doc(c(),wallet)))).data(),manager);
    await db.doc(walletPersonalPath).update({balance:50});
    await assertFails(getDocFromServer(doc(c(),wallet)));
    // No publication or live writer: remove only the test fixture.
    await local.withSecurityRulesDisabled(ctx=>deleteDoc(doc(ctx.firestore(),wallet)));
  }finally{await local.cleanup();}
});


test('04/01 trusted wallet refresh writes only derived projection and is idempotent',async()=>{
  await seedWalletEvidence();
  const wallet=base+'/wallet/current', before=(await db.doc(base).get()).data();
  const first=await refreshWallet({store,uid});
  assert.equal(first.replayed,false);assert.equal(first.view.giftResidual,70);
  assert.equal((await refreshWallet({store,uid})).replayed,true);
  await db.doc(walletGiftPath).update({balance:15});
  const second=await refreshWallet({store,uid});
  assert.equal(second.view.giftResidual,15);
  assert.deepEqual((await db.doc(wallet).get()).data(),second.view);
  await db.doc(walletGiftPath).delete();
  await assert.rejects(refreshWallet({store,uid}),{code:'wallet-gift-source-unproven'});
  assert.deepEqual((await db.doc(wallet).get()).data(),second.view);
  assert.deepEqual((await db.doc(base).get()).data(),before);
  await assertFails(setDoc(doc(client(),wallet),{...second.view,giftResidual:1000000}));
});
test('04/01 use received ID atomically in existing account and public directory; return original; retain ownership',async()=>{
  await seedWalletEvidence();
  const {buildAccount}=require('./uid-trusted-fixture.cjs');
  for(const [path,row] of Object.entries(buildAccount()))await db.doc(path).set(row);
  const inv=require('./uid-trusted-fixture.cjs').build()[view];
  await seed(inv);
  await db.doc(base+'/inventoryHistory/1').set(inv);
  const active='deda_stage71_active_identifier/'+original,pub='deda_public_active_aliases/'+original;
  const aliasPath='deda_public_alias_routes/'+identifier;
  const registry='deda_stage71_granted_registry/'+identifier;
  const receipt='deda_stage74_id_gift_receipts/'+identifier;
  await db.doc(active).set({originalId:original,activeId:original,updatedAt:FieldValue.serverTimestamp()});
  await db.doc(pub).set({originalId:original,activeId:original,baseColor:null,updatedAt:FieldValue.serverTimestamp()});
  const use=(id,rev)=>activateOwnedId({store,uid,identifier:id,expectedRevision:rev});
  await assert.rejects(use(identifier,1),{code:'active-id-ownership-unproven'});
  inv.revision=2;inv.idGifts[0].acceptance={uid,identifier,group:'001',receivedMs:ms+1};
  await seed(inv);await apply();
  await db.doc(registry).set({identifier,recipientOriginalId:original,group:'001',baseColor:'gold',kind:'gifted'});
  const {Timestamp}=require('firebase-admin/firestore');
  await db.doc(receipt).set({identifier,originalId:original,group:'001',receivedAt:Timestamp.fromMillis(ms+1)});
  await db.doc(aliasPath).set({aliasId:identifier,originalId:peerId,baseColor:'gold'});
  await assert.rejects(use(identifier,1),{code:'active-id-ownership-unproven'});
  await db.doc(aliasPath).delete();
  const old=(await db.doc(acctView).get()).data(),before=(await db.doc(base).get()).data();
  const owned=await read();
  const switched=await use(identifier,1);
  assert.equal(switched.view.profile.activeId,identifier);
  assert.equal(switched.view.profile.fixedColor,'gold');
  assert.deepEqual(switched.view,{...old,revision:2,profile:{...old.profile,activeId:identifier,fixedColor:'gold'}});
  for(const p of [acctSource,acctView,base+'/accountHistory/2'])
    assert.deepEqual((await db.doc(p).get()).data(),switched.view);
  assert.equal((await db.doc(active).get()).data().activeId,identifier);
  assert.equal((await db.doc(pub).get()).data().activeId,identifier);
  assert.equal((await db.doc(aliasPath).get()).data().originalId,original);
  await assert.rejects(use(original,1),{code:'active-id-revision-conflict'});
  assert.equal((await use(identifier,2)).replayed,true);
  const returned=await use(original,2);
  assert.equal(returned.view.profile.activeId,original);
  assert.equal(returned.view.profile.fixedColor,null);
  assert.equal((await db.doc(pub).get()).data().activeId,original);
  assert.equal((await db.doc(aliasPath).get()).data().originalId,original);
  assert.deepEqual(await read(),owned);
  assert.deepEqual((await db.doc(base).get()).data(),before);
  await assertFails(setDoc(doc(client(),acctView),{...returned.view,revision:4}));
});
test('04/01 original five point stages use one ledger, reserve/return once and terminal spend stays spent',async()=>{
  const core=require('./reconcile-core.cjs');
  const {reconcileLabReceipt}=require('./reconcile-store.cjs');
  const {build}=require('./uid-trusted-fixture.cjs');
  const docs=build();
  await db.doc(base).set(docs[base]);
  const operate=(threshold,action)=>pointTier({store,uid,threshold,action});
  await assert.rejects(operate(5000,'reserve'),{code:'insufficient-points'});
  await assert.rejects(operate(5000,'claim'),{code:'point-tier-not-reserved'});
  // The existing trusted receipt worker supplies synthetic earned points.
  const receiptId='stage04_synthetic_points_0001';
  const award=core.parseReceipt({format:1,accountKey:uid,source:'task-claim-v1',
    sourceId:'stage04-synthetic-earned-points',kind:'award',
    delta:{points:25000,coins:0,xp:0,earnedDiamonds:0}},uid,'lab-uid');
  await db.doc(base+'/receipts/'+receiptId).set(award);
  await reconcileLabReceipt({store,accountKey:uid,receiptId});
  const before=(await db.doc(base).get()).data();
  await assert.rejects(operate(10000,'reserve'),{code:'point-tier-previous-unclaimed'});
  for(const threshold of [5000,10000,15000,20000,25000]){
    const initial=(await db.doc(base).get()).data();
    const reserved=await Promise.all([operate(threshold,'reserve'),operate(threshold,'reserve')]);
    assert.equal(reserved.filter(x=>x.replayed).length,1);
    assert.equal(reserved[0].state.balances.points,initial.balances.points-threshold);
    if(threshold===25000){
      await assert.rejects(operate(threshold,'claim'),{code:'point-tier-ineligible'});
    }else{
      const claimed=await Promise.all([operate(threshold,'claim'),operate(threshold,'claim')]);
      assert.equal(claimed.filter(x=>x.replayed).length,1);
      assert.equal(claimed[0].state.balances.points,initial.balances.points+threshold/100);
    }
  }
  const final=(await db.doc(base).get()).data();
  assert.equal(final.balances.points,before.balances.points+500-25000);
  for(const unit of ['coins','xp','earnedDiamonds'])assert.equal(final.balances[unit],before.balances[unit]);
  assert.equal((await operate(5000,'claim')).state.balances.points,final.balances.points);
  assert.equal((await db.collection(base+'/events').get()).size,10);
  await assertFails(setDoc(doc(client(),base),{...final,balances:{...final.balances,points:999999}}));
});
