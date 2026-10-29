"use strict";
// READ ONLY. No wallet / UID / ID / frame writes in this endpoint.
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore} = require("firebase-admin/firestore");
const {readReviewedRecovery, RecoveryReviewRequired} =
  require("./deda_recovery_verified_view_core");

const recoveryViewKey = defineSecret("DEDA_RECOVERY_VIEW_REVIEW_HMAC_KEY");
exports.dedaReviewedAccountRecoveryViewV1 = onCall({
  enforceAppCheck: true,
  secrets: [recoveryViewKey],
  timeoutSeconds: 30,
  memory: "256MiB",
}, async request => {
  try {
    return await readReviewedRecovery({
      request, auth: getAuth(), db: getFirestore(),
      secret: recoveryViewKey.value(),
    });
  } catch (error) {
    if (error instanceof RecoveryReviewRequired) {
      throw new HttpsError("failed-precondition", "recovery-needs-verification");
    }
    console.error("DEDA_RECOVERY_REVIEW_READ_UNAVAILABLE");
    throw new HttpsError("unavailable", "recovery-view-unavailable");
  }
});
