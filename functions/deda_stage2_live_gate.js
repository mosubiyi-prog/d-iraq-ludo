"use strict";

/** DEDA 100436 step 2: server-only, default-deny production opt-in.
 * This is rollout configuration, NOT authentication evidence. Firebase Auth,
 * canonical account + UID, App Check, server rate limits, and Firestore Rules
 * still independently decide every request.
 *
 * No app flag, Git branch, or client-provided value can enable this.
 * Never deploy without an independently reviewed rule set and real device QA.
 */
const FEATURE_KEYS = Object.freeze({
  pinProof: "DEDA_STAGE2_LIVE_PIN_PROOF",
  deviceGrant: "DEDA_STAGE2_LIVE_DEVICE_GRANT",
  journal: "DEDA_STAGE2_LIVE_JOURNAL",
});
const REQUIRED = Object.freeze([
  "DEDA_STAGE2_LIVE_OWNER_APPROVED",
  "DEDA_STAGE2_LIVE_FIRESTORE_RULES_CONFIRMED",
  "DEDA_STAGE2_LIVE_SAME_UID_QA_PASSED",
]);
function stage2LiveGateEnabled(feature, env = process.env) {
  if (!Object.prototype.hasOwnProperty.call(FEATURE_KEYS, feature) ||
      !env || typeof env !== "object") return false;
  // Emulator tests are independently gated by their pre-existing flags.
  if (env.FUNCTIONS_EMULATOR === "true" ||
      env.FIREBASE_EMULATOR_HUB != null) return false;
  const project = env.GCLOUD_PROJECT || env.GOOGLE_CLOUD_PROJECT;
  if (typeof project !== "string" ||
      !/^[a-z][a-z0-9-]{4,29}[a-z0-9]$/.test(project) ||
      (env.GCLOUD_PROJECT != null && env.GOOGLE_CLOUD_PROJECT != null &&
       env.GCLOUD_PROJECT !== env.GOOGLE_CLOUD_PROJECT) ||
      env.DEDA_STAGE2_LIVE_TARGET_PROJECT !== project) return false;
  if (REQUIRED.some((name) => env[name] !== "1")) return false;
  return env[FEATURE_KEYS[feature]] === "1";
}
module.exports = {stage2LiveGateEnabled};
