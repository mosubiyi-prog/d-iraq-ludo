"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {stage2LiveGateEnabled} = require("../deda_stage2_live_gate.js");

const approved = Object.freeze({
  GCLOUD_PROJECT: "deda-private-stage2",
  DEDA_STAGE2_LIVE_TARGET_PROJECT: "deda-private-stage2",
  DEDA_STAGE2_LIVE_OWNER_APPROVED: "1",
  DEDA_STAGE2_LIVE_FIRESTORE_RULES_CONFIRMED: "1",
  DEDA_STAGE2_LIVE_SAME_UID_QA_PASSED: "1",
  DEDA_STAGE2_LIVE_PIN_PROOF: "1",
  DEDA_STAGE2_LIVE_DEVICE_GRANT: "1",
  DEDA_STAGE2_LIVE_JOURNAL: "1",
});

test("default denies every live recovery callable", () => {
  for (const key of ["pinProof", "deviceGrant", "journal"]) {
    assert.equal(stage2LiveGateEnabled(key, {}), false);
    assert.equal(stage2LiveGateEnabled(key, {GCLOUD_PROJECT: "deda-private-stage2"}), false);
  }
});
test("requires explicit owner, rules and same-UID QA approval independently", () => {
  for (const name of [
    "DEDA_STAGE2_LIVE_OWNER_APPROVED",
    "DEDA_STAGE2_LIVE_FIRESTORE_RULES_CONFIRMED",
    "DEDA_STAGE2_LIVE_SAME_UID_QA_PASSED",
    "DEDA_STAGE2_LIVE_TARGET_PROJECT",
    "GCLOUD_PROJECT",
  ]) {
    const invalid = {...approved};
    delete invalid[name];
    for (const feature of ["pinProof","deviceGrant","journal"]) {
      assert.equal(stage2LiveGateEnabled(feature, invalid), false, name);
    }
  }
});
test("fails closed for emulator, mismatched cloud project and unsupported keys", () => {
  for (const bad of [
    {FUNCTIONS_EMULATOR: "true"},
    {FIREBASE_EMULATOR_HUB: "127.0.0.1:4400"},
    {GCLOUD_PROJECT: "other-project"},
    {GOOGLE_CLOUD_PROJECT: "other-project"},
    {DEDA_STAGE2_LIVE_TARGET_PROJECT: "other-project"},
    {DEDA_STAGE2_LIVE_SAME_UID_QA_PASSED: "false"},
  ]) assert.equal(stage2LiveGateEnabled("pinProof", {...approved, ...bad}), false);
  assert.equal(stage2LiveGateEnabled("wallet", approved), false);
  assert.equal(stage2LiveGateEnabled("__proto__", approved), false);
  assert.equal(stage2LiveGateEnabled("pinProof", null), false);
});
test("per-function opt-in is independent; production gate is not a client toggle", () => {
  const env = {...approved, DEDA_STAGE2_LIVE_JOURNAL: "0"};
  assert.equal(stage2LiveGateEnabled("pinProof", env), true);
  assert.equal(stage2LiveGateEnabled("deviceGrant", env), true);
  assert.equal(stage2LiveGateEnabled("journal", env), false);
  assert.equal(stage2LiveGateEnabled("journal", approved), true);
});
