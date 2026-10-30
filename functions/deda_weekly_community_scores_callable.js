"use strict";
/** Community task score endpoints. Source only. Separate owner-approved deploy.
 * No wallet, gem, level, or profile mutations; Auth & App Check required.
 */
const {onCall,HttpsError}=require("firebase-functions/v2/https");
const {getAuth}=require("firebase-admin/auth");
const {getFirestore}=require("firebase-admin/firestore");
const {claim,standings}=require("./deda_weekly_community_scores_core");
function forwardError(e){
  if(e?.publicCode){
    throw new HttpsError("failed-precondition",
      "community-weekly-"+e.publicCode.toLowerCase());
  }
  console.error("DEDA_COMMUNITY_WEEKLY_BACKEND_ERROR");
  throw new HttpsError("unavailable","community-weekly-unavailable");
}
exports.dedaWeeklyCommunityClaimV1=onCall({
  enforceAppCheck:true,memory:"256MiB",timeoutSeconds:30,
},async request=>{
  try{return await claim({db:getFirestore(),auth:getAuth(),request});}
  catch(e){forwardError(e);}
});
exports.dedaWeeklyCommunityStandingsV1=onCall({
  enforceAppCheck:true,memory:"256MiB",timeoutSeconds:30,
},async request=>{
  try{return await standings({db:getFirestore(),auth:getAuth(),request});}
  catch(e){forwardError(e);}
});
