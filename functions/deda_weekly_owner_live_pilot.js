"use strict";
const {onCall,HttpsError}=require("firebase-functions/v2/https");
const {getAuth}=require("firebase-admin/auth");
const {getFirestore}=require("firebase-admin/firestore");
const {defineSecret}=require("firebase-functions/params");
const {claim,standings}=require("./deda_weekly_owner_live_pilot_core");
const privateKey=defineSecret("DEDA_WEEKLY_OWNER_PILOT_READ_KEY");
function errorToCallable(e){
 if(e&&e.publicCode){
  throw new HttpsError("failed-precondition",
   "owner-weekly-pilot-"+e.publicCode.toLowerCase());
 }
 console.error("DEDA_OWNER_WEEKLY_PILOT_BACKEND_ERROR");
 throw new HttpsError("unavailable","owner-weekly-pilot-unavailable");
}
exports.dedaWeeklyOwnerPilotClaimV1=onCall({
 enforceAppCheck:true,memory:"256MiB",timeoutSeconds:30,
},async request=>{
 try{return await claim({db:getFirestore(),auth:getAuth(),request});}
 catch(e){errorToCallable(e);}
});
exports.dedaWeeklyOwnerPilotStandingsV1=onCall({
 enforceAppCheck:true,memory:"256MiB",timeoutSeconds:30,
 secrets:[privateKey],
},async request=>{
 try{return await standings({
  db:getFirestore(),auth:getAuth(),request,secret:privateKey.value(),
 });}catch(e){errorToCallable(e);}
});
