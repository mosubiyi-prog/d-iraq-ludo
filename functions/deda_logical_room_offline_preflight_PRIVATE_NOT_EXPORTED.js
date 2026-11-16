"use strict";

/**
 * DEDA logical identity room — OFFLINE DESIGN PREFLIGHT ONLY.
 *
 * NOT imported by functions/index.js; never exported as a Cloud Function.
 * No Firestore, Firebase Auth, token, claims, database, I/O or device access.
 * Inputs are hypothetical trusted-server snapshots supplied by an INTERNAL
 * tester only. This helper DOES NOT verify the provenance of those inputs.
 *
 * CRITICAL: Never turn a candidate here into an authorization decision.
 * A/B/C keep every record and UID. The live room needs separately verified
 * historical ownership and per-domain server-side authorization.
 */
const DOMAIN_SOURCES = Object.freeze({
  registration: "directory_and_credentials_created_uid",
  original_id: "immutable_original_id_owner_uid",
  premium_id: "original_id_and_verified_grants",
  frames: "original_id_and_purchase_receipts",
  social_profile: "social_profile_owner_uid",
  friends: "uid_pair_memberships_reconcile_individually",
  gifts: "original_id_and_unique_gift_receipts",
  diamonds: "account_key_original_id_and_ledger",
  level: "account_key_and_verified_xp_ledger",
  league: "account_key_and_weekly_account_receipts",
  tasks: "account_key_and_daily_task_receipts",
  places: "place_owner_uid_or_verified_account_key",
  settings: "device_local_and_verified_cloud_settings",
  administration: "separate_admins_authenticated_uid_gate",
});
const STRICT_ID = /^@DEDA-[A-Z0-9]{6}$/;
const STRICT_ACCOUNT = /^(?:07\d{9}|9647\d{9})$/;
const VALID_UID = /^[A-Za-z0-9:_-]{6,128}$/;
const OWNED_DOMAINS = new Set(Object.keys(DOMAIN_SOURCES));

function deny(reason) {
  return Object.freeze({
    decision: "HOLD", reason,
    crossUidReadPermitted: false,
    crossUidWritePermitted: false,
    loginPermitted: false,
    createUidPermitted: false,
    createTokenPermitted: false,
    adminEntryPermitted: false,
    financialGrantPermitted: false,
    domainPlans: Object.freeze([]),
  });
}
function inspectRoomCandidate({snapshot, sessionUid, domains} = {}) {
  if (!snapshot || typeof snapshot !== "object" ||
      Array.isArray(snapshot) || !STRICT_ACCOUNT.test(snapshot.accountKey) ||
      !STRICT_ID.test(snapshot.originalId)) return deny("INVALID_CANDIDATE");
  const {accountKey, originalId, directory, credentials, route, social,
    originalUser, registeredUser, socialUser} = snapshot;
  if (![directory,credentials,route,social,originalUser,registeredUser,socialUser]
      .every(x => x && typeof x === "object" && !Array.isArray(x))) {
    return deny("UNVERIFIED_RECORD_SHAPE");
  }
  const A = route.ownerUid, B = directory.createdUid, C = social.ownerUid;
  if (![A,B,C,credentials.createdUid].every(x =>
      typeof x === "string" && VALID_UID.test(x))) return deny("INVALID_UID_SHAPE");
  if (credentials.createdUid !== B ||
      directory.accountKey !== accountKey ||
      credentials.accountKey !== accountKey ||
      originalUser.accountKey !== accountKey ||
      registeredUser.accountKey !== accountKey ||
      socialUser.accountKey !== accountKey ||
      originalUser.sharePersonalId !== originalId ||
      socialUser.sharePersonalId !== originalId ||
      route.publicId !== originalId || route.kind !== "personal" ||
      route.active !== true || directory.active !== true ||
      credentials.active !== true || social.publicId !== originalId) {
    return deny("HISTORICAL_RECORD_CONFLICT");
  }
  if (!Array.isArray(domains) || domains.length === 0 ||
      domains.some(x => typeof x !== "string" || !OWNED_DOMAINS.has(x)) ||
      new Set(domains).size !== domains.length) return deny("INVALID_DOMAIN_SCOPE");
  const sessionKind = typeof sessionUid === "string" && VALID_UID.test(sessionUid)
    ? [A,B,C].includes(sessionUid) ? "historical_uid_seen" : "untrusted_current_uid"
    : "unverified_session";
  // Describes historical SOURCE KEYS, never claims that the current principal
  // owns any of them. All grants remain false irrespective of caller fields.
  const plans = domains.map(domain => Object.freeze({
    domain, historicalSource: DOMAIN_SOURCES[domain],
    authorization: "NOT_GRANTED",
    sourceWrite: false,
    sourceUidReassignment: false,
    duplicateReceiptIssuance: false,
    separateAdminVerification: domain === "administration",
  }));
  return Object.freeze({
    decision: "HOLD_FOR_INDEPENDENT_PROOF_AND_SERVER_RULES",
    reason: A !== B || B !== C ? "HISTORICAL_UID_SPLIT" : "AUTH_STILL_UNPROVEN",
    sessionKind,
    crossUidReadPermitted: false,
    crossUidWritePermitted: false,
    loginPermitted: false,
    createUidPermitted: false,
    createTokenPermitted: false,
    adminEntryPermitted: false,
    financialGrantPermitted: false,
    domainPlans: Object.freeze(plans),
  });
}
module.exports = {inspectRoomCandidate, DOMAIN_SOURCES};