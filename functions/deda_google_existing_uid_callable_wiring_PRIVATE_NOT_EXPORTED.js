"use strict";

// DEDA replacement-phone Google exact-UID callable — isolated server binding.
// This file is deliberately NOT imported by functions/index.js. It has NO
// deployed route, production Firebase effect, or package/build alteration.
//
// Later production release must independently approve the audited Android
// Play Integrity/AppCheck configuration, original Play app signing, exact
// Google Web OAuth audience, source/rules parity and two-phone QA.
const {createPrivateExistingGoogleCallable} = require(
  "./deda_google_existing_uid_token_exchange_PRIVATE_NOT_EXPORTED.js"
);
const PROD_PROJECT="deda-25b88";
const AUDIENCE=/^[0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$/;

function prepareExistingGoogleUidCallable({
  projectId,productionAudience,ownerApproved,
  onCall,HttpsError,auth,db,getJwks,now,
}) {
  // An OAuth client from the QA lab or another Firebase project must never
  // be trusted by the DEDA production account directory.
  if(projectId!==PROD_PROJECT || ownerApproved!==true ||
     typeof productionAudience!=="string" ||
     !AUDIENCE.test(productionAudience)) {
    throw Error("deda-google-existing-uid-backend-not-approved");
  }
  return createPrivateExistingGoogleCallable({
    onCall,HttpsError,auth,db,productionAudience,getJwks,now,
  });
}
module.exports={prepareExistingGoogleUidCallable};
