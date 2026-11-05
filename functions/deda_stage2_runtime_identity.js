"use strict";

/**
 * Stage2 recovery callables must run as their own dedicated, least-privileged
 * runtime identity. This identity was created by the DEDA project owner on
 * Google Cloud; it is NOT the privileged GitHub deployment service account.
 *
 * Binding an identity here does not grant it access to any Firestore, Auth,
 * KMS, or other resource. Those permissions must be reviewed separately.
 * Production is additionally OFF by default via deda_stage2_live_gate.js.
 */
const RUNTIME_ACCOUNT =
  "deda-recovery-runtime@deda-25b88.iam.gserviceaccount.com";

function recoveryCallableOptions(timeoutSeconds) {
  if (!Number.isInteger(timeoutSeconds) ||
      timeoutSeconds < 1 || timeoutSeconds > 60) {
    throw new TypeError("invalid-recovery-timeout");
  }
  return {
    enforceAppCheck: true,
    timeoutSeconds,
    serviceAccount: RUNTIME_ACCOUNT,
  };
}

module.exports = {RUNTIME_ACCOUNT, recoveryCallableOptions};
