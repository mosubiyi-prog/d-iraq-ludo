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
  verifiedProspectiveGoogle,
  serverConfiguredRecoveryOAuthAudience,
  originalRecords,
  pinProof,
  independentProof,
  reviewRecord,
  nowMs,
  incidentCutoffMs,
} = {}) {
  // Historical QA-lab completion is NOT a prerequisite for a real
  // production-owner review. It proves only device-to-device QA consistency,
  // not account ownership. If supplied, reject incorrect/cross-project lab
  // evidence; if absent, continue to the independently verified production
  // Google evidence and the old-account owner-proof gates below.
  if (labEvidence != null &&
      (labEvidence.firebaseProjectId !== QA_PROJECT ||
       labEvidence.twoDeviceSameUid !== true)) {
    return out("LAB_PROOF_UNVERIFIED_OR_DIFFERENT_PROJECT");
  }

  // TWO DISJOINT REVIEW LANES:
  //
  // (A) A historically pre-linked production Firebase Google identity.
  // (B) A newly verified Google OIDC identity, purely as a future factor,
  //     alongside INDEPENDENT manual recovery evidence for the old account.
  //
  // OIDC in lane B is checked by a trusted server WITHOUT signing in to
  // Firebase Auth; never use FirebaseAuth.signInWithCredential on an
  // unverified legacy owner (which could create yet another UID).
  //
  // The production OAuth audience must come from a server configuration,
  // NEVER the QA Web OAuth client or a user-provided client ID.
  if (verifiedProductionGoogle && verifiedProspectiveGoogle) {
    return out("MIXED_GOOGLE_EVIDENCE_LANES_NOT_ALLOWED");
  }

  let historical = false;
  if (verifiedProspectiveGoogle) {
    const oidc = verifiedProspectiveGoogle;
    const validAudience = typeof serverConfiguredRecoveryOAuthAudience === "string" &&
      /^[0-9]+-[a-zA-Z0-9_-]+\.apps\.googleusercontent\.com$/.test(
        serverConfiguredRecoveryOAuthAudience);
    if (!validAudience ||
        oidc.verifier !== "trusted_google_oidc_backend" ||
        oidc.issuer !== "https://accounts.google.com" ||
        oidc.audience !== serverConfiguredRecoveryOAuthAudience ||
        oidc.audienceVerified !== true ||
        oidc.oauthClientProjectId !== PRODUCTION_PROJECT ||
        oidc.nonceVerified !== true ||
        oidc.freshAndUnexpired !== true ||
        oidc.subjectVerified !== true ||
        oidc.providerId !== "google.com" ||
        oidc.verified !== true ||
        independentProof?.kind !== "independent_verified_recovery_factor") {
      return out("NEW_GOOGLE_REQUIRES_SERVER_OIDC_AND_INDEPENDENT_MANUAL_OWNER_PROOF");
    }
    // The new Google identity is NOT currently linked to a legacy UID.
    // Verify old owner exclusively through the independent recovery factor.
    if (!originalRecords || !originalRecords.route ||
        !ORIGINAL_UID.test(originalRecords.route.ownerUid || "") ||
        independentProof.originalUid !== originalRecords.route.ownerUid) {
      return out("ORIGINAL_UID_ANCHOR_CONFLICT");
    }
  } else {
    historical = true;
    const google = verifiedProductionGoogle;
    if (!google || google.firebaseProjectId !== PRODUCTION_PROJECT ||
        google.verifier !== "trusted_production_firebase_auth_admin" ||
        google.revocationChecked !== true ||
        google.providerId !== "google.com" ||
        google.verified !== true) {
      return out("NO_VERIFIED_PRODUCTION_GOOGLE_AUTH");
    }

    // Even a new PROD Firebase Google login is not proof that it owned the
    // OLD DEDA account unless a pre-incident binding is independently audited.
    if (!google.preExistingBindingVerified ||
        google.bindingAuditOrigin !== "trusted_server_pre_enrollment_v1" ||
        !ORIGINAL_UID.test(google.originalUid || "") ||
        !Number.isSafeInteger(incidentCutoffMs) ||
        !Number.isSafeInteger(google.enrolledAtMs) ||
        google.enrolledAtMs <= 0 ||
        google.enrolledAtMs >= incidentCutoffMs) {
      return out("GOOGLE_NOT_HISTORICALLY_BOUND_TO_OLD_UID");
    }

    if (!originalRecords || !originalRecords.route ||
        originalRecords.route.ownerUid !== google.originalUid) {
      return out("ORIGINAL_UID_ANCHOR_CONFLICT");
    }
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

  return out(historical
    ? "MANUAL_CANONICAL_RECONCILIATION_CANDIDATE_NOT_AUTHORIZED"
    : "NEW_GOOGLE_MANUAL_LEGACY_RECOVERY_CANDIDATE_NOT_AUTHORIZED");
}

module.exports = {
  inspectLegacyGoogleOwnerBridge,
};
