"use strict";

// DEDA 100441 — SOURCE-ONLY, NOT DEPLOYED, NOT EXPORTED BY functions/index.js.
// Future non-mutating canonical UID preflight Callable candidate.
//
// An explicit operator-reviewed feature switch MUST be supplied by a separate
// trusted server module. OFF by default, with NO environment-driven auto-enable.
// No client credential/phone/PIN establishes ownership. No custom token,
// sign-in, UID creation, owner migration, admin access, reward or wallet writes.
// Every response is identical regardless of whether an account exists or
// whether its canonical records match. Legacy 100340 is NOT routed here.
//
// This is not a complete rollout: independent owner proof, client transition,
// backup/rollback, rate-limit key provisioning, IAM and device QA are still
// blockers. The only potential write here is a separate rate-limit ledger,
// and this file is not wired to the production Functions entrypoint.

const {createHmac} = require("node:crypto");
const {recoveryCallableOptions} = require("./deda_stage2_runtime_identity.js");
const {
  inspectServerCanonicalOwner,
} = require("./deda_100441_server_canonical_uid_read_adapter_PRIVATE_NOT_EXPORTED.js");

const ACCOUNT = /^(?:07\d{9}|9647\d{9})$/;
const ORIGINAL_ID = /^@DEDA-[A-Z0-9]{6}$/;
const AUTH_UID = /^[A-Za-z0-9:_-]{6,128}$/;
const MAX_TOKEN_LENGTH = 8192;
const WINDOW_MS = 60 * 60 * 1000;
const DAY_MS = 24 * WINDOW_MS;
const MAX_WINDOW = 5;
const MAX_DAY = 12;

function isValidKey(key) {
  return (typeof key === "string" && key.length >= 32) ||
    (Buffer.isBuffer(key) && key.length >= 32);
}
function opaqueBucket(accountKey, key) {
  if (!ACCOUNT.test(accountKey) || !isValidKey(key)) {
    throw new TypeError("server-only-limiter-key-required");
  }
  // Server-only HMAC key, never a client-supplied secret, no plaintext account
  // numbers or raw PIN stored in rate-limiter document IDs.
  return createHmac("sha256", key)
    .update("deda-100441-uid-preflight-limit/v1:", "utf8")
    .update(accountKey, "utf8")
    .digest("hex");
}
function validCount(value) {
  return Number.isSafeInteger(value) && value >= 0;
}

/**
 * Consume a rate-limit attempt BEFORE reading any account records.
 * A transaction on one account bucket prevents races across UIDs/phones.
 * Failure, corrupted state or missing permissions must DENY, not bypass.
 * Only writes to deda_100441_uid_preflight_rate_limits (never user data).
 */
async function consumeAccountScopedLimit(db, accountKey, key, nowMs) {
  if (!db || typeof db.doc !== "function" ||
      typeof db.runTransaction !== "function" ||
      !Number.isSafeInteger(nowMs) || nowMs <= 0) return false;
  let digest;
  try { digest = opaqueBucket(accountKey, key); } catch (_) {return false;}
  const ref = db.doc("deda_100441_uid_preflight_rate_limits/" + digest);
  try {
    return await db.runTransaction(async tx => {
      const snapshot = await tx.get(ref);
      const old = snapshot.exists ? snapshot.data() : null;
      if (snapshot.exists && (!old || typeof old !== "object")) return false;
      const windowStartMs = old?.windowStartMs;
      const currentWindow = windowStartMs != null &&
        Number.isSafeInteger(windowStartMs) && nowMs >= windowStartMs &&
        nowMs - windowStartMs < WINDOW_MS;
      const dayBucket = Math.floor(nowMs / DAY_MS);
      const currentDay = old?.dayBucket === dayBucket;

      // Corrupted counters never silently reset within an existing period.
      if ((currentWindow && !validCount(old?.windowCount)) ||
          (currentDay && !validCount(old?.dayCount)) ||
          (snapshot.exists && old?.version !== 1)) return false;

      const windowCount = currentWindow ? old.windowCount : 0;
      const dayCount = currentDay ? old.dayCount : 0;
      if (windowCount >= MAX_WINDOW || dayCount >= MAX_DAY) return false;
      tx.set(ref, {
        version: 1,
        windowStartMs: currentWindow ? windowStartMs : nowMs,
        windowCount: windowCount + 1,
        dayBucket,
        dayCount: dayCount + 1,
        lastAttemptMs: nowMs,
      });
      return true;
    });
  } catch (_) {
    return false;
  }
}

function bearerToken(request) {
  const header = request?.rawRequest?.headers?.authorization;
  if (typeof header !== "string") return null;
  const match = /^Bearer ([A-Za-z0-9._~+/=-]+)$/.exec(header);
  return match && match[1].length >= 16 &&
    match[1].length <= MAX_TOKEN_LENGTH ? match[1] : null;
}

function publicReviewStatus() {
  // Client never receives a UID, registered phone, public ID, account
  // existence, match/split diagnosis, raw PIN, limits or owner privileges.
  return Object.freeze({status: "review_required"});
}

function createPrivateCanonicalUidPreflightCallable({
  onCall, HttpsError, auth, db, limiterKey,
  now = Date.now, enabled = false,
} = {}) {
  if (typeof onCall !== "function" ||
      typeof HttpsError !== "function" ||
      typeof auth?.verifyIdToken !== "function" ||
      typeof auth?.getUser !== "function" ||
      typeof db?.doc !== "function" ||
      typeof db?.runTransaction !== "function") {
    throw new TypeError("trusted-server-dependencies-required");
  }
  function deny() {
    // The same public denial is used for disabled, malformed, missing app
    // check, untrusted caller, rate limit, unavailable server and errors.
    throw new HttpsError("permission-denied", "owner-review-unavailable");
  }
  return onCall(recoveryCallableOptions(25), async request => {
    if (enabled !== true ||
        !isValidKey(limiterKey) ||
        !request?.app?.appId ||
        !AUTH_UID.test(request?.auth?.uid || "") ||
        request?.auth?.token?.firebase?.sign_in_provider === "anonymous") {
      return deny();
    }
    const d = request.data;
    if (!d || typeof d !== "object" || Array.isArray(d) ||
        Object.keys(d).length !== 2 ||
        !Object.prototype.hasOwnProperty.call(d, "accountKey") ||
        !Object.prototype.hasOwnProperty.call(d, "originalId") ||
        !ACCOUNT.test(d.accountKey || "") ||
        !ORIGINAL_ID.test(d.originalId || "")) {
      return deny();
    }
    const idToken = bearerToken(request);
    if (!idToken) return deny();

    try {
      // Require Firebase Auth verifier and Callable framework to agree:
      // client-supplied UID or Firebase provider metadata is never enough.
      const decoded = await auth.verifyIdToken(idToken, true);
      if (decoded?.uid !== request.auth.uid) return deny();

      const allowed = await consumeAccountScopedLimit(
        db, d.accountKey, limiterKey, now()
      );
      if (!allowed) return deny();

      // The existing source-only adapter independently checks ID token,
      // Auth UserRecord and canonical Firestore evidence. No new auth logic.
      const checked = await inspectServerCanonicalOwner({
        accountKey: d.accountKey, originalId: d.originalId, idToken,
      }, {auth, db});
      if (checked?.decision !== "HOLD_FOR_INDEPENDENT_OWNER_REVIEW" ||
          checked.canSignIn !== false ||
          checked.canIssueToken !== false ||
          checked.canCreateUid !== false ||
          checked.canReassignOwner !== false ||
          checked.canWriteFirestore !== false ||
          checked.canModifyAdmin !== false ||
          checked.canModifyFinances !== false) {
        return deny();
      }

      // Intentionally identical response for canonical, split, incomplete,
      // unrelated or missing accounts. Still NOT an owner verification.
      return publicReviewStatus();
    } catch (_) {
      return deny();
    }
  });
}

// Export only the factory & limiter for PRIVATE OFFLINE TESTS. No onCall
// registration is made here; functions/index.js MUST NOT import this file.
module.exports = {
  createPrivateCanonicalUidPreflightCallable,
  consumeAccountScopedLimit,
};
