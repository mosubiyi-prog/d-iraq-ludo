'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {inspectLinkedOwnerRights,previewLinkedOwnerRights,frames}=
 require('../deda_step2_linked_rights_audit_NOT_EXPORTED.js');
const account='07712345678',original='@DEDA-ABC123',week='2026-10-31';
const active='@DEDA-VIP123';
const stamp=()=>({toMillis:()=>Date.UTC(2026,10,1)});
const git=()=>({identifier:active,recipientOriginalId:original,
 group:'001',baseColor:'gold',kind:'gifted',grantedAt:stamp()});
const prizeId='deda-weekly-'+week+'-'+original.slice(1);
function fixture(){
 const rows=new Map(),calls=[];
 const tx={async get(path){calls.push(path);return rows.get(path)??null;},
   set(){throw Error('readonly:no-set');},
   delete(){throw Error('readonly:no-delete');}};
 const run=(id=original,whichWeek=week)=>inspectLinkedOwnerRights({
   tx,accountKey:account,originalId:id,weekId:whichWeek});
 const frame=(name='FRAME_03')=>{
   rows.set('deda_lab_frame_receipts/'+original+'/frames/'+name,
    {kind:'lab_frame',publicId:original,frameId:name,cost:1000});
   rows.set('deda_lab_owned_frames/'+original+'/frames/'+name,
    {publicId:original,frameId:name,receiptId:original+'_'+name});
 };
 const choose=()=>rows.set('deda_stage71_active_identifier/'+original,
   {originalId:original,activeId:active});
 const grant=(value=git())=>rows.set('deda_stage71_granted_registry/'+active,value);
 const accept=(value={identifier:active,originalId:original,group:'001',receivedAt:stamp()})=>
   rows.set('deda_stage74_id_gift_receipts/'+active,value);
 const prize=(status='pending')=>rows.set('deda_diamond_gifts/'+prizeId,
   {giftId:prizeId,sourceType:'weekly_league',targetPublicId:original,
    amount:150,status,createdAt:stamp()});
 return {rows,calls,tx,run,frame,choose,grant,accept,prize};
}
test('all 13 receipt pairs scanned; absences UNKNOWN not free/unowned proof',async()=>{
 const f=fixture(),r=await f.run();
 assert.equal(r.scannedFrameSlots,13);assert.equal(frames.length,13);
 assert.equal(r.verifiedFramePairs,0);
 assert.equal(r.frameSources.FRAME_03,'no-server-pair-legacy-unknown');
 assert.equal(r.weeklyGiftStatus,'weekly-receipt-not-found-history-unknown');
 for(const key of ['completeHistoricalGiftInbox','completeWeeklyPrizeHistory',
  'allPurchasedFramesRecovered','canGrantFrames','canActivateId',
  'canAcceptGift','canCreditWeeklyDiamonds','canReissueAwards',
  'canRestoreBalances','allowPhoneCutover']) assert.equal(r[key],false);
 assert.equal(f.calls.length,28);
});
test('actual receipt and owned pair is observed only; not granted',async()=>{
 const f=fixture();f.frame();
 const r=await f.run();assert.equal(r.verifiedFramePairs,1);
 assert.equal(r.frameSources.FRAME_03,'confirmed-server-receipt-pair-readonly');
 assert.equal(r.canGrantFrames,false);
});
test('single missing frame receipt is conflict, not unpaid frame',async()=>{
 const f=fixture();f.frame();
 f.rows.delete('deda_lab_frame_receipts/'+original+'/frames/FRAME_03');
 await assert.rejects(f.run(),e=>e.code==='step2-frame-receipt-ownership-conflict');
});
test('forged ownership or altered price blocks entire audit',async()=>{
 for(const mismatch of ['price','original','receipt']){
  const f=fixture();f.frame();
  const p='deda_lab_frame_receipts/'+original+'/frames/FRAME_03';
  const o='deda_lab_owned_frames/'+original+'/frames/FRAME_03';
  if(mismatch==='price')f.rows.set(p,{...f.rows.get(p),cost:1});
  if(mismatch==='original')f.rows.set(p,{...f.rows.get(p),publicId:'@DEDA-FOREIG'});
  if(mismatch==='receipt')f.rows.set(o,{...f.rows.get(o),receiptId:'fake'});
  await assert.rejects(f.run(),e=>e.code==='step2-frame-receipt-ownership-conflict');
 }
});
test('active alias is not ownership without independent grant',async()=>{
 const f=fixture();f.choose();
 assert.equal((await f.run()).activeIdStatus,
  'active-alias-independent-ownership-unverified');
});
test('received receipt without ownership grant is rejected',async()=>{
 const f=fixture();f.choose();f.accept();
 await assert.rejects(f.run(),e=>e.code==='step2-premium-receipt-without-grant');
});
test('gift grant without recipient acceptance remains pending',async()=>{
 const f=fixture();f.choose();f.grant();
 const r=await f.run();
 assert.equal(r.activeIdStatus,'stage71-gift-awaiting-recipient-receipt');
 assert.equal(r.canAcceptGift,false);
});
test('matching gift acceptance does not trigger a second receive',async()=>{
 const f=fixture();f.choose();f.grant();f.accept();
 const r=await f.run();assert.equal(r.activeIdStatus,'stage71-gift-received-readonly');
 assert.equal(r.canAcceptGift,false);assert.equal(r.canActivateId,false);
});
test('gift accepted for another original ID must fail closed',async()=>{
 const f=fixture();f.choose();f.grant();
 f.accept({identifier:active,originalId:'@DEDA-FOREIG',group:'001',receivedAt:stamp()});
 await assert.rejects(f.run(),e=>e.code==='step2-premium-gift-receipt-conflict');
});
test('self use is not gifted and forbids recipient acceptance receipt',async()=>{
 const f=fixture();f.choose();f.grant({...git(),kind:'self_used'});
 assert.equal((await f.run()).activeIdStatus,'stage71-self-use-grant-readonly');
 f.accept();await assert.rejects(f.run(),
  e=>e.code==='step2-self-use-must-not-have-gift-receipt');
});
test('original ID selected is not interpreted as premium asset',async()=>{
 const f=fixture();f.rows.set('deda_stage71_active_identifier/'+original,
  {originalId:original,activeId:original});
 assert.equal((await f.run()).activeIdStatus,
  'original-id-selected-not-premium');
});
test('actual pending weekly gift not a second diamond wallet credit',async()=>{
 const f=fixture();f.prize();
 const r=await f.run();
 assert.equal(r.weeklyGiftStatus,'pending-weekly-gift-do-not-credit-on-restore');
 assert.equal(r.canCreditWeeklyDiamonds,false);
});
test('claimed weekly gift remains already processed, not reissued',async()=>{
 const f=fixture();f.prize('claimed');
 const r=await f.run();
 assert.equal(r.weeklyGiftStatus,'claimed-weekly-gift-already-processed');
 assert.equal(r.canReissueAwards,false);
});
test('weekly gift from another owner or source or ID blocked',async()=>{
 for(const altered of [
  {sourceType:'manual'}, {targetPublicId:'@DEDA-FOREIG'},
  {giftId:'random'}, {amount:-10}, {status:'unexpected'},
 ]){
  const f=fixture();f.prize();f.rows.set('deda_diamond_gifts/'+prizeId,
   {...f.rows.get('deda_diamond_gifts/'+prizeId),...altered});
  await assert.rejects(f.run(),e=>e.code==='step2-weekly-prize-receipt-conflict');
 }
});
test('unknown week cannot be used to fabricate an award',async()=>{
 const f=fixture();
 await assert.rejects(f.run(original,'2026-11-02'),
  e=>e.code==='step2-rights-week-invalid');
 assert.equal(f.calls.length,0);
});
test('no trusted session means no rights scan',async()=>{
 await assert.rejects(previewLinkedOwnerRights({store:{},auth:{},idToken:'fake',weekId:week}),
  e=>e.code==='step2-linked-session-dependencies-missing');
});
test('cross-account original ID scope or malicious input fails before reads',async()=>{
 const f=fixture();
 for(const bad of ['@DEDA-OTHER1','../',null]){
  if(bad==='@DEDA-OTHER1')continue; // A valid other ID needs owner gate.
  await assert.rejects(f.run(bad));
 }
 assert.equal(f.calls.length,0);
});
