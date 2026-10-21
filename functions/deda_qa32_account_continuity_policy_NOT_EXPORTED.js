"use strict";

// QA32 cross-device account recovery SAFETY POLICY ONLY.
// Not exported from functions/index.js; no live Firestore mutation.
// Caller must supply a fresh identity proof from trusted Firebase Admin
// session/phone verification, never from a client's accountKey parameter.
const ID = /^@DEDA-[A-Z0-9]{6}$/;
const FIELDS = ["xp", "taskPoints", "coins", "diamonds"];

function validUnsignedSafe(value) {
  return Number.isSafeInteger(value) && value >= 0;
}

function verifiedIdentity(proof) {
  if (!proof || typeof proof !== "object") return false;
  const canonical = proof.userAccountKey;
  const ownedPlaceKey = proof.publishedOwnerAccountKey;
  const hasPlace = proof.hasPublishedPlace === true;
  if (typeof proof.authUid !== "string" || !proof.authUid ||
      proof.userUid !== proof.authUid ||
      proof.sessionUid !== proof.authUid ||
      typeof canonical !== "string" || !canonical.trim() ||
      proof.sessionAccountKey !== canonical ||
      (hasPlace && (typeof ownedPlaceKey !== "string" ||
        ownedPlaceKey !== canonical)) ||
      (ownedPlaceKey != null && ownedPlaceKey !== canonical)) {
    return false;
  }
  if (typeof proof.originalId !== "string" ||
      !ID.test(proof.originalId) ||
      proof.originalId !== proof.sessionOriginalId) return false;
  // This boolean is a server-origin input only. The module does not
  // authorize remote access; Firestore Rules / Admin verifier must enforce it.
  return proof.verifiedPhoneByAdmin === true;
}

/** Returns READ_ONLY outcomes. Not a merge algorithm or authorization API. */
function inspectContinuity(proof, server, device) {
  if (!verifiedIdentity(proof)) {
    return Object.freeze({status: "blocked-identity", allowWrite: false});
  }
  if (!server || typeof server !== "object") {
    return Object.freeze({status: "needs-verified-recovery",
      allowWrite: false});
  }
  if (server.accountKey !== proof.userAccountKey ||
      server.originalId !== proof.originalId ||
      !validUnsignedSafe(server.ledgerRevision) ||
      FIELDS.some(field => !validUnsignedSafe(server[field]))) {
    return Object.freeze({status: "blocked-server-record", allowWrite: false});
  }
  // A new handset's fresh SharedPreferences is not evidence of a reset.
  // Device balances, even if larger, may include stale spend events or
  // duplicated task rewards: never auto-upload/merge via max or sum.
  const unusedDevice = device;
  void unusedDevice;
  return Object.freeze({
    status: "display-verified-server",
    allowWrite: false,
    ownerAccountKey: proof.userAccountKey,
    originalId: proof.originalId,
    ledgerRevision: server.ledgerRevision,
    xp: server.xp,
    taskPoints: server.taskPoints,
    coins: server.coins,
    diamonds: server.diamonds,
  });
}

module.exports = {inspectContinuity, verifiedIdentity};
