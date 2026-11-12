"use strict";

// DEDA 100441 — PRIVATE SERVER-SIDE READ ADAPTER, NOT A CALLABLE.
// No import by functions/index.js; no HTTP trigger, token minting, Auth link,
// Firestore write, credential rotation, finance/admin action or UID migration.
// LEGACY 100340 production traffic is not routed through this adapter.
//
// This module accepts Firebase Admin Auth and Firestore objects injected by an
// INTERNAL trusted server process; NEVER invoke from a browser/client. Caller
// must enforce App Check, abuse controls and account-enumeration protection
// before any future external exposure. Inputs alone never prove ownership.
// All statuses are review-only, including a completely matching account.

const {
  inspectCanonicalUid,
} = require("./deda_100441_canonical_uid_anti_split_preflight_PRIVATE_NOT_EXPORTED.js");

const ACCOUNT = /^(?:07\d{9}|9647\d{9})$/;
const ORIGINAL_ID = /^@DEDA-[A-Z0-9]{6}$/;
const UID = /^[A-Za-z0-9:_-]{6,128}$/;
const DURABLE_PROVIDER = new Set(["password", "google.com", "phone"]);
const MAX_TOKEN_LENGTH = 8192;

function outcome(classification) {
  return Object.freeze({
    decision: "HOLD_FOR_INDEPENDENT_OWNER_REVIEW",
    classification,
    canSignIn: false,
    canIssueToken: false,
    canCreateUid: false,
    canModifyAuth: false,
    canWriteFirestore: false,
    canReassignOwner: false,
    canModifyAdmin: false,
    canModifyFinances: false,
    // Do NOT expose the account existence/result to clients.
    serverInternalOnly: true,
  });
}

function dataOrNull(snapshot) {
  if (!snapshot || snapshot.exists !== true ||
      typeof snapshot.data !== "function") return null;
  const data = snapshot.data();
  return data && typeof data === "object" && !Array.isArray(data)
    ? data : null;
}

function asUid(value) {
  return typeof value === "string" && UID.test(value);
}

function verifiedProvider(decoded, record, accountKey) {
  if (!decoded || !record || record.disabled === true ||
      !asUid(decoded.uid) || record.uid !== decoded.uid) return null;
  const provider = decoded.firebase?.sign_in_provider;
  if (!DURABLE_PROVIDER.has(provider)) return null;
  if (provider === "password") {
    // Firebase Admin UserRecord.providerData need not list "password".
    const expected = accountKey + "@deda-login.invalid";
    if (record.email !== expected || decoded.email !== expected) return null;
    return provider;
  }
  if (!Array.isArray(record.providerData) ||
      !record.providerData.some(item => item?.providerId === provider)) {
    return null;
  }
  return provider;
}

function metadataOnlyAccount(document) {
  if (!document) return null;
  // Never pass the stored PIN to the preflight or any return value.
  return {
    accountKey: document.accountKey,
    createdUid: document.createdUid,
    active: document.active,
  };
}

function metadataOnlyRoute(document) {
  if (!document) return null;
  return {
    publicId: document.publicId, kind: document.kind,
    active: document.active, ownerUid: document.ownerUid,
  };
}

/**
 * Build an internal review-only outcome using ONLY server-verified evidence.
 * Auth ID token verification (with checkRevoked=true) happens before any
 * Firestore document lookup. The Firebase Admin SDK validates signature,
 * issuer, audience, expiration, disabled/revocation and project binding.
 *
 * @param {object} input - accountKey, originalId and Firebase ID token
 * @param {object} deps - injected trusted Firebase Admin auth & firestore
 * @returns {Readonly<object>} HOLD only; never a login/ownership grant.
 */
async function inspectServerCanonicalOwner(input, deps) {
  if (!input || typeof input !== "object" || Array.isArray(input) ||
      typeof input.idToken !== "string" ||
      input.idToken.length < 16 || input.idToken.length > MAX_TOKEN_LENGTH ||
      !ACCOUNT.test(input.accountKey || "") ||
      !ORIGINAL_ID.test(input.originalId || "") ||
      !deps || typeof deps.auth?.verifyIdToken !== "function" ||
      typeof deps.auth?.getUser !== "function" ||
      typeof deps.db?.doc !== "function") {
    return outcome("INVALID_OR_UNVERIFIED_REQUEST");
  }

  let decoded, record, provider;
  try {
    // Never trust a client-supplied uid, provider, phone or account record.
    decoded = await deps.auth.verifyIdToken(input.idToken, true);
    if (!asUid(decoded?.uid)) return outcome("UNVERIFIED_AUTH_SESSION");
    record = await deps.auth.getUser(decoded.uid);
    provider = verifiedProvider(decoded, record, input.accountKey);
    if (!provider) return outcome("NO_INDEPENDENT_DURABLE_AUTH");
  } catch (_) {
    // Treat expired/revoked/disabled/unknown token indistinguishably.
    return outcome("UNVERIFIED_AUTH_SESSION");
  }

  const uid = decoded.uid;
  try {
    const names = [
      "deda_account_directory/" + input.accountKey,
      "deda_credentials/" + input.accountKey,
      "deda_share_ids/" + input.originalId,
      "users/" + uid,
      "deda_social_profiles/" + input.originalId,
      "deda_sessions/" + uid,
      "admins/" + uid,
    ];
    // Reads only; no batches, transactions, SET/UPDATE/DELETE or writes.
    const results = await Promise.all(names.map(path => deps.db.doc(path).get()));
    if (results[6]?.exists === true ||
        record.customClaims?.admin === true) {
      // Never derive/admin-grant from general manager entry visibility.
      return outcome("ADMIN_PRINCIPAL_REQUIRES_SEPARATE_REVIEW");
    }
    const dir = dataOrNull(results[0]);
    const credential = dataOrNull(results[1]);
    const route = dataOrNull(results[2]);
    const user = dataOrNull(results[3]);
    const social = dataOrNull(results[4]);
    const session = dataOrNull(results[5]);
    const checked = inspectCanonicalUid({
      accountKey: input.accountKey,
      originalId: input.originalId,
      directory: metadataOnlyAccount(dir),
      credentials: metadataOnlyAccount(credential),
      route: metadataOnlyRoute(route),
      user: user ? {
        accountKey: user.accountKey, sharePersonalId: user.sharePersonalId,
      } : null,
      social: social ? {
        publicId: social.publicId, ownerUid: social.ownerUid,
      } : null,
      session: session ? {
        uid: session.uid, accountKey: session.accountKey,
      } : null,
      liveAuthUid: uid,
      authProvider: provider,
    });

    if (checked.status === "SPLIT") {
      return outcome("SPLIT_DETECTED_NO_ACCOUNT_TRANSFER");
    }
    if (checked.status === "MATCH_CANDIDATE") {
      // Even same-UID Auth is insufficient for financial/admin restoration.
      return outcome("CANONICAL_MATCH_REQUIRES_SEPARATE_OWNER_REVIEW");
    }
    return outcome("INCOMPLETE_OR_LEGACY_ACCOUNT_PROOF");
  } catch (_) {
    // Missing reads/permissions/network are NOT an invitation to retry with
    // a new anonymous UID or silently reconstruct user ownership.
    return outcome("SERVER_EVIDENCE_UNAVAILABLE");
  }
}

module.exports = {inspectServerCanonicalOwner};
