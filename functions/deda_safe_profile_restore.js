"use strict";
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore} = require("firebase-admin/firestore");
const {recoverSafeProfile, RecoveryHold} =
  require("./deda_safe_profile_restore_core");

exports.dedaSafeProfileRestoreV1 = onCall({
  enforceAppCheck: true, timeoutSeconds: 30, memory: "256MiB",
}, async (request) => {
  try {
    return await recoverSafeProfile({
      request, db: getFirestore(), auth: getAuth(),
    });
  } catch (error) {
    if (error instanceof RecoveryHold) {
      throw new HttpsError("permission-denied",
        "recovery-identity-or-source-unverified");
    }
    // Never leak account key, PIN, phone, balances or UID in failures.
    console.error("DEDA_SAFE_PROFILE_RESTORE_UNAVAILABLE");
    throw new HttpsError("unavailable", "recovery-profile-unavailable");
  }
});
