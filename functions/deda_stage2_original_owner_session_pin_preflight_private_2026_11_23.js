"use strict";

// Stage2 PRIVATE, NOT WIRED AND NOT DEPLOYED. No PIN issuance or approval.
// Fail-closed owner-session preflight for the existing single canonical
// manual PIN worker. A requester's phone/name/anonymous UID is NOT proof.
// A verified, recent non-anonymous Firebase Auth session must already belong
// to the original UID. Replacement-device requests without that proof stay
// on HOLD pending independently trusted account ownership verification.
// A preflight is NOT sufficient to authorize a later write: the eventual
// server-only approval transaction must recheck every owner and request link.
const {
  accountMatches, syncMarkerMatches,
} = require("./deda_pin_manual_recovery_compat_private_v1.js");

const MAX_REAUTH_AGE_SECONDS = 300;
const noProof = () => ({eligible: false, reason: "owner-proof-unavailable"});

async function verifyOriginalOwnerSessionBeforePinApproval({
  db, auth, requestId, idToken, nowMs = Date.now(),
} = {}) {
  if (!db || !auth || typeof auth.verifyIdToken !== "function" ||
      typeof auth.getUser !== "function" ||
      !/^[A-Za-z0-9_-]{6,160}$/.test(requestId || "") ||
      typeof idToken !== "string" || idToken.length < 8 ||
      !Number.isSafeInteger(nowMs)) return noProof();

  try {
    const requestSnap = await db.collection("recovery_requests")
        .doc(requestId).get();
    const request = requestSnap.exists ? requestSnap.data() : null;
    if (!request || !["new", "review"].includes(request.status) ||
        typeof request.accountKey !== "string" ||
        !/^(?:07\d{9}|9647\d{9})$/.test(request.accountKey)) {
      return noProof();
    }
    const key = request.accountKey;
    const dSnap = await db.collection("deda_account_directory").doc(key).get();
    const directory = dSnap.exists ? dSnap.data() : null;
    const uid = directory?.createdUid;
    if (typeof uid !== "string" || uid.length < 6 ||
        request.requesterUid !== uid) return noProof();

    // Independently verified by Admin Auth, never by client-supplied UID.
    const decoded = await auth.verifyIdToken(idToken, true);
    const nowSeconds = Math.floor(nowMs / 1000);
    if (decoded?.uid !== uid || decoded.firebase?.sign_in_provider !==
        "password" || decoded.email !== directory.authEmail ||
        !Number.isInteger(decoded.auth_time) ||
        decoded.auth_time > nowSeconds ||
        nowSeconds - decoded.auth_time > MAX_REAUTH_AGE_SECONDS) {
      return noProof();
    }

    const [credentialSnap, profileSnap, adminSnap, lockSnap, authUser] =
        await Promise.all([
          db.collection("deda_credentials").doc(key).get(),
          db.collection("users").doc(uid).get(),
          db.collection("admins").doc(uid).get(),
          db.collection("deda_pin_recovery_locks").doc(key).get(),
          auth.getUser(uid),
        ]);
    if (lockSnap.exists || !credentialSnap.exists || !profileSnap.exists ||
        !syncMarkerMatches(credentialSnap.data()) ||
        !accountMatches({
          key, directory, credential: credentialSnap.data(),
          profile: profileSnap.data(), adminExists: adminSnap.exists,
          authUser,
        })) return noProof();

    // No PIN, token, email, profile, or account ownership details returned.
    return {eligible: true, requestId, originalUid: uid, accountKey: key};
  } catch (_) {
    // Token revocation, offline Auth, malformed records: identical denial.
    return noProof();
  }
}

module.exports = {verifyOriginalOwnerSessionBeforePinApproval};
