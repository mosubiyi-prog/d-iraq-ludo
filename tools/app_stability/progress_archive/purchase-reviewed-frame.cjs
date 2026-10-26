'use strict';
// Existing internal 1000-diamond frame purchase, committed once with ownership.
// No new billing, caller amounts, automatic reward, wallet bootstrap or export.
const core=require('./reconcile-core.cjs');
const {frames}=require('./purchase-frames.cjs');
const {loadMigratedContext}=require('./migration-gate.cjs');
const {requireReviewedActivation}=require('./reviewed-activation-proof.cjs');
const {withVerifiedOwnerSession}=require('./point-tier-session.cjs');
const cost=1000;
function fail(code){throw Object.assign(new Error(code),{code});}
function balance(value){if(!Number.isSafeInteger(value)||value<0)fail('frame-invalid-wallet');return value;}
function stamp(t){return t&&Number.isSafeInteger(t.seconds)&&Number.isSafeInteger(t.nanoseconds)&&
 t.nanoseconds>=0&&t.nanoseconds<1000000000;}
function list(value){return Array.isArray(value)&&value.every(v=>typeof v==='string')&&new Set(value).size===value.length;}
function confirmed(receipt,ownership,originalId,frameId){return receipt&&ownership&&receipt.kind==='lab_frame'&&
 receipt.publicId===originalId&&receipt.frameId===frameId&&receipt.cost===cost&&
 ownership.publicId===originalId&&ownership.frameId===frameId&&ownership.receiptId===`${originalId}_${frameId}`;}
function gateway(record,accountKey){return record&&record.accountKey===accountKey&&record.active===true&&
 record.status==='active'&&record.accessType==='general_manager_gateway'&&record.allowedRole==='general_manager';}
async function purchaseReviewedFrameForOwnerSession(options){
 const keys=['store','auth','idToken','frameId'];
 if(!options||typeof options!=='object'||Array.isArray(options)||Object.keys(options).length!==keys.length||
  !keys.every(k=>Object.hasOwn(options,k))||!frames.includes(options.frameId))fail('invalid-reviewed-frame-request');
 const {store,auth,idToken,frameId}=options;
 if(!store||typeof store.runTransaction!=='function'||typeof store.serverTimestamp!=='function'||
  typeof store.readOwnerSession!=='function'||!auth||typeof auth.verifyIdToken!=='function'||
  typeof idToken!=='string'||!idToken.length)fail('invalid-reviewed-frame-dependencies');
 return withVerifiedOwnerSession(options,async(tx,accountKey,actor)=>{
  const context=await loadMigratedContext(tx,accountKey);
  const activation=await requireReviewedActivation(tx,context);
  const {root,migration,state}=context;
  const fence=await tx.get(`${root}/fences/${activation.legacyFenceId}`),originalId=fence.originalId;
  if(typeof originalId!=='string'||!/^@DEDA-[A-Z0-9]{6}$/.test(originalId))fail('frame-canonical-owner-required');
  const user=await tx.get(`users/${actor.uid}`),route=await tx.get(`deda_share_ids/${originalId}`);
  if(user?.sharePersonalId!==originalId||!route||route.publicId!==originalId||route.active!==true||route.kind!=='personal'||
   typeof route.ownerUid!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(route.ownerUid))fail('frame-canonical-owner-required');
  const routeOwner=await tx.get(`users/${route.ownerUid}`);
  if(!routeOwner||routeOwner.accountKey!==accountKey)fail('frame-canonical-owner-required');
  const receiptPath=`deda_lab_frame_receipts/${originalId}/frames/${frameId}`;
  const ownershipPath=`deda_lab_owned_frames/${originalId}/frames/${frameId}`;
  const nativePath=`deda_native_account_cosmetics/${originalId}`;
  const auditPath=`${root}/framePurchases/${frameId}`;
  const receipt=await tx.get(receiptPath),ownership=await tx.get(ownershipPath);
  const native=await tx.get(nativePath),audit=await tx.get(auditPath);
  if(!native||native.originalId!==originalId||!list(native.ownedFrames)||!list(native.pendingFrames))fail('frame-invalid-native-inventory');
  const pair=confirmed(receipt,ownership,originalId,frameId);
  if((receipt!==null||ownership!==null)&&!pair)fail('frame-conflicting-ownership-proof');
  const giftPath=`deda_diamond_gift_balances/${originalId}`,gmPath=`deda_gm_personal_diamond_wallets/${accountKey}`;
  const gift=await tx.get(giftPath),access=await tx.get(`admin_entry_access/${accountKey}`);
  const gm=await tx.get(gmPath),isManager=gateway(access,accountKey);
  const giftedBalance=gift===null?0:balance(gift.balance);
  if(gift!==null&&gift.publicId!==originalId)fail('frame-invalid-wallet');
  let managerBalance=null;
  if(isManager){
   if(!gm||gm.accountKey!==accountKey||gm.initialBalance!==1000000)fail('frame-manager-wallet-unavailable');
   managerBalance=balance(gm.balance);
  }
  const response=(replayed,legacyOwned,next,payment,gifted=giftedBalance,manager=managerBalance)=>Object.freeze({
   replayed,legacyOwned,owned:true,originalId,frameId,state:next,payment,giftedBalance:gifted,managerBalance:manager,
   purchasableBalance:manager??balance(next.balances.earnedDiamonds+gifted)});
  if(audit!==null){
   const keys=['format','accountKey','migrationId','evidenceDigest','originalId','frameId','cost',
    'payment','progressVersion','eventKey','executedByUid','createdAt'];
   if(Object.keys(audit).length!==keys.length||!keys.every(k=>Object.hasOwn(audit,k))||
    audit.format!==1||audit.accountKey!==accountKey||audit.migrationId!==migration.migrationId||
    audit.evidenceDigest!==migration.evidenceDigest||audit.originalId!==originalId||audit.frameId!==frameId||
    audit.cost!==cost||!audit.payment||Object.keys(audit.payment).length!==3||
    !['earnedDiamonds','giftedDiamonds','managerDiamonds'].every(k=>Object.hasOwn(audit.payment,k)&&
      Number.isSafeInteger(audit.payment[k])&&audit.payment[k]>=0)||
    Object.values(audit.payment).reduce((a,b)=>a+b,0)!==cost||
    (audit.payment.managerDiamonds!==0&&audit.payment.managerDiamonds!==cost)||
    typeof audit.executedByUid!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(audit.executedByUid)||
    !stamp(audit.createdAt)||!Number.isSafeInteger(audit.progressVersion)||audit.progressVersion<1||
    audit.progressVersion>state.version||!pair||!native.ownedFrames.includes(frameId))fail('frame-purchase-audit-conflict');
   if(audit.payment.earnedDiamonds>0){
    const expected=core.parseReceipt({format:1,accountKey,source:'cosmetic-debit-v1',
     sourceId:`frame-purchase|${migration.migrationId}|${originalId}|${frameId}`,kind:'spend',
     delta:{points:0,coins:0,xp:0,earnedDiamonds:-audit.payment.earnedDiamonds}},accountKey);
    const key=core.eventKey(expected),event=await tx.get(`deda_verified_progress/${accountKey}/events/${key}`);
    const storedReceipt=await tx.get(`deda_progress_receipts/${accountKey}/events/frame_${key}`);
    const classification=await tx.get(`${root}/classifications/${key}`);
    if(audit.eventKey!==key||!event||event.format!==1||event.accountKey!==accountKey||event.eventKey!==key||
     event.receiptId!==`frame_${key}`||event.appliedVersion!==audit.progressVersion||!stamp(event.createdAt)||
     !core.sameEvent(core.parseReceipt(event.receipt,accountKey),expected)||
     !core.sameEvent(core.parseReceipt(storedReceipt,accountKey),expected)||
     !classification||classification.accountKey!==accountKey||classification.migrationId!==migration.migrationId||
     classification.evidenceDigest!==migration.evidenceDigest||classification.disposition!=='after-cutover'||
     !core.sameEvent(core.parseReceipt(classification.receipt,accountKey),expected))fail('frame-purchase-audit-conflict');
   }else if(audit.eventKey!==null)fail('frame-purchase-audit-conflict');
   return response(true,false,state,audit.payment);
  }
  // Existing server ownership remains owned. Never charge again to fabricate
  // a new-format receipt, including native-only historical purchases.
  if(pair||native.ownedFrames.includes(frameId))return response(true,true,state,null);
  if(native.pendingFrames.length!==0)fail('frame-native-payment-pending');
  const payment={earnedDiamonds:0,giftedDiamonds:0,managerDiamonds:0};
  if(isManager){
   if(managerBalance<cost)fail('frame-insufficient-diamonds');
   payment.managerDiamonds=cost;
  }else{
   if(state.balances.earnedDiamonds<cost&&giftedBalance<cost-state.balances.earnedDiamonds)fail('frame-insufficient-diamonds');
   payment.earnedDiamonds=Math.min(cost,state.balances.earnedDiamonds);
   payment.giftedDiamonds=cost-payment.earnedDiamonds;
  }
  let next=state,eventKey=null,eventReceipt=null;
  if(payment.earnedDiamonds>0){
   eventReceipt=core.parseReceipt({format:1,accountKey,source:'cosmetic-debit-v1',
    sourceId:`frame-purchase|${migration.migrationId}|${originalId}|${frameId}`,kind:'spend',
    delta:{points:0,coins:0,xp:0,earnedDiamonds:-payment.earnedDiamonds}},accountKey);
   eventKey=core.eventKey(eventReceipt);
   for(const p of [`deda_verified_progress/${accountKey}/events/${eventKey}`,
    `deda_progress_receipts/${accountKey}/events/frame_${eventKey}`,`${root}/classifications/${eventKey}`]){
    if(await tx.get(p)!==null)fail('frame-partial-purchase-conflict');
   }
   next=core.applyEvent(state,eventReceipt);
  }
  const createdAt=store.serverTimestamp();
  // Every source read and proof check precedes the first staged write. Only
  // this transaction can create payment, ownership, event and current state.
  if(eventReceipt){
   const receiptId=`frame_${eventKey}`;
   tx.set(`deda_progress_receipts/${accountKey}/events/${receiptId}`,eventReceipt);
   tx.set(`${root}/classifications/${eventKey}`,{format:1,accountKey,migrationId:migration.migrationId,
    evidenceDigest:migration.evidenceDigest,disposition:'after-cutover',receipt:eventReceipt});
   tx.set(`deda_verified_progress/${accountKey}/events/${eventKey}`,{format:1,accountKey,eventKey,
    receipt:eventReceipt,receiptId,appliedVersion:next.version,afterBalances:next.balances,createdAt});
   tx.set(`deda_verified_progress/${accountKey}`,{...next});
  }
  if(payment.giftedDiamonds>0)tx.set(giftPath,{...gift,balance:giftedBalance-payment.giftedDiamonds,updatedAt:createdAt});
  if(payment.managerDiamonds>0)tx.set(gmPath,{...gm,balance:managerBalance-cost,updatedAt:createdAt});
  tx.set(receiptPath,{publicId:originalId,frameId,kind:'lab_frame',cost,createdAt});
  tx.set(ownershipPath,{publicId:originalId,frameId,receiptId:`${originalId}_${frameId}`,createdAt});
  tx.set(nativePath,{...native,ownedFrames:[...native.ownedFrames,frameId],updatedAt:createdAt});
  tx.set(auditPath,{format:1,accountKey,migrationId:migration.migrationId,evidenceDigest:migration.evidenceDigest,
   originalId,frameId,cost,payment,progressVersion:next.version,eventKey,executedByUid:actor.uid,createdAt});
  return response(false,false,next,payment,giftedBalance-payment.giftedDiamonds,
   isManager?managerBalance-payment.managerDiamonds:null);
 });
}
async function readReviewedPurchaseBalanceForOwnerSession(options){
 if(!options||typeof options!=='object'||Array.isArray(options)||Object.keys(options).length!==3||
  !['store','auth','idToken'].every(k=>Object.hasOwn(options,k)))fail('invalid-reviewed-balance-request');
 const {store,auth,idToken}=options;
 if(!store||typeof store.runTransaction!=='function'||typeof store.readOwnerSession!=='function'||
  !auth||typeof auth.verifyIdToken!=='function'||typeof idToken!=='string'||!idToken.length)fail('invalid-reviewed-frame-dependencies');
 return withVerifiedOwnerSession(options,async(tx,accountKey,actor)=>{
  const context=await loadMigratedContext(tx,accountKey),activation=await requireReviewedActivation(tx,context);
  const fence=await tx.get(`${context.root}/fences/${activation.legacyFenceId}`),originalId=fence.originalId;
  if(typeof originalId!=='string'||!/^@DEDA-[A-Z0-9]{6}$/.test(originalId))fail('frame-canonical-owner-required');
  const user=await tx.get(`users/${actor.uid}`),route=await tx.get(`deda_share_ids/${originalId}`);
  if(user?.sharePersonalId!==originalId||!route||route.publicId!==originalId||route.active!==true||route.kind!=='personal'||
   typeof route.ownerUid!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(route.ownerUid))fail('frame-canonical-owner-required');
  if((await tx.get(`users/${route.ownerUid}`))?.accountKey!==accountKey)fail('frame-canonical-owner-required');
  const gift=await tx.get(`deda_diamond_gift_balances/${originalId}`),access=await tx.get(`admin_entry_access/${accountKey}`);
  const giftedBalance=gift===null?0:balance(gift.balance);
  if(gift!==null&&gift.publicId!==originalId)fail('frame-invalid-wallet');
  let managerBalance=null;
  if(gateway(access,accountKey)){
   const gm=await tx.get(`deda_gm_personal_diamond_wallets/${accountKey}`);
   if(!gm||gm.accountKey!==accountKey||gm.initialBalance!==1000000)fail('frame-manager-wallet-unavailable');
   managerBalance=balance(gm.balance);
  }
  const purchasableBalance=managerBalance??balance(context.state.balances.earnedDiamonds+giftedBalance);
  return Object.freeze({state:context.state,originalId,giftedBalance,managerBalance,purchasableBalance});
 });
}
module.exports={purchaseReviewedFrameForOwnerSession,readReviewedPurchaseBalanceForOwnerSession};
