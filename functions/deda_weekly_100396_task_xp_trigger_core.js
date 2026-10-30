"use strict";
const {mirrorVerifiedTaskXp,TaskXpHold}=
 require("./deda_weekly_verified_xp_mirror_NOT_EXPORTED.js");
const ACCOUNT=/^[0-9]{10,16}$/;
const EVENT=/^[0-9a-f]{64}$/;
/** One and only automatic XP->weekly score hook. No new XP is awarded. */
async function processProof({db,proof,eventKey,secret,nowMs=Date.now()}){
 if(!proof||proof.productionApproved!==true||
    proof.issuer!=="deda_server_verified_original_action_v1")
  return {status:"UNAPPROVED_PROOF_IGNORED",counted:false};
 if(!ACCOUNT.test(proof.accountKey||"")||
    !EVENT.test(eventKey||"")||proof.eventKey!==eventKey)
  throw new TaskXpHold("INVALID_PROOF_DOCUMENT");
 const configSnap=await db.doc("deda_weekly_verified_calendar/active").get();
 const config=configSnap.exists?configSnap.data():null;
 if(config?.enabled!==true || config?.publisherApproved!==true ||
    config?.allowLocalTaskBooleanProofs!==false ||
    config?.allowClientMintedXp!==false ||
    !Number.isSafeInteger(config.firstOpenMs)||
    config.firstOpenMs<=0)
  return {status:"OWNER_CALENDAR_NOT_ENABLED",counted:false};
 return mirrorVerifiedTaskXp({
  db,accountKey:proof.accountKey,eventKey,secret,
  firstOpenMs:config.firstOpenMs,nowMs,
 });
}
module.exports={processProof};
