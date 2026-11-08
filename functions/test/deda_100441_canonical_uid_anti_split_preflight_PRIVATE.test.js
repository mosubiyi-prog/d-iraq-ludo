"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {inspectCanonicalUid} = require(
  "../deda_100441_canonical_uid_anti_split_preflight_PRIVATE_NOT_EXPORTED.js"
);

const A = "firebase-owner-original-A";
const B = "firebase-registration-B";
const C = "firebase-social-session-C";
const accountKey = "07" + "1".repeat(9); // artificial, NOT a real phone
const originalId = "@DEDA-ABC123";

function sameUid() {
  return {
    accountKey, originalId,
    directory: {accountKey, createdUid: A, active: true},
    credentials: {accountKey, createdUid: A, active: true},
    route: {publicId: originalId, kind: "personal", active: true, ownerUid: A},
    user: {accountKey, sharePersonalId: originalId},
    social: {publicId: originalId, ownerUid: A},
    liveAuthUid: A, authProvider: "password",
    session: {uid: A, accountKey},
  };
}
function assertNoPrivilege(outcome) {
  assert.equal(outcome.canSignIn, false);
  assert.equal(outcome.canCreateUid, false);
  assert.equal(outcome.canReassignOwner, false);
  assert.equal(outcome.canWriteFirestore, false);
  assert.equal(outcome.canModifyAdmin, false);
  assert.equal(outcome.canModifyFinances, false);
  assert.equal(outcome.requiresSeparateOwnerProof, true);
  assert.equal(outcome.legacyProductionUnchanged, true);
  assert.equal(Object.isFrozen(outcome), true);
}

test("coherent records are ONLY a future candidate, never a login grant", () => {
  const outcome = inspectCanonicalUid(sameUid());
  assert.equal(outcome.status, "MATCH_CANDIDATE");
  assertNoPrivilege(outcome);
});

test("real-shaped A/B/C split is detected before any auth decision", () => {
  const x = sameUid();
  x.directory.createdUid = B;
  x.credentials.createdUid = B;
  x.social.ownerUid = C;
  x.liveAuthUid = C;
  x.session.uid = C;
  const outcome = inspectCanonicalUid(x);
  assert.equal(outcome.status, "SPLIT");
  assert.equal(outcome.detail, "ORIGINAL_ROUTE_VS_REGISTRATION_UID");
  assertNoPrivilege(outcome);
});

test("mismatched directory vs PIN registration cannot pick either UID", () => {
  const x = sameUid();
  x.credentials.createdUid = B;
  const outcome = inspectCanonicalUid(x);
  assert.equal(outcome.detail, "DIRECTORY_AND_CREDENTIAL_UID_MISMATCH");
  assertNoPrivilege(outcome);
});

test("social owner C cannot silently replace the original owner A", () => {
  const x = sameUid();
  x.social.ownerUid = C;
  const outcome = inspectCanonicalUid(x);
  assert.equal(outcome.detail, "SOCIAL_VS_REGISTRATION_UID");
  assertNoPrivilege(outcome);
});

test("new anonymous login UID cannot claim old account by knowing PIN", () => {
  const x = sameUid();
  x.liveAuthUid = B;
  x.authProvider = "anonymous";
  x.session.uid = B;
  x.credentials.pin = "000000"; // ignored even if someone supplies it
  const outcome = inspectCanonicalUid(x);
  assert.equal(outcome.detail, "LIVE_AUTH_UID_NOT_CANONICAL");
  assertNoPrivilege(outcome);
});

test("anonymous login with same UID still cannot become durable recovery", () => {
  const x = sameUid();
  x.authProvider = "anonymous";
  const outcome = inspectCanonicalUid(x);
  assert.equal(outcome.detail, "NO_DURABLE_AUTH_PROVIDER");
  assertNoPrivilege(outcome);
});

test("no valid session on owner phone cannot be treated as signed in", () => {
  for (const x of [
    {...sameUid(), liveAuthUid: null},
    {...sameUid(), session: null},
    {...sameUid(), session: {uid: A, accountKey: "07111111110"}},
  ]) {
    const out = inspectCanonicalUid(x);
    assert.equal(out.status, "HOLD");
    assertNoPrivilege(out);
  }
});

test("missing registration never creates a new UID; partial row also holds", () => {
  for (const x of [
    {...sameUid(), directory: null, credentials: null},
    {...sameUid(), credentials: null},
    {...sameUid(), directory: null},
  ]) {
    const out = inspectCanonicalUid(x);
    assert.equal(out.status, "HOLD");
    assertNoPrivilege(out);
  }
});

test("immutable six-character original ID is required; premium alias excluded", () => {
  const x = sameUid();
  x.originalId = "@DEDA-ABCD";
  const out = inspectCanonicalUid(x);
  assert.equal(out.detail, "INVALID_ACCOUNT_OR_ORIGINAL_ID");
  assertNoPrivilege(out);
});

test("incomplete legacy social/route records wait for review, never overwrite", () => {
  for (const x of [
    {...sameUid(), route: null},
    {...sameUid(), social: null},
    {...sameUid(), user: null},
  ]) {
    const out = inspectCanonicalUid(x);
    assert.equal(out.status, "HOLD");
    assertNoPrivilege(out);
  }
});

test("trustedInstallIds, admin gateway and client claims confer no rights", () => {
  const x = sameUid();
  x.authProvider = "anonymous";
  x.trustedInstallIds = ["legacy-install"];
  x.adminEntryAllowed = true;
  x.pinWasTyped = true;
  const out = inspectCanonicalUid(x);
  assert.equal(out.detail, "NO_DURABLE_AUTH_PROVIDER");
  assertNoPrivilege(out);
});

test("wrong account metadata, revoked registration and uncertain input fail closed", () => {
  const cases = [
    null, {}, [], {...sameUid(), accountKey: "invalid"},
    {...sameUid(), credentials: {...sameUid().credentials, accountKey: "07111111110"}},
    {...sameUid(), directory: {...sameUid().directory, active: false}},
    {...sameUid(), route: {...sameUid().route, active: false}},
    {...sameUid(), authProvider: "not-a-real-provider"},
  ];
  for (const x of cases) {
    const out = inspectCanonicalUid(x);
    assert.notEqual(out.status, "MATCH_CANDIDATE");
    assertNoPrivilege(out);
  }
});

test("output never leaks UID, phone, PIN, original ID or social contents", () => {
  const out = inspectCanonicalUid({...sameUid(), credentials: {
    ...sameUid().credentials, pin: "123456",
  }});
  const json = JSON.stringify(out);
  for (const secret of [A, B, C, accountKey, originalId, "123456"]) {
    assert.equal(json.includes(secret), false);
  }
  assertNoPrivilege(out);
});
