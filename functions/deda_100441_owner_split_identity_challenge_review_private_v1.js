"use strict";

// DEDA 100441 — PRIVATE OFFLINE REVIEW GATE, NOT a Firebase callable.
// Not imported into functions/index.js, not a deployed authentication path.
// This cannot issue tokens, link providers, create anonymous UIDs, edit
// Firestore, migrate accounts, or confer GM access. Server-side inputs only.
//
// The original 6-digit PIN is not independent proof of ownership. Production
// recovery requires a separately authenticated, previously enrolled factor,
// a single-use server-recorded challenge, documented ownership reconciliation,
// independent review, backups and a narrow owner-approved cutover. This source
// intentionally has NO successful login/authorization return state.

const MAX_PROOF_AGE_MS = 10 * 60 * 1000;
const ID = /^@DEDA-[A-Z0-9]{6}$/;
const ACCOUNT = /^(?:07\d{9}|9647\d{9})$/;
const NONCE_DIGEST = /^[0-9a-f]{64}$/;
const VALID_SECOND_FACTORS = new Set([
  "pre_enrolled_original_device_key",
  "pre_linked_firebase_identity_provider",
  "independent_verified_recovery_factor",
]);

function serverRecordShape(snapshot) {
  if (!snapshot || typeof snapshot !== "object" ||
      Array.isArray(snapshot) || !ACCOUNT.test(snapshot.accountKey) ||
      !ID.test(snapshot.originalId) ||
      !snapshot.route || !snapshot.directory || !snapshot.credentials ||
      !snapshot.social || !snapshot.originalUser ||
      !snapshot.pinRegisteredUser || !snapshot.socialUser) return null;

  const a = snapshot.route.ownerUid;
  const b = snapshot.directory.createdUid;
  const c = snapshot.social.ownerUid;
  if (![a,b,c].every(uid => typeof uid === "string" &&
      uid.length >= 6 && uid.length <= 128)) return null;

  const originalRouteValid =
      snapshot.route.publicId === snapshot.originalId &&
      snapshot.route.kind === "personal" &&
      snapshot.route.active === true &&
      snapshot.originalUser.accountKey === snapshot.accountKey &&
      snapshot.originalUser.sharePersonalId === snapshot.originalId;
  const registrationValid =
      snapshot.directory.accountKey === snapshot.accountKey &&
      snapshot.directory.active === true &&
      snapshot.credentials.accountKey === snapshot.accountKey &&
      snapshot.credentials.active === true &&
      snapshot.credentials.createdUid === b &&
      snapshot.pinRegisteredUser.accountKey === snapshot.accountKey;
  const socialValid =
      snapshot.social.publicId === snapshot.originalId &&
      snapshot.socialUser.accountKey === snapshot.accountKey &&
      snapshot.socialUser.sharePersonalId === snapshot.originalId;
  const threeWaySplit = a !== b && a !== c && b !== c;
  const allSame = a === b && b === c;

  return Object.freeze({
    originalRouteValid, registrationValid, socialValid,
    threeWaySplit, allSame,
    // Deliberately DO NOT return actual UIDs or account keys.
  });
}

function safeEvidenceAssessment(snapshot) {
  const shape = serverRecordShape(snapshot);
  if (!shape) return Object.freeze({
    decision: "HOLD",
    reason: "UNVERIFIED_SERVER_SHAPE",
    loginPermitted: false,
  });
  if (!shape.originalRouteValid || !shape.registrationValid ||
      !shape.socialValid) return Object.freeze({
    decision: "HOLD",
    reason: "INCOMPLETE_CANONICAL_PROOF",
    loginPermitted: false,
  });
  if (shape.threeWaySplit) return Object.freeze({
    decision: "HOLD",
    reason: "THREE_UID_SPLIT",
    loginPermitted: false,
  });
  if (!shape.allSame) return Object.freeze({
    decision: "HOLD",
    reason: "PARTIAL_UID_SPLIT",
    loginPermitted: false,
  });
  return Object.freeze({
    decision: "HOLD",
    reason: "CANONICAL_RECORDS_MATCH_AUTH_STILL_REQUIRED",
    loginPermitted: false,
  });
}

function recent(nowMs, verifiedAtMs) {
  return Number.isSafeInteger(nowMs) &&
      Number.isSafeInteger(verifiedAtMs) &&
      nowMs >= verifiedAtMs &&
      nowMs - verifiedAtMs <= MAX_PROOF_AGE_MS;
}

// The record of a prior trusted factor must be created by the trusted server,
// never from request.data/client SharedPreferences. This pure helper does not
// establish the provenance of any input; it can only reject absent/invalid
// fields. DO NOT use it as a callable or return an Auth token from its result.
function reviewReadiness({
  serverSnapshot, pinProof, independentProof, reviewRecord, nowMs,
  incidentCutoffMs,
} = {}) {
  const assessment = safeEvidenceAssessment(serverSnapshot);
  if (assessment.reason === "UNVERIFIED_SERVER_SHAPE" ||
      assessment.reason === "INCOMPLETE_CANONICAL_PROOF") {
    return Object.freeze({decision:"HOLD",reason:assessment.reason,
      loginPermitted:false});
  }

  if (!pinProof || pinProof.source !== "trusted_server_checker" ||
      pinProof.rateLimitEnforced !== true ||
      pinProof.verified !== true ||
      pinProof.accountKey !== serverSnapshot.accountKey ||
      !recent(nowMs,pinProof.verifiedAtMs) ||
      !NONCE_DIGEST.test(pinProof.challengeHash || "")) {
    return Object.freeze({decision:"HOLD",reason:"NO_VALID_SERVER_PIN_PROOF",
      loginPermitted:false});
  }

  // It is a hard block unless a provider/device factor was PRE-ENROLLED or a
  // separate, authoritative recovery provider verified the same original UID.
  if (!independentProof ||
      independentProof.source !== "trusted_independent_verifier" ||
      independentProof.verified !== true ||
      !VALID_SECOND_FACTORS.has(independentProof.kind) ||
      independentProof.accountKey !== serverSnapshot.accountKey ||
      // A/B/C are conflicting historical references. Do NOT preselect A
      // merely because it currently owns the public-ID route. Only accept
      // a separately verified factor bound to one of the THREE existing
      // server-snapshot UIDs, then require independent reconciliation.
      ![
        serverSnapshot.route.ownerUid,
        serverSnapshot.directory.createdUid,
        serverSnapshot.social.ownerUid,
      ].includes(independentProof.originalUid) ||
      independentProof.challengeHash !== pinProof.challengeHash ||
      !recent(nowMs,independentProof.verifiedAtMs) ||
      independentProof.priorEnrollmentOrProviderVerified !== true ||
      // Historical factors must have a separately audited enrollment date
      // strictly earlier than the incident. A newly registered device or
      // provider can never become retrospective ownership proof.
      (independentProof.kind !== "independent_verified_recovery_factor" &&
       (!Number.isSafeInteger(incidentCutoffMs) || incidentCutoffMs <= 0 ||
        incidentCutoffMs > nowMs ||
        !Number.isSafeInteger(independentProof.enrolledAtMs) ||
        independentProof.enrolledAtMs <= 0 ||
        independentProof.enrolledAtMs >= incidentCutoffMs))) {
    return Object.freeze({decision:"HOLD",reason:"NO_TRUSTED_INDEPENDENT_FACTOR",
      loginPermitted:false});
  }

  if (!reviewRecord || reviewRecord.source !== "independent_server_review" ||
      reviewRecord.ownerApproved !== true ||
      // Bind the human review to the SAME verified account and historical
      // UID candidate; independent proof for B/C cannot reuse review of A.
      reviewRecord.accountKey !== serverSnapshot.accountKey ||
      reviewRecord.reviewedOriginalUid !== independentProof.originalUid ||
      reviewRecord.originalSnapshotBackedUp !== true ||
      reviewRecord.rollbackDocumented !== true ||
      reviewRecord.reconciliationPlanDocumented !== true ||
      reviewRecord.adminPrivilegesSeparatelyVerified !== true ||
      reviewRecord.challengeHash !== pinProof.challengeHash ||
      !recent(nowMs,reviewRecord.reviewedAtMs) ||
      // Both proofs must precede (or coincide with) the independent review.
      // Fresh but prewritten approvals cannot be reused for a later proof.
      reviewRecord.reviewedAtMs < pinProof.verifiedAtMs ||
      reviewRecord.reviewedAtMs < independentProof.verifiedAtMs ||
      !Array.isArray(reviewRecord.reviewers) ||
      reviewRecord.reviewers.length !== 2 ||
      !reviewRecord.reviewers.every(x => typeof x === "string" && x.length > 3) ||
      reviewRecord.reviewers[0] === reviewRecord.reviewers[1]) {
    return Object.freeze({decision:"HOLD",reason:"INDEPENDENT_REVIEW_INCOMPLETE",
      loginPermitted:false});
  }

  // The result NEVER authorizes a UID cutover. Reviewer and owner still need
  // an independently implemented, audited and separately approved service.
  return Object.freeze({
    decision:"CANDIDATE_FOR_SEPARATE_OWNER_REVIEW",
    reason:"NO_AUTHORIZATION_ISSUED",
    loginPermitted:false,
  });
}

module.exports = {
  safeEvidenceAssessment, reviewReadiness,
};
