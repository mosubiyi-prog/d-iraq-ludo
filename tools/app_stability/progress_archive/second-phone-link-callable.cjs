"use strict";
/**
 * PRIVATE QA-only callable ENTRYPOINT FACTORY; never exported by live
 * functions/index.js. Derives canonical account and old UID only on the
 * server from authenticated new-UID's Stage54 PIN proof and directory.
 * No client-supplied IDs, account numbers, XP, diamonds or inventory.
 * Emulator-only; original APK/rules remain unchanged.
 */
const {createHmac}=require("node:crypto");
const {linkSecondPhoneToCanonicalAccount}=
  require("./second-phone-account-link.cjs");
const PROJECT="demo-deda-restore-readiness";
const ACCOUNT=/^[0-9]{10,16}$/;
const UID=/^[A-Za-z0-9_-]{8,128}$/;
function emulatorOnly(){
 if(process.env.GCLOUD_PROJECT!==PROJECT||
    process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
    process.env.DEDA_RESTORE_AUDIT_EMULATOR_ONLY!=="true"||
    !process.env.FIREBASE_AUTH_EMULATOR_HOST||
    !process.env.FIREBASE_FUNCTIONS_EMULATOR_HOST||
    !/^[a-f0-9]{64}$/.test(process.env.DEDA_RESTORE_AUDIT_LINK_KEY_HEX||""))
   throw Error("DEDA_SECOND_PHONE_CALLABLE_REFUSE_PRODUCTION");
}
function createSecondPhoneLinkCallable({onCall,HttpsError,db,auth,serverTimestamp}={}){
 if(typeof onCall!=="function"||typeof HttpsError!=="function"||
    !db||typeof db.doc!=="function"||typeof db.collection!=="function"||
    typeof db.runTransaction!=="function"||
    !auth||typeof auth.verifyIdToken!=="function"||typeof auth.getUser!=="function"||
    typeof serverTimestamp!=="function")
   throw Error("DEDA_SECOND_PHONE_CALLABLE_BAD_DEPENDENCIES");
 return onCall({enforceAppCheck:false,timeoutSeconds:30,memory:"256MiB"},
  async request=>{
   emulatorOnly();
   const deny=()=>{throw new HttpsError("permission-denied","private-account-link-denied");};
   const unavailable=()=>{throw new HttpsError("unavailable","private-account-link-unavailable");};
   // Real Functions callable auth verifier populates this from the ID token;
   // the raw bearer is separately reverified with Admin SDK (revocation check).
   const uid=request?.auth?.uid;
   if(!UID.test(uid||"")||
      request?.auth?.token?.firebase?.sign_in_provider!=="anonymous"||
      !request?.data||typeof request.data!=="object"||
      Array.isArray(request.data)||Object.keys(request.data).length!==0)
     deny();
   const header=request?.rawRequest?.headers?.authorization;
   const match=typeof header==="string"?/^Bearer ([A-Za-z0-9._-]{16,8192})$/.exec(header):null;
   if(!match)deny();
   const idToken=match[1];
   let token,user;
   try{
     token=await auth.verifyIdToken(idToken,true);
     user=await auth.getUser(uid);
   }catch(_){deny();}
   if(token?.uid!==uid||token?.firebase?.sign_in_provider!=="anonymous"||
      user?.uid!==uid||user.disabled===true||!!user.email||
      user.providerData?.length>0)deny();
   let accountKey,oldUid;
   try{
     const bindingSnap=await db.doc("deda_stage54_private_account_bindings/"+uid).get();
     const binding=bindingSnap.exists?bindingSnap.data():null;
     accountKey=binding?.accountKey;
     if(!ACCOUNT.test(accountKey||"")||binding.uid!==uid||
        binding.authProvider!=="anonymous"||
        binding.state!=="LOCAL_VERIFIED_HOLD_ONLY"||
        binding.emulatorOnly!==true||binding.canMigrate!==false||
        binding.canGrant!==false)deny();
     const dirSnap=await db.doc("deda_account_directory/"+accountKey).get();
     const directory=dirSnap.exists?dirSnap.data():null;
     oldUid=directory?.createdUid;
     if(!UID.test(oldUid||"")||oldUid===uid||
        directory.accountKey!==accountKey||directory.active!==true)deny();
   }catch(e){
     if(e instanceof HttpsError)throw e;
     unavailable();
   }
   const linkId=createHmac("sha256",
     Buffer.from(process.env.DEDA_RESTORE_AUDIT_LINK_KEY_HEX,"hex"))
     .update(JSON.stringify(["deda-readonly-link-v1",accountKey,oldUid,uid]))
     .digest("hex");
   // All transactional reads happen before the sole permitted account-link
   // write. This is a link pointer, not restoration or league authorization.
   const store={
     serverTimestamp,
     runTransaction: action=>db.runTransaction(tx=>action({
       get:async path=>{
         const s=await tx.get(db.doc(path));
         return s.exists?s.data():null;
       },
       list:async(path,{limit})=>{
         if(!/^deda_verified_progress\/[0-9]{10,16}\/events$/.test(path)||
            !Number.isInteger(limit)||limit<1||limit>256)
           throw Error("REFUSED_COLLECTION_QUERY");
         const q=db.collection(path).orderBy("appliedVersion","asc").limit(limit);
         const rows=await tx.get(q);
         return rows.docs.map(d=>({id:d.id,data:d.data()}));
       },
       set:(path,doc)=>{
         if(path!=="deda_private_second_phone_links/"+uid)
           throw Error("REFUSED_PRODUCTION_OR_WALLET_WRITE");
         tx.set(db.doc(path),doc);
       },
     }),{maxAttempts:3}),
   };
   try{
     const linked=await linkSecondPhoneToCanonicalAccount({
       store,auth,idToken,accountKey,oldUid,newUid:uid,linkId,
     });
     return Object.freeze({status:linked.status,replayed:linked.replayed,
       emulatorOnly:true,verifiedProgress:linked.verifiedProgress,
       canRestoreFinancialBalances:false,
       canCreditXp:false,canCreditDiamonds:false,
       canRestoreFrames:false,canRestorePremiumId:false,
       canIssueLeagueGift:false,productionReady:false});
   }catch(e){
     if(e instanceof HttpsError)throw e;
     // Never disclose account, UID, PIN, receipt details or held balances.
     unavailable();
   }
  });
}
module.exports={createSecondPhoneLinkCallable};
