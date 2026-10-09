"use strict";

/**
 * Stage 13 - OFFLINE-ONLY release audit. Not a Cloud Function.
 * This script checks CODE in a checkout, not the deployed Firebase project.
 * Its status is deliberately BLOCKED until real rollout prerequisites can be
 * verified independently. No caller-supplied true/false flags can approve it.
 */
const fs = require("node:fs");
const path = require("node:path");

const REQUIRED = Object.freeze({
  index: "functions/index.js",
  main: "lib/main.dart",
  admin: "lib/deda_admin_task_management_page.dart",
  pub: "functions/deda_daily_task_publisher.js",
  restore: "functions/deda_daily_task_restore.js",
  auth: "functions/deda_daily_task_restore_callable.js",
  reward: "functions/deda_daily_reward_shadow_ledger.js",
  verify: "functions/deda_daily_task_share_verifier.js",
  seasonal: "functions/deda_daily_login_seasonal_shadow.js",
  loginUi: "lib/deda_daily_login_offer_preview_page.dart",
  loginPolicy: "lib/deda_daily_login_offer_preview_policy.dart",
  rules: "firestore.rules",
  slots: "lib/deda_daily_task_slots.dart",
});

const SLOT_IDS = Object.freeze([
  "share_personal_location",
  "open_map",
  "share_registered_place",
  "open_saved_place",
  "open_received_place",
  "review_added_place",
  "traffic_skills",
  "long_trip",
]);

const BLOCKERS = Object.freeze([
  "live-firestore-rules-not-independently-verified",
  "production-app-check-not-device-verified",
  "trusted-publisher-scheduler-not-deployed",
  "manager-restore-and-seasonal-callables-not-deployed",
  "real-user-action-proof-not-complete-for-all-tasks",
  "server-wallet-points-coins-diamonds-not-integrated",
  "legacy-local-points-migration-and-deduplication-not-tested",
  "daily-login-server-claim-not-implemented",
  "admin-preview-is-not-a-live-schedule-or-claim",
  "end-to-end-android-and-tablet-tests-not-complete",
  "owner-has-not-approved-production-rollout",
]);

function loadSources(root) {
  const out = {};
  for (const [key, relative] of Object.entries(REQUIRED)) {
    const file = path.join(root, relative);
    out[key] = fs.readFileSync(file, "utf8");
  }
  return out;
}

function inspectSourceBoundaries(s) {
  const failures = [];
  function demand(value, name) {
    if (!value) failures.push(name);
  }
  const all = Object.keys(REQUIRED).every(
      (key) => typeof s[key] === "string" && s[key].length > 30);
  demand(all, "missing-required-source");
  if (!all) return failures;

  // Guard against accidentally exporting or wiring currently unreviewed code.
  for (const forbidden of [
    "deda_daily_task_publisher",
    "deda_daily_task_restore",
    "deda_daily_task_restore_callable",
    "deda_daily_task_share_verifier",
    "deda_daily_reward_shadow_ledger",
    "deda_daily_login_seasonal_shadow",
  ]) {
    demand(!s.index.includes(forbidden), "unexpected-production-export-" + forbidden);
  }
  demand(s.pub.includes("rewardsEnabled: false"),
      "config-publisher-must-not-enable-payments");
  demand(s.pub.includes("disabled_until_verified_server_ledger"),
      "publisher-claim-mode-must-be-disabled");
  demand(s.reward.includes("STAGE9_EMULATOR_ONLY_DO_NOT_PAY"),
      "reward-ledger-must-fail-outside-emulator");
  demand(s.verify.includes("STAGE10_EMULATOR_ONLY_DO_NOT_PAY"),
      "share-verifier-must-fail-outside-emulator");
  demand(s.seasonal.includes("STAGE11_EMULATOR_ONLY_NO_LIVE_PAYOUT"),
      "seasonal-policy-must-fail-outside-emulator");
  demand(s.auth.includes("enforceAppCheck: true"),
      "restore-adapter-appcheck-gate-missing");
  demand(s.main.includes("static const int pointsPerDailyLogin = 10;"),
      "legacy-login-points-unexpectedly-changed");
  demand(s.loginPolicy.includes("canGrantRewards => false"),
      "login-preview-payout-guard-missing");
  demand(!s.loginUi.includes("FirebaseFirestore") &&
         !s.loginUi.includes("FirebaseFunctions") &&
         !s.loginUi.includes("claimDailyLoginReward("),
      "manager-preview-accidentally-wired-to-network-or-wallet");
  demand(s.rules.includes("match /deda_daily_published_task_slots/{slotId}") &&
         s.rules.includes("allow create, update, delete: if false;"),
      "public-task-client-write-guard-not-found");
  demand(s.rules.includes("match /deda_daily_task_publication_history/"),
      "publication-history-private-guard-missing");
  for (const id of SLOT_IDS) {
    demand(
        s.pub.includes("\n  " + id + ":") &&
        s.slots.includes("id: '" + id + "'") &&
        s.slots.includes("action: '" + id + "'"),
        "task-slot-contract-missing-" + id);
  }
  demand(s.slots.includes("static const int regularLoginPoints = 10;"),
      "daily-login-reference-mismatch");
  return failures;
}

function report(root) {
  const issues = inspectSourceBoundaries(loadSources(root));
  return {
    auditedFiles: Object.keys(REQUIRED).length,
    immutableSlots: SLOT_IDS.length,
    sourceGuardStatus: issues.length === 0 ? "passed" : "failed",
    sourceGuardFailures: issues,
    // This is a readiness barrier, not an endorsement to publish.
    productionRolloutStatus: "blocked",
    productionDeployApproved: false,
    blockers: [...BLOCKERS],
    evidenceScope: "repository-files-only;not-live-firebase",
  };
}

if (require.main === module) {
  const result = report(path.resolve(__dirname, ".."));
  process.stdout.write(JSON.stringify(result, null, 2) + "\n");
  if (result.sourceGuardFailures.length) process.exitCode = 1;
}

module.exports = {REQUIRED, SLOT_IDS, BLOCKERS, inspectSourceBoundaries, report};
