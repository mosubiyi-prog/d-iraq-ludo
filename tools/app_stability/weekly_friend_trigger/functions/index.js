"use strict";
/** REAL original Firestore onUpdate transport, but LOCAL EMULATOR ONLY.
 * This is not imported by production functions/index.js.
 * No callable accepts client-provided fake before/after events.
 */
const {onDocumentUpdated}=require("firebase-functions/v2/firestore");
const {initializeApp}=require("firebase-admin/app");
const {getFirestore}=require("firebase-admin/firestore");
const {PROJECT,recordOriginalAcceptedFriendAction}=require(
  "../../../../functions/deda_weekly_original_friend_accepted_action_NOT_EXPORTED.js");
function hardStop(){
  if(process.env.GCLOUD_PROJECT!==PROJECT||
    process.env.DEDA_WEEKLY_FRIEND_TRIGGER_EMULATOR_ONLY!=="true"||
    process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
    process.env.FIREBASE_FUNCTIONS_EMULATOR_HOST!=="127.0.0.1:5001")
    throw Error("DEDA_FRIEND_EVENT_TRIGGER_ONLY_LOCAL_EMULATORS");
}
hardStop();
initializeApp({projectId:PROJECT});
exports.dedaPrivateOriginalFriendAcceptedOnUpdate=onDocumentUpdated({
 document:"deda_friendships/{relationId}",region:"us-central1",
 memory:"256MiB",timeoutSeconds:30,
},async event=>{
  hardStop();
  const before=event.data?.before?.data();
  const after=event.data?.after?.data();
  if(!before||!after||before.status!=="pending"||after.status!=="accepted")
    return;
  // Only Firestore's genuine before/after snapshots are accepted.
  const firstOpenMs=Number(process.env.DEDA_WEEKLY_FRIEND_FIRST_OPEN_MS);
  if(!Number.isSafeInteger(firstOpenMs)||firstOpenMs<=0)
    throw Error("DEDA_FRIEND_FIRST_OPEN_PRIVATE_QA_MISSING");
  const result=await recordOriginalAcceptedFriendAction({
    db:getFirestore(),relationId:event.params.relationId,before,after,
    firstOpenMs,serverNowMs:Date.now(),
  });
  console.info("PRIVATE_FRIEND_ACCEPTED_ACTION_ONLY",JSON.stringify({
    outcome:result.outcome,proofsAdded:result.proofsAdded,
    canCreditXp:false,canCreditLeague:false,canCreditDiamonds:false,
  }));
});
