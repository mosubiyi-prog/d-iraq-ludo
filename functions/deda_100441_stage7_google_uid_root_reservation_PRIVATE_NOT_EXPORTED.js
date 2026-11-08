"use strict";

// DEDA 100441 / STAGE 7 — isolated Google-primary NEW ACCOUNT reservation.
// NOT imported into functions/index.js and NOT callable by clients.
// No live Firebase operations: tests inject Admin Auth and Firestore Emulator.
// Google verifies GOOGLE identity, NEVER a typed Iraqi phone number.
// This flow deliberately does not claim a phone number, PIN account directory,
// immutable DEDA ID, user profile, wallet, gifts, admin role or league prizes.
// It cannot repair A/B/C historical split identities.
//
// A positive result is ONLY a reservation for a future manually approved
// v2 account-creation state machine, not sign-in permission. App Check,
// full account issuance, device OAuth and abuse control remain future gates.

const {createHmac} = require("node:crypto");
const UID = /^[a-zA-Z0-9:_-]{6,128}$/;
const SUBJECT = /^[^\s]{4,512}$/;
const PROVIDER = "google.com";
const EXPIRY_MS = 15 * 60 * 1000;
const TOKEN_MAX = 8192;
const OUT = (classification) => Object.freeze({
  classification,
  decision: "HOLD_GOOGLE_ROOT_PENDING_APPROVED_REGISTRATION",
  ownerUidGranted: false,
  phoneOwnershipProved: false,
  mayClaimPhoneNumber: false,
  mayCreateDedaProfile: false,
  maySignIn: false,
  mayMintAuthToken: false,
  mayTransferExistingAccount: false,
  mayModifyAdmin: false,
  mayModifyWallet: false,
  mayModifyGifts: false,
  mayModifyLeague: false,
  internalOnly: true,
});

function digest(subject, key) {
  return createHmac("sha256", key)
    .update("deda-stage7-google-root-subject-index-v1:", "utf8")
    .update(subject, "utf8").digest("hex");
}
function row(s) {
  return s?.exists === true && typeof s.data === "function" ? s.data() : null;
}
function acceptableAuth(decoded, user) {
  if (!decoded || !UID.test(decoded.uid || "") ||
      decoded?.firebase?.sign_in_provider !== PROVIDER ||
      user?.uid !== decoded.uid || user?.disabled === true ||
      user?.customClaims?.admin === true ||
      !Array.isArray(user?.providerData)) return null;
  const google = user.providerData.filter(
    p => p?.providerId === PROVIDER && SUBJECT.test(p.uid || ""));
  return google.length === 1 ? google[0].uid : null;
}

/**
 * @param {{idToken:string}} input no phone, name, PIN or display ID accepted.
 * @param {object} deps trusted injected Admin Auth, Firestore and HMAC key.
 */
async function reserveNewGoogleRoot(input, deps) {
  if (deps?.enabled !== true ||
      !input || typeof input !== "object" || Array.isArray(input) ||
      Object.keys(input).length !== 1 ||
      typeof input.idToken !== "string" ||
      input.idToken.length < 16 || input.idToken.length > TOKEN_MAX ||
      typeof deps?.auth?.verifyIdToken !== "function" ||
      typeof deps?.auth?.getUser !== "function" ||
      typeof deps?.db?.doc !== "function" ||
      typeof deps?.db?.runTransaction !== "function" ||
      !Buffer.isBuffer(deps?.subjectIndexKey) ||
      deps.subjectIndexKey.length < 32 ||
      typeof deps.now !== "function") {
    return OUT("NOT_ENABLED_OR_INVALID_REQUEST");
  }

  let decoded, user, subject;
  try {
    decoded = await deps.auth.verifyIdToken(input.idToken, true);
    if (!UID.test(decoded?.uid || "")) return OUT("UNVERIFIED_AUTH_SESSION");
    user = await deps.auth.getUser(decoded.uid);
    subject = acceptableAuth(decoded, user);
    if (!subject) return OUT("UNVERIFIED_GOOGLE_PROVIDER");
  } catch (_) {
    return OUT("UNVERIFIED_AUTH_SESSION");
  }

  const nowMs = deps.now();
  if (!Number.isSafeInteger(nowMs) || nowMs <= 0 ||
      nowMs > Number.MAX_SAFE_INTEGER - EXPIRY_MS) return OUT("INVALID_SERVER_CLOCK");

  const uid = decoded.uid;
  const subjectDigest = digest(subject, deps.subjectIndexKey);
  const paths = [
    "users/" + uid,
    "admins/" + uid,
    "deda_sessions/" + uid,
    "deda_owner_provider_enrollments/" + uid,
    "deda_google_uid_reservations_private_v1/" + uid,
    "deda_google_subject_index_private_v1/" + subjectDigest,
  ];
  const refs = paths.map(p => deps.db.doc(p));
  try {
    return await deps.db.runTransaction(async tx => {
      // Transactional read-before-write, including the global Google subject
      // reservation, so competing same-provider reservations cannot both win.
      const snaps = await Promise.all(refs.map(r => tx.get(r)));
      const values = snaps.map(row);
      if (values.slice(0,4).some(v => v !== null)) {
        // Existing/split/legacy accounts never enter a new-account lane.
        return OUT("EXISTING_ACCOUNT_OR_ADMIN_REQUIRES_SEPARATE_REVIEW");
      }
      const [reservation, index] = values.slice(4);
      if (reservation !== null || index !== null) {
        const same = reservation?.uid === uid &&
          reservation?.providerId === PROVIDER &&
          reservation?.subjectDigest === subjectDigest &&
          reservation?.status === "pending_phone_independent_proof" &&
          reservation?.version === 1 &&
          index?.uid === uid &&
          index?.subjectDigest === subjectDigest &&
          index?.status === "reserved" &&
          index?.version === 1 &&
          Number.isSafeInteger(reservation?.expiresAtMs) &&
          reservation.expiresAtMs > nowMs;
        return OUT(same ? "SAME_UID_PENDING_REVIEW_NO_DUPLICATE" :
          "PRIOR_RESERVATION_CONFLICT_OR_EXPIRED");
      }
      tx.create(refs[4], {
        version: 1, uid, providerId: PROVIDER,
        subjectDigest, status: "pending_phone_independent_proof",
        createdAtMs: nowMs, expiresAtMs: nowMs + EXPIRY_MS,
        phoneClaimed: false, dedaAccountCreated: false,
      });
      tx.create(refs[5], {
        version: 1, uid, subjectDigest, status: "reserved",
        createdAtMs: nowMs,
      });
      return OUT("GOOGLE_UID_RESERVED_PHONE_UNVERIFIED");
    });
  } catch (_) {
    return OUT("SERVER_TRANSACTION_UNAVAILABLE");
  }
}

module.exports = {reserveNewGoogleRoot};
