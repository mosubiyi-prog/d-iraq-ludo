"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {inspectLegacyGoogleOwnerBridge} = require(
  "../deda_100441_lab_to_legacy_google_proof_gate_PRIVATE_NOT_EXPORTED.js"
);

const nowMs = 1800000000000;
const incidentCutoffMs = nowMs - 5000000;
const A = "synthetic-original-owner-AAA";
const B = "synthetic-pin-owner-BBB";
const C = "synthetic-social-owner-CCC";
const accountKey = "07700000000";
const originalId = "@DEDA-ABC123";
const challengeHash = "a".repeat(64);

function snapshot() {
  return {
    accountKey, originalId,
    route: {publicId: originalId, kind: "personal", active: true, ownerUid: A},
    directory: {accountKey, createdUid: B, active: true},
    credentials: {accountKey, createdUid: B, active: true},
    social: {publicId: originalId, ownerUid: C},
    originalUser: {accountKey, sharePersonalId: originalId},
    pinRegisteredUser: {accountKey, sharePersonalId: null},
    socialUser: {accountKey, sharePersonalId: originalId},
  };
}

function lab() {
  return {firebaseProjectId: "deda-qa-uid-lab-20261108", twoDeviceSameUid: true};
}

function prodGoogle() {
  return {
    firebaseProjectId: "deda-25b88",
    verifier: "trusted_production_firebase_auth_admin",
    revocationChecked: true,
    providerId: "google.com",
    verified: true,
    originalUid: A,
    preExistingBindingVerified: true,
    bindingAuditOrigin: "trusted_server_pre_enrollment_v1",
    enrolledAtMs: incidentCutoffMs - 100000,
  };
}

function pin() {
  return {
    source: "trusted_server_checker",
    verified: true,
    rateLimitEnforced: true,
    accountKey,
    verifiedAtMs: nowMs - 1000,
    challengeHash,
  };
}

function independent() {
  return {
    source: "trusted_independent_verifier",
    verified: true,
    kind: "pre_linked_firebase_identity_provider",
    priorEnrollmentOrProviderVerified: true,
    originalUid: A,
    accountKey,
    verifiedAtMs: nowMs - 900,
    challengeHash,
  };
}

function review() {
  return {
    source: "independent_server_review",
    ownerApproved: true,
    originalSnapshotBackedUp: true,
    rollbackDocumented: true,
    reconciliationPlanDocumented: true,
    adminPrivilegesSeparatelyVerified: true,
    challengeHash,
    reviewedAtMs: nowMs - 500,
    reviewers: ["synthetic-reviewer-one", "synthetic-reviewer-two"],
  };
}

function inspect(overrides={}) {
  return inspectLegacyGoogleOwnerBridge({
    labEvidence: lab(),
    verifiedProductionGoogle: prodGoogle(),
    originalRecords: snapshot(),
    pinProof: pin(),
    independentProof: independent(),
    reviewRecord: review(),
    nowMs, incidentCutoffMs,
    ...overrides,
  });
}

function mustDeny(result) {
  assert.equal(result.decision, "HOLD_FOR_INDEPENDENT_LEGACY_OWNER_PROOF");
  for (const [key, value] of Object.entries(result)) {
    if (key.endsWith("Permitted")) assert.equal(value, false, key);
  }
  assert.equal(result.internalOfflineOnly, true);
  for(const key of ["uid", "originalUid", "phone", "email", "idToken",
      "pin", "customToken", "accountKey", "originalId"]) {
    assert.equal(key in result, false, "sensitive output " + key);
  }
  assert.equal(Object.isFrozen(result), true);
}

test("actual QA outcome alone cannot link old owner", () => {
  const r = inspect({verifiedProductionGoogle:null});
  assert.equal(r.classification, "NO_VERIFIED_PRODUCTION_GOOGLE_AUTH");
  mustDeny(r);
});

test("unverified or wrong QA project cannot be substituted", () => {
  for(const l of [null, {}, {twoDeviceSameUid:true,firebaseProjectId:"deda-25b88"},
    {firebaseProjectId:"deda-qa-uid-lab-20261108",twoDeviceSameUid:false}]) {
    const r = inspect({labEvidence:l});
    assert.equal(r.classification, "LAB_PROOF_MISSING_OR_DIFFERENT_PROJECT");
    mustDeny(r);
  }
});

test("QA Firebase credential must never be treated as production auth", () => {
  mustDeny(inspect({verifiedProductionGoogle:{
    ...prodGoogle(), firebaseProjectId:"deda-qa-uid-lab-20261108",
  }}));
});

test("production token without trusted verifier fails closed", () => {
  const r=inspect({verifiedProductionGoogle:{
    ...prodGoogle(),verifier:"client_supplied_claim",
  }});
  assert.equal(r.classification,"NO_VERIFIED_PRODUCTION_GOOGLE_AUTH");
  mustDeny(r);
});

test("anonymous, revoked and unsupported providers cannot prove Google link", () => {
  for(const x of [
    {providerId:"anonymous"}, {providerId:"password"},
    {revocationChecked:false}, {verified:false}
  ]) {
    const r=inspect({verifiedProductionGoogle:{...prodGoogle(),...x}});
    assert.equal(r.classification,"NO_VERIFIED_PRODUCTION_GOOGLE_AUTH");
    mustDeny(r);
  }
});

test("newly signed-in Google does not imply historical DEDA ownership", () => {
  const r=inspect({verifiedProductionGoogle:{
    ...prodGoogle(), preExistingBindingVerified:false,
  }});
  assert.equal(r.classification, "GOOGLE_NOT_HISTORICALLY_BOUND_TO_OLD_UID");
  mustDeny(r);
});

test("post-incident provider binding cannot retroactively prove old account", () => {
  const r=inspect({verifiedProductionGoogle:{
    ...prodGoogle(), enrolledAtMs:incidentCutoffMs+1,
  }});
  assert.equal(r.classification, "GOOGLE_NOT_HISTORICALLY_BOUND_TO_OLD_UID");
  mustDeny(r);
});

test("Google binding to UID B or C cannot override original-ID anchor A", () => {
  for(const uid of [B,C]) {
    const r=inspect({verifiedProductionGoogle:{
      ...prodGoogle(), originalUid:uid,
    }});
    assert.equal(r.classification,"ORIGINAL_UID_ANCHOR_CONFLICT");
    mustDeny(r);
  }
});

test("incomplete historical owner route cannot be accepted", () => {
  const old=snapshot();
  delete old.route;
  const r=inspect({originalRecords:old});
  assert.equal(r.classification,"ORIGINAL_UID_ANCHOR_CONFLICT");
  mustDeny(r);
});

test("PIN alone never passes without independent ownership factor", () => {
  const r=inspect({independentProof:null});
  assert.equal(r.classification,"OWNER_PROOF_OR_REVIEW_NOT_COMPLETE");
  mustDeny(r);
});

test("missing review, backup or second reviewer cannot authorize", () => {
  for (const reviewRecord of [
    null, {...review(),originalSnapshotBackedUp:false},
    {...review(),reviewers:["same-person","same-person"]},
    {...review(),rollbackDocumented:false}
  ]) {
    const r=inspect({reviewRecord});
    assert.equal(r.classification,"OWNER_PROOF_OR_REVIEW_NOT_COMPLETE");
    mustDeny(r);
  }
});

test("historical A/B/C divergence with full *synthetic* review is STILL not a login", () => {
  const r=inspect();
  assert.equal(r.classification,
    "MANUAL_CANONICAL_RECONCILIATION_CANDIDATE_NOT_AUTHORIZED");
  mustDeny(r);
});

test("forged client fields or missing server snapshot fail closed", () => {
  const r=inspect({originalRecords:{route:{ownerUid:A}}});
  assert.equal(r.classification,"OWNER_PROOF_OR_REVIEW_NOT_COMPLETE");
  mustDeny(r);
});

test("source module is pure and cannot write/issue tokens/link users", () => {
  const fs = require("node:fs");
  const path = require("node:path");
  const src=fs.readFileSync(path.resolve(__dirname,
    "../deda_100441_lab_to_legacy_google_proof_gate_PRIVATE_NOT_EXPORTED.js"),"utf8");
  for(const term of ["createCustomToken(", "signInWithCredential(",
    "signInAnonymously(", "updateUser(", "deleteUser(", "linkWithCredential(",
    ".set(", ".update(", ".delete(", "firebase-admin", "firebase-functions"]) {
    assert.equal(src.includes(term),false,term);
  }
});
