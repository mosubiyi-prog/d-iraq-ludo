"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  validCanonicalProof, accountKeyForPhone,
} = require("../deda_owner_pin_verify_private_v1.js");
const {syncMarkerMatches} =
    require("../deda_pin_manual_recovery_compat_private_v1.js");
const {stage2LiveGateEnabled} =
    require("../deda_stage2_live_gate.js");

// Dummy values only. Simulates production CONFLICT SHAPE, not real identities.
const key = "07700000000";
const originalId = "@DEDA-ABC123";
const a = "fixture-owner-route-A";
const b = "fixture-pin-register-B";
const c = "fixture-social-session-C";
const email = key + "@deda-login.invalid";
const userA = {accountKey:key, sharePersonalId:originalId};
const userB = {accountKey:key, sharePersonalId:null};
const userC = {accountKey:key, sharePersonalId:originalId};
const route = {publicId:originalId, kind:"personal", active:true, ownerUid:a};
const directory = {accountKey:key, active:true, createdUid:b};
const credential = {accountKey:key, active:true, createdUid:b};
const noLinkedAuth = (uid) =>
  ({uid, disabled:false, email:null, providerData:[]});

function verify({directoryData=directory, credentialData=credential,
  user=userB, authUser=noLinkedAuth(b), idRoute=route,
  adminExists=false}={}) {
  return validCanonicalProof({
    key, directory:directoryData, credentials:credentialData,
    projection:user, route:idRoute, adminExists, authUser,
  });
}

test("step2: UID A cannot pass PIN registration belonging to UID B", () => {
  assert.equal(verify({user:userA,authUser:noLinkedAuth(a)}), null);
});
test("step2: UID B cannot own original route even with a synthetic email", () => {
  assert.equal(verify({
    authUser:{uid:b,disabled:false,email},
  }), null);
});
test("step2: UID C cannot override the original owner route", () => {
  assert.equal(verify({
    user:userC, authUser:{uid:c,disabled:false,email},
  }), null);
});
test("step2: PIN alone is insufficient without a linked Auth provider", () => {
  const aligned = {accountKey:key, active:true, createdUid:a};
  assert.equal(verify({
    directoryData:aligned, credentialData:aligned, user:userA,
    authUser:noLinkedAuth(a),
  }), null);
});
test("step2: fully aligned linked positive test is NOT live owner proof", () => {
  const aligned = {accountKey:key, active:true, createdUid:a};
  const value = verify({
    directoryData:aligned, credentialData:aligned, user:userA,
    authUser:{uid:a,disabled:false,email},
  });
  assert.deepEqual(value,{originalUid:a,originalId});
});
test("step2: credentials without synchronized PIN metadata fail closed", () => {
  assert.equal(syncMarkerMatches({pinSyncVersion:0}), false);
  assert.equal(syncMarkerMatches({pinSyncVersion:1}), false);
  const ta = {toMillis:()=>1000};
  const tb = {toMillis:()=>2000};
  assert.equal(syncMarkerMatches({
    pinSyncVersion:1,updatedAt:ta,pinSyncedAt:tb,
  }), false);
  assert.equal(syncMarkerMatches({
    pinSyncVersion:1,updatedAt:ta,pinSyncedAt:ta,
  }), true);
});
test("step2: all production recovery paths remain OFF by default", () => {
  for (const feature of ["pinProof","deviceGrant","journal"]) {
    assert.equal(stage2LiveGateEnabled(feature,{}),false);
    assert.equal(stage2LiveGateEnabled(feature,{
      GCLOUD_PROJECT:"deda-25b88",
      DEDA_STAGE2_LIVE_TARGET_PROJECT:"deda-25b88",
      DEDA_STAGE2_LIVE_OWNER_APPROVED:"0",
      DEDA_STAGE2_LIVE_FIRESTORE_RULES_CONFIRMED:"1",
      DEDA_STAGE2_LIVE_SAME_UID_QA_PASSED:"1",
      DEDA_STAGE2_LIVE_PIN_PROOF:"1",
      DEDA_STAGE2_LIVE_DEVICE_GRANT:"1",
      DEDA_STAGE2_LIVE_JOURNAL:"1",
    }),false);
  }
  assert.equal(accountKeyForPhone(key),key);
});
