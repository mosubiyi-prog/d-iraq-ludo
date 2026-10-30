"use strict";
const {onCall,HttpsError}=require("firebase-functions/v2/https");
const {getAuth}=require("firebase-admin/auth");
const {getFirestore}=require("firebase-admin/firestore");
const {recordMonitoredTask,MonitorHold}=
  require("./deda_weekly_100396_observation_core.js");

// This is an owner-only QA observation signal, not an authoritative task proof.
exports.dedaWeeklyObserveTaskClaimQaV1=onCall({
  enforceAppCheck:true,timeoutSeconds:15,memory:"256MiB",
},async request=>{
  try{
    return await recordMonitoredTask({
      db:getFirestore(),auth:getAuth(),request,
    });
  }catch(e){
    if(e instanceof MonitorHold)
      throw new HttpsError("failed-precondition","weekly-qa-observation-not-ready");
    console.error("DEDA_WEEKLY_QA_OBSERVATION_UNAVAILABLE");
    throw new HttpsError("unavailable","weekly-qa-observation-unavailable");
  }
});
