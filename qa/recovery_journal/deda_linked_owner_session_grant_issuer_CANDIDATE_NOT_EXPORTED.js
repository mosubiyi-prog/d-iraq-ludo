"use strict";

// DEDA WORK VAULT / PRIVATE 100436 EMULATOR-ONLY CANDIDATE.
// NOT imported by functions/index.js, NOT deployed, NO real users or Firebase.
// This callable issues a narrowly scoped two-minute session-bootstrap grant
// AFTER an original UID signs in through Firebase password Auth.
//
// A six-digit PIN is weak: production activation also requires Firebase Auth
// abuse controls, mandatory AppCheck and server-side per-UID rate limits.
// This candidate never returns PINs, writes sessions, grants diamonds, changes
// user metadata, creates accounts, or bypasses the original UID.
//
// The grant is bound to the ORIGINAL UID, account key, normal public ID, and
// existing device installation ID; it cannot authorize an admin session.

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");

const ENABLED = process.env.DEDA_LINKED_OWNER_GRANT_ISSUER_ENABLED === "true";
const GRANT_MS = 2 * 60 * 1000;
const HOUR_MS = 60 * 60 * 1000;
const MAX_PER_HOUR = 3;
const deny = (code, message) => { throw new HttpsError(code, message); };
const validAccount = x => typeof x === "string" && /^[0-9]{10,16}$/.test(x);
const validId = x => typeof x === "string" && /^@DEDA-[A-Z0-9]{6}$/.test(x);
const validInstall = x => typeof x === "string" && /^[0-9a-f]{48}$/.test(x);
const ts = x => x && typeof x.toMillis === "function" ? x.toMillis() : NaN;

async function issueLinkedOwnerGrant(request, db = getFirestore(),
    nowMs = Date.now()) {
  if (!ENABLED) deny("unavailable", "linked-owner-bootstrap-not-enabled");
  if (!request?.auth?.uid) deny("unauthenticated", "firebase-linked-owner-required");
  if (!request?.app?.appId) deny("permission-denied", "valid-appcheck-required");
  const uid = request.auth.uid;
  const data = request.data;
  if (!data || typeof data !== "object" || Array.isArray(data) ||
      Object.keys(data).length !== 3 ||
      !["accountKey", "originalId", "installId"].every(x =>
        Object.prototype.hasOwnProperty.call(data, x))) {
    deny("invalid-argument", "invalid-bootstrap-fields");
  }
  const {accountKey, originalId, installId} = data;
  if (!validAccount(accountKey) || !validId(originalId) ||
      !validInstall(installId) ||
      request.auth.token?.firebase?.sign_in_provider !== "password" ||
      request.auth.token?.email !== accountKey + "@deda-login.invalid") {
    deny("permission-denied", "original-uid-owner-auth-required");
  }
  if (!Number.isSafeInteger(nowMs) || nowMs <= 0) {
    deny("invalid-argument", "invalid-server-clock");
  }

  const directoryRef = db.doc("deda_account_directory/" + accountKey);
  const credentialRef = db.doc("deda_credentials/" + accountKey);
  const userRef = db.doc("users/" + uid);
  const routeRef = db.doc("deda_share_ids/" + originalId);
  const adminRef = db.doc("admins/" + uid);
  const sessionRef = db.doc("deda_sessions/" + uid);
  const grantRef = db.doc(
      "deda_recovery_session_bootstrap_grants/" + uid +
      "/installs/" + installId);
  const limitRef = db.doc("deda_recovery_session_grant_limits/" + uid);

  // A transaction retries only Firestore reads/writes. NO reward/PIN/account
  // side effects occur inside it. All eight reads precede any mutation.
  return db.runTransaction(async tx => {
    const [directory, credential, user, route, admin, session, grant, limit] =
      await Promise.all([
        tx.get(directoryRef), tx.get(credentialRef), tx.get(userRef),
        tx.get(routeRef), tx.get(adminRef), tx.get(sessionRef),
        tx.get(grantRef), tx.get(limitRef),
      ]);
    const d=directory.data(), c=credential.data(), u=user.data(),
          r=route.data(), existing=session.data(), old=grant.data(),
          limiter=limit.data();
    if (!directory.exists || !credential.exists || !user.exists ||
        !route.exists || admin.exists ||
        d.accountKey !== accountKey || d.active !== true ||
        d.createdUid !== uid ||
        c.accountKey !== accountKey || c.active !== true ||
        c.createdUid !== uid ||
        u.accountKey !== accountKey || u.sharePersonalId !== originalId ||
        r.publicId !== originalId || r.kind !== "personal" ||
        r.active !== true || r.ownerUid !== uid ||
        (session.exists &&
          (existing.uid !== uid || existing.accountKey !== accountKey))) {
      deny("permission-denied", "immutable-original-uid-evidence-missing");
    }

    // Repeated requests on an already approved, unexpired same-device grant
    // are truly read-only and consume no additional rate-limit allowance.
    if (grant.exists && old.ownerUid === uid &&
        old.accountKey === accountKey && old.originalId === originalId &&
        old.installId === installId &&
        old.purpose === "linked_uid_new_device_session_v1" &&
        old.state === "approved" && ts(old.issuedAt) <= nowMs &&
        ts(old.expiresAt) > nowMs &&
        ts(old.expiresAt) - ts(old.issuedAt) <= 5 * 60 * 1000) {
      return {approved: true, reused: true, expiresAtMs: ts(old.expiresAt)};
    }

    const windowStartedAt = ts(limiter?.windowStartedAt);
    const withinHour = limit.exists && Number.isFinite(windowStartedAt) &&
      nowMs >= windowStartedAt && nowMs - windowStartedAt < HOUR_MS;
    const previousCount = withinHour ? limiter.count : 0;
    if (!Number.isInteger(previousCount) ||
        previousCount < 0 || previousCount >= MAX_PER_HOUR) {
      deny("resource-exhausted", "linked-owner-grant-hourly-limit");
    }
    const issuedAt = Timestamp.fromMillis(nowMs);
    const expiresAt = Timestamp.fromMillis(nowMs + GRANT_MS);
    tx.set(grantRef, {
      ownerUid: uid, accountKey, originalId, installId,
      purpose: "linked_uid_new_device_session_v1",
      state: "approved", issuedAt, expiresAt,
    });
    tx.set(limitRef, {
      ownerUid: uid,
      windowStartedAt: withinHour ? limiter.windowStartedAt : issuedAt,
      count: previousCount + 1,
      updatedAt: issuedAt,
    });
    return {approved: true, reused: false, expiresAtMs: nowMs + GRANT_MS};
  });
}

// Exporting from this isolated file does not publish any Cloud Function.
// Production requires separate owner permission, deployed rules review,
// App Check, Auth abuse protections and a new QA signing round.
exports.dedaIssueLinkedOriginalUidDeviceGrant = onCall(
  {enforceAppCheck: true, timeoutSeconds: 20},
  request => issueLinkedOwnerGrant(request));
exports.__privateIssueLinkedOwnerGrantForQaOnly = issueLinkedOwnerGrant;
