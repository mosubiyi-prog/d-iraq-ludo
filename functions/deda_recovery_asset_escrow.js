"use strict";
// Unreleased opt-in legacy asset evidence ESCROW. Not a wallet restore endpoint.
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore} = require("firebase-admin/firestore");
const {captureLegacyAccountEscrow, RecoveryEscrowHold} =
  require("./deda_recovery_asset_escrow_core");

const escrowSecret = defineSecret("DEDA_RECOVERY_ESCROW_HMAC_KEY");
exports.dedaLegacyAssetEscrowV1 = onCall({
  enforceAppCheck: true,
  secrets: [escrowSecret],
  timeoutSeconds: 30,
  memory: "256MiB",
}, async (request) => {
  try {
    return await captureLegacyAccountEscrow({
      request, db: getFirestore(), auth: getAuth(),
      secret: escrowSecret.value(),
    });
  } catch (error) {
    if (error instanceof RecoveryEscrowHold) {
      throw new HttpsError("failed-precondition",
        "legacy-recovery-evidence-requires-review");
    }
    // No PIN, phone, accountKey, premium IDs or balance values in logs.
    console.error("DEDA_RECOVERY_ESCROW_UNAVAILABLE");
    throw new HttpsError("unavailable", "legacy-recovery-escrow-unavailable");
  }
});
