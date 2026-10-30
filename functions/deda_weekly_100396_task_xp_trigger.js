"use strict";
/**
 * DEDA 100396: connect the independent proof of an ALREADY-APPLIED XP
 * receipt to a once-only weekly tally. This is an internal Firestore trigger,
 * never a client callable. It cannot mint a task, XP, or monetary prize.
 * Disabled unless the owner explicitly enables a reviewed server config.
 */
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {defineSecret} = require("firebase-functions/params");
const {getFirestore} = require("firebase-admin/firestore");
const {mirrorVerifiedTaskXp, TaskXpHold} =
  require("./deda_weekly_verified_xp_mirror_NOT_EXPORTED.js");

const ACTION_KEY=defineSecret("DEDA_WEEKLY_ACTION_PROOF_HMAC_KEY");
const ACCOUNT=/^[0-9]{10,16}$/;
const EVENT=/^[0-9a-f]{64}$/;

async function processProof({
 db, proof, eventKey, secret, nowMs=Date.now(),
}){
 if(!proof || proof.productionApproved!==true ||
    proof.issuer!=="deda_server_verified_original_action_v1")
  return {status:"UNAPPROVED_PROOF_IGNORED", counted:false};
 if(!ACCOUNT.test(proof.accountKey||"") ||
    !EVENT.test(eventKey||"") ||
    proof.eventKey!==eventKey)
  throw new TaskXpHold("INVALID_PROOF_DOCUMENT");
 // Only a separately reviewed owner-enabled, server-only calendar
 // authorizes competition scoring. This MUST NOT be writable by clients.
 const configSnap=await db.doc("deda_weekly_verified_calendar/active").get();
 const config=configSnap.exists?configSnap.data():null;
 if(config?.enabled!==true || config?.publisherApproved!==true ||
    config?.allowLocalTaskBooleanProofs!==false ||
    config?.allowClientMintedXp!==false ||
    !Number.isSafeInteger(config.firstOpenMs) ||
    config.firstOpenMs<=0)
  return {status:"OWNER_CALENDAR_NOT_ENABLED", counted:false};
 return mirrorVerifiedTaskXp({
  db, accountKey:proof.accountKey,eventKey,secret,
  firstOpenMs:config.firstOpenMs,nowMs,
 });
}
function makeTrigger(){
 return onDocumentCreated({
  document:"deda_weekly_server_action_proofs/{eventKey}",
  secrets:[ACTION_KEY],
  retry:false,
 },async event=>{
  const proof=event.data?.data();
  if(!proof)return;
  try{
   await processProof({
    db:getFirestore(),proof,eventKey:event.params.eventKey,
    secret:Buffer.from(ACTION_KEY.value(),"utf8"),
   });
  }catch(e){
   // A malformed or unsupported proof is a hold, not a partial payout.
   // Admin can inspect event status; never leak accountKey or phone.
   console.error("DEDA_WEEKLY_APPLIED_XP_MIRROR_HELD",
      e instanceof TaskXpHold ? e.name : "backend-unavailable");
   throw e;
  }
 });
}
module.exports={processProof,makeTrigger};
