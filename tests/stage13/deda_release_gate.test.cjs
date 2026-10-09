"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  REQUIRED, BLOCKERS, SLOT_IDS, inspectSourceBoundaries, report,
} = require("../../scripts/deda_stage13_release_gate.cjs");

const root = path.resolve(__dirname, "../..");

function sources() {
  const out = {};
  for (const [key, name] of Object.entries(REQUIRED)) {
    out[key] = fs.readFileSync(path.join(root, name), "utf8");
  }
  return out;
}

test("Repository safety boundaries are intact across twelve stages", () => {
  const result = report(root);
  assert.equal(result.auditedFiles, 13);
  assert.equal(result.immutableSlots, 8);
  assert.equal(result.sourceGuardStatus, "passed",
      JSON.stringify(result.sourceGuardFailures));
  assert.deepEqual(result.sourceGuardFailures, []);
});

test("Never conflate source-code checks with a green-light for production", () => {
  const result = report(root);
  assert.equal(result.productionRolloutStatus, "blocked");
  assert.equal(result.productionDeployApproved, false);
  assert.ok(result.blockers.length >= 10);
  assert.ok(BLOCKERS.includes("owner-has-not-approved-production-rollout"));
  assert.equal(result.evidenceScope, "repository-files-only;not-live-firebase");
});

test("Trusted publisher is still config-only and unexported", () => {
  const s = sources();
  for (const mod of [
    "deda_daily_task_publisher",
    "deda_daily_task_restore",
    "deda_daily_task_restore_callable",
    "deda_daily_reward_shadow_ledger",
    "deda_daily_task_share_verifier",
    "deda_daily_login_seasonal_shadow",
  ]) assert.ok(!s.index.includes(mod));
  assert.ok(s.pub.includes("rewardsEnabled: false"));
});

test("Reject silently connecting a shadow-money module to real functions", () => {
  const src = sources();
  const modified = {...src, index: src.index +
    '\nrequire("./deda_daily_reward_shadow_ledger");\n'};
  assert.ok(inspectSourceBoundaries(modified)
      .includes("unexpected-production-export-deda_daily_reward_shadow_ledger"));
});

test("Reject switching config publication to real payouts", () => {
  const src = sources();
  const altered = {...src, pub: src.pub.replace(
      "rewardsEnabled: false", "rewardsEnabled: true")};
  assert.ok(inspectSourceBoundaries(altered)
      .includes("config-publisher-must-not-enable-payments"));
});

test("Reject removing the emulator-only ledger protection", () => {
  const src = sources();
  const altered = {...src, reward: src.reward.replaceAll(
      "STAGE9_EMULATOR_ONLY_DO_NOT_PAY", "ALLOW_PRODUCTION")};
  assert.ok(inspectSourceBoundaries(altered)
      .includes("reward-ledger-must-fail-outside-emulator"));
});

test("Reject enabling direct preview payouts or changing old login points", () => {
  const src = sources();
  const altered = {...src,
    loginPolicy: src.loginPolicy.replace("canGrantRewards => false",
        "canGrantRewards => true"),
    main: src.main.replace("static const int pointsPerDailyLogin = 10;",
        "static const int pointsPerDailyLogin = 50;"),
  };
  const failures = inspectSourceBoundaries(altered);
  assert.ok(failures.includes("login-preview-payout-guard-missing"));
  assert.ok(failures.includes("legacy-login-points-unexpectedly-changed"));
});

test("Reject accidental conversion of unpublished tasks into a different slot", () => {
  const src = sources();
  const altered = {...src, slots: src.slots.replace(
      "'long_trip'", "'new_unreviewed_task'")};
  assert.ok(inspectSourceBoundaries(altered)
      .includes("task-slot-contract-missing-long_trip"));
  assert.equal(SLOT_IDS.length, 8);
  assert.ok(!SLOT_IDS.includes("daily_login"));
});

test("Reject a direct Firebase wallet or remote-save hook in manager preview", () => {
  const src = sources();
  const altered = {...src, loginUi: src.loginUi +
      "\n// FirebaseFunctions would be unsafe in this page\n"};
  assert.ok(inspectSourceBoundaries(altered)
      .includes("manager-preview-accidentally-wired-to-network-or-wallet"));
});

test("Reject missing App Check requirement in the future restore callable", () => {
  const src = sources();
  const altered = {...src, auth: src.auth.replaceAll(
      "enforceAppCheck: true", "enforceAppCheck: false")};
  assert.ok(inspectSourceBoundaries(altered)
      .includes("restore-adapter-appcheck-gate-missing"));
});

test("Reject incomplete source audit instead of falsely approving it", () => {
  const src = sources();
  delete src.rules;
  assert.ok(inspectSourceBoundaries(src).includes("missing-required-source"));
});
