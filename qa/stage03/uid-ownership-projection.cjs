'use strict';
// Protected read projection only; no purchase, award, wallet or alias mutation.
// Source fixtures are synthetic and written only by a trusted emulator context.
const {isDeepStrictEqual:equal}=require('node:util');
const core=require('./reconcile-core.cjs');
const {LAB_UID,account,parseState}=core;
const {frames}=require('./purchase-frames.cjs');
const {weekStart}=require('./deda_weekly_direct_prize_plan.js');
const fail=code=>{throw Object.assign(Error(code),{code})};
const requireThat=(ok,code)=>{if(!ok)fail(code)};
function exact(v,keys){
  requireThat(v&&typeof v==='object'&&!Array.isArray(v)&&
    Object.keys(v).length===keys.length&&keys.every(k=>Object.hasOwn(v,k)),'ownership-schema');
}
const stamp=v=>Number.isSafeInteger(v)&&v>0;
const alias=v=>typeof v==='string'&&/^@DEDA-[A-Z0-9]{4,12}$/.test(v);
const key=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
function unique(rows,field,max,parse){
  requireThat(Array.isArray(rows)&&rows.length<=max,'ownership-source-incomplete');
  const seen=new Set();
  return rows.map(row=>{
    const p=parse(row);
    requireThat(!seen.has(p[field]),'duplicate-ownership-source');
    seen.add(p[field]);return p;
  }).sort((a,b)=>a[field]<b[field]?-1:a[field]>b[field]?1:0);
}
function parse(source,uid){
  account(uid,'lab-uid');
  exact(source,['format','uid','revision','complete','frames','idGifts','diamondGifts']);
  requireThat(source.format===1&&source.uid===uid&&source.complete===true&&
    Number.isSafeInteger(source.revision)&&source.revision>0,'ownership-source-incomplete');
  const frameRows=unique(source.frames,'frameId',frames.length,row=>{
    exact(row,['frameId','receipt','ownership']);
    const {frameId,receipt:r,ownership:o}=row;
    requireThat(frames.includes(frameId),'unknown-paid-frame');
    exact(r,['uid','frameId','kind','cost','createdMs']);
    exact(o,['uid','frameId','receiptId','createdMs']);
    requireThat(r.uid===uid&&o.uid===uid&&r.frameId===frameId&&o.frameId===frameId&&
      r.kind==='lab_frame'&&r.cost===1000&&o.receiptId===uid+'_'+frameId&&
      stamp(r.createdMs)&&r.createdMs===o.createdMs,'frame-proof-mismatch');
    return {frameId,receipt:{...r},ownership:{...o}};
  });
  const idGifts=unique(source.idGifts,'identifier',200,row=>{
    exact(row,['identifier','grant','acceptance']);
    const {identifier,grant:g,acceptance:a}=row;
    exact(g,['uid','identifier','group','baseColor','kind','grantedMs']);
    requireThat(alias(identifier)&&g.uid===uid&&g.identifier===identifier&&
      ['001','002'].includes(g.group)&&['gold','diamond','royal','pink'].includes(g.baseColor)&&
      g.kind==='gifted'&&stamp(g.grantedMs),'id-grant-mismatch');
    if(a!==null){
      exact(a,['uid','identifier','group','receivedMs']);
      requireThat(a.uid===uid&&a.identifier===identifier&&a.group===g.group&&
        stamp(a.receivedMs)&&a.receivedMs>=g.grantedMs,'id-acceptance-mismatch');
    }
    return {identifier,grant:{...g},acceptance:a===null?null:{...a}};
  });
  const diamondGifts=unique(source.diamondGifts,'giftId',200,row=>{
    exact(row,['giftId','uid','sourceType','weekId','amount','status','createdMs','receivedMs']);
    requireThat(key(row.giftId)&&row.uid===uid&&['admin','weekly_league'].includes(row.sourceType)&&
      Number.isSafeInteger(row.amount)&&row.amount>=1&&row.amount<=1000000&&
      stamp(row.createdMs)&&['pending','received'].includes(row.status)&&
      (row.status==='pending'?row.receivedMs===null:stamp(row.receivedMs)&&row.receivedMs>=row.createdMs),
      'diamond-gift-mismatch');
    if(row.sourceType==='weekly_league'){
      requireThat(row.giftId==='deda-weekly-'+row.weekId+'-'+uid&&
        row.createdMs>=weekStart(row.weekId)+7*24*60*60*1000,'weekly-gift-proof-mismatch');
    }else requireThat(row.weekId===null,'unexpected-week');
    return {...row};
  });
  // Historical grants are not active alias selection; received gifts are NOT balances.
  return {format:1,uid,revision:source.revision,complete:true,frames:frameRows,idGifts,diamondGifts};
}
function preserve(old,next){
  const retain=(rows,newRows,field,valid)=>{
    const lookup=new Map(newRows.map(r=>[r[field],r]));
    for(const row of rows)requireThat(lookup.has(row[field])&&valid(row,lookup.get(row[field])),'ownership-history-regression');
  };
  retain(old.frames,next.frames,'frameId',equal);
  retain(old.idGifts,next.idGifts,'identifier',(a,b)=>equal(a.grant,b.grant)&&
    (a.acceptance===null||equal(a.acceptance,b.acceptance)));
  retain(old.diamondGifts,next.diamondGifts,'giftId',(a,b)=>{
    const {status:as,receivedMs:ar,...ax}=a,{status:bs,receivedMs:br,...bx}=b;
    return equal(ax,bx)&&(as==='pending'||(bs==='received'&&ar===br));
  });
}
async function project({store,uid}){
  return projectRevision({store,uid,sourceName:'inventorySources',viewName:'inventory',
    historyName:'inventoryHistory',parseView:parse,preserveView:preserve});
}
async function projectRevision({store,uid,sourceName,viewName,historyName,parseView,preserveView,checkSource}){

  requireThat(/^127\.0\.0\.1:[0-9]+$/.test(process.env.FIRESTORE_EMULATOR_HOST||'')&&
    process.env.GCLOUD_PROJECT==='demo-deda-stage03-uid','ownership-emulator-only');
  account(uid,'lab-uid');
  const base='deda_lab_uid_authority/'+uid,view=base+'/'+viewName+'/current';
  return store.runTransaction(async tx=>{
    const raw=await tx.get(base+'/'+sourceName+'/current');
    requireThat(raw!==null,'ownership-source-missing');
    const next=parseView(raw,uid);
    if(checkSource)await checkSource(tx,base,next);
    const prevRaw=await tx.get(view);
    const old=prevRaw===null?null:parseView(prevRaw,uid);
    const history=base+'/'+historyName+'/'+String(next.revision);
    const receipt=await tx.get(history);
    if(old!==null&&next.revision===old.revision){
      requireThat(equal(next,old)&&equal(receipt,next),'ownership-revision-conflict');
      return {replayed:true,view:old};
    }
    requireThat(next.revision===(old?.revision??0)+1&&receipt===null,'ownership-revision-conflict');
    if(old!==null)preserveView(old,next);
    tx.set(view,next);tx.set(history,next);
    return {replayed:false,view:next};
  });
}
// Account continuity projection in the SAME protected UID tree.
// Synthetic, trusted emulator records only; never treats this as an issuer.
const taskIds=new Set(['share_personal_location','open_map','share_registered_place',
  'open_saved_place','open_received_place','review_added_place','traffic_skills','long_trip']);
const original=v=>typeof v==='string'&&/^@DEDA-[A-Z0-9]{6}$/.test(v);
const name=v=>typeof v==='string'&&v.trim()===v&&v.length>=1&&v.length<=96&&!/[<>\x00-\x1f]/.test(v);
const member=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{6,128}$/.test(v);
function realDay(v){
  if(typeof v!=='string'||!/^20\d{2}-\d{2}-\d{2}$/.test(v))return false;
  const ms=Date.parse(v+'T00:00:00Z');
  return Number.isFinite(ms)&&new Date(ms).toISOString().slice(0,10)===v;
}
function baghdadDay(ms){return new Date(ms+3*3600000).toISOString().slice(0,10)}
function parseAccount(raw,uid){
  account(uid,'lab-uid');
  exact(raw,['format','uid','revision','complete','profile','friends','tasks','league']);
  requireThat(raw.format===1&&raw.uid===uid&&raw.complete===true&&
    Number.isSafeInteger(raw.revision)&&raw.revision>0,'account-source-incomplete');
  const p=raw.profile;
  exact(p,['displayName','originalId','activeId','fixedColor']);
  requireThat(name(p.displayName)&&original(p.originalId)&&alias(p.activeId)&&
    (p.activeId===p.originalId?p.fixedColor===null:['gold','diamond','royal','pink'].includes(p.fixedColor)),
    'account-profile-invalid');
  const friends=unique(raw.friends,'pairKey',200,row=>{
    exact(row,['pairKey','members','requesterUid','recipientUid','requesterPublicId','recipientPublicId','requesterName','recipientName','status']);
    const a=row.requesterUid,b=row.recipientUid;
    requireThat(member(a)&&member(b)&&a!==b&&[a,b].includes(uid)&&
      Array.isArray(row.members)&&row.members.length===2&&row.members.includes(a)&&row.members.includes(b)&&
      row.pairKey===[a,b].sort().join('__')&&alias(row.requesterPublicId)&&alias(row.recipientPublicId)&&
      (a===uid?row.requesterPublicId:row.recipientPublicId)===p.originalId&&
      name(row.requesterName)&&name(row.recipientName)&&['pending','accepted','rejected'].includes(row.status),
      'account-friend-proof');
    return {...row,members:[a,b]};
  });
  const tasks=unique(raw.tasks,'claimKey',20000,row=>{
    exact(row,['claimKey','dayId','taskId','completedMs','claimedMs']);
    requireThat(realDay(row.dayId)&&taskIds.has(row.taskId)&&row.claimKey===row.dayId+'|'+row.taskId&&
      stamp(row.completedMs)&&baghdadDay(row.completedMs)===row.dayId&&
      (row.claimedMs===null||(stamp(row.claimedMs)&&row.claimedMs>=row.completedMs&&baghdadDay(row.claimedMs)===row.dayId)),
      'account-task-proof');
    return {...row};
  });
  const taskMap=new Map(tasks.map(x=>[x.claimKey,x]));
  const league=unique(raw.league,'weekId',520,row=>{
    exact(row,['weekId','claimedKeys','completedTasks','weeklyXp']);
    const start=weekStart(row.weekId),close=start+7*86400000-6*3600000;
    requireThat(Array.isArray(row.claimedKeys)&&row.claimedKeys.length<=56&&
      new Set(row.claimedKeys).size===row.claimedKeys.length&&row.completedTasks===row.claimedKeys.length&&
      row.weeklyXp===20*row.completedTasks,'account-league-score');
    for(const k of row.claimedKeys){
      const event=taskMap.get(k);
      requireThat(event&&event.claimedMs!==null&&event.claimedMs>=start&&event.claimedMs<close,
        'account-league-claim-proof');
    }
    return {...row,claimedKeys:[...row.claimedKeys].sort()};
  });
  return {format:1,uid,revision:raw.revision,complete:true,profile:{...p},friends,tasks,league};
}
function preserveAccount(old,next){
  requireThat(old.profile.originalId===next.profile.originalId,'account-original-id-change');
  const tasks=new Map(next.tasks.map(x=>[x.claimKey,x]));
  for(const row of old.tasks){
    const n=tasks.get(row.claimKey);
    requireThat(n&&n.completedMs===row.completedMs&&(row.claimedMs===null||n.claimedMs===row.claimedMs),
      'account-task-history-regression');
  }
  const weeks=new Map(next.league.map(x=>[x.weekId,x]));
  for(const row of old.league){
    const n=weeks.get(row.weekId);
    requireThat(n&&row.claimedKeys.every(k=>n.claimedKeys.includes(k)),'account-league-history-regression');
  }
  // Friend removal/rejection may be legitimate; this view is a full snapshot
  // from the trusted source, not an append-only grant ledger.
}
async function projectAccount({store,uid}){
  return projectRevision({store,uid,sourceName:'accountSources',viewName:'account',
    historyName:'accountHistory',parseView:parseAccount,preserveView:preserveAccount,
    checkSource:async(tx,base,next)=>{
      if(next.profile.activeId===next.profile.originalId)return;
      const inventory=await tx.get(base+'/inventory/current');
      requireThat(inventory!==null,'account-active-id-unproven');
      const verified=parse(inventory,uid);
      const g=verified.idGifts.find(x=>x.identifier===next.profile.activeId);
      requireThat(g&&g.acceptance!==null&&g.grant.baseColor===next.profile.fixedColor,
        'account-active-id-unproven');
    }});
}
// 04/01: read existing wallet schema in the local demo only. No new
// document, write, role grant, phone mapping or production source import.
// The legacy-shaped records below must be synthetic and owned by the pinned
// lab UID. Both wallet balances and protected revisions are read in one tx.
function requireDemo(store,uid){
  requireThat(/^127\.0\.0\.1:[0-9]+$/.test(process.env.FIRESTORE_EMULATOR_HOST||'')&&
    process.env.GCLOUD_PROJECT==='demo-deda-stage03-uid'&&
    store?.db?.projectId==='demo-deda-stage03-uid','wallet-emulator-only');
  account(uid,'lab-uid');
}
async function readWalletEvidence({store,uid}){
  requireDemo(store,uid);
  return store.runTransaction(tx=>walletEvidence(tx,uid));
}
async function walletEvidence(tx,uid){
  const base='deda_lab_uid_authority/'+uid;
  const max=9007199254740990;
  const money=x=>Number.isSafeInteger(x)&&x>=0&&x<=max;
    const progress=parseState(await tx.get(base),uid,'lab-uid');
    const inventory=parse(await tx.get(base+'/inventory/current'),uid);
    const profile=parseAccount(await tx.get(base+'/account/current'),uid);
    const originalId=profile.profile.originalId;
    const user=await tx.get('users/'+uid);
    const session=await tx.get('deda_sessions/'+uid);
    const route=await tx.get('deda_share_ids/'+originalId);
    requireThat(user&&session&&route&&user.accountKey===uid&&
      user.sharePersonalId===originalId&&session.uid===uid&&session.accountKey===uid&&
      route.ownerUid===uid&&route.publicId===originalId&&route.kind==='personal'&&
      route.active===true,'wallet-owner-unproven');
    const gift=await tx.get('deda_diamond_gift_balances/'+originalId);
    requireThat(gift&&gift.publicId===originalId&&
      (!Object.hasOwn(gift,'ownerUid')||gift.ownerUid===uid)&&money(gift.balance),
      'wallet-gift-source-unproven');
    const admin=await tx.get('admins/'+uid);
    const access=await tx.get('admin_entry_access/'+uid);
    const personal=await tx.get('deda_gm_personal_diamond_wallets/'+uid);
    // Only the demo's explicit active GM role AND gateway may admit a
    // personal wallet. Missing gift balance or ambiguous roles always HOLD.
    const hasManagerPersonal=admin?.role==='general_manager'&&admin.active===true&&
      admin.status==='active'&&access?.accountKey===uid&&access.active===true&&
      access.status==='active'&&access.accessType==='general_manager_gateway'&&
      access.allowedRole==='general_manager';
    let managerPersonal=0;
    if(hasManagerPersonal){
      requireThat(personal&&personal.accountKey===uid&&money(personal.balance),
        'wallet-manager-source-unproven');
      managerPersonal=personal.balance;
    }else{
      // Ordinary synthetic account: all three privileged records absent.
      // A partial or conflicting record does not establish ordinary status.
      requireThat(admin===null&&access===null&&personal===null,'wallet-role-unproven');
    }
    const earned=progress.balances.earnedDiamonds;
    requireThat(money(earned)&&gift.balance<=max-earned&&
      managerPersonal<=max-earned-gift.balance,'wallet-overflow');
    return Object.freeze({format:1,uid,complete:true,sourceKind:'synthetic-lab-wallet-v1',
      progressVersion:progress.version,inventoryRevision:inventory.revision,
      accountRevision:profile.revision,originalId,
      giftResidual:gift.balance,managerPersonal,hasManagerPersonal});
}

// Existing protected projection, updated atomically from verified sources.
// Only the trusted DEMO worker may write it, never a callable/client.
async function refreshWallet({store,uid}){
  requireDemo(store,uid);
  return store.runTransaction(async tx=>{
    const next=await walletEvidence(tx,uid);
    const path='deda_lab_uid_authority/'+uid+'/wallet/current';
    const old=await tx.get(path);
    if(old!==null){
      requireThat(old.uid===uid&&old.sourceKind==='synthetic-lab-wallet-v1'&&
        old.originalId===next.originalId&&old.progressVersion<=next.progressVersion&&
        old.inventoryRevision<=next.inventoryRevision&&old.accountRevision<=next.accountRevision,
        'wallet-projection-conflict');
      if(equal(old,next))return {replayed:true,view:next};
    }
    tx.set(path,{...next});
    return {replayed:false,view:next};
  });
}

// Switch a previously received ID in the existing account/history and
// original public directory in ONE transaction. No grant, UID, or debit.
// Trusted emulator only; no new client permissions or production routing.
async function activateOwnedId({store,uid,identifier,expectedRevision}){
  requireDemo(store,uid);
  requireThat(alias(identifier)&&Number.isSafeInteger(expectedRevision)&&expectedRevision>0,
    'active-id-request-invalid');
  const base='deda_lab_uid_authority/'+uid;
  return store.runTransaction(async tx=>{
    const accountPath=base+'/account/current', sourcePath=base+'/accountSources/current';
    const old=parseAccount(await tx.get(accountPath),uid);
    const previous=await tx.get(sourcePath);
    const oldHistory=await tx.get(base+'/accountHistory/'+old.revision);
    requireThat(equal(old,previous)&&equal(old,oldHistory),'active-id-history-conflict');
    requireThat(old.revision===expectedRevision,'active-id-revision-conflict');
    const inv=parse(await tx.get(base+'/inventory/current'),uid);
    const invSource=await tx.get(base+'/inventorySources/current');
    const invHistory=await tx.get(base+'/inventoryHistory/'+inv.revision);
    requireThat(equal(inv,invSource)&&equal(inv,invHistory),'active-id-inventory-conflict');
    const originalId=old.profile.originalId;
    const user=await tx.get('users/'+uid),session=await tx.get('deda_sessions/'+uid);
    const route=await tx.get('deda_share_ids/'+originalId);
    requireThat(user&&session&&route&&user.accountKey===uid&&user.sharePersonalId===originalId&&
      session.uid===uid&&session.accountKey===uid&&route.ownerUid===uid&&
      route.publicId===originalId&&route.kind==='personal'&&route.active===true,
      'active-id-owner-unproven');
    const activePath='deda_stage71_active_identifier/'+originalId;
    const publicPath='deda_public_active_aliases/'+originalId;
    const active=await tx.get(activePath),pub=await tx.get(publicPath);
    requireThat(active&&pub&&active.originalId===originalId&&active.activeId===old.profile.activeId&&
      pub.originalId===originalId&&pub.activeId===old.profile.activeId&&pub.baseColor===old.profile.fixedColor,
      'active-id-directory-conflict');
    let color=null,aliasPath=null;
    if(identifier!==originalId){
      const g=inv.idGifts.find(x=>x.identifier===identifier);
      const registry=await tx.get('deda_stage71_granted_registry/'+identifier);
      const receipt=await tx.get('deda_stage74_id_gift_receipts/'+identifier);
      const competing=await tx.get('deda_share_ids/'+identifier);
      aliasPath='deda_public_alias_routes/'+identifier;
      const aliasRoute=await tx.get(aliasPath);
      requireThat(g&&g.acceptance&&registry&&receipt&&registry.identifier===identifier&&
        registry.recipientOriginalId===originalId&&registry.group===g.grant.group&&
        registry.baseColor===g.grant.baseColor&&registry.kind==='gifted'&&
        receipt.identifier===identifier&&receipt.originalId===originalId&&receipt.group===g.grant.group&&
        receipt.receivedAt&&typeof receipt.receivedAt.toMillis==='function'&&
        receipt.receivedAt.toMillis()===g.acceptance.receivedMs&&
        competing===null&&(!aliasRoute||(aliasRoute.aliasId===identifier&&aliasRoute.originalId===originalId&&
          aliasRoute.baseColor===g.grant.baseColor)), 'active-id-ownership-unproven');
      color=g.grant.baseColor;
    }
    if(identifier===old.profile.activeId)return {replayed:true,view:old};
    requireThat(old.revision<9007199254740990,'active-id-revision-overflow');
    const next=parseAccount({...old,revision:old.revision+1,
      profile:{...old.profile,activeId:identifier,fixedColor:color}},uid);
    const history=base+'/accountHistory/'+next.revision;
    requireThat(await tx.get(history)===null,'active-id-history-conflict');
    const now=store.serverTimestamp();
    tx.set(accountPath,next);tx.set(sourcePath,next);tx.set(history,next);
    tx.set(activePath,{originalId,activeId:identifier,updatedAt:now});
    tx.set(publicPath,{originalId,activeId:identifier,baseColor:color,updatedAt:now});
    if(aliasPath)tx.set(aliasPath,{aliasId:identifier,originalId,baseColor:color,updatedAt:now});
    return {replayed:false,view:next};
  });
}

// The original five-stage reserve/return operation uses the EXISTING
// receipt/event ledger and reconcile core, not a separate point balance.
// The fixed campaign exists only in the disposable demo. The user supplies
// a threshold/action, never an amount, eligibility, or a reward receipt.
const thresholds=Object.freeze([5000,10000,15000,20000,25000]);
function pointReceipt(uid,threshold,action){
  const reserve=core.parseReceipt({format:1,accountKey:uid,source:'point-reservation-v1',
    sourceId:'stage04-synthetic-tier|'+threshold,kind:'spend',
    delta:{points:-threshold,coins:0,xp:0,earnedDiamonds:0}},uid,'lab-uid');
  if(action==='reserve')return reserve;
  return core.parseReceipt({format:1,accountKey:uid,source:'point-tier-return-v1',
    sourceId:'stage04-synthetic-tier|'+threshold+'|'+core.eventKey(reserve),kind:'award',
    delta:{points:threshold+threshold/100,coins:0,xp:0,earnedDiamonds:0}},uid,'lab-uid');
}
async function pointTier({store,uid,threshold,action}){
  requireDemo(store,uid);
  const index=thresholds.indexOf(threshold);
  requireThat(index>=0&&['reserve','claim'].includes(action)&&
    !(action==='claim'&&threshold===25000),'point-tier-ineligible');
  const base='deda_lab_uid_authority/'+uid;
  return store.runTransaction(async tx=>{
    const state=parseState(await tx.get(base),uid,'lab-uid');
    // All paths are derived from the existing stable event key.
    async function evidence(receipt){
      const k=core.eventKey(receipt);
      const rp=base+'/receipts/'+k, ep=base+'/events/'+k;
      const r=await tx.get(rp),e=await tx.get(ep);
      requireThat((r===null)===(e===null),'point-tier-partial-history');
      if(r!==null)requireThat(core.sameEvent(core.parseReceipt(r,uid,'lab-uid'),receipt)&&
        e.format===1&&e.accountKey===uid&&e.eventKey===k&&e.receiptId===k&&
        core.sameEvent(core.parseReceipt(e.receipt,uid,'lab-uid'),receipt)&&
        Number.isSafeInteger(e.appliedVersion)&&e.appliedVersion>=2&&e.appliedVersion<=state.version,
        'point-tier-history-conflict');
      return {rp,ep,k,applied:e};
    }
    const reservation=await evidence(pointReceipt(uid,threshold,'reserve'));
    const target=action==='reserve'?reservation:await evidence(pointReceipt(uid,threshold,'claim'));
    if(index>0){
      const prior=await evidence(pointReceipt(uid,thresholds[index-1],'claim'));
      requireThat(prior.applied!==null,'point-tier-previous-unclaimed');
    }
    if(action==='claim')requireThat(reservation.applied!==null,'point-tier-not-reserved');
    if(target.applied!==null)return {replayed:true,state};
    const receipt=pointReceipt(uid,threshold,action);
    const next=core.applyEvent(state,receipt,'lab-uid');
    tx.set(target.rp,{...receipt});
    tx.set(target.ep,{format:1,accountKey:uid,eventKey:target.k,receipt,receiptId:target.k,
      appliedVersion:next.version,afterBalances:next.balances,createdAt:store.serverTimestamp()});
    tx.set(base,{...next});
    return {replayed:false,state:next};
  });
}
module.exports={project,parse,projectAccount,parseAccount,readWalletEvidence,refreshWallet,activateOwnedId,pointTier,pointReceipt};
