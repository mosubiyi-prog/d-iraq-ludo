'use strict';
// Fixed synthetic lab fixture. No input from a phone, no real reward issuer.
const {isDeepStrictEqual:equal}=require('node:util');
const core=require('./reconcile-core.cjs');
const {parse,parseAccount}=require('./uid-ownership-projection.cjs');
const uid=core.LAB_UID, project='deda-qa-uid-lab-20261108';
const base='deda_lab_uid_authority/'+uid;
const zero=()=>({points:0,coins:0,xp:0,earnedDiamonds:0});
const receipt=(source,sourceId,kind,delta)=>core.parseReceipt({format:1,accountKey:uid,source,sourceId,kind,delta},uid,'lab-uid');
function build(){
  const docs={};
  const events=[
    ['stage03_synthetic_bootstrap_01',receipt('account-bootstrap-v1','stage03-synthetic-new-lab','baseline',zero())],
    ['stage03_synthetic_task_000001',receipt('task-claim-v1','stage03-synthetic-task-01','award',{points:5,coins:10,xp:20,earnedDiamonds:0})],
    ['stage03_synthetic_ad_00000001',receipt('rewarded-ad-v1','stage03-synthetic-ad-01','award',{...zero(),earnedDiamonds:1200})],
    ['stage03_synthetic_frame_00001',receipt('cosmetic-debit-v1','stage03-synthetic-frame-03','spend',{...zero(),earnedDiamonds:-1000})],
  ];
  let state=null;
  for(const [id,r] of events){
    const k=core.eventKey(r);
    state=core.applyEvent(state,r,'lab-uid');
    docs[base+'/receipts/'+id]=r;
    docs[base+'/events/'+k]={format:1,accountKey:uid,eventKey:k,receipt:r,receiptId:id,
      appliedVersion:state.version,afterBalances:state.balances};
  }
  docs[base]=state;
  const ms=Date.UTC(2026,10,7,3),identifier='@DEDA-QAFIXTURE',weekId='2026-10-31';
  const inventory=parse({format:1,uid,revision:1,complete:true,
    frames:[{frameId:'FRAME_03',receipt:{uid,frameId:'FRAME_03',kind:'lab_frame',cost:1000,createdMs:ms},
      ownership:{uid,frameId:'FRAME_03',receiptId:uid+'_FRAME_03',createdMs:ms}}],
    idGifts:[{identifier,grant:{uid,identifier,group:'001',baseColor:'gold',kind:'gifted',grantedMs:ms},acceptance:null}],
    diamondGifts:[{giftId:'deda-weekly-'+weekId+'-'+uid,uid,sourceType:'weekly_league',weekId,
      amount:250,status:'pending',createdMs:ms,receivedMs:null}]},uid);
  docs[base+'/inventorySources/current']=inventory;
  docs[base+'/inventory/current']=inventory;
  docs[base+'/inventoryHistory/1']=inventory;
  return docs;
}
function checkStored(path,data,expected){
  if(path.startsWith(base+'/events/')){
    if(!data||!data.createdAt||typeof data.createdAt.toMillis!=='function')return false;
    const {createdAt,...body}=data;return equal(body,expected);
  }
  return equal(data,expected);
}
async function apply({store,projectId}){
  if(projectId!==project)throw Error('wrong-lab-project');
  const docs=build(),paths=Object.keys(docs);
  return store.runTransaction(async tx=>{
    const existing=await Promise.all(paths.map(path=>tx.get(path)));
    if(existing.some(v=>v!==null)){
      if(!existing.every((v,i)=>v!==null&&checkStored(paths[i],v,docs[paths[i]])))throw Error('unknown-or-partial-fixture-no-write');
      return {replayed:true,count:paths.length};
    }
    // Only fixed synthetic data and immutable matching receipt markers.
    for(const path of paths){
      const data=docs[path];
      tx.set(path,path.startsWith(base+'/events/')?{...data,createdAt:store.serverTimestamp()}:data);
    }
    return {replayed:false,count:paths.length};
  });
}
// Separate fixed, NON-FINANCIAL synthetic account snapshot for the existing
// pinned lab UID. Do not alter build() or reopen the earlier 12-doc fixture.
function buildAccount(){
  const peer='synthetic-peer-001',original='@DEDA-QA1234',peerId='@DEDA-QA5678';
  const dayId='2026-11-01',taskId='open_map',claimKey=dayId+'|'+taskId;
  const completedMs=Date.UTC(2026,10,1,10);
  const row=parseAccount({format:1,uid,revision:1,complete:true,
    profile:{displayName:'Synthetic QA',originalId:original,activeId:original,fixedColor:null},
    friends:[{pairKey:[uid,peer].sort().join('__'),members:[uid,peer],requesterUid:uid,recipientUid:peer,
      requesterPublicId:original,recipientPublicId:peerId,requesterName:'Synthetic QA',
      recipientName:'Synthetic peer',status:'accepted'}],
    tasks:[{claimKey,dayId,taskId,completedMs,claimedMs:completedMs+1}],
    league:[{weekId:'2026-10-31',claimedKeys:[claimKey],completedTasks:1,weeklyXp:20}]},uid);
  return {[base+'/accountSources/current']:row,[base+'/account/current']:row,[base+'/accountHistory/1']:row};
}
module.exports={build,apply,checkStored,project,uid,base,buildAccount};
