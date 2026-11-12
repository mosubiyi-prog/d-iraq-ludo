"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  safeEvidenceAssessment,
  reviewReadiness,
} = require("../functions/deda_100441_owner_split_identity_challenge_review_private_v1");

const ACCOUNT = "9647712345678";
const ID = "@DEDA-ABC123";
const A = "uid-old-owner-A";
const B = "uid-old-registration-B";
const C = "uid-old-social-C";
const now = 1770134000000; // synthetic test time
const cutoff = now - 80000;
const hash = "a".repeat(64);

function historicalSnapshot() {
  return {
    accountKey: ACCOUNT, originalId: ID,
    route: {publicId: ID, kind:"personal", active:true, ownerUid:A},
    directory: {accountKey:ACCOUNT, active:true, createdUid:B},
    credentials: {accountKey:ACCOUNT, active:true, createdUid:B},
    social: {publicId:ID, ownerUid:C},
    originalUser: {accountKey:ACCOUNT, sharePersonalId:ID},
    pinRegisteredUser: {accountKey:ACCOUNT},
    socialUser: {accountKey:ACCOUNT, sharePersonalId:ID},
  };
}
function verifiedProofs() {
  return {
    serverSnapshot:historicalSnapshot(),
    nowMs:now,
    incidentCutoffMs:cutoff,
    pinProof: {
      source:"trusted_server_checker", rateLimitEnforced:true,
      verified:true, accountKey:ACCOUNT, challengeHash:hash,
      verifiedAtMs:now-900,
    },
    independentProof: {
      source:"trusted_independent_verifier", verified:true,
      kind:"pre_enrolled_original_device_key",
      originalUid:A, accountKey:ACCOUNT, challengeHash:hash,
      verifiedAtMs:now-800, priorEnrollmentOrProviderVerified:true,
      enrolledAtMs:cutoff-10000,
    },
    reviewRecord: {
      source:"independent_server_review", ownerApproved:true,
      accountKey:ACCOUNT, reviewedOriginalUid:A, challengeHash:hash,
      originalSnapshotBackedUp:true, rollbackDocumented:true,
      reconciliationPlanDocumented:true,
      adminPrivilegesSeparatelyVerified:true,
      reviewedAtMs:now-100,
      reviewers:["trusted-reviewer-one","trusted-reviewer-two"],
    },
  };
}

test("split history is detected without deciding an owner", () => {
  const observed=safeEvidenceAssessment(historicalSnapshot());
  assert.equal(observed.decision,"HOLD");
  assert.equal(observed.reason,"THREE_UID_SPLIT");
  assert.equal(observed.loginPermitted,false);
});

test("known PIN + phone alone cannot recover a split legacy account", () => {
  const input=verifiedProofs();
  delete input.independentProof;
  const result=reviewReadiness(input);
  assert.equal(result.reason,"NO_TRUSTED_INDEPENDENT_FACTOR");
  assert.equal(result.loginPermitted,false);
});

test("unverified or replayed PIN fails closed", () => {
  const input=verifiedProofs();
  input.pinProof.verifiedAtMs=now-3600000;
  assert.equal(reviewReadiness(input).reason,"NO_VALID_SERVER_PIN_PROOF");
  assert.equal(reviewReadiness({...verifiedProofs(),pinProof:null}).loginPermitted,false);
});

test("recently enrolled device cannot pretend to predate the incident", () => {
  const input=verifiedProofs();
  input.independentProof.enrolledAtMs=cutoff+1;
  assert.equal(reviewReadiness(input).reason,"NO_TRUSTED_INDEPENDENT_FACTOR");
  assert.equal(reviewReadiness(input).loginPermitted,false);
});

test("a different historical account or wrong UID cannot claim this record", () => {
  let input=verifiedProofs();
  input.independentProof.originalUid="new-unknown-uid-D";
  assert.equal(reviewReadiness(input).reason,"NO_TRUSTED_INDEPENDENT_FACTOR");
  input=verifiedProofs();
  input.independentProof.accountKey="9647700000000";
  assert.equal(reviewReadiness(input).reason,"NO_TRUSTED_INDEPENDENT_FACTOR");
});

test("independent recovery factor and dual reviewer must agree on same UID", () => {
  const input=verifiedProofs();
  input.reviewRecord.reviewedOriginalUid=B;
  assert.equal(reviewReadiness(input).reason,"INDEPENDENT_REVIEW_INCOMPLETE");
  input.reviewRecord.reviewedOriginalUid=A;
  input.reviewRecord.reviewers=["one-reviewer","one-reviewer"];
  assert.equal(reviewReadiness(input).reason,"INDEPENDENT_REVIEW_INCOMPLETE");
});

test("a good full review can ONLY become candidate; NEVER a login or transfer", () => {
  const reviewed=reviewReadiness(verifiedProofs());
  assert.deepEqual(reviewed,{
    decision:"CANDIDATE_FOR_SEPARATE_OWNER_REVIEW",
    reason:"NO_AUTHORIZATION_ISSUED",
    loginPermitted:false,
  });
  assert.equal(Object.hasOwn(reviewed,"uid"),false);
  assert.equal(Object.hasOwn(reviewed,"token"),false);
  assert.equal(Object.hasOwn(reviewed,"canModifyAdmin"),false);
});

test("credential shape mismatch still stops even after a good device proof", () => {
  const input=verifiedProofs();
  input.serverSnapshot.credentials.createdUid=A;
  const blocked=reviewReadiness(input);
  assert.equal(blocked.reason,"INCOMPLETE_CANONICAL_PROOF");
  assert.equal(blocked.loginPermitted,false);
});
