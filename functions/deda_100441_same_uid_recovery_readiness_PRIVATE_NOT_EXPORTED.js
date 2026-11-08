"use strict";

// DEDA 100441 — Stage 5, purely READ-ONLY same-Firebase-UID new-device
// assessment. Not a Callable, not imported by functions/index.js,
// not a sign-in or account migration API. Never read a raw PIN.
//
// Intended use: only after an already-linked, independently authenticated
// Firebase provider signs in to the SAME original Firebase Auth user.
// All outputs are non-authorizing, INTERNAL review classifications.
//
// The immutable provider enrollment row MUST have been created previously
// by an independent trusted server process, not by app clients. If this
// provenance cannot be proved, do not use this candidate for privileges.
// No existing A/B/C account is auto-selected, linked, or mutated.
//
// No new Auth user, no custom token, no Firestore writes, no admin/finance
// operations, no silent anonymous fallback, no 100340 compatibility change.

const {
  inspectCanonicalUid,
} = require("./deda_100441_canonical_uid_anti_split_preflight_PRIVATE_NOT_EXPORTED.js");

const ACCOUNT = /^(?:07\d{9}|9647\d{9})$/;
const ORIGINAL_ID = /^@DEDA-[A-Z0-9]{6}$/;
const UID = /^[A-Za-z0-9:_-]{6,128}$/;
const TOKEN_MIN = 16;
const TOKEN_MAX = 8192;
const INDEPENDENT_PROVIDERS = new Set(["google.com", "phone"]);
const PROVIDER_SUBJECT = /^[^\s]{4,512}$/;

const hold = classification => Object.freeze({
  decision: "HOLD_INDEPENDENT_OWNER_PROOF_AND_SERVER_REVIEW",
  classification,
  canSignIn: false,
  canCreateUid: false,
  canMintToken: false,
  canBootstrapSession: false,
  canWriteFirestore: false,
  canTransferOwnership: false,
  canModifyAdmin: false,
  canModifyWallet: false,
  canModifyGifts: false,
  canModifyLeague: false,
  nonPublicServerReviewOnly: true,
});

function docData(snap) {
  if (snap?.exists !== true || typeof snap.data !== "function") return null;
  const obj = snap.data();
  return obj && typeof obj === "object" && !Array.isArray(obj) ? obj : null;
}

function stableUid(uid) {
  return typeof uid === "string" && UID.test(uid);
}
function properProvider(token, user) {
  if (user?.disabled === true || !stableUid(user?.uid) ||
      token?.uid !== user.uid) return null;
  const id = token?.firebase?.sign_in_provider;
  if (!INDEPENDENT_PROVIDERS.has(id)) return null;
  if (!Array.isArray(user.providerData)) return null;
  const matching = user.providerData.filter(p => p?.providerId === id &&
    typeof p.uid === "string" && PROVIDER_SUBJECT.test(p.uid));
  return matching.length === 1 ? {id, subject:matching[0].uid} : null;
}

function enrollmentMatches(enrollment, user, request, provider, nowMs) {
  if (!enrollment || !provider) return false;
  if (enrollment.status !== "active" ||
      enrollment.source !== "trusted_server_pre_enrollment_v1" ||
      enrollment.ownerUid !== user.uid ||
      enrollment.accountKey !== request.accountKey ||
      enrollment.originalId !== request.originalId ||
      enrollment.providerId !== provider.id ||
      enrollment.providerSubject !== provider.subject ||
      enrollment.revision !== 1 ||
      !Number.isSafeInteger(enrollment.enrolledAtMs) ||
      enrollment.enrolledAtMs <= 0 ||
      !Number.isSafeInteger(nowMs) ||
      nowMs <= enrollment.enrolledAtMs) return false;
  // The enrollment is an independent audit artifact; its provenance and
  // Firestore rules still require separate review before ever going live.
  return true;
}

/**
 * @param {{idToken:string, accountKey:string, originalId:string}} input
 * @param {{auth: FirebaseAuthAdmin, db: FirestoreAdmin, now:Function}} deps
 * This module verifies the actual Firebase ID token with checkRevoked=true,
 * looks up Auth UserRecord, then reads ONLY server Firestore snapshots.
 * A different UID is a SPLIT, not an invitation to relink or create another.
 */
async function assessSameUidRecovery(input, deps) {
  if (!input || typeof input !== "object" || Array.isArray(input) ||
      typeof input.idToken !== "string" ||
      input.idToken.length < TOKEN_MIN ||
      input.idToken.length > TOKEN_MAX ||
      !ACCOUNT.test(input.accountKey || "") ||
      !ORIGINAL_ID.test(input.originalId || "") ||
      typeof deps?.auth?.verifyIdToken !== "function" ||
      typeof deps?.auth?.getUser !== "function" ||
      typeof deps?.db?.doc !== "function") {
    return hold("INVALID_OR_UNVERIFIED_REQUEST");
  }

  let decoded, user, provider;
  try {
    decoded = await deps.auth.verifyIdToken(input.idToken, true);
    if (!stableUid(decoded?.uid)) return hold("UNVERIFIED_AUTH_SESSION");
    user = await deps.auth.getUser(decoded.uid);
    provider = properProvider(decoded, user);
    if (!provider) return hold("NO_PRELINKED_INDEPENDENT_PROVIDER");
  } catch (_) {
    return hold("UNVERIFIED_AUTH_SESSION");
  }

  const uid = decoded.uid;
  let data;
  try {
    const paths = [
      "deda_account_directory/" + input.accountKey,
      "deda_credentials/" + input.accountKey,
      "deda_share_ids/" + input.originalId,
      "users/" + uid,
      "deda_social_profiles/" + input.originalId,
      "deda_sessions/" + uid,
      "admins/" + uid,
      "deda_owner_provider_enrollments/" + uid,
    ];
    const docs = await Promise.all(paths.map(path => deps.db.doc(path).get()));
    data = docs.map(docData);
  } catch (_) {
    return hold("SERVER_EVIDENCE_UNAVAILABLE");
  }
  if (data[6] || user?.customClaims?.admin === true) {
    // Separate admin review; no assumptions about existing GM access.
    return hold("ADMIN_REQUIRES_SEPARATE_REVIEW");
  }

  if (!enrollmentMatches(data[7], user, input, provider,
      typeof deps.now === "function" ? deps.now() : Date.now())) {
    return hold("NO_TRUSTED_PREVIOUS_PROVIDER_ENROLLMENT");
  }

  const directory = data[0], credentials = data[1], route = data[2];
  const projection = data[3], social = data[4], session = data[5];

  if (!directory || !credentials || !route || !projection || !social) {
    return hold("INCOMPLETE_LEGACY_OWNER_DOCUMENTS");
  }

  // Distinguish a verifiable A/B/C conflict from missing documents before
  // any session/bootstrap attempt; never select A, B or C on heuristics.
  if (directory.createdUid !== uid || credentials.createdUid !== uid ||
      route.ownerUid !== uid || social.ownerUid !== uid) {
    return hold("SPLIT_UID_NO_IMPLICIT_RECOVERY");
  }

  // Reuse canonical UID policy. Only missing SAME-UID session is permitted
  // as a candidate for an independently approved session bootstrap.
  const canonical = inspectCanonicalUid({
    accountKey:input.accountKey, originalId:input.originalId,
    directory: {
      accountKey: directory.accountKey, active:directory.active,
      createdUid:directory.createdUid,
    },
    credentials: {
      accountKey:credentials.accountKey, active:credentials.active,
      createdUid:credentials.createdUid,
    },
    route: {
      publicId:route.publicId, kind:route.kind, active:route.active,
      ownerUid:route.ownerUid,
    },
    user: {
      accountKey:projection.accountKey,
      sharePersonalId:projection.sharePersonalId,
    },
    social: {publicId:social.publicId, ownerUid:social.ownerUid},
    session: session ? {uid:session.uid,accountKey:session.accountKey} : null,
    liveAuthUid:uid, authProvider:provider.id,
  });

  if (canonical.status === "MATCH_CANDIDATE") {
    return hold("SAME_UID_EXISTING_SESSION_REVIEW_ONLY");
  }
  if (canonical.status === "HOLD" &&
      canonical.detail === "LIVE_SERVER_SESSION_NOT_VERIFIED" &&
      !session) {
    return hold("SAME_UID_SEPARATE_SESSION_BOOTSTRAP_REQUIRED");
  }
  if (canonical.status === "SPLIT") return hold("SPLIT_UID_NO_IMPLICIT_RECOVERY");
  return hold("INCOMPLETE_OR_CONFLICTING_ACCOUNT_PROOF");
}

module.exports = {assessSameUidRecovery};
