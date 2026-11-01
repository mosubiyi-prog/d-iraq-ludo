"use strict";
// Separately staged, HOLD-only callable. Not a production login cutover.
const {onCall,HttpsError}=require("firebase-functions/v2/https");
const {defineSecret}=require("firebase-functions/params");
const {getAuth}=require("firebase-admin/auth");
const {getFirestore}=require("firebase-admin/firestore");
const {PinDenied}=require("./deda_secure_pin_gate_core");
const {CanonicalDenied,canonicalOriginalHold}=
    require("./deda_canonical_account_proof_core");
const rateSecret=defineSecret("DEDA_ACCOUNT_PIN_RATE_KEY");

function makeCallableCanonicalOriginalHold() {
  return onCall({enforceAppCheck:true,secrets:[rateSecret],
    timeoutSeconds:30,memory:"256MiB"},async request=>{
    try {
      return await canonicalOriginalHold({request,db:getFirestore(),
        auth:getAuth(),secret:rateSecret.value()});
    } catch(e) {
      if(e instanceof PinDenied || e instanceof CanonicalDenied)
        throw new HttpsError("permission-denied","identity-preflight-denied");
      if(e?.message==="SECURE_PIN_GATE_CONFIG_MISSING")
        throw new HttpsError("failed-precondition","identity-service-not-configured");
      console.error("DEDA_CANONICAL_HOLD_UNAVAILABLE");
      throw new HttpsError("unavailable","identity-service-unavailable");
    }
  });
}
module.exports={makeCallableCanonicalOriginalHold};
