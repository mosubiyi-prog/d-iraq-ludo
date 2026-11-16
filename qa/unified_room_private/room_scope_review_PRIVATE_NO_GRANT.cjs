"use strict";
// DEDA UNIFIED ROOM / PRIVATE QA ONLY / NEVER EXPORTED / NO AUTHORIZATION.
// A deterministic review plan, NOT a security oracle. All inputs in tests
// are synthetic. Do not call from Flutter or production Functions.
// Only a separately audited trusted service can verify real provenance.
const DOMAINS = Object.freeze(new Set([
  "profile", "original_id", "premium_id", "friends",
  "league", "gifts", "wallet", "places"
]));
const ACCOUNT = /^(?:07\d{9}|9647\d{9})$/;
const ORIGINAL = /^@DEDA-[A-Z0-9]{6}$/;
const UID = /^[A-Za-z0-9:_-]{6,128}$/;
function output(decision, reason, domain = null) {
  return Object.freeze({
    decision, reason, domain,
    grantsAccess: false,
    grantsWrite: false,
    issuesToken: false,
    changesUid: false,
    requiresIndependentOwnerProof: true,
    requiresTrustedServerEnforcement: true,
  });
}
function validUid(v) { return typeof v === "string" && UID.test(v); }
function planRoomRead({
  origin, auth, session, room, review, scope, domain, action, nowMs
} = {}) {
  if (domain === "admin" || domain === "administration")
    return output("HOLD", "ADMIN_UID_ROLE_SEPARATE", domain);
  if (!DOMAINS.has(domain))
    return output("HOLD", "UNKNOWN_DOMAIN", domain);
  if (action !== "read_projection")
    return output("HOLD", "NO_CROSS_UID_MUTATION", domain);
  // This marker is *only* an offline fixture label, never a trust proof.
  if (origin !== "private-offline-synthetic")
    return output("HOLD", "NO_SYNTHETIC_REVIEW_CONTEXT", domain);
  if (!auth || !validUid(auth.uid) || auth.anonymous !== false ||
      auth.provider !== "durable-verified" ||
      !Number.isSafeInteger(auth.epoch) || auth.epoch < 1)
    return output("HOLD", "NO_DURABLE_AUTH_OBSERVATION", domain);
  if (!session || session.uid !== auth.uid ||
      session.epoch !== auth.epoch || session.accountKey !== room?.accountKey)
    return output("HOLD", "SESSION_IDENTITY_CHANGED_OR_MISSING", domain);
  if (!room || !ACCOUNT.test(room.accountKey || "") ||
      !ORIGINAL.test(room.originalId || "") ||
      !Array.isArray(room.historicalUids) ||
      new Set(room.historicalUids).size !== 3 ||
      room.historicalUids.length !== 3 ||
      !room.historicalUids.every(validUid) ||
      !room.historicalUids.includes(auth.uid))
    return output("HOLD", "INVALID_OR_UNLINKED_HISTORICAL_ROOM", domain);
  if (!review || review.status !== "INDEPENDENT_OWNER_REVIEWED" ||
      review.accountKey !== room.accountKey ||
      review.originalId !== room.originalId ||
      review.callerUid !== auth.uid ||
      !Number.isSafeInteger(nowMs) ||
      !Number.isSafeInteger(review.reviewedAtMs) ||
      nowMs < review.reviewedAtMs || nowMs - review.reviewedAtMs > 600000 ||
      review.separatelyAudited !== true)
    return output("HOLD", "NO_RECENT_INDEPENDENT_OWNER_REVIEW", domain);
  if (!scope || scope.domain !== domain ||
      scope.accountKey !== room.accountKey ||
      scope.originalId !== room.originalId ||
      scope.readerUid !== auth.uid ||
      !validUid(scope.sourceUid) ||
      !room.historicalUids.includes(scope.sourceUid) ||
      scope.independentlyReviewed !== true ||
      scope.sourceStatus !== "HISTORIC_UNMODIFIED" ||
      scope.reviewId !== review.reviewId ||
      typeof scope.reviewId !== "string" ||
      scope.reviewId.length < 12)
    return output("HOLD", "NO_DOMAIN_SPECIFIC_SOURCE_REVIEW", domain);
  // A CANDIDATE cannot read Firestore. Runtime must enforce signed, scoped
  // server authorization and Firestore Rules compatibility separately.
  return output("READ_PLAN_CANDIDATE", "SERVER_AUTHORIZATION_STILL_REQUIRED", domain);
}
module.exports = {planRoomRead, DOMAINS};
