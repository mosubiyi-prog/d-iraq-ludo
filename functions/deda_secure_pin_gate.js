"use strict";
// New opt-in backend endpoint. App/Rules cutover is intentionally a separate,
// owner-reviewed stage so installed legacy APKs cannot lose their accounts.
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore} = require("firebase-admin/firestore");
const {securePinPreflight, PinDenied} = require("./deda_secure_pin_gate_core");

const pinRateSecret = defineSecret("DEDA_ACCOUNT_PIN_RATE_KEY");
function makeCallableSecurePinGate() {
  return onCall({
    enforceAppCheck: true,
    secrets: [pinRateSecret],
    timeoutSeconds: 30,
    memory: "256MiB",
  }, async (request) => {
    try {
      return await securePinPreflight({
        request, db: getFirestore(), auth: getAuth(),
        secret: pinRateSecret.value(),
      });
    } catch (error) {
      if (error instanceof PinDenied) {
        throw new HttpsError("permission-denied", "identity-preflight-denied");
      }
      if (error?.message === "SECURE_PIN_GATE_CONFIG_MISSING") {
        throw new HttpsError("failed-precondition", "identity-service-not-configured");
      }
      // Deliberately omit account key, PIN, identifiers and raw error details.
      console.error("DEDA_SECURE_PIN_GATE_UNAVAILABLE");
      throw new HttpsError("unavailable", "identity-preflight-unavailable");
    }
  });
}
module.exports = {makeCallableSecurePinGate};
