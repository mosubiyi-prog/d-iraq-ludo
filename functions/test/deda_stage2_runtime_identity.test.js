"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  RUNTIME_ACCOUNT, recoveryCallableOptions,
} = require("../deda_stage2_runtime_identity.js");

const root = path.resolve(__dirname, "..");
test("only owner-created dedicated runtime, never CI deployer or default appspot", () => {
  assert.equal(RUNTIME_ACCOUNT,
      "deda-recovery-runtime@deda-25b88.iam.gserviceaccount.com");
  assert.notEqual(RUNTIME_ACCOUNT,
      "firebase-adminsdk-fbsvc@deda-25b88.iam.gserviceaccount.com");
  assert.notEqual(RUNTIME_ACCOUNT, "deda-25b88@appspot.gserviceaccount.com");
});
test("every callable option retains App Check and exact scoped runtime", () => {
  for (const timeout of [20,30]) {
    assert.deepEqual(recoveryCallableOptions(timeout), {
      enforceAppCheck:true,
      timeoutSeconds:timeout,
      serviceAccount:RUNTIME_ACCOUNT,
    });
  }
  for (const invalid of [-1,0,61,1.2,"20",null]) {
    assert.throws(()=>recoveryCallableOptions(invalid),TypeError);
  }
});
test("only targeted stage2 callable source uses restricted runtime options", () => {
  for (const [file, count] of Object.entries({
    "deda_owner_pin_verify_private_v1.js":1,
    "deda_linked_owner_session_grant_private_v1.js":1,
    "deda_recovery_journal_completion_private_v1.js":1,
  })) {
    const body=fs.readFileSync(path.join(root,file),"utf8");
    const optionsCalls=body.match(/recoveryCallableOptions\((20|30)\)/g)||[];
    assert.equal(optionsCalls.length,count,file);
    assert.match(body,/deda_stage2_runtime_identity\.js/);
    assert.match(body,/enforceAppCheck|recoveryCallableOptions/);
  }
});
test("production recovery rollout gates still deny absent approvals", () => {
  const {stage2LiveGateEnabled}=require("../deda_stage2_live_gate.js");
  for (const key of ["pinProof","deviceGrant","journal"]) {
    assert.equal(stage2LiveGateEnabled(key,{}),false);
    assert.equal(stage2LiveGateEnabled(key,{
      GOOGLE_CLOUD_PROJECT:"deda-25b88",
      DEDA_STAGE2_LIVE_TARGET_PROJECT:"deda-25b88",
    }),false);
  }
});
