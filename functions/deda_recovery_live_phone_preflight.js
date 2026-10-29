"use strict";
/**
 * LIVE Firebase Auth + App Check recovery ownership PRE-FLIGHT.
 *
 * Intentionally read-only: NEVER transfers ownership, reads financial data,
 * changes PINs, grants XP/gems/IDs or touches existing sessions. Verified
 * possession of a phone number alone cannot authorize a financial cutover.
 * This is a production-side integration point, not the recovery operation.
 */
function verifiedIraqiPhone(value) {
  if (typeof value !== "string" || !/^\+9647[0-9]{9}$/.test(value)) return null;
  const local="0"+value.slice(4);
  const international=value.slice(1);
  return {local,international};
}
function createRecoveryPhonePreflight({onCall,HttpsError,auth,db}) {
  if (typeof onCall!=="function"||typeof HttpsError!=="function"||
      !auth||typeof auth.verifyIdToken!=="function"||
      typeof auth.getUser!=="function"||!db||typeof db.doc!=="function")
    throw Error("DEDA_RECOVERY_PREFLIGHT_BAD_DEPENDENCIES");
  return onCall({
    enforceAppCheck:true,consumeAppCheckToken:false,
    timeoutSeconds:25,memory:"256MiB",
  },async request=>{
    const deny=()=>{throw new HttpsError("permission-denied","verified-phone-required");};
    if(!request?.auth?.uid||!request.app?.appId||
       !request.data||typeof request.data!=="object"||
       Array.isArray(request.data)||Object.keys(request.data).length!==0)
      deny();
    const uid=request.auth.uid;
    let verified,record;
    try{
      // No caller-provided number, account key, original ID or wallet amount.
      // Phone number comes exclusively from revoked-checked Firebase Auth.
      const raw=request.rawRequest?.headers?.authorization;
      const m=typeof raw==="string"?
        /^Bearer ([A-Za-z0-9._-]{16,8192})$/.exec(raw):null;
      if(!m)deny();
      verified=await auth.verifyIdToken(m[1],true);
      if(!verified||verified.uid!==uid||!verified.phone_number)deny();
      record=await auth.getUser(uid);
      if(!record||record.uid!==uid||record.disabled===true||
         record.phoneNumber!==verified.phone_number)deny();
    }catch(e){
      if(e instanceof HttpsError)throw e;
      deny();
    }
    const phone=verifiedIraqiPhone(record.phoneNumber);
    if(!phone)deny();
    const keys=[phone.local,phone.international];
    let matches=[];
    try{
      const snapshots=await Promise.all(keys.map(key=>
        db.doc("deda_account_directory/"+key).get()));
      matches=snapshots.map((snap,i)=>({key:keys[i],snap}))
        .filter(({key,snap})=>snap.exists&&
          snap.data()?.active===true&&snap.data()?.accountKey===key);
    }catch(_){
      throw new HttpsError("unavailable","recovery-check-unavailable");
    }
    // Do NOT expose account numbers, profile, PIN, IDs, balances, rewards,
    // entitlement lists or a migration authorization to mobile client.
    return Object.freeze({
      format:1,verifiedPhone:true,appCheckVerified:true,
      accountState:matches.length===1?"candidate-found":
        matches.length>1?"requires-owner-review":"no-active-directory",
      canTransferAccount:false,canWriteWallet:false,
      canGrantAssets:false,canChangePin:false,canIssueLeagueRewards:false,
    });
  });
}
module.exports={verifiedIraqiPhone,createRecoveryPhonePreflight};
