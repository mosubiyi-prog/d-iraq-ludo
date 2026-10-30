"use strict";
const {onCall,HttpsError}=require("firebase-functions/v2/https");
const {defineSecret}=require("firebase-functions/params");
const {getAuth}=require("firebase-admin/auth");
const {getFirestore}=require("firebase-admin/firestore");
const {readWeeklyStandings,WeeklyHold}=
 require("./deda_weekly_100396_standings_reader_core");
const VIEW_KEY=defineSecret("DEDA_WEEKLY_PUBLIC_STANDINGS_HMAC_KEY");
exports.dedaWeeklyVerifiedStandingsV1=onCall({
 enforceAppCheck:true,secrets:[VIEW_KEY],timeoutSeconds:30,
 memory:"256MiB",
},async request=>{
 try{
  return await readWeeklyStandings({
   db:getFirestore(),auth:getAuth(),request,
   secret:Buffer.from(VIEW_KEY.value(),"utf8"),
  });
 }catch(error){
  if(error instanceof WeeklyHold)
   throw new HttpsError("failed-precondition",
    "weekly-verified-source-not-ready");
  console.error("DEDA_WEEKLY_STANDINGS_UNAVAILABLE");
  throw new HttpsError("unavailable","weekly-standings-unavailable");
 }
});
