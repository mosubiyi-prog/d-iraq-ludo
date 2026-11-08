"use strict";

// DEDA stage 6 — ISOLATED SERVER-ONLY enrollment candidate, NOT DEPLOYED.
// Not imported by functions/index.js. Do not call from Flutter, a browser,
// or with user-controlled registration "proof". The only accepted scenario
// is a NEW (registrationVersion=2) Google-first account whose phone/account
// ownership was INDEPENDENTLY verified by a trusted server issuer BEFORE this
// function is invoked. That issuer does NOT exist in the production app yet.
// Legacy 100340 / split A-B-C accounts intentionally fail closed.
//
// Firebase Auth and Firestore are separate systems: this enrolls an existing
// fully provisioned UID only; it NEVER creates Auth users, issues tokens,
// claims a phone, moves owners or updates money/admin/gifts/league records.
// Only possible writes: new provider enrollment + consume pre-verified intent.
// No Cloud Function is exported here; all operations remain test-only.

const {createHmac, timingSafeEqual} = require("node:crypto");
const ACCOUNT = /^(?:07\d{9}|9647\d{9})$/;
const ORIGINAL = /^@DEDA-[A-Z0-9]{6}$/;
const UID = /^[A-Za-z0-9:_-]{6,128}$/;
const SUBJECT = /^[^\s]{4,512}$/;
const NONCE = /^[0-9a-f]{64}$/;
const PROOF_KIND = "independently_verified_phone_challenge_v1";
const PROVIDER = "google.com";
const INTENT_MAX_MS = 10 * 60 * 1000;
const TOKEN_LIMIT = 8192;

const hold = status => Object.freeze({
  status,
  authorizedToSignIn: false,
  mayCreateUid: false,
  mayTransferOwnership: false,
  mayModifyAdmin: false,
  mayModifyFinances: false,
  legacyAccountUntouched: true,
});

function verifiedIntentSignature(intent, key) {
  // Digest must be issued by a trusted, separate phone verification service.
  // This verifier does not issue claims or validate the user's phone itself.
  if (!Buffer.isBuffer(key) || key.length < 32) return null;
  const message = [
    "DEDA_STAGE6_PHONE_VERIFIED_INTENT_V1",
    intent.accountKey, intent.ownerUid, intent.originalId,
    intent.providerId, intent.providerSubject, intent.nonce,
    String(intent.issuedAtMs), String(intent.expiresAtMs), intent.proofKind,
  ].join("\n");
  return createHmac("sha256", key).update(message, "utf8").digest("hex");
}
function intentValid(intent, fields, nowMs, key) {
  if (!intent || intent.status !== "verified" ||
      intent.proofKind !== PROOF_KIND ||
      intent.accountKey !== fields.accountKey ||
      intent.ownerUid !== fields.uid ||
      intent.originalId !== fields.originalId ||
      intent.providerId !== PROVIDER ||
      intent.providerSubject !== fields.subject ||
      typeof intent.nonce !== "string" || !NONCE.test(intent.nonce) ||
      !Number.isSafeInteger(intent.issuedAtMs) ||
      !Number.isSafeInteger(intent.expiresAtMs) ||
      intent.issuedAtMs <= 0 ||
      intent.issuedAtMs > nowMs ||
      intent.expiresAtMs <= nowMs ||
      intent.expiresAtMs - intent.issuedAtMs > INTENT_MAX_MS ||
      typeof intent.mac !== "string" ||
      !/^[0-9a-f]{64}$/.test(intent.mac)) return false;
  const expected = verifiedIntentSignature(intent, key);
  return expected != null &&
    timingSafeEqual(Buffer.from(expected,"hex"),Buffer.from(intent.mac,"hex"));
}
function read(snap) {
  return snap?.exists === true && typeof snap.data === "function" ?
    snap.data() : null;
}
function stableOwner(rows, f) {
  const [dir, cred, route, user, social, session, admin] = rows;
  return !admin &&
    dir?.accountKey === f.accountKey &&
    cred?.accountKey === f.accountKey &&
    dir?.active === true && cred?.active === true &&
    dir?.registrationVersion === 2 && cred?.registrationVersion === 2 &&
    dir?.authMethod === "google_uid_first_v1" &&
    cred?.authMethod === "google_uid_first_v1" &&
    dir?.createdUid === f.uid && cred?.createdUid === f.uid &&
    user?.accountKey === f.accountKey &&
    user?.sharePersonalId === f.originalId &&
    user?.registrationVersion === 2 &&
    route?.publicId === f.originalId && route?.kind === "personal" &&
    route?.active === true && route?.ownerUid === f.uid &&
    social?.publicId === f.originalId && social?.ownerUid === f.uid &&
    session?.uid === f.uid && session?.accountKey === f.accountKey;
}

/**
 * input is internal routing metadata, NOT ownership evidence.
 * deps.auth and deps.db are Firebase Admin objects.
 * deps.intentMacKey must come from a SERVER secret manager, NOT GitHub/client.
 * deps.now is a trusted monotonic-enough server clock for the short challenge.
 * This operation is OFF by default and cannot be invoked from Cloud Functions
 * because functions/index.js does not import this module.
 */
async function enrollNewGoogleOwner(input, deps) {
  if (!input || typeof input !== "object" || Array.isArray(input) ||
      !ACCOUNT.test(input.accountKey || "") ||
      !ORIGINAL.test(input.originalId || "") ||
      typeof input.idToken !== "string" ||
      input.idToken.length < 16 || input.idToken.length > TOKEN_LIMIT ||
      typeof deps?.auth?.verifyIdToken !== "function" ||
      typeof deps?.auth?.getUser !== "function" ||
      typeof deps?.db?.doc !== "function" ||
      typeof deps?.db?.runTransaction !== "function" ||
      !Buffer.isBuffer(deps?.intentMacKey) ||
      deps.intentMacKey.length < 32 ||
      typeof deps.now !== "function" ||
      deps.enabled !== true) return hold("NOT_ENABLED_OR_INVALID_REQUEST");

  let decoded, authRecord, subject;
  try {
    decoded = await deps.auth.verifyIdToken(input.idToken, true);
    if (!UID.test(decoded?.uid || "") ||
        decoded?.firebase?.sign_in_provider !== PROVIDER) {
      return hold("NO_VERIFIED_GOOGLE_FIRST_IDENTITY");
    }
    authRecord = await deps.auth.getUser(decoded.uid);
    if (authRecord?.uid !== decoded.uid ||
        authRecord.disabled === true ||
        authRecord?.customClaims?.admin === true ||
        !Array.isArray(authRecord.providerData)) {
      return hold("NO_VERIFIED_GOOGLE_FIRST_IDENTITY");
    }
    const linked = authRecord.providerData.filter(p =>
      p?.providerId === PROVIDER && SUBJECT.test(p?.uid || ""));
    if (linked.length !== 1) return hold("NO_VERIFIED_GOOGLE_FIRST_IDENTITY");
    subject = linked[0].uid;
  } catch (_) {
    return hold("UNVERIFIED_AUTH_TOKEN");
  }

  const nowMs = deps.now();
  if (!Number.isSafeInteger(nowMs) || nowMs <= 0) {
    return hold("INVALID_SERVER_CLOCK");
  }
  const f = {
    uid:decoded.uid, accountKey:input.accountKey,
    originalId:input.originalId, subject,
  };
  const names = [
    "deda_account_directory/" + f.accountKey,
    "deda_credentials/" + f.accountKey,
    "deda_share_ids/" + f.originalId,
    "users/" + f.uid,
    "deda_social_profiles/" + f.originalId,
    "deda_sessions/" + f.uid,
    "admins/" + f.uid,
    "deda_owner_registration_verified_intents/" + f.accountKey,
    "deda_owner_provider_enrollments/" + f.uid,
  ];
  const refs = names.map(p => deps.db.doc(p));
  try {
    return await deps.db.runTransaction(async tx => {
      // Firestore transactions: EVERY read before the first write.
      const docs = await Promise.all(refs.map(ref => tx.get(ref)));
      const rows = docs.map(read);
      if (!stableOwner(rows.slice(0,7), f)) {
        return hold("NOT_A_VERIFIED_NEW_CANONICAL_ACCOUNT");
      }

      const intent = rows[7];
      const old = rows[8];
      if (old) {
        // Only an identical server-enrolled row is idempotent. Never relink.
        const match = intent?.status === "consumed" &&
          intent?.consumedByUid === f.uid &&
          old.source === "trusted_server_pre_enrollment_v1" &&
          old.status === "active" && old.revision === 1 &&
          old.ownerUid === f.uid &&
          old.accountKey === f.accountKey &&
          old.originalId === f.originalId &&
          old.providerId === PROVIDER &&
          old.providerSubject === subject;
        return hold(match ? "ALREADY_ENROLLED_SAME_UID" :
          "EXISTING_ENROLLMENT_CONFLICT");
      }
      if (!intentValid(intent, f, nowMs, deps.intentMacKey)) {
        return hold("NO_INDEPENDENT_PHONE_VERIFICATION");
      }
      tx.create(refs[8], {
        source:"trusted_server_pre_enrollment_v1", status:"active",
        revision:1, ownerUid:f.uid, accountKey:f.accountKey,
        originalId:f.originalId, providerId:PROVIDER,
        providerSubject:subject, enrolledAtMs:nowMs,
        intentNonceDigest:intent.nonce,
      });
      tx.update(refs[7], {
        status:"consumed", consumedAtMs:nowMs, consumedByUid:f.uid,
      });
      return hold("ENROLLED_FOR_FUTURE_INDEPENDENT_REVIEW");
    });
  } catch (_) {
    // Ambiguous Firestore acknowledgement never authorizes a new UID/token.
    // Retry must read back the exact same enrollment + consumed intent.
    return hold("TRANSACTION_UNAVAILABLE_OR_CONFLICT");
  }
}

module.exports = {enrollNewGoogleOwner};
