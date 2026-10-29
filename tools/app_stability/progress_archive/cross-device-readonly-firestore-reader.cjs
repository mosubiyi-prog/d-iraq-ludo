"use strict";
/**
 * Private Firebase Admin SDK adapter: coherent, server-owned READ-ONLY
 * transaction for DEDA second-phone recovery preflight. Strictly synthetic
 * Firestore Emulator only. NEVER imported/exported by live Functions.
 *
 * A successful audit remains HOLD and MUST NOT grant/spend any amount.
 */
const PROJECT="demo-deda-restore-readiness";
const ROOT="deda_verified_progress";
const UID="[A-Za-z0-9_-]{8,128}";
const KEY="[0-9]{10,16}";
const docPattern=new RegExp("^(?:deda_account_directory/"+KEY+
  "|deda_account_profiles/"+KEY+"|users/"+UID+
  "|deda_stage54_private_account_bindings/"+UID+
  "|deda_progress_migrations/(?:"+KEY+
      "(?:/(?:settlements|activations|settlementReviews|fences)/[A-Za-z0-9_-]{20,80})?"+
      "|_policy/settings/verified-cutover-v1)"+
  "|deda_progress_receipts/"+KEY+"/events/[A-Za-z0-9_-]{20,80}"+
  "|deda_verified_progress/"+KEY+
     "(?:/events/[0-9a-f]{64})?)$");
const listPattern=new RegExp("^"+ROOT+"/"+KEY+"/events$");
function guard(){
 if(process.env.GCLOUD_PROJECT!==PROJECT||
    process.env.DEDA_RESTORE_AUDIT_EMULATOR_ONLY!=="true"||
    process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080")
   throw Error("DEDA_READ_ONLY_FIRESTORE_EMULATOR_REQUIRED");
}
function makeReadOnlyFirestoreReader(db){
 guard();
 if(!db||typeof db.doc!=="function"||
    typeof db.collection!=="function"||
    typeof db.runTransaction!=="function")
   throw Error("INVALID_FIRESTORE_ADMIN_ADAPTER");
 return Object.freeze({
   runReadOnlyTransaction:async action=>{
     guard(); // Re-check on each invocation, not just at construction.
     if(typeof action!=="function")throw Error("READONLY_ACTION_REQUIRED");
     return db.runTransaction(async transaction=>{
       const view=Object.freeze({
         get:async path=>{
           if(typeof path!=="string"||!docPattern.test(path))
             throw Error("DENIED_READONLY_DOCUMENT_PATH");
           const doc=await transaction.get(db.doc(path));
           return doc.exists?doc.data():null;
         },
         list:async(path,{limit}={})=>{
           if(typeof path!=="string"||!listPattern.test(path)||
              !Number.isInteger(limit)||limit<1||limit>256)
             throw Error("DENIED_READONLY_COLLECTION_QUERY");
           const q=db.collection(path).orderBy("appliedVersion","asc")
             .limit(limit);
           const snapshot=await transaction.get(q);
           return snapshot.docs.map(doc=>({id:doc.id,data:doc.data()}));
         },
       });
       // Transaction exposes no set/create/update/delete to audit code.
       return action(view);
     },{readOnly:true});
   },
 });
}
module.exports={makeReadOnlyFirestoreReader};
