"use strict";

// PRIVATE OFFLINE SECURITY GATE, NEVER DEPLOYED OR EXPORTED.
// Links the SUCCESSFUL QA-lab result to the requirements for a LEGACY DEDA
// owner-proof review WITHOUT treating a lab Google credential as proof of
// historical DEDA ownership. No read or write to live Firebase occurs here.
//
// All arguments are server-reviewed evidence candidates, NEVER client claims.
// This pure helper cannot verify a token or the provenance of supplied facts:
// these must be independently verified by a trusted production verifier before
// invocation. Therefore ALL returns DENY sign-in/link/merge/transfer rights,
// including the most favorable test case.
//
// Deliberately no Auth SDK, Firestore SDK, or token generation/import.

const {reviewReadiness} = require(
  "./deda_100441_owner_split_identity_challenge_review_private_v1.js"
);

const PRODUCTION_PROJECT = "deda-25b88";
const QA_PROJECT = "deda-qa-uid-lab-20261108";
const ORIGINAL_UID = /^[a-zA-Z0-9:_-]{6,128}$/;

function out(classification) {
  return Object.freeze({
    decision: "HOLD_FOR_INDEPENDENT_LEGACY_OWNER_PROOF",
    classification,
    signInPermitted: false,
    googleLinkPermitted: false,
    uidSelectionPermitted: false,
    issueTokenPermitted: false,
    mergePermitted: false,
    changeSessionPermitted: false,
    changeWalletPermitted: false,
    changeAdminPermitted: false,
    writeFirestorePermitted: false,
    internalOfflineOnly: true,
  });
}

/**
 * Gate for the OLD A/B/C recovery lane. Never for new Google registration.
 *
 * labEvidence: evidence of QA Google login on two devices, informational only.
 * verifiedProductionGoogle: must be from a trusted, independently checked
 * PROD Firebase Auth verifier, not a client-supplied token/label.
 * originalRecords, pinProof, independentProof and reviewRecord:
 * trusted server-side inputs for the EXISTING owner-review gate.
 *
 * No output ever contains UID, phone number, email, Google subject or PIN.
 */
function inspectLegacyGoogleOwnerBridge({
  labEvidence,
  verifiedProductionGoogle,
  originalRecords,
  pinProof,
  independentProof,
  reviewRecord,
  nowMs,
  incidentCutoffMs,
} = {}) {
  // A real lab success is valuable, but not account ownership evidence.
  // The QA Firebase project MUST NEVER be an authorization issuer for prod.
  if (!labEvidence || labEvidence.firebaseProjectId !== QA_PROJECT ||
      labEvidence.twoDeviceSameUid !== true) {
    return out("LAB_PROOF_MISSING_OR_DIFFERENT_PROJECT");
  }

  const google = verifiedProductionGoogle;
  if (!google || google.firebaseProjectId !== PRODUCTION_PROJECT ||
      google.verifier !== "trusted_production_firebase_auth_admin" ||
      google.revocationChecked !== true ||
      google.providerId !== "google.com" ||
      google.verified !== true) {
    return out("NO_VERIFIED_PRODUCTION_GOOGLE_AUTH");
  }

  // New Google login to the production Firebase project is NOT proof of an
  // older DEDA account unless the SAME Google subject was ALREADY enrolled
  // and independently auditable against that existing original UID.
  if (!google.preExistingBindingVerified ||
      google.bindingAuditOrigin !== "trusted_server_pre_enrollment_v1" ||
      !ORIGINAL_UID.test(google.originalUid || "") ||
      !Number.isSafeInteger(incidentCutoffMs) ||
      !Number.isSafeInteger(google.enrolledAtMs) ||
      google.enrolledAtMs <= 0 ||
      google.enrolledAtMs >= incidentCutoffMs) {
    return out("GOOGLE_NOT_HISTORICALLY_BOUND_TO_OLD_UID");
  }

  // The original personal-ID route is a useful historical anchor, but it
  // cannot be guessed from PIN, today's QA UID or a different DEDA account.
  if (!originalRecords || !originalRecords.route ||
      originalRecords.route.ownerUid !== google.originalUid) {
    return out("ORIGINAL_UID_ANCHOR_CONFLICT");
  }

  // Existing owner proof logic requires a separate PIN challenge, independent
  // enrollment proof, two-person review, snapshots and rollback.
  // It never grants Auth, and neither does this additional boundary check.
  const assessed = reviewReadiness({
    serverSnapshot: originalRecords,
    pinProof,
    independentProof,
    reviewRecord,
    nowMs,
  });

  if (assessed.decision !== "CANDIDATE_FOR_SEPARATE_OWNER_REVIEW" ||
      assessed.loginPermitted !== false) {
    return out("OWNER_PROOF_OR_REVIEW_NOT_COMPLETE");
  }

  return out("MANUAL_CANONICAL_RECONCILIATION_CANDIDATE_NOT_AUTHORIZED");
}

module.exports = {
  inspectLegacyGoogleOwnerBridge,
};
