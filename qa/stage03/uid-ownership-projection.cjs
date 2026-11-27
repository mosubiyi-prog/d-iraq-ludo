'use strict';
// Protected projections and isolated trusted demo candidates; no production or client authority.
// Source fixtures are synthetic and written only by a trusted emulator context.
const {isDeepStrictEqual:equal}=require('node:util');
const core=require('./reconcile-core.cjs');
const {LAB_UID,account,parseState}=core;
const {frames}=require('./purchase-frames.cjs');
const {weekStart,plan,WEEK_MS}=require('./deda_weekly_direct_prize_plan.js');
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
    const fields=['pairKey','members','requesterUid','recipientUid','requesterPublicId','recipientPublicId','requesterName','recipientName','status'];
    if(Object.hasOwn(row,'requestRevision')){
      fields.push('requestRevision');
      requireThat(Number.isSafeInteger(row.requestRevision)&&row.requestRevision>0&&
        row.requestRevision<=raw.revision,'account-friend-request-revision');
    }
    exact(row,fields);
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

async function storeVerifiedFrames(tx,uid,original){
    const verified=[];
    for(const frameId of frames){
      const r=await tx.get('deda_lab_frame_receipts/'+original+'/frames/'+frameId);
      const o=await tx.get('deda_lab_owned_frames/'+original+'/frames/'+frameId);
      if(r===null&&o===null)continue;
      requireThat(r&&o,'store-frame-pair-incomplete');
      exact(r,['publicId','frameId','kind','cost','createdAt']);
      exact(o,['publicId','frameId','receiptId','createdAt']);
      const a=r.createdAt,b=o.createdAt;
      requireThat(r.publicId===original&&o.publicId===original&&
        r.frameId===frameId&&o.frameId===frameId&&r.kind==='lab_frame'&&
        r.cost===1000&&o.receiptId===original+'_'+frameId&&
        a&&b&&typeof a.toMillis==='function'&&typeof a.isEqual==='function'&&
        a.isEqual(b)&&stamp(Math.floor(a.toMillis())),'store-frame-proof-mismatch');
      const createdMs=Math.floor(a.toMillis());
      verified.push({frameId,receipt:{uid,frameId,kind:r.kind,cost:r.cost,createdMs},
        ownership:{uid,frameId,receiptId:uid+'_'+frameId,createdMs}});
    }
    return verified;
}

// 04/04: mirror the ORIGINAL checkout's completed receipt pair, not a
// second purchase. Trusted synthetic emulator only; no debit or new grant.
// The wallet evidence already proves the canonical original ID -> same UID.
async function syncStoreFrameReceipts({store,uid}){
  requireDemo(store,uid);
  return store.runTransaction(async tx=>{
    const evidence=await walletEvidence(tx,uid);
    const original=evidence.originalId,base='deda_lab_uid_authority/'+uid;
    const source=base+'/inventorySources/current',view=base+'/inventory/current';
    const old=parse(await tx.get(view),uid);
    requireThat(equal(parse(await tx.get(source),uid),old)&&
      equal(await tx.get(base+'/inventoryHistory/'+old.revision),old),
      'store-inventory-history-conflict');
    const verified=await storeVerifiedFrames(tx,uid,original);
    // A projection with a prior paid item may never silently drop it.
    const next=parse({...old,revision:old.revision+1,frames:verified},uid);
    preserve(old,next);
    if(equal(next.frames,old.frames))return {replayed:true,view:old};
    const history=base+'/inventoryHistory/'+next.revision;
    requireThat(await tx.get(history)===null,'store-inventory-history-conflict');
    tx.set(source,next);tx.set(view,next);tx.set(history,next);
    return {replayed:false,view:next};
  });
}

// Trusted local emulator only: one debit, original receipt pair and existing
// UID inventory/history. Reuse the reviewed checkout's earned-first / GM-only
// payment policy and existing reconcile core. Not a callable, not a new wallet.
async function purchaseStoreFrameCandidate({store,uid,frameId}){
  requireDemo(store,uid);
  requireThat(frames.includes(frameId),'store-frame-invalid');
  const {Timestamp}=require('firebase-admin/firestore');
  const now=Timestamp.fromMillis(Date.now()),createdMs=now.toMillis();
  return store.runTransaction(async tx=>{
    const evidence=await walletEvidence(tx,uid),original=evidence.originalId;
    const base='deda_lab_uid_authority/'+uid, source=base+'/inventorySources/current',
      view=base+'/inventory/current',wallet=base+'/wallet/current';
    const state=parseState(await tx.get(base),uid,'lab-uid');
    const old=parse(await tx.get(view),uid);
    requireThat(equal(parse(await tx.get(source),uid),old)&&
      equal(await tx.get(base+'/inventoryHistory/'+old.revision),old),'store-inventory-history-conflict');
    const verified=await storeVerifiedFrames(tx,uid,original);
    // Never charge against an unsynchronized or regressed ownership source.
    requireThat(equal(verified,old.frames),'store-inventory-readback-required');
    const nativePath='deda_native_account_cosmetics/'+original;
    const native=await tx.get(nativePath);
    requireThat(native&&native.originalId===original&&Array.isArray(native.ownedFrames)&&
      Array.isArray(native.pendingFrames)&&new Set(native.ownedFrames).size===native.ownedFrames.length&&
      native.ownedFrames.every(f=>frames.includes(f))&&native.pendingFrames.length===0,
      'store-native-proof-held');
    const auditPath=base+'/framePurchases/'+frameId;
    const audit=await tx.get(auditPath);
    const owned=old.frames.find(f=>f.frameId===frameId);
    if(owned){
      if(audit!==null){
        requireThat(audit.format===1&&audit.uid===uid&&audit.originalId===original&&audit.frameId===frameId&&
          audit.cost===1000&&audit.createdMs===owned.receipt.createdMs&&
          Number.isSafeInteger(audit.progressVersion)&&audit.progressVersion<=state.version&&
          audit.payment&&['earnedDiamonds','giftedDiamonds','managerDiamonds'].every(k=>
            Number.isSafeInteger(audit.payment[k])&&audit.payment[k]>=0)&&
          Object.keys(audit.payment).length===3&&Object.values(audit.payment).reduce((a,b)=>a+b,0)===1000&&
          (audit.payment.managerDiamonds===0||audit.payment.managerDiamonds===1000)&&
          native.ownedFrames.includes(frameId),'store-purchase-audit-conflict');
        if(audit.payment.earnedDiamonds>0){
          const r=core.parseReceipt({format:1,accountKey:uid,source:'cosmetic-debit-v1',
            sourceId:'stage04-store-frame|'+original+'|'+frameId,kind:'spend',
            delta:{points:0,coins:0,xp:0,earnedDiamonds:-audit.payment.earnedDiamonds}},uid,'lab-uid');
          const k=core.eventKey(r),saved=await tx.get(base+'/receipts/'+k),event=await tx.get(base+'/events/'+k);
          requireThat(audit.eventKey===k&&saved&&event&&event.accountKey===uid&&event.eventKey===k&&
            event.receiptId===k&&event.appliedVersion===audit.progressVersion&&
            core.sameEvent(core.parseReceipt(saved,uid,'lab-uid'),r)&&
            core.sameEvent(core.parseReceipt(event.receipt,uid,'lab-uid'),r),'store-purchase-audit-conflict');
        }else requireThat(audit.eventKey===null,'store-purchase-audit-conflict');
      }
      return {replayed:true,view:old,state};
    }
    requireThat(audit===null&&!native.ownedFrames.includes(frameId),'store-purchase-proof-conflict');
    const walletOld=await tx.get(wallet);
    requireThat(walletOld===null||equal(walletOld,evidence),'store-wallet-refresh-required');
    const giftPath='deda_diamond_gift_balances/'+original,gmPath='deda_gm_personal_diamond_wallets/'+uid;
    const gift=await tx.get(giftPath),gm=await tx.get(gmPath);
    const payment={earnedDiamonds:0,giftedDiamonds:0,managerDiamonds:0};
    if(evidence.hasManagerPersonal){
      requireThat(evidence.managerPersonal>=1000,'store-insufficient-diamonds');
      payment.managerDiamonds=1000;
    }else{
      requireThat(state.balances.earnedDiamonds+evidence.giftResidual>=1000,'store-insufficient-diamonds');
      payment.earnedDiamonds=Math.min(1000,state.balances.earnedDiamonds);
      payment.giftedDiamonds=1000-payment.earnedDiamonds;
    }
    let nextState=state,receipt=null,eventKey=null;
    if(payment.earnedDiamonds){
      receipt=core.parseReceipt({format:1,accountKey:uid,source:'cosmetic-debit-v1',
        sourceId:'stage04-store-frame|'+original+'|'+frameId,kind:'spend',
        delta:{points:0,coins:0,xp:0,earnedDiamonds:-payment.earnedDiamonds}},uid,'lab-uid');
      eventKey=core.eventKey(receipt);
      requireThat(await tx.get(base+'/receipts/'+eventKey)===null&&
        await tx.get(base+'/events/'+eventKey)===null,'store-partial-debit');
      nextState=core.applyEvent(state,receipt,'lab-uid');
    }
    const row={frameId,receipt:{uid,frameId,kind:'lab_frame',cost:1000,createdMs},
      ownership:{uid,frameId,receiptId:uid+'_'+frameId,createdMs}};
    const next=parse({...old,revision:old.revision+1,frames:[...old.frames,row]},uid);
    preserve(old,next);
    const history=base+'/inventoryHistory/'+next.revision;
    requireThat(await tx.get(history)===null,'store-inventory-history-conflict');
    // All checks/read operations precede the first write.
    if(receipt){
      tx.set(base+'/receipts/'+eventKey,receipt);
      tx.set(base+'/events/'+eventKey,{format:1,accountKey:uid,eventKey,receipt,receiptId:eventKey,
        appliedVersion:nextState.version,afterBalances:nextState.balances,createdAt:now});
      tx.set(base,{...nextState});
    }
    if(payment.giftedDiamonds)tx.set(giftPath,{...gift,balance:evidence.giftResidual-payment.giftedDiamonds,updatedAt:now});
    if(payment.managerDiamonds)tx.set(gmPath,{...gm,balance:evidence.managerPersonal-payment.managerDiamonds,updatedAt:now});
    tx.set('deda_lab_frame_receipts/'+original+'/frames/'+frameId,{publicId:original,frameId,kind:'lab_frame',cost:1000,createdAt:now});
    tx.set('deda_lab_owned_frames/'+original+'/frames/'+frameId,{publicId:original,frameId,receiptId:original+'_'+frameId,createdAt:now});
    tx.set(nativePath,{...native,ownedFrames:[...native.ownedFrames,frameId],updatedAt:now});
    tx.set(auditPath,{format:1,uid,originalId:original,frameId,cost:1000,payment,
      progressVersion:nextState.version,eventKey,createdMs});
    tx.set(source,next);tx.set(view,next);tx.set(history,next);
    tx.set(wallet,{...evidence,progressVersion:nextState.version,inventoryRevision:next.revision,
      giftResidual:evidence.giftResidual-payment.giftedDiamonds,managerPersonal:evidence.managerPersonal-payment.managerDiamonds});
    return {replayed:false,view:next,state:nextState,payment};
  });
}

// Capture the EXISTING trusted transaction, without committing it. The
// resulting exact approval is a synthetic emulator transport, not an issuer
// or a general client authority. Reuse the same arithmetic and receipt keys.
async function prepareStoreFrameCandidate({store,uid,frameId}){
  requireDemo(store,uid);
  let plan;
  const capture={db:store.db,serverTimestamp:()=>store.serverTimestamp(),
    runTransaction:action=>store.runTransaction(async tx=>{
      const before=new Map(),writes=new Map();
      const result=await action({
        get:async path=>{const row=await tx.get(path);before.set(path,row);return row;},
        set:(path,data)=>writes.set(path,data)});
      requireThat(!result.replayed&&writes.size>0&&writes.size<=13,
        'store-plan-not-new-purchase');
      const account=before.get('deda_lab_uid_authority/'+uid+'/account/current');
      const progress=before.get('deda_lab_uid_authority/'+uid);
      const inventory=before.get('deda_lab_uid_authority/'+uid+'/inventory/current');
      requireThat(account&&progress&&inventory,'store-plan-source-held');
      const rows=Array.from(writes,([p,after])=>{
        requireThat(before.has(p),'store-plan-missing-before');
        return {p,before:before.get(p),after};
      });
      plan={format:1,uid,originalId:account.profile.originalId,frameId,cost:1000,
        progressRevision:progress.version,inventoryRevision:inventory.revision,
        accountRevision:account.revision,rows};
      return result;
    })};
  await purchaseStoreFrameCandidate({store:capture,uid,frameId});
  return plan;
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

// Shared read-only wallet proof for isolated emulator candidates. No client
// balance or derived projection writes. Keep both candidate suites identical.
function generateWalletRead(originalRules){
  const anchor='      match /account/current {';
  if(originalRules.split(anchor).length!==2 || originalRules.includes('match /wallet/current {'))throw Error('wallet-rule-anchor');
  return originalRules.replace(anchor,()=>[
    '      match /wallet/current {',
    '        function sourceCurrent(w) {',
    '          let root = /databases/$(database)/documents/deda_lab_uid_authority/$(uid);',
    '          let account = get(/databases/$(database)/documents/deda_lab_uid_authority/$(uid)/account/current).data;',
    '          let gift = get(/databases/$(database)/documents/deda_diamond_gift_balances/$(w.originalId)).data;',
    '          let route = get(/databases/$(database)/documents/deda_share_ids/$(w.originalId)).data;',
    '          let user = get(/databases/$(database)/documents/users/$(uid)).data;',
    '          let session = get(/databases/$(database)/documents/deda_sessions/$(uid)).data;',
    '          return w.format == 1 && w.uid == uid && w.complete == true && w.sourceKind == "synthetic-lab-wallet-v1" &&',
    '            user.accountKey == uid && user.sharePersonalId == w.originalId && session.accountKey == uid && session.uid == uid &&',
    '            w.giftResidual is int && w.giftResidual >= 0 && w.managerPersonal is int && w.managerPersonal >= 0 &&',
    '            w.hasManagerPersonal is bool && get(root).data.balances.earnedDiamonds is int && get(root).data.balances.earnedDiamonds >= 0 &&',
    '            w.giftResidual + w.managerPersonal + get(root).data.balances.earnedDiamonds <= 9007199254740990 &&',
    '            w.originalId == account.profile.originalId && w.accountRevision == account.revision &&',
    '            w.progressVersion == get(root).data.version &&',
    '            w.inventoryRevision == get(/databases/$(database)/documents/deda_lab_uid_authority/$(uid)/inventory/current).data.revision &&',
    '            route.ownerUid == uid && route.publicId == w.originalId && route.active == true && route.kind == "personal" &&',
    '            gift.publicId == w.originalId && (!gift.keys().hasAny(["ownerUid"]) || gift.ownerUid == uid) &&',
    '            gift.balance == w.giftResidual && managerCurrent(w);',
    '        }',
    '        function managerCurrent(w) {',
    '          let ap = /databases/$(database)/documents/admins/$(uid);',
    '          let gp = /databases/$(database)/documents/admin_entry_access/$(uid);',
    '          let mp = /databases/$(database)/documents/deda_gm_personal_diamond_wallets/$(uid);',
    '          return w.hasManagerPersonal == false ?',
    '            (w.managerPersonal == 0 && !exists(ap) && !exists(gp) && !exists(mp)) :',
    '            (get(ap).data.role == "general_manager" && get(ap).data.active == true && get(ap).data.status == "active" &&',
    '            get(gp).data.accountKey == uid && get(gp).data.active == true && get(gp).data.status == "active" &&',
    '            get(gp).data.accessType == "general_manager_gateway" && get(gp).data.allowedRole == "general_manager" &&',
    '            get(mp).data.accountKey == uid && get(mp).data.balance == w.managerPersonal);',
    '        }',
    '        allow get: if owner(uid) && sourceCurrent(resource.data);',
    '        allow list, create, update, delete: if false;',
    '      }',anchor].join('\n'));
}
// Candidate rules only for the existing one-owner synthetic account.
// Base rules remain read-only, and no deployment or broad permission.
function generateFriendCandidateRules(originalRules){
  const anchor='      match /account/current {\n        allow get: if owner(uid);\n        allow list, create, update, delete: if false;\n      }';
  const tail='    match /{document=**} { allow read, write: if false; }';
  if(originalRules.split(anchor).length!==2||originalRules.split(tail).length!==2||
      originalRules.includes('function friendTransition('))throw Error('friends-rule-anchor');
  const pair=[LAB_UID,'synthetic-peer-001'].sort().join('__');
  const path='/databases/$(database)/documents/deda_lab_uid_authority/'+LAB_UID;
  const graph='/databases/$(database)/documents/deda_friendships/'+pair;
  const peer='/databases/$(database)/documents/deda_social_profiles/@DEDA-QA5678';
  const route='/databases/$(database)/documents/deda_share_ids/@DEDA-QA5678';
  const root=[
    "",
    "    function friendOwner() { return owner(\"OWNER\"); }",
    "    function friendAccount() { return get(BASE/account/current).data; }",
    "    function friendAfter() { return getAfter(BASE/account/current).data; }",
    "    function friendDirectory() {",
    "      let p=get(PEER).data;",
    "      let r=get(ROUTE).data;",
    "      return r.keys().hasOnly([\"ownerUid\",\"publicId\",\"kind\",\"active\"]) &&",
    "        r.ownerUid==\"synthetic-peer-001\" && r.publicId==\"@DEDA-QA5678\" &&",
    "        r.kind==\"personal\" && r.active==true &&",
    "        p.keys().hasOnly([\"ownerUid\",\"publicId\",\"displayName\",\"avatarStyle\",\"frameStyle\",\"backgroundStyle\",\"level\",\"badges\"]) &&",
    "        p.ownerUid==r.ownerUid && p.publicId==r.publicId && p.displayName is string &&",
    "        p.avatarStyle is int && p.frameStyle is int && p.backgroundStyle is int &&",
    "        p.level is int && p.badges is list;",
    "    }",
    "    function friendRow(a,r) {",
    "      return r.pairKey==\"PAIR\" &&",
    "        ((r.requesterUid==a.uid && r.recipientUid==\"synthetic-peer-001\" &&",
    "          r.members==[a.uid,\"synthetic-peer-001\"] && r.requesterPublicId==a.profile.originalId &&",
    "          r.recipientPublicId==\"@DEDA-QA5678\") ||",
    "         (r.recipientUid==a.uid && r.requesterUid==\"synthetic-peer-001\" &&",
    "          r.members==[\"synthetic-peer-001\",a.uid] && r.recipientPublicId==a.profile.originalId &&",
    "          r.requesterPublicId==\"@DEDA-QA5678\"));",
    "    }",
    "    function friendBefore(a) {",
    "      return a.friends.size()==0 ? !exists(GRAPH) :",
    "        a.friends.size()==1 && friendRow(a,a.friends[0]) &&",
    "          get(GRAPH).data==a.friends[0];",
    "    }",
    "    function friendAfterGraph(n) {",
    "      return n.friends.size()==0 ? !existsAfter(GRAPH) :",
    "        n.friends.size()==1 && getAfter(GRAPH).data==n.friends[0];",
    "    }",
    "    function friendSend(a,n) {",
    "      let p=get(PEER).data;",
    "      return n.friends==[{",
    "        \"pairKey\":\"PAIR\",\"members\":[a.uid,\"synthetic-peer-001\"],",
    "        \"requesterUid\":a.uid,\"recipientUid\":\"synthetic-peer-001\",",
    "        \"requesterPublicId\":a.profile.originalId,\"recipientPublicId\":\"@DEDA-QA5678\",",
    "        \"requesterName\":a.profile.displayName,\"recipientName\":p.displayName,",
    "        \"status\":\"pending\",\"requestRevision\":n.revision",
    "      }] && (a.friends.size()==0 || a.friends[0].status==\"rejected\");",
    "    }",
    "    function friendRespond(a,n) {",
    "      return a.friends.size()==1 && n.friends.size()==1 &&",
    "        a.friends[0].status==\"pending\" && a.friends[0].recipientUid==a.uid &&",
    "        n.friends[0].diff(a.friends[0]).affectedKeys().hasOnly([\"status\"]) &&",
    "        n.friends[0].status in [\"accepted\",\"rejected\"];",
    "    }",
    "    function friendTransition(a,n) {",
    "      return a.uid==\"OWNER\" && a.profile.originalId==\"@DEDA-QA1234\" &&",
    "        a.complete==true && a.format==1 &&",
    "        n.diff(a).affectedKeys().hasOnly([\"revision\",\"friends\"]) &&",
    "        n.revision==a.revision+1 && n.revision<=9007199254740990 &&",
    "        friendDirectory() && friendBefore(a) && friendAfterGraph(n) &&",
    "        (friendSend(a,n) || friendRespond(a,n) ||",
    "          (a.friends.size()==1 && a.friends[0].status==\"accepted\" && n.friends.size()==0));",
    "    }",
    "    function friendLinked(a,n) {",
    "      return n.revision==a.revision+1 &&",
    "        get(BASE/accountSources/current).data==a &&",
    "        get(BASE/accountHistory/$(string(a.revision))).data==a &&",
    "        !exists(BASE/accountHistory/$(string(n.revision))) &&",
    "        getAfter(BASE/accountSources/current).data==n &&",
    "        getAfter(BASE/accountHistory/$(string(n.revision))).data==n;",
    "    }",
    "    match /deda_share_ids/{id} {",
    "      allow get: if friendOwner() && id==\"@DEDA-QA5678\" && friendDirectory();",
    "      allow list, write: if false;",
    "    }",
    "    match /deda_social_profiles/{id} {",
    "      allow get: if friendOwner() && id==\"@DEDA-QA5678\" && friendDirectory();",
    "      allow list, write: if false;",
    "    }",
    "    match /deda_friendships/{id} {",
    "      allow get: if friendOwner() && id==\"PAIR\";",
    "      allow create, update: if friendOwner() && id==\"PAIR\" &&",
    "        friendAfter().revision==friendAccount().revision+1 &&",
    "        friendAfter().friends==[request.resource.data];",
    "      allow delete: if friendOwner() && id==\"PAIR\" &&",
    "        friendAfter().revision==friendAccount().revision+1 &&",
    "        friendAfter().friends==[];",
    "      allow list: if false;",
    "    }"
  ].join('\n')
    .replaceAll('OWNER',()=>LAB_UID).replaceAll('PAIR',()=>pair)
    .replaceAll('BASE',()=>path).replaceAll('GRAPH',()=>graph)
    .replaceAll('PEER',()=>peer).replaceAll('ROUTE',()=>route);
  const block=anchor.replace('allow list, create, update, delete: if false;',
    'allow update: if owner(uid) && friendTransition(resource.data,request.resource.data) && friendLinked(resource.data,request.resource.data);\n        allow list, create, delete: if false;')+
    '\n      match /accountSources/current {\n        allow update: if owner(uid) && resource.data==friendAccount() && request.resource.data==friendAfter() && friendAfter().revision==friendAccount().revision+1;\n        allow read, create, delete: if false;\n      }\n      match /accountHistory/{revision} {\n        allow create: if owner(uid) && revision==string(friendAfter().revision) && request.resource.data==friendAfter() && friendAfter().revision==friendAccount().revision+1;\n        allow read, update, delete: if false;\n      }';
  return originalRules.replace(anchor,()=>block).replace(tail,()=>root+tail);
}

// 04/03: read-only fixture for the existing weekly paths. No client writes,
// no second Auth user and no settlement. The emulator caller seeds these
// documents explicitly; this helper does not write to any database.
async function buildLeagueCandidate({store,uid,weekId,peerTasks=[]}){
  requireDemo(store,uid);
  const start=weekStart(weekId),close=start+7*86400000-6*3600000;
  const {Timestamp}=require('firebase-admin/firestore');
  const base='deda_lab_uid_authority/'+uid;
  return store.runTransaction(async tx=>{
    const raw=await tx.get(base+'/account/current');
    const a=parseAccount(raw,uid);
    requireThat(equal(raw,await tx.get(base+'/accountSources/current'))&&
      equal(raw,await tx.get(base+'/accountHistory/'+a.revision))&&
      a.profile.originalId==='@DEDA-QA1234','league-fixture-owner-proof');
    const peer='@DEDA-QA5678',other='synthetic-peer-001';
    const route=await tx.get('deda_share_ids/'+peer),p=await tx.get('deda_social_profiles/'+peer);
    requireThat(route?.ownerUid===other&&route.publicId===peer&&route.kind==='personal'&&
      route.active===true&&p?.ownerUid===other&&p.publicId===peer&&name(p.displayName),
      'league-fixture-peer-proof');
    const valid=rows=>unique(rows,'claimKey',20000,t=>{
      exact(t,['claimKey','dayId','taskId','completedMs','claimedMs']);
      requireThat(realDay(t.dayId)&&taskIds.has(t.taskId)&&t.claimKey===t.dayId+'|'+t.taskId&&
        stamp(t.completedMs)&&baghdadDay(t.completedMs)===t.dayId&&
        (t.claimedMs===null||(stamp(t.claimedMs)&&t.claimedMs>=t.completedMs&&
          baghdadDay(t.claimedMs)===t.dayId)),'league-fixture-task-proof');
      return t;
    }).filter(t=>t.claimedMs!==null&&t.claimedMs>=start&&t.claimedMs<close);
    const own=valid(a.tasks),otherRows=valid(peerTasks);
    const claimed=own.map(x=>x.claimKey).sort();
    requireThat(equal(claimed,a.league.find(x=>x.weekId===weekId)?.claimedKeys??[]),
      'league-fixture-owner-claims');
    const path='deda_weekly_direct_weeks/'+weekId,docs={},rows=[];
    function add(id,ownerUid,activeId,displayName,tasks){
      requireThat(tasks.length<=56,'league-fixture-claim-limit');
      if(!tasks.length)return;
      const sorted=[...tasks].sort((x,y)=>x.claimedMs-y.claimedMs||x.claimKey.localeCompare(y.claimKey));
      const last=sorted.at(-1),keys=tasks.map(x=>x.claimKey).sort();
      rows.push({publicId:id,ownerUid,activeId,displayName,claimedKeys:keys,reachedMs:last.claimedMs});
      docs[path+'/scores/'+id]={weekId,weekStart:Timestamp.fromMillis(start),publicId:id,
        displayName,claimedKeys:keys,lastClaimKey:last.claimKey,completedTasks:keys.length,
        weeklyXp:keys.length*20,updatedAt:Timestamp.fromMillis(last.claimedMs)};
    }
    add(a.profile.originalId,uid,a.profile.activeId,a.profile.displayName,own);
    add(peer,other,peer,p.displayName,otherRows);
    docs[path]={format:1,synthetic:true,complete:true,ownerUid:uid,weekId,
      accountRevision:a.revision,rows};
    return docs;
  });
}

// 04/03 bridge: the existing worker creates exactly one legacy Hadaya gift.
// Import that *existing* receipt into the protected UID inventory, using the
// existing prize planner. No gift issuance, claim, balance or admin mutation.
// This candidate is restricted to the same synthetic owner and peer in demo.
async function syncLeagueGiftCandidate({store,uid,weekId,atMs}){
  return leagueGiftEvidence({store,uid,weekId,atMs});
}
async function leagueGiftEvidence({store,uid,weekId,atMs,inspectOnly=false,transaction=null}){
  requireDemo(store,uid);
  const start=weekStart(weekId),end=start+WEEK_MS,cutoff=end-6*3600000;
  requireThat(Number.isSafeInteger(atMs)&&atMs>=end,'league-gift-before-close');
  const db=store.db,base='deda_lab_uid_authority/'+uid;
  const ownerId='@DEDA-QA1234',peerId='@DEDA-QA5678',peerUid='synthetic-peer-001';
  const weekPath='deda_weekly_direct_weeks/'+weekId;
  const floor=[250,200,150,100,100,100,100,100,100,100];
  const work=async tx=>{
    const get=async path=>{const s=await tx.get(db.doc(path));return s.exists?s.data():null;};
    const acct=parseAccount(await get(base+'/account/current'),uid);
    requireThat(acct.profile.originalId===ownerId&&
      equal(acct,await get(base+'/accountSources/current'))&&
      equal(acct,await get(base+'/accountHistory/'+acct.revision)),
      'league-gift-account-conflict');
    const user=await get('users/'+uid),session=await get('deda_sessions/'+uid);
    requireThat(user?.accountKey===uid&&user.sharePersonalId===ownerId&&
      session?.uid===uid&&session.accountKey===uid,'league-gift-owner-conflict');
    for(const [id,who] of [[ownerId,uid],[peerId,peerUid]]){
      const route=await get('deda_share_ids/'+id);
      requireThat(route?.ownerUid===who&&route.publicId===id&&
        route.kind==='personal'&&route.active===true,'league-gift-directory-conflict');
    }
    const proof=await get(weekPath);
    exact(proof,['format','synthetic','complete','ownerUid','weekId','accountRevision','rows']);
    requireThat(proof.format===1&&proof.synthetic===true&&proof.complete===true&&
      proof.ownerUid===uid&&proof.weekId===weekId&&proof.accountRevision===acct.revision&&
      Array.isArray(proof.rows)&&proof.rows.length<=2,'league-gift-ranking-conflict');
    const scores=await tx.get(db.collection(weekPath+'/scores').limit(3));
    requireThat(scores.size===proof.rows.length,'league-gift-ranking-conflict');
    const records=scores.docs.map(d=>({id:d.id,data:d.data()})),seen=new Set();
    const ownClaims=acct.league.find(x=>x.weekId===weekId)?.claimedKeys??[];
    for(const p of proof.rows){
      exact(p,['publicId','ownerUid','activeId','displayName','claimedKeys','reachedMs']);
      const isOwner=p.publicId===ownerId;
      requireThat(!seen.has(p.publicId)&&
        (isOwner?p.ownerUid===uid&&p.activeId===acct.profile.activeId&&
          p.displayName===acct.profile.displayName:p.publicId===peerId&&
          p.ownerUid===peerUid&&p.activeId===peerId)&&
        Array.isArray(p.claimedKeys)&&p.claimedKeys.length>=1&&p.claimedKeys.length<=56&&
        new Set(p.claimedKeys).size===p.claimedKeys.length&&
        p.claimedKeys.every(k=>{
          if(typeof k!=='string')return false;
          const [day,task,...rest]=k.split('|');
          return !rest.length&&realDay(day)&&taskIds.has(task)&&
            Date.parse(day+'T09:00:00Z')>=start&&Date.parse(day+'T09:00:00Z')<cutoff;
        })&&Number.isSafeInteger(p.reachedMs)&&p.reachedMs>=start&&p.reachedMs<cutoff,
        'league-gift-ranking-conflict');
      seen.add(p.publicId);
      const s=records.find(r=>r.id===p.publicId)?.data;
      requireThat(s&&s.publicId===p.publicId&&s.weekId===weekId&&
        s.displayName===p.displayName&&s.updatedAt?.toMillis?.()===p.reachedMs&&
        s.weeklyXp===20*p.claimedKeys.length&&s.completedTasks===p.claimedKeys.length&&
        equal(s.claimedKeys,p.claimedKeys)&&(!isOwner||equal(p.claimedKeys,ownClaims)),
        'league-gift-score-conflict');
    }
    requireThat(seen.has(ownerId)===(ownClaims.length>0),'league-gift-owner-score-missing');
    const amounts=await get('deda_weekly_direct_prize_plans/'+weekId);
    const control=await get('deda_weekly_direct_control/active');
    requireThat(amounts?.weekId===weekId&&Array.isArray(amounts.amounts)&&
      amounts.amounts.length===10&&amounts.amounts.every((n,i)=>
        Number.isSafeInteger(n)&&n>=floor[i]&&n<=1000000),'league-gift-plan-conflict');
    requireThat(control?.weekId===weekId&&control.paused===false,'league-gift-control-held');
    const reviews=await tx.get(db.collection('deda_weekly_direct_reviews/'+weekId+'/users').limit(3));
    requireThat(reviews.size<=2,'league-gift-review-conflict');
    const freezes=new Map();
    for(const d of reviews.docs){
      const v=d.data();
      requireThat(seen.has(d.id)&&typeof v.frozen==='boolean','league-gift-review-conflict');
      freezes.set(d.id,v.frozen);
    }
    const result=plan({weekId,atMs,records,freezes,approvedAmounts:amounts.amounts});
    const winner=result.winners.find(w=>w.publicId===ownerId);
    const old=parse(await get(base+'/inventory/current'),uid);
    requireThat(equal(old,await get(base+'/inventorySources/current'))&&
      equal(old,await get(base+'/inventoryHistory/'+old.revision)),'league-gift-inventory-conflict');
    const canonicalId='deda-weekly-'+weekId+'-'+uid;
    const prior=old.diamondGifts.find(g=>g.giftId===canonicalId);
    const legacyId='deda-weekly-'+weekId+'-'+ownerId.slice(1);
    const gift=await get('deda_diamond_gifts/'+legacyId);
    if(!winner||!gift){
      requireThat(!prior&&!gift,'league-gift-existing-conflict');
      return {state:winner?'awaiting-issuance':'not-eligible',view:old,winner,winnerCount:result.winners.length};
    }
    const created=gift.createdAt?.toMillis?.(),received=gift.claimedAt?.toMillis?.();
    requireThat(winner.giftId===legacyId&&gift.giftId===legacyId&&
      gift.sourceType==='weekly_league'&&gift.adminUid==='deda-weekly-league-system'&&
      gift.targetPublicId===ownerId&&gift.targetName===winner.name&&gift.amount===winner.amount&&
      Number.isSafeInteger(created)&&created>=end&&created<=atMs&&
      (gift.status==='pending'?gift.claimedAt==null:
        gift.status==='received'&&Number.isSafeInteger(received)&&received>=created&&received<=atMs),
      'league-gift-receipt-conflict');
    const nextGift={giftId:canonicalId,uid,sourceType:'weekly_league',weekId,
      amount:winner.amount,status:gift.status,createdMs:created,
      receivedMs:gift.status==='received'?received:null};
    if(inspectOnly)return {state:'verified-issued',view:old,winner,winnerCount:result.winners.length};
    if(prior&&equal(prior,nextGift))return {state:'replayed',view:old};
    const next=parse({...old,revision:old.revision+1,
      diamondGifts:[...old.diamondGifts.filter(g=>g.giftId!==canonicalId),nextGift]},uid);
    preserve(old,next);
    const history=base+'/inventoryHistory/'+next.revision;
    requireThat(await get(history)===null,'league-gift-inventory-conflict');
    tx.set(db.doc(base+'/inventory/current'),next);
    tx.set(db.doc(base+'/inventorySources/current'),next);
    tx.set(db.doc(history),next);
    return {state:'projected',view:next};
  };
  return transaction?work(transaction):db.runTransaction(work);
}


// Use the ORIGINAL payout worker and its original deterministic gift path.
// One authenticated synthetic account only. All proof is rechecked inside
// the actual gift transaction; no alternate issuer or new authority.
async function settleLeagueCandidate({store,uid,weekId,atMs}){
  requireDemo(store,uid);
  const end=weekStart(weekId)+WEEK_MS;
  requireThat(Number.isSafeInteger(atMs)&&atMs>=end&&atMs<end+36*3600000,
    'league-settlement-window');
  const inspect=transaction=>leagueGiftEvidence({store,uid,weekId,atMs,
    inspectOnly:true,transaction});
  const opening=await inspect(null);
  // The peer is not a real account and must never receive a gift.
  requireThat(opening.winnerCount===1&&opening.winner?.publicId==='@DEDA-QA1234',
    'league-settlement-single-proven-owner');
  const {settleWeek}=require('./deda_weekly_direct_prize_worker.cjs');
  const {Timestamp}=require('firebase-admin/firestore');
  const dry=await settleWeek(store.db,weekId,atMs,{dryRun:true});
  requireThat(dry.eligible===1&&dry.diamonds===opening.winner.amount&&
    equal(dry.receipts,[opening.winner.giftId]),'league-settlement-plan-changed');
  const report=await settleWeek(store.db,weekId,atMs,{
    dryRun:false,clockTimestamp:()=>Timestamp.fromMillis(atMs),
    verifyDemoCandidate:async ({tx,winner})=>{
      const fresh=await inspect(tx);
      requireThat(fresh.winnerCount===1&&equal(fresh.winner,opening.winner)&&
        equal(winner,fresh.winner),'league-settlement-proof-changed');
    },
  });
  requireThat(report.created+report.existing===1&&report.invalid===0&&report.held===0,
    'league-settlement-held');
  // The original pending receipt is the source of truth; re-run safely
  // after interruption. Projection never credits the balance.
  const projected=await syncLeagueGiftCandidate({store,uid,weekId,atMs});
  return {report,projection:projected.state,view:projected.view};
}

function generateLeagueCandidateRules(originalRules){
  const tail='    match /{document=**} { allow read, write: if false; }';
  if(originalRules.split(tail).length!==2||originalRules.includes('function leagueFixtureOwner('))
    throw Error('league-rule-anchor');
  const root=[
    '    function leagueFixtureOwner() { return owner("'+LAB_UID+'"); }',
    '    function fixtureWeek(w) { return w.matches("^20[0-9]{2}-[0-9]{2}-[0-9]{2}$"); }',
    '    function fixtureComplete(w) {',
    '      let p=get(/databases/$(database)/documents/deda_weekly_direct_weeks/$(w)).data;',
    '      return p.synthetic==true && p.complete==true && p.ownerUid=="'+LAB_UID+'" && p.weekId==w;',
    '    }',
    '    match /deda_weekly_direct_weeks/{w} {',
    '      allow get: if leagueFixtureOwner() && fixtureWeek(w);',
    '      allow list, write: if false;',
    '      match /scores/{id} {',
    '        allow get: if leagueFixtureOwner() && fixtureWeek(w) && fixtureComplete(w);',
    '        allow list: if leagueFixtureOwner() && fixtureWeek(w) && fixtureComplete(w) && request.query.limit<=5001;',
    '        allow write: if false;',
    '      }',
    '    }',
    '    match /deda_weekly_direct_prize_plans/{w} {',
    '      allow get: if leagueFixtureOwner() && fixtureWeek(w) && fixtureComplete(w);',
    '      allow list, write: if false;',
    '    }',
    '    match /deda_weekly_direct_control/active {',
    '      allow get: if leagueFixtureOwner();',
    '      allow list, write: if false;',
    '    }',
    '    match /deda_share_ids/{id} {',
    '      allow get: if leagueFixtureOwner() && id in ["@DEDA-QA1234","@DEDA-QA5678"];',
    '      allow list, write: if false;',
    '    }',
    '    match /deda_social_profiles/{id} {',
    '      allow get: if leagueFixtureOwner() && id in ["@DEDA-QA1234","@DEDA-QA5678"];',
    '      allow list, write: if false;',
    '    }',
  ].join('\n')+'\n';
  return originalRules.replace(tail,()=>root+tail);
}

// 04/02: exercise the original relationship operations in a trusted DEMO
// transaction. The peer is a synthetic fixture, never a new Auth user.
// No callable/client writer or production permission; a second real owner's
// projection and public directory authorization require later integration.
async function executeFriendCandidateCommand({store,uid,command}){
  requireDemo(store,uid);
  exact(command,['format','action','peerUid','peerPublicId','pairKey','expectedRevision','requestRevision']);
  requireThat(command.format===1&&command.peerUid==='synthetic-peer-001'&&
    command.peerPublicId==='@DEDA-QA5678'&&
    command.pairKey===[uid,command.peerUid].sort().join('__')&&
    (command.requestRevision===null||stamp(command.requestRevision)),'friends-command-invalid');
  // Internal emulator worker, NOT a client endpoint.
  return mutateFriendCandidate({store,uid,peerUid:command.peerUid,
    expectedRevision:command.expectedRevision,action:command.action,
    expectedRequestRevision:command.requestRevision});
}
async function mutateFriendCandidate({store,uid,peerUid,expectedRevision,action,simulatePeer=false,expectedRequestRevision=undefined}){
  requireDemo(store,uid);
  requireThat(peerUid==='synthetic-peer-001'&&peerUid!==uid&&
    Number.isSafeInteger(expectedRevision)&&expectedRevision>=1&&
    typeof simulatePeer==='boolean'&&
    ['send','accept','reject','remove'].includes(action),'friends-candidate-input');
  // Only the trusted demo worker may simulate the already-existing peer.
  // The authenticated owner remains pinned by requireDemo; this flag is
  // never an Auth principal, callable parameter, or client permission.
  const actor=simulatePeer?peerUid:uid;
  const recipient=simulatePeer?uid:peerUid;
  const base='deda_lab_uid_authority/'+uid;
  const pair=[uid,peerUid].sort().join('__');
  // Use the same SDK transaction as the trusted store; removal requires a
  // real document delete, not a fabricated rejection or tombstone.
  return store.db.runTransaction(async tx=>{
    const ref=path=>store.db.doc(path);
    const get=async path=>{const row=await tx.get(ref(path));return row.exists?row.data():null;};
    const old=parseAccount(await get(base+'/account/current'),uid);
    const source=await get(base+'/accountSources/current');
    const history=await get(base+'/accountHistory/'+old.revision);
    requireThat(old.revision===expectedRevision&&old.revision<9007199254740990&&
      equal(old,source)&&equal(old,history),'friends-revision-conflict');
    const user=await get('users/'+uid),session=await get('deda_sessions/'+uid);
    const original=old.profile.originalId,peerId='@DEDA-QA5678';
    const own=await get('deda_share_ids/'+original),route=await get('deda_share_ids/'+peerId);
    const profile=await get('deda_social_profiles/'+peerId);
    function verifiedRoute(row,owner,id){
      return row&&row.ownerUid===owner&&row.publicId===id&&row.kind==='personal'&&row.active===true;
    }
    requireThat(user?.accountKey===uid&&user.sharePersonalId===original&&
      session?.uid===uid&&session.accountKey===uid&&verifiedRoute(own,uid,original)&&
      peerId!==original&&peerId!==old.profile.activeId&&verifiedRoute(route,peerUid,peerId)&&
      profile?.ownerUid===peerUid&&profile.publicId===peerId&&name(profile.displayName),
      'friends-directory-owner-unproven');
    const graphPath='deda_friendships/'+pair;
    const graph=await get(graphPath);
    const previous=old.friends.find(row=>row.pairKey===pair)||null;
    requireThat(equal(graph,previous),'friends-canonical-projection-conflict');
    requireThat(expectedRequestRevision===undefined ||
      (previous?.requestRevision??null)===expectedRequestRevision,'friends-command-stale-request');
    let nextRow;
    if(action==='send'){
      requireThat(previous===null||previous.status==='rejected','friends-existing-request-or-relation');
      nextRow={pairKey:pair,members:[actor,recipient],requesterUid:actor,recipientUid:recipient,
        requesterPublicId:simulatePeer?peerId:original,recipientPublicId:simulatePeer?original:peerId,
        requesterName:simulatePeer?profile.displayName:old.profile.displayName,
        recipientName:simulatePeer?old.profile.displayName:profile.displayName,status:'pending',
        requestRevision:old.revision+1};
    }else if(action==='accept'||action==='reject'){
      requireThat(previous&&previous.status==='pending'&&previous.recipientUid===actor&&
        previous.requesterUid===recipient,'friends-not-pending-recipient');
      nextRow={...previous,status:action==='accept'?'accepted':'rejected'};
    }else{
      requireThat(previous&&previous.status==='accepted','friends-not-accepted');
      nextRow=null;
    }
    const next=parseAccount({...old,revision:old.revision+1,
      friends:[...old.friends.filter(row=>row.pairKey!==pair),...(nextRow?[nextRow]:[])]},uid);
    const nextHistory=base+'/accountHistory/'+next.revision;
    requireThat(await get(nextHistory)===null,'friends-history-conflict');
    preserveAccount(old,next);
    // No wallet/task/league writer and no participant identity change.
    requireThat(equal(next.profile,old.profile)&&equal(next.tasks,old.tasks)&&
      equal(next.league,old.league),'friends-unrelated-change');
    tx.set(ref(base+'/account/current'),next);
    tx.set(ref(base+'/accountSources/current'),next);
    tx.set(ref(nextHistory),next);
    if(nextRow)tx.set(ref(graphPath),nextRow);else tx.delete(ref(graphPath));
    return next;
  });
}
module.exports={prepareStoreFrameCandidate,purchaseStoreFrameCandidate,syncStoreFrameReceipts,project,parse,projectAccount,parseAccount,readWalletEvidence,refreshWallet,activateOwnedId,pointTier,pointReceipt,generateWalletRead,mutateFriendCandidate,executeFriendCandidateCommand,generateFriendCandidateRules,buildLeagueCandidate,syncLeagueGiftCandidate,settleLeagueCandidate,generateLeagueCandidateRules};
