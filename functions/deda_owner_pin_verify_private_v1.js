"use strict";

// DEDA 100436 — PRIVATE, NOT WIRED TO functions/index.js.
// Candidate callable for explicit replacement-phone owner sign-in only.
// NO deployment, rules mutation, PIN change, admin grant, or data transfer.
// Must be approved and subjected to Auth/AppCheck/Firestore emulator QA first.
const {timingSafeEqual} = require("node:crypto");
const {syncMarkerMatches} = require("./deda_pin_manual_recovery_compat_private_v1.js");
const {recoveryCallableOptions} = require("./deda_stage2_runtime_identity.js");

const WINDOW_MS = 15 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;
const MAX_WINDOW_ATTEMPTS = 5;
const MAX_DAY_ATTEMPTS = 20;

function accountKeyForPhone(value) {
  if (typeof value !== "string") return null;
  const key = value.replace(/[\s()-]/g, "");
  // Preserve the accountKey EXACTLY as created. Never silently migrate a
  // stored 07... account into a different 964... account.
  return /^(?:07\d{9}|9647\d{9})$/.test(key) ? key : null;
}

function pinMatches(stored, submitted) {
  const candidate = typeof stored === "string" && /^\d{6}$/.test(stored) ?
    stored : "000000";
  const a = Buffer.from(candidate, "utf8");
  const b = Buffer.from(submitted, "utf8");
  return b.length === a.length && timingSafeEqual(a, b) &&
    typeof stored === "string" && /^\d{6}$/.test(stored);
}

// Consume an attempt BEFORE verifying the PIN. Account-scoped, atomic and
// shared across devices and anonymous Firebase UIDs. No PIN or token stored.
async function consumeAttempt(db, accountKey, nowMs) {
  const ref = db.collection("deda_owner_pin_verify_limits").doc(accountKey);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const last = snap.exists ? snap.data() || {} : {};
    const oldWindow = Number.isSafeInteger(last.windowStartMs) ?
      last.windowStartMs : -1;
    const sameWindow = oldWindow >= 0 && nowMs >= oldWindow &&
      nowMs - oldWindow < WINDOW_MS;
    const windowStartMs = sameWindow ? oldWindow : nowMs;
    const windowAttempts = sameWindow &&
      Number.isSafeInteger(last.windowAttempts) ?
      last.windowAttempts : 0;
    const dayBucket = Math.floor(nowMs / DAY_MS);
    const sameDay = last.dayBucket === dayBucket;
    const dayAttempts = sameDay && Number.isSafeInteger(last.dayAttempts) ?
      last.dayAttempts : 0;
    if (windowAttempts >= MAX_WINDOW_ATTEMPTS ||
        dayAttempts >= MAX_DAY_ATTEMPTS) return false;
    tx.set(ref, {
      windowStartMs, windowAttempts: windowAttempts + 1,
      dayBucket, dayAttempts: dayAttempts + 1,
      lastAttemptMs: nowMs,
    });
    return true;
  });
}

function validCanonicalProof({key, directory, credentials, projection,
  route, adminExists, authUser}) {
  if (!directory || !credentials || !projection || !route ||
      adminExists || directory.active !== true ||
      credentials.active !== true ||
      directory.accountKey !== key || credentials.accountKey !== key ||
      projection.accountKey !== key) return null;

  const uid = directory.createdUid;
  const originalId = projection.sharePersonalId;
  if (typeof uid !== "string" || uid.length < 6 ||
      credentials.createdUid !== uid ||
      !/^@DEDA-[A-Z0-9]{6}$/.test(originalId) ||
      route.publicId !== originalId || route.kind !== "personal" ||
      route.active !== true || route.ownerUid !== uid ||
      !authUser || authUser.uid !== uid || authUser.disabled === true ||
      authUser.email !== `${key}@deda-login.invalid` ||
      (directory.authEmail != null &&
        directory.authEmail !== authUser.email)) return null;
  return {originalUid: uid, originalId};
}

function createOwnerPinVerifyCallable({onCall, HttpsError, db, auth,
  now = Date.now, enabled = false,
  // Only unit-test injection; the production index NEVER provides this.
  allowLegacyCustomTokensForQa = false}) {
  if (typeof onCall !== "function" || typeof HttpsError !== "function" ||
      !db || !auth) throw new TypeError("missing-server-dependencies");
  const deny = () => {
    // Same public error for incorrect PIN, missing account, unlinked UID,
    // rate limit, and temporary server failures: no account enumeration.
    throw new HttpsError("permission-denied", "owner-verification-unavailable");
  };
  return onCall(recoveryCallableOptions(30), async (request) => {
    if (!enabled || !request || !request.app?.appId ||
        !request.auth?.uid ||
        request.auth.token?.firebase?.sign_in_provider !== "anonymous") {
      return deny();
    }
    const key = accountKeyForPhone(request.data?.phone);
    const pin = request.data?.pin;
    if (!key || typeof pin !== "string" || !/^\d{6}$/.test(pin)) {
      return deny();
    }

    try {
      const nowMs = now();
      if (!Number.isSafeInteger(nowMs) ||
          !await consumeAttempt(db, key, nowMs)) return deny();

      const [directorySnap, credentialSnap, lockSnap] = await Promise.all([
        db.collection("deda_account_directory").doc(key).get(),
        db.collection("deda_credentials").doc(key).get(),
        db.collection("deda_pin_recovery_locks").doc(key).get(),
      ]);
      const directory = directorySnap.exists ? directorySnap.data() : null;
      const credentials = credentialSnap.exists ? credentialSnap.data() : null;
      // An old PIN must never pass when Firebase Auth and Firestore have
      // diverged, or when a rotation was committed but not acknowledged.
      // Existing linked owners need an explicitly synchronized migration;
      // an absent or stale sync marker fails CLOSED.
      if (lockSnap.exists || !syncMarkerMatches(credentials) ||
          !pinMatches(credentials?.pin, pin)) return deny();

      const uid = directory?.createdUid;
      if (typeof uid !== "string" || uid.length < 6) return deny();
      const [userSnap, adminSnap] = await Promise.all([
        db.collection("users").doc(uid).get(),
        db.collection("admins").doc(uid).get(),
      ]);
      const projection = userSnap.exists ? userSnap.data() : null;
      const originalId = projection?.sharePersonalId;
      if (typeof originalId !== "string" ||
          !/^@DEDA-[A-Z0-9]{6}$/.test(originalId)) return deny();
      const [routeSnap, authUser] = await Promise.all([
        db.collection("deda_share_ids").doc(originalId).get(),
        auth.getUser(uid),
      ]);
      const proof = validCanonicalProof({
        key, directory, credentials, projection,
        route: routeSnap.exists ? routeSnap.data() : null,
        adminExists: adminSnap.exists, authUser,
      });
      if (!proof) return deny();

      // Existing linked-owner Firebase Auth password-provider sessions are
      // the mode tested by the two-device session bootstrap rules. Return
      // owner proof after rate-limited verification, without minting a
      // custom token; the client still MUST prove the SAME UID using
      // signInWithEmailAndPassword before any authorized session write.
      if (request.data?.proofMode === "linked-password") {
        return {
          originalUid: proof.originalUid, originalId: proof.originalId,
          accountKey: key,
        };
      }
      // Production never issues a custom Auth token merely from a six-digit
      // legacy PIN. That would bypass the linked password provider/session
      // flow. Only an explicitly injected private test can exercise this path.
      if (allowLegacyCustomTokensForQa !== true) return deny();
      const customToken = await auth.createCustomToken(proof.originalUid);
      if (typeof customToken !== "string" || !customToken) return deny();
      return {
        customToken, originalUid: proof.originalUid,
        originalId: proof.originalId, accountKey: key,
      };
    } catch (_) {
      // Never log PIN, phone, token, or a distinct "account not found" error.
      return deny();
    }
  });
}

module.exports = {
  accountKeyForPhone, pinMatches, consumeAttempt,
  validCanonicalProof, createOwnerPinVerifyCallable,
};
