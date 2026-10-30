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
const {TaskXpHold} =
  require("./deda_weekly_verified_xp_mirror_NOT_EXPORTED.js");
const {processProof} =
  require("./deda_weekly_100396_task_xp_trigger_core.js");
const ACTION_KEY=defineSecret("DEDA_WEEKLY_ACTION_PROOF_HMAC_KEY");

function makeTrigger(){
 return onDocumentCreated({
  document:"deda_weekly_server_action_proofs/{eventKey}",
  secrets:[ACTION_KEY],
  retry:true,
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
   // Permanent identity/proof denials should not enter a retry loop.
   // Transient Firestore failures retry safely via event/score locks.
   if(e instanceof TaskXpHold)return;
   throw e;
  }
 });
}
module.exports={processProof,makeTrigger};
