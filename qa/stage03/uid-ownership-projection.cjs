'use strict';
// Protected read projection only; no purchase, award, wallet or alias mutation.
// Source fixtures are synthetic and written only by a trusted emulator context.
const {isDeepStrictEqual:equal}=require('node:util');
const {LAB_UID,account}=require('./reconcile-core.cjs');
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
  requireThat(/^127\.0\.0\.1:[0-9]+$/.test(process.env.FIRESTORE_EMULATOR_HOST||'')&&
    process.env.GCLOUD_PROJECT==='demo-deda-stage03-uid','ownership-emulator-only');
  account(uid,'lab-uid');
  const base='deda_lab_uid_authority/'+uid,view=base+'/inventory/current';
  return store.runTransaction(async tx=>{
    const raw=await tx.get(base+'/inventorySources/current');
    requireThat(raw!==null,'ownership-source-missing');
    const next=parse(raw,uid);
    const prevRaw=await tx.get(view);
    const old=prevRaw===null?null:parse(prevRaw,uid);
    const history=base+'/inventoryHistory/'+String(next.revision);
    const receipt=await tx.get(history);
    if(old!==null&&next.revision===old.revision){
      requireThat(equal(next,old)&&equal(receipt,next),'ownership-revision-conflict');
      return {replayed:true,view:old};
    }
    requireThat(next.revision===(old?.revision??0)+1&&receipt===null,'ownership-revision-conflict');
    if(old!==null)preserve(old,next);
    tx.set(view,next);tx.set(history,next);
    return {replayed:false,view:next};
  });
}
module.exports={project,parse};
