"use strict";

// DEDA 100441 — ISOLATED, SOURCE-ONLY anti-split assessment.
// NOT imported by functions/index.js; NOT a Callable, Auth provider or rule.
// No Firebase reads, writes, token creation, migration or login capability.
// The caller MUST collect all evidence itself using independently trusted
// server-side sources. Client-provided fields must NEVER authorize anything.
// Legacy 100340 remains untouched. This module is a future-rollout preflight.

const ACCOUNT_KEY = /^(?:07\d{9}|9647\d{9})$/;
const ORIGINAL_ID = /^@DEDA-[A-Z0-9]{6}$/;
const UID = /^[A-Za-z0-9:_-]{6,128}$/;
const VALID_PROVIDERS = new Set(["password", "google.com", "phone"]);

function uid(value) {
  return typeof value === "string" && UID.test(value);
}

function result(status, detail) {
  return Object.freeze({
    status,
    detail,
    // Intentionally never an authorization result, even if all rows match.
    canSignIn: false,
    canCreateUid: false,
    canReassignOwner: false,
    canWriteFirestore: false,
    canModifyAdmin: false,
    canModifyFinances: false,
    requiresSeparateOwnerProof: true,
    legacyProductionUnchanged: true,
  });
}

/**
 * Pure read-only classification of a TRUSTED SERVER SNAPSHOT.
 * This module does not verify the snapshot's provenance. Do not call with
 * Firestore reads controlled by the user or with a client-asserted UID.
 *
 * @param {Object} snapshot
 * @param {string} snapshot.accountKey
 * @param {string} snapshot.originalId immutable six-character DEDA ID
 * @param {?Object} snapshot.directory deda_account_directory metadata
 * @param {?Object} snapshot.credentials metadata only; NEVER pass raw PIN
 * @param {?Object} snapshot.route deda_share_ids/{originalId}
 * @param {?Object} snapshot.user users/{directory.createdUid}
 * @param {?Object} snapshot.social deda_social_profiles/{originalId}
 * @param {?Object} snapshot.session deda_sessions/{liveAuthUid}
 * @param {?string} snapshot.liveAuthUid from server-verified Firebase Auth
 * @param {?string} snapshot.authProvider from server-verified Firebase Auth
 */
function inspectCanonicalUid(snapshot) {
  if (!snapshot || typeof snapshot !== "object" ||
      Array.isArray(snapshot) ||
      !ACCOUNT_KEY.test(snapshot.accountKey || "") ||
      !ORIGINAL_ID.test(snapshot.originalId || "")) {
    return result("HOLD", "INVALID_ACCOUNT_OR_ORIGINAL_ID");
  }

  const {accountKey, originalId, directory, credentials,
    route, user, social, session, liveAuthUid, authProvider} = snapshot;

  if (!directory && !credentials) {
    // Fresh registration is a SEPARATE operation. Never implicitly create a
    // Firebase UID simply because a phone/account record is absent.
    return result("HOLD", "NO_VERIFIED_ACCOUNT_REGISTRATION");
  }
  if (!directory || !credentials) {
    return result("HOLD", "PARTIAL_ACCOUNT_REGISTRATION");
  }
  const createdUid = directory.createdUid;
  if (!uid(createdUid) || !uid(credentials.createdUid) ||
      directory.active !== true || credentials.active !== true ||
      directory.accountKey !== accountKey ||
      credentials.accountKey !== accountKey) {
    return result("HOLD", "INVALID_ACCOUNT_REGISTRATION");
  }
  if (createdUid !== credentials.createdUid) {
    return result("SPLIT", "DIRECTORY_AND_CREDENTIAL_UID_MISMATCH");
  }

  if (!route || route.publicId !== originalId ||
      route.kind !== "personal" || route.active !== true ||
      !uid(route.ownerUid)) {
    // Some legacy owners have incomplete route projections. Keep their
    // existing client untouched; do not invent or transfer ownership.
    return result("HOLD", "ORIGINAL_ID_ROUTE_NOT_VERIFIED");
  }
  if (route.ownerUid !== createdUid) {
    return result("SPLIT", "ORIGINAL_ROUTE_VS_REGISTRATION_UID");
  }
  if (!user || user.accountKey !== accountKey ||
      user.sharePersonalId !== originalId) {
    return result("HOLD", "REGISTERED_USER_PROJECTION_NOT_VERIFIED");
  }
  if (!social || social.publicId !== originalId ||
      !uid(social.ownerUid)) {
    return result("HOLD", "SOCIAL_PROJECTION_NOT_VERIFIED");
  }
  if (social.ownerUid !== createdUid) {
    return result("SPLIT", "SOCIAL_VS_REGISTRATION_UID");
  }

  if (!uid(liveAuthUid)) {
    return result("HOLD", "NO_VERIFIED_LIVE_AUTH_UID");
  }
  if (liveAuthUid !== createdUid) {
    // A successful six-digit PIN check on a NEW anonymous Firebase UID
    // must never be interpreted as the right to adopt the existing account.
    return result("SPLIT", "LIVE_AUTH_UID_NOT_CANONICAL");
  }
  if (!session || session.uid !== liveAuthUid ||
      session.accountKey !== accountKey) {
    return result("HOLD", "LIVE_SERVER_SESSION_NOT_VERIFIED");
  }
  if (authProvider === "anonymous" || !VALID_PROVIDERS.has(authProvider)) {
    // A matching anonymous session may belong to the old device, but is
    // not a durable replacement-phone identity or independent owner proof.
    return result("HOLD", "NO_DURABLE_AUTH_PROVIDER");
  }

  return result("MATCH_CANDIDATE", "REQUIRES_SEPARATE_AUTH_AND_OWNER_REVIEW");
}

module.exports = {inspectCanonicalUid};
