'use strict';
// PRIVATE STEP2 / NOT_EXPORTED / NO_DEPLOY. Observes reviewed server receipts;
// a legacy phone's balance or snapshot is NEVER a trusted credit instruction.
const core=require('../tools/app_stability/progress_archive/reconcile-core.cjs');
const {loadMigratedContext}=require('../tools/app_stability/progress_archive/migration-gate.cjs');
const {requireReviewedActivation}=require('../tools/app_stability/progress_archive/reviewed-activation-proof.cjs');
const {withVerifiedOwnerSession}=require('../tools/app_stability/progress_archive/point-tier-session.cjs');
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{20,80}$/.test(v);
const original=v=>typeof v==='string'&&/^@DEDA-[A-Z0-9]{6}$/.test(v);
const fail=code=>{throw Object.assign(new Error(code),{code});};
function exact(value,fields,code){
 if(!value||typeof value!=='object'||Array.isArray(value)||
    Object.keys(value).length!==fields.length||
    !fields.every(k=>Object.hasOwn(value,k)))fail(code);
}
function sameBalances(a,b){return core.units.every(u=>a[u]===b[u]);}
/**
 * READ-ONLY transaction helper. Caller must ALREADY have verified owner
 * session, migration/activation and original ID inside THIS transaction.
 * Not callable from the app. Never guesses missing receipts as zero.
 */
async function inspectClassifiedReceipt({tx,accountKey,context,receiptId}){
 if(!tx||typeof tx.get!=='function'||typeof accountKey!=='string'||
    !/^[0-9]{8,16}$/.test(accountKey)||!id(receiptId)||
    context?.migration?.accountKey!==accountKey||
    context?.migration?.phase!=='cutover-complete')
   fail('step2-receipt-audit-scope-invalid');
 const migration=context.migration;
 const state=core.parseState(context.state,accountKey);
 if(migration.baselineEventKey!==state.initializedBy||
    !id(migration.migrationId)||!/^[a-f0-9]{64}$/.test(migration.evidenceDigest))
   fail('step2-baseline-not-proven');
 const raw=await tx.get('deda_progress_receipts/'+accountKey+'/events/'+receiptId);
 if(raw===null)fail('step2-verified-receipt-missing');
 const receipt=core.parseReceipt(raw,accountKey);
 if(receipt.kind==='baseline')fail('step2-baseline-receipt-not-replayable');
 const key=core.eventKey(receipt);
 const classification=await tx.get('deda_progress_migrations/'+accountKey+'/classifications/'+key);
 exact(classification,['format','accountKey','migrationId','evidenceDigest','disposition','receipt'],'step2-receipt-classification-missing');
 if(classification.format!==1||classification.accountKey!==accountKey||
    classification.migrationId!==migration.migrationId||
    classification.evidenceDigest!==migration.evidenceDigest||
    !['included-in-baseline','after-cutover'].includes(classification.disposition)||
    !core.sameEvent(core.parseReceipt(classification.receipt,accountKey),receipt))
   fail('step2-receipt-classification-conflict');
 const applied=await tx.get('deda_verified_progress/'+accountKey+'/events/'+key);
 let status;
 if(classification.disposition==='included-in-baseline'){
   if(applied!==null)fail('step2-included-receipt-was-applied-again');
   status='already-in-reviewed-baseline';
 }else if(applied===null){
   status='classified-but-not-applied';
 }else{
   exact(applied,['format','accountKey','eventKey','receipt','receiptId','appliedVersion',
       'afterBalances','createdAt'],'step2-applied-marker-invalid');
   if(applied.format!==1||applied.accountKey!==accountKey||
      applied.eventKey!==key||!id(applied.receiptId)||
      !Number.isSafeInteger(applied.appliedVersion)||applied.appliedVersion<2||
      applied.appliedVersion>state.version||
      !core.sameEvent(core.parseReceipt(applied.receipt,accountKey),receipt))
     fail('step2-applied-marker-conflict');
   const after=core.vector(applied.afterBalances);
   if(applied.appliedVersion===state.version&&
      !sameBalances(after,state.balances))fail('step2-applied-state-conflict');
   status='already-applied-once';
 }
 return Object.freeze({status,accountKey,eventKey:key,source:receipt.source,
   canCreateReceipt:false,canCreditDiamonds:false,canCreditPoints:false,
   canReapplySpend:false,canReissuePrizes:false,allowPhoneCutover:false});
}
/**
 * Gated pilot ONLY: does not replace the newer linked-password owner proof
 * needed by real 100434 two-phone recovery.
 */
async function previewReviewedReceiptForOwner({store,auth,idToken,receiptId}){
 if(!id(receiptId))fail('step2-invalid-receipt-id');
 return withVerifiedOwnerSession({store,auth,idToken},async(tx,accountKey,actor)=>{
   const context=await loadMigratedContext(tx,accountKey);
   const activation=await requireReviewedActivation(tx,context);
   const fence=await tx.get(context.root+'/fences/'+activation.legacyFenceId);
   const originalId=fence?.originalId;
   if(!original(originalId))fail('step2-original-owner-unproven');
   const route=await tx.get('deda_share_ids/'+originalId);
   const user=await tx.get('users/'+actor.uid);
   const oldUser=route?.ownerUid?await tx.get('users/'+route.ownerUid):null;
   if(!route||route.kind!=='personal'||route.publicId!==originalId||
      route.active!==true||!oldUser||oldUser.accountKey!==accountKey||
      oldUser.sharePersonalId!==originalId||!user||
      user.accountKey!==accountKey||user.sharePersonalId!==originalId)
     fail('step2-original-owner-unproven');
   return inspectClassifiedReceipt({tx,accountKey,context,receiptId});
 });
}
module.exports={inspectClassifiedReceipt,previewReviewedReceiptForOwner};
