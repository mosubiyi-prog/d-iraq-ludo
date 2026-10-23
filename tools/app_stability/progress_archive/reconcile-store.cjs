'use strict';
// UNDEPLOYED trusted-worker prototype. NOT a callable or client balance API.
// Receipts must be produced by a separately verified server authority. This
// module never interprets archives/client amounts as verified receipts.
const core=require('./reconcile-core.cjs');
function fail(code){throw Object.assign(new Error(code),{code});}
function receiptPath(account,id){
  core.account(account);
  if(typeof id!=='string'||!/^[A-Za-z0-9_-]{20,80}$/.test(id))fail('invalid-receipt-id');
  return `deda_progress_receipts/${account}/events/${id}`;
}
async function reconcileVerifiedReceipt({store,accountKey,receiptId}){
  const path=receiptPath(accountKey,receiptId);
  return store.runTransaction(async tx=>{
    const raw=await tx.get(path);
    if(raw===null)fail('verified-receipt-missing');
    const receipt=core.parseReceipt(raw,accountKey);
    const key=core.eventKey(receipt);
    const statePath=`deda_verified_progress/${accountKey}`;
    const eventPath=`${statePath}/events/${key}`;
    const applied=await tx.get(eventPath);
    const state=await tx.get(statePath);
    if(applied!==null){
      if(applied.eventKey!==key||!core.sameEvent(core.parseReceipt(applied.receipt,accountKey),receipt))fail('source-event-conflict');
      const current=core.parseState(state,accountKey);
      if(!Number.isSafeInteger(applied.appliedVersion)||applied.appliedVersion<1||applied.appliedVersion>current.version)fail('invalid-applied-version');
      // Return CURRENT state: an older award replay must not resurrect its
      // historical after-balance after later spending.
      return Object.freeze({replayed:true,state:current});
    }
    const next=core.applyEvent(state,receipt);
    // All reads occur above. Both projection and immutable applied marker are
    // committed together. A retried transaction recalculates from live state.
    tx.set(eventPath,{format:1,accountKey,eventKey:key,receipt,receiptId,
      appliedVersion:next.version,afterBalances:next.balances,createdAt:store.serverTimestamp()});
    tx.set(statePath,{...next});
    return Object.freeze({replayed:false,state:next});
  });
}
// A server bootstrap may wrap its Admin Firestore instance here. Not invoked
// by functions/index.js; tests provide a security-disabled EMULATOR context.
class DedaTrustedProgressTransactionStore{
  constructor({db,serverTimestamp}){this.db=db;this.serverTimestamp=serverTimestamp;}
  runTransaction(action){
    return this.db.runTransaction(async transaction=>action({
      get:async path=>{const snap=await transaction.get(this.db.doc(path));return snap.exists?snap.data():null;},
      set:(path,data)=>transaction.set(this.db.doc(path),data),
    }));
  }
}
module.exports={reconcileVerifiedReceipt,DedaTrustedProgressTransactionStore};
