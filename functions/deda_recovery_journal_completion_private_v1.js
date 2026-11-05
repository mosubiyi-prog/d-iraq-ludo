"use strict";

// DEDA WORK VAULT ONLY. Do not import/export from functions/index.js, deploy,
// or enable without owner approval, server evidence producers, Firestore Rules
// Emulator QA, and verified same-original-UID sign-in on two devices.
//
// The CLIENT can create a reserved row, but CANNOT mark a row as verified.
// This App Check callable will mark verified ONLY after a separate trusted
// server worker has produced a matching, immutable source-domain attestation.
// No server attestation writer is present in this vault yet: fail CLOSED.
// A client-provided receiptId is NEVER sufficient proof of restoration.

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

const enabled = process.env.FUNCTIONS_EMULATOR === "true" &&
  process.env.DEDA_RECOVERY_JOURNAL_SERVER_ENABLED === "true";
const eligible = new Set([
  "originalBackupReadback",
  "purchaseBackupReadback",
  "levelPointsRestore",
  "publishedPlaceRecovery",
]);

const validAccount = (x) => typeof x === "string" && /^[0-9]{10,16}$/.test(x);
const validOriginal = (x) => typeof x === "string" && /^@DEDA-[A-Z0-9]{6}$/.test(x);
const validIntent = (x) => typeof x === "string" && /^[A-Za-z0-9_-]{20,100}$/.test(x);
const validReceipt = (x) => typeof x === "string" && /^[A-Za-z0-9_-]{12,128}$/.test(x);
const deny = (code, message) => {throw new HttpsError(code, message);};

function validatePayload(data, uid, token) {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    deny("invalid-argument", "invalid-journal-completion-request");
  }
  const keys = [
    "accountKey", "originalUid", "originalId", "intentId", "code",
    "operationKey", "receiptId",
  ];
  if (Object.keys(data).length !== keys.length ||
      Object.keys(data).some((x) => !keys.includes(x))) {
    deny("invalid-argument", "invalid-journal-completion-fields");
  }
  const {accountKey, originalUid, originalId, intentId, code, operationKey, receiptId} = data;
  if (!validAccount(accountKey) || !validOriginal(originalId) ||
      !validIntent(intentId) || !eligible.has(code) || !validReceipt(receiptId) ||
      originalUid !== uid ||
      token?.firebase?.sign_in_provider !== "password" ||
      token?.email !== accountKey + "@deda-login.invalid" ||
      operationKey !== `deda_guardian_v1/${uid}/${intentId}/${code}`) {
    deny("permission-denied", "original-owner-completion-proof-required");
  }
}

async function verifyImmutableServerOwner(db, uid, data) {
  // The linked Firebase credential is not enough: verify the server's
  // immutable directory, original user UID, original ID, and live account
  // session. Never use a locally typed name, premium ID, or guessed phone.
  const {accountKey, originalId} = data;
  const [directory, user, route, session] = await Promise.all([
    db.doc(`deda_account_directory/${accountKey}`).get(),
    db.doc(`users/${uid}`).get(),
    db.doc(`deda_share_ids/${originalId}`).get(),
    db.doc(`deda_sessions/${uid}`).get(),
  ]);
  if (!directory.exists || !user.exists || !route.exists || !session.exists ||
      directory.data()?.accountKey !== accountKey ||
      directory.data()?.active !== true ||
      directory.data()?.createdUid !== uid ||
      user.data()?.accountKey !== accountKey ||
      user.data()?.sharePersonalId !== originalId ||
      route.data()?.publicId !== originalId ||
      route.data()?.ownerUid !== uid ||
      route.data()?.kind !== "personal" ||
      route.data()?.active !== true ||
      session.data()?.uid !== uid ||
      session.data()?.accountKey !== accountKey) {
    deny("permission-denied", "original-owner-server-provenance-missing");
  }
}

async function verifiedCompletion(request, db = getFirestore()) {
  if (!enabled) deny("unavailable", "journal-verification-not-activated");
  if (!request.auth?.uid) deny("unauthenticated", "linked-owner-required");
  const uid = request.auth.uid, data = request.data;
  validatePayload(data, uid, request.auth.token);
  await verifyImmutableServerOwner(db, uid, data);

  const id = `${data.intentId}_${data.code}`;
  const rowRef = db.doc(`deda_recovery_journals/${uid}/steps/${id}`);
  const proofRef = db.doc(
      `deda_recovery_server_attestations/${uid}/receipts/${id}`);

  // Firestore transaction retries on conflicts. ALL reads precede writes.
  // No worker side effect runs here: no grants, purchases, rewards or PIN.
  return db.runTransaction(async (tx) => {
    const [row, proof] = await Promise.all([tx.get(rowRef), tx.get(proofRef)]);
    const r = row.data(), p = proof.data();
    const identical = r &&
      r.ownerUid === uid &&
      r.accountKey === data.accountKey &&
      r.originalId === data.originalId &&
      r.intentId === data.intentId &&
      r.code === data.code &&
      r.operationKey === data.operationKey;
    if (!row.exists || !identical) {
      deny("failed-precondition", "journal-reservation-not-proven");
    }

    // The attestation is NOT writable/readable by clients under candidate
    // security rules. A future approved server-side domain worker must
    // independently verify source readback and write these exact fields.
    // Without that trusted writer, this function can NEVER approve a claim.
    if (!proof.exists ||
        p.ownerUid !== uid ||
        p.accountKey !== data.accountKey ||
        p.originalId !== data.originalId ||
        p.intentId !== data.intentId ||
        p.code !== data.code ||
        p.operationKey !== data.operationKey ||
        p.receiptId !== data.receiptId ||
        p.serverVerified !== true ||
        p.issuedBy !== "deda-approved-domain-verifier-v1" ||
        typeof p.sourceRevision !== "string" ||
        !/^[A-Za-z0-9_-]{12,128}$/.test(p.sourceRevision)) {
      deny("failed-precondition", "trusted-server-readback-missing");
    }
    if (r.state === "verified") {
      if (r.receiptId !== data.receiptId) {
        deny("failed-precondition", "journal-receipt-conflict");
      }
      return {verified: true, receiptId: data.receiptId};
    }
    if (r.state !== "reserved" || "receiptId" in r) {
      deny("failed-precondition", "journal-state-conflict");
    }

    tx.update(rowRef, {
      state: "verified",
      receiptId: data.receiptId,
      verifiedAt: FieldValue.serverTimestamp(),
    });
    return {verified: true, receiptId: data.receiptId};
  });
}

// Export is local to this FILE. It will NOT become a deployed Cloud Function
// unless someone explicitly wires it into functions/index.js and deploys.
exports.dedaRecoveryJournalComplete = onCall(
    {enforceAppCheck: true, timeoutSeconds: 30},
    (request) => verifiedCompletion(request));
exports.__privateVerifiedCompletionForQaOnly = verifiedCompletion;
