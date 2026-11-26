'use strict';
const {test,before,after,beforeEach}=require('node:test');
const assert=require('node:assert/strict');
const {readFileSync}=require('node:fs');
const {initializeTestEnvironment,assertSucceeds,assertFails}=require('@firebase/rules-unit-testing');
const {doc,setDoc,deleteDoc,getDocFromServer,writeBatch,serverTimestamp,Timestamp,runTransaction,updateDoc}=require('firebase/firestore');
const {build,buildAccount,base,uid}=require('../stage03/uid-trusted-fixture.cjs');
const {generateProfileName,generateProfileActions,syntheticPrizeCode}=require('./profile-name-candidate.cjs');
const projectId='demo-deda-stage03-uid';
const account=base+'/account/current',source=base+'/accountSources/current',history=base+'/accountHistory/';
const original=buildAccount()[account], rights=build();
let env;
const client=(id=uid,provider='password')=>env.authenticatedContext(id,{firebase:{sign_in_provider:provider}}).firestore();
const renamed=(old,name='Synthetic Name Two')=>({...structuredClone(old),revision:old.revision+1,profile:{...old.profile,displayName:name}});
const write=(db,next,paths=[account,source,history+next.revision])=>{
  const b=writeBatch(db);
  for(const path of paths)b.set(doc(db,path),next);
  return b.commit();
};
const read=async(path)=>{
  let value;
  await env.withSecurityRulesDisabled(async ctx=>{
    value=(await getDocFromServer(doc(ctx.firestore(),path))).data();
  });
  return value;
};
before(async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^127\.0\.0\.1:[0-9]+$/);
  assert.equal(process.env.GCLOUD_PROJECT,projectId);
  env=await initializeTestEnvironment({projectId,firestore:{rules:generateProfileActions(readFileSync('original.rules','utf8'))}});
});
after(async()=>{if(env)await env.cleanup()});
beforeEach(async()=>{
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore(),batch=writeBatch(db);
    for(const [path,data] of Object.entries({...rights,...buildAccount()}))batch.set(doc(db,path),data);
    await batch.commit();
  });
});
test('owner name only updates same UID atomically, keeps two revisions and every protected right',async()=>{
  const second=renamed(original,'اسم تجريبي جديد');
  await assertSucceeds(write(client(),second));
  assert.deepEqual((await assertSucceeds(getDocFromServer(doc(client(),account)))).data(),second);
  assert.deepEqual(await read(source),second);
  assert.deepEqual(await read(history+'1'),original);
  assert.deepEqual(await read(history+'2'),second);
  const third=renamed(second,'Synthetic Name Three');
  await assertSucceeds(write(client(),third));
  assert.deepEqual(await read(history+'2'),second);
  assert.deepEqual(await read(history+'3'),third);
  for(const [path,data] of Object.entries(rights))assert.deepEqual(await read(path),data);
  await assertFails(write(client(),second)); // stale client cannot revert
  await assertFails(getDocFromServer(doc(client(),source)));
  await assertFails(getDocFromServer(doc(client(),history+'3')));
});
test('partial, foreign, anonymous, no-op, invalid name and unrelated protected changes are denied',async()=>{
  const c=client(),next=renamed(original);
  for(const paths of [[account],[source],[history+'2'],[account,source],[account,history+'2']])
    await assertFails(write(c,next,paths));
  for(const db of [client('foreign'),client(uid,'anonymous'),env.unauthenticatedContext().firestore()])
    await assertFails(write(db,next));
  for(const name of ['x','  test','test ','<test>','bad\nname','a'.repeat(97),original.profile.displayName])
    await assertFails(write(c,renamed(original,name)));
  const changes=[
    x=>x.uid='foreign',x=>x.profile.originalId='@DEDA-QA9999',
    x=>x.profile.activeId='@DEDA-QA9999',x=>x.profile.fixedColor='gold',
    x=>x.profile.role='admin',x=>x.tasks=[],x=>x.friends=[],x=>x.league=[],
    x=>x.revision=5,x=>x.complete=false,x=>x.wallet=1000000,
  ];
  for(const mutate of changes){const x=renamed(original);mutate(x);await assertFails(write(c,x));}
  await assertFails(write(c,next,[account,source,history+'99']));
  await assertFails(deleteDoc(doc(c,account)));
  await assertFails(setDoc(doc(c,history+'1'),next));
  await assertFails(setDoc(doc(c,base),{...rights[base],balances:{...rights[base].balances,earnedDiamonds:1000000}}));
  assert.deepEqual(await read(account),original);
  assert.deepEqual(await read(source),original);
  assert.equal(await read(history+'2'),undefined);
});

test('competing editors cannot overwrite the same revision or lose protected rights',async()=>{
  const first=renamed(original,'Synthetic Editor One');
  const second=renamed(original,'Synthetic Editor Two');
  const results=await Promise.allSettled([write(client(),first),write(client(),second)]);
  assert.equal(results.filter(x=>x.status==='fulfilled').length,1);
  assert.equal(results.filter(x=>x.status==='rejected').length,1);
  const winner=results[0].status==='fulfilled'?first:second;
  assert.deepEqual(await read(account),winner);
  assert.deepEqual(await read(source),winner);
  assert.deepEqual(await read(history+'1'),original);
  assert.deepEqual(await read(history+'2'),winner);
  assert.equal(await read(history+'3'),undefined);
  for(const [path,data] of Object.entries(rights))assert.deepEqual(await read(path),data);
});
test('rename stops on missing or inconsistent provenance and mismatched atomic values',async()=>{
  const next=renamed(original), different=renamed(original,'Different Synthetic Name');
  const seed=async(path,value)=>env.withSecurityRulesDisabled(async ctx=>{
    const ref=doc(ctx.firestore(),path);
    if(value===undefined)await deleteDoc(ref);else await setDoc(ref,value);
  });
  for(const path of [source,history+'1']){
    for(const value of [undefined,{...structuredClone(original),profile:{...original.profile,displayName:'Inconsistent Source'}}]){
      await seed(path,value);
      await assertFails(write(client(),next));
      assert.deepEqual(await read(account),original);
      assert.equal(await read(history+'2'),undefined);
      assert.deepEqual(await read(path),value);
      await seed(path,original);
    }
  }
  await seed(history+'2',different);
  await assertFails(write(client(),next));
  assert.deepEqual(await read(history+'2'),different);
  await seed(history+'2',undefined);
  const db=client(),batch=writeBatch(db);
  batch.set(doc(db,account),next);
  batch.set(doc(db,source),different);
  batch.set(doc(db,history+'2'),next);
  await assertFails(batch.commit());
  assert.deepEqual(await read(account),original);
  assert.deepEqual(await read(source),original);
  assert.equal(await read(history+'2'),undefined);
  for(const [path,data] of Object.entries(rights))assert.deepEqual(await read(path),data);
});


test('Spark candidate: fixed synthetic point reserve and return are atomic, replay and mint denied',async()=>{
  const core=require('../stage03/reconcile-core.cjs');
  const {pointReceipt}=require('../stage03/uid-ownership-projection.cjs');
  const award=core.parseReceipt({format:1,accountKey:uid,source:'task-claim-v1',
    sourceId:'stage04-synthetic-ui-earn',kind:'award',delta:{points:25000,coins:0,xp:0,earnedDiamonds:0}},uid,'lab-uid');
  const initial=core.applyEvent(rights[base],award,'lab-uid');
  await env.withSecurityRulesDisabled(ctx=>setDoc(doc(ctx.firestore(),base),initial));
  let state=initial;
  // Use the existing trusted emulator refresh, never the authenticated client.
  // The original account and progress revisions must both stay current.
  const {refreshWallet}=require('../stage03/uid-ownership-projection.cjs');
  const wallet=base+'/wallet/current',o=original.profile.originalId;
  const seedWallet=async()=>env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore(),b=writeBatch(db);
    b.set(doc(db,'users/'+uid),{accountKey:uid,sharePersonalId:o});
    b.set(doc(db,'deda_sessions/'+uid),{accountKey:uid,uid});
    b.set(doc(db,'deda_share_ids/'+o),{ownerUid:uid,publicId:o,kind:'personal',active:true});
    b.set(doc(db,'deda_diamond_gift_balances/'+o),{publicId:o,balance:70});
    await b.commit();
  });
  const refresh=async()=>{
    let result;
    await env.withSecurityRulesDisabled(async ctx=>{
      const db=ctx.firestore();
      const store={db:{projectId},runTransaction:fn=>runTransaction(db,tx=>fn({
        get:async path=>{const snap=await tx.get(doc(db,path));return snap.exists()?snap.data():null;},
        set:(path,value)=>tx.set(doc(db,path),value),
      }))};
      result=await refreshWallet({store,uid});
    });
    return result.view;
  };
  const readWallet=()=>getDocFromServer(doc(client(),wallet));
  await seedWallet();
  // Direct read path needs no trusted refresh and grants no balance writes.
  const giftPath='deda_diamond_gift_balances/'+o,personalPath='deda_gm_personal_diamond_wallets/'+uid;
  const readSource=(c,p)=>getDocFromServer(doc(c,p));
  assert.equal((await assertSucceeds(readSource(client(),giftPath))).data().balance,70);
  assert.equal((await assertSucceeds(readSource(client(),personalPath))).exists(),false);
  await assertFails(readSource(client('foreign'),giftPath));
  await assertFails(readSource(client('foreign'),personalPath));
  await assertFails(readSource(client(uid,'anonymous'),giftPath));
  await assertFails(setDoc(doc(client(),giftPath),{publicId:o,balance:1000000}));
  await assertFails(setDoc(doc(client(),personalPath),{accountKey:uid,balance:1000000}));
  const trustedSet=(p,d)=>env.withSecurityRulesDisabled(ctx=>setDoc(doc(ctx.firestore(),p),d));
  const trustedDelete=p=>env.withSecurityRulesDisabled(ctx=>deleteDoc(doc(ctx.firestore(),p)));
  await trustedSet(giftPath,{publicId:o,balance:15});
  assert.equal((await assertSucceeds(readSource(client(),giftPath))).data().balance,15);
  await trustedSet(giftPath,{publicId:o,balance:70,ownerUid:'foreign'});
  await assertFails(readSource(client(),giftPath));
  await trustedSet(giftPath,{publicId:o,balance:70});
  const ap='admins/'+uid,gp='admin_entry_access/'+uid;
  await trustedSet(ap,{role:'general_manager',active:true,status:'active'});
  await assertFails(readSource(client(),personalPath));
  await trustedSet(gp,{accountKey:uid,active:true,status:'active',accessType:'general_manager_gateway',allowedRole:'general_manager'});
  await trustedSet(personalPath,{accountKey:uid,balance:1000000});
  assert.equal((await assertSucceeds(readSource(client(),personalPath))).data().balance,1000000);
  await trustedSet(personalPath,{accountKey:uid,balance:25});
  assert.equal((await assertSucceeds(readSource(client(),personalPath))).data().balance,25);
  await assertFails(readSource(client(),ap));
  await assertFails(readSource(client(),gp));
  for(const p of [ap,gp,personalPath])await trustedDelete(p);
  let proof=await refresh();
  assert.deepEqual((await assertSucceeds(readWallet())).data(),proof);
  await assertFails(setDoc(doc(client(),wallet),{...proof,giftResidual:999999}));
  await assertFails(getDocFromServer(doc(client('foreign'),wallet)));
  const second=renamed(original);
  await assertSucceeds(write(client(),second));
  await assertFails(readWallet());
  proof=await refresh();
  assert.equal(proof.accountRevision,second.revision);
  assert.deepEqual((await assertSucceeds(readWallet())).data(),proof);
  const attempt=(c,threshold,action,{delta=null,omit=null,old=state}={})=>{
    const r=pointReceipt(uid,threshold,action),k=core.eventKey(r);
    const next=core.applyEvent(old,r,'lab-uid');
    const actual=delta===null?next:{...next,balances:{...next.balances,points:next.balances.points+delta}};
    const batch=writeBatch(c);
    const rows={[base]:actual,[base+'/receipts/'+k]:r,[base+'/events/'+k]:{
      format:1,accountKey:uid,eventKey:k,receipt:r,receiptId:k,appliedVersion:actual.version,
      afterBalances:actual.balances,createdAt:serverTimestamp()}};
    for(const [p,row] of Object.entries(rows))if(!omit||!p.includes(omit))batch.set(doc(c,p),row);
    return {next,commit:batch.commit()};
  };
  const prizePath='prize_winner_requests/prize_v1_'+uid;
  const terminalKey=core.eventKey(pointReceipt(uid,25000,'reserve'));
  const rewardCode=syntheticPrizeCode(terminalKey);
  assert.match(rewardCode,/^[A-Z][0-9][a-f0-9]{14}$/);
  const prizeRow=points=>({ownerUid:uid,cycleId:'prize_v1',accountKey:uid,
    name:second.profile.displayName,phone:'',dedaId:second.profile.originalId,
    rewardCode,pointsAtCompletion:points,completedThresholds:[5000,10000,15000,20000,25000],
    finalReservedPoints:25000,status:'new',adminMessage:'',prizeDetails:'',userReply:'',
    createdAt:serverTimestamp(),updatedAt:serverTimestamp()});
  const request=(c,row,path=prizePath)=>setDoc(doc(c,path),row);
  await assertSucceeds(getDocFromServer(doc(client(),prizePath)));
  await assertFails(request(client(),prizeRow(505)));
  await assertFails(attempt(client(),10000,'reserve').commit);
  await assertFails(attempt(client(),5000,'claim').commit);
  await assertFails(attempt(client(),5000,'reserve',{delta:1}).commit);
  // A delta that matches a different valid tier cannot borrow its proof.
  await assertFails(attempt(client(),5000,'reserve',{delta:-5000}).commit);
  await assertFails(attempt(client(),5000,'reserve',{delta:10050}).commit);
  await assertFails(attempt(client(),5000,'reserve',{omit:'/events/'}).commit);
  await assertFails(attempt(client('foreign'),5000,'reserve').commit);
  for(const t of [5000,10000,15000,20000,25000]){
    await assertFails(request(client(),prizeRow(505)));
    const reserve=attempt(client(),t,'reserve');
    await assertSucceeds(reserve.commit);state=reserve.next;
    await assertFails(readWallet());
    proof=await refresh();
    assert.equal(proof.progressVersion,state.version);
    assert.equal(proof.giftResidual,70);
    assert.deepEqual((await assertSucceeds(readWallet())).data(),proof);
    if(t!==25000){
      const claim=attempt(client(),t,'claim');
      await assertSucceeds(claim.commit);state=claim.next;
      await assertFails(readWallet());
      proof=await refresh();
      assert.equal(proof.progressVersion,state.version);
      assert.deepEqual((await assertSucceeds(readWallet())).data(),proof);
    }
    assert.deepEqual(await read(base),state);
  }
  assert.equal(state.balances.points,505);
  const row=prizeRow(state.balances.points);
  for(const override of [{rewardCode:'X000000000000000'},{phone:'fabricated-phone'},
    {name:'Not the account name'},{dedaId:'@DEDA-QA9999'},{status:'approved'},
    {pointsAtCompletion:506},{completedThresholds:[25000]},{ownerUid:'foreign'},
    {finalReservedPoints:0},{adminMessage:'approved'},{extra:true}]){
    await assertFails(request(client(),{...row,...override}));
  }
  await assertFails(request(client('foreign'),row));
  await assertFails(request(client(uid,'anonymous'),row));
  await assertFails(request(client(),row,prizePath+'-duplicate'));
  const firstKey=core.eventKey(pointReceipt(uid,5000,'reserve'));
  const firstPath=base+'/events/'+firstKey,firstEvent=await read(firstPath);
  await env.withSecurityRulesDisabled(ctx=>deleteDoc(doc(ctx.firestore(),firstPath)));
  await assertFails(request(client(),row));
  await env.withSecurityRulesDisabled(ctx=>setDoc(doc(ctx.firestore(),firstPath),firstEvent));
  const outcomes=await Promise.allSettled([request(client(),row),request(client(),row)]);
  assert.equal(outcomes.filter(x=>x.status==='fulfilled').length,1);
  const saved=(await assertSucceeds(getDocFromServer(doc(client(),prizePath)))).data();
  assert.equal(saved.rewardCode,rewardCode);assert.equal(saved.status,'new');
  assert.equal(saved.pointsAtCompletion,state.balances.points);
  assert.equal(saved.accountKey,uid);assert.equal(saved.phone,'');
  await assertFails(request(client(),row));
  await assertFails(deleteDoc(doc(client(),prizePath)));
  await assertFails(getDocFromServer(doc(client('foreign'),prizePath)));
  await assertFails(getDocFromServer(doc(client(uid,'anonymous'),prizePath)));
  assert.deepEqual(await read(prizePath),saved);
  const change=(c,d)=>updateDoc(doc(c,prizePath),{...d,updatedAt:serverTimestamp()});
  const reply={status:'reviewing',userReply:'Synthetic reply',userReplyAt:serverTimestamp()};
  const confirm={status:'delivered',winnerConfirmedAt:serverTimestamp(),deliveredAt:serverTimestamp()};
  await assertFails(change(client(),reply));
  await assertFails(change(client(),confirm));
  await assertFails(change(client(),{status:'prize_sent',prizeDetails:'Synthetic prize'}));
  // Trusted emulator context simulates the original administrative response;
  // no client has administrative write authority and no real prize is issued.
  await trustedSet(prizePath,{...saved,status:'needs_info',adminMessage:'Synthetic inquiry'});
  await assertFails(change(client('foreign'),reply));
  await assertFails(change(client(),{...reply,rewardCode:'X000000000000000'}));
  await assertFails(change(client(),{...reply,userReply:'x'.repeat(601)}));
  await assertSucceeds(change(client(),reply));
  await assertFails(change(client(),reply));
  const reviewed=await read(prizePath);
  assert.equal(reviewed.status,'reviewing');
  assert.equal(reviewed.userReply,'Synthetic reply');
  await trustedSet(prizePath,{...reviewed,status:'prize_sent',prizeDetails:'Synthetic test only'});
  await assertFails(change(client('foreign'),confirm));
  await assertFails(change(client(),{...confirm,pointsAtCompletion:99999}));
  await assertSucceeds(change(client(),confirm));
  await assertFails(change(client(),confirm));
  const delivered=await read(prizePath);
  assert.equal(delivered.status,'delivered');
  assert.equal(delivered.rewardCode,rewardCode);
  assert.equal(delivered.pointsAtCompletion,505);
  await assertFails(attempt(client(),5000,'claim').commit);
  await assertFails(setDoc(doc(client(),base),{...state,version:state.version+1,
    balances:{...state.balances,points:999999}}));
  assert.deepEqual(await read(base),state);
});

test('Spark candidate: only accepted fixed synthetic alias switches atomically, original stays reserved',async()=>{
  const o=original.profile.originalId,a='@DEDA-QAFIXTURE';
  const active='deda_stage71_active_identifier/'+o,pub='deda_public_active_aliases/'+o,
    alias='deda_public_alias_routes/'+a;
  const invPath=base+'/inventory/current',inv=structuredClone(rights[invPath]),g=inv.idGifts[0];
  const rec={identifier:a,originalId:o,group:g.grant.group,receivedAt:Timestamp.fromMillis(g.grant.grantedMs+1)};
  await env.withSecurityRulesDisabled(async ctx=>{
    const c=ctx.firestore(),b=writeBatch(c);
    b.set(doc(c,'deda_share_ids/'+o),{ownerUid:uid,publicId:o,kind:'personal',active:true});
    b.set(doc(c,active),{originalId:o,activeId:o,updatedAt:serverTimestamp()});
    b.set(doc(c,pub),{originalId:o,activeId:o,baseColor:null,updatedAt:serverTimestamp()});
    b.set(doc(c,'deda_stage71_granted_registry/'+a),{identifier:a,recipientOriginalId:o,group:g.grant.group,baseColor:'gold',kind:'gifted'});
    b.set(doc(c,'deda_stage74_id_gift_receipts/'+a),rec);
    await b.commit();
  });
  function use(c,old,id,omit=''){
    const p={...old.profile,activeId:id,fixedColor:id===o?null:'gold'};
    const next={...old,revision:old.revision+1,profile:p};
    const b=writeBatch(c);
    const rows={[account]:next,[source]:next,[history+next.revision]:next,
      [active]:{originalId:o,activeId:id,updatedAt:serverTimestamp()},
      [pub]:{originalId:o,activeId:id,baseColor:p.fixedColor,updatedAt:serverTimestamp()}};
    if(id!==o)rows[alias]={aliasId:id,originalId:o,baseColor:p.fixedColor,updatedAt:serverTimestamp()};
    for(const [path,row] of Object.entries(rows))if(path!==omit)b.set(doc(c,path),row);
    return {next,commit:b.commit()};
  }
  await assertFails(use(client(),original,a).commit);
  g.acceptance={uid,identifier:a,group:g.grant.group,receivedMs:g.grant.grantedMs+1};
  await env.withSecurityRulesDisabled(ctx=>setDoc(doc(ctx.firestore(),invPath),inv));
  await assertFails(use(client(),original,a,pub).commit);
  await assertFails(use(client('foreign'),original,a).commit);
  await env.withSecurityRulesDisabled(ctx=>setDoc(doc(ctx.firestore(),alias),{aliasId:a,originalId:'@DEDA-QA5678',baseColor:'gold'}));
  await assertFails(use(client(),original,a).commit);
  await env.withSecurityRulesDisabled(ctx=>deleteDoc(doc(ctx.firestore(),alias)));
  const second=use(client(),original,a);await assertSucceeds(second.commit);
  assert.deepEqual(await read(account),second.next);
  assert.equal((await read(pub)).activeId,a);
  const third=use(client(),second.next,o);await assertSucceeds(third.commit);
  assert.deepEqual(await read(account),third.next);
  assert.equal((await read(pub)).activeId,o);
  assert.equal((await read(alias)).originalId,o);
  assert.deepEqual(await read(invPath),inv);
  assert.deepEqual(await read(base),rights[base]);
});
