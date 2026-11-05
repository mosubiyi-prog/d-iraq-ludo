"use strict";

// DEDA 100436 — private compatibility candidate; not deployed or enabled.
// One canonical PIN: deda_credentials/{accountKey}.pin.
// Firebase Auth password is kept in sync for legacy linked sign-in, but it is
// NEVER considered an independent authority for restored owner access.
// A per-account server lock prevents new custom-token issuance mid-rotation.
// Firestore + Firebase Auth cannot commit atomically: on uncertain outcome the
// lock remains and an operator must reconcile; NEVER invent a successful login.
const {randomInt} = require("node:crypto");

function validPin(value) {
  return typeof value === "string" && /^\d{6}$/.test(value);
}
function millis(value) {
  return value && typeof value.toMillis === "function" ?
    value.toMillis() : NaN;
}
function syncMarkerMatches(credential) {
  return credential?.pinSyncVersion === 1 &&
    Number.isFinite(millis(credential.updatedAt)) &&
    millis(credential.updatedAt) === millis(credential.pinSyncedAt);
}
function accountMatches({key, directory, credential, profile, adminExists,
  authUser}) {
  if (!/^(?:07\d{9}|9647\d{9})$/.test(key) ||
      !directory || !credential || !profile || adminExists ||
      directory.active !== true || credential.active !== true ||
      directory.accountKey !== key || credential.accountKey !== key ||
      !validPin(credential.pin)) return false;
  const uid = directory.createdUid;
  return typeof uid === "string" && uid.length >= 6 &&
    credential.createdUid === uid && profile.accountKey === key &&
    authUser?.uid === uid && authUser?.disabled !== true &&
    authUser?.email === `${key}@deda-login.invalid` &&
    directory.authEmail === authUser.email;
}

// A recovery task must originate from a previously approved admin workflow.
// This helper does not approve requests or accept any client-supplied PIN.
async function completeApprovedManualPinRecovery({
  db, auth, Timestamp, requestId, nowMs = Date.now(),
  generatePin = () => String(randomInt(100000, 1000000)),
}) {
  if (!db || !auth || !Timestamp ||
      !/^[A-Za-z0-9_-]{6,160}$/.test(requestId || "") ||
      !Number.isSafeInteger(nowMs)) {
    throw new Error("manual-pin-invalid-server-arguments");
  }
  const requestRef = db.collection("recovery_requests").doc(requestId);
  const requestSnap = await requestRef.get();
  const request = requestSnap.exists ? requestSnap.data() : null;
  if (!request || request.status !== "approved") {
    throw new Error("manual-pin-not-approved");
  }
  const key = request.accountKey;
  if (typeof key !== "string" ||
      !/^(?:07\d{9}|9647\d{9})$/.test(key) ||
      typeof request.requesterUid !== "string" ||
      request.requesterUid.length < 6) {
    throw new Error("manual-pin-invalid-account");
  }
  const directoryRef = db.collection("deda_account_directory").doc(key);
  const credentialRef = db.collection("deda_credentials").doc(key);
  const lockRef = db.collection("deda_pin_recovery_locks").doc(key);
  const [dSnap, cSnap] = await Promise.all([
    directoryRef.get(), credentialRef.get(),
  ]);
  const directory = dSnap.exists ? dSnap.data() : null;
  const credential = cSnap.exists ? cSnap.data() : null;
  const uid = directory?.createdUid;
  if (typeof uid !== "string" || uid.length < 6 ||
      directory?.authEmail !== `${key}@deda-login.invalid`) {
    throw new Error("manual-pin-owner-link-missing");
  }
  const [pSnap, aSnap, authUser] = await Promise.all([
    db.collection("users").doc(uid).get(),
    db.collection("admins").doc(uid).get(),
    auth.getUserByEmail(directory.authEmail),
  ]);
  if (!accountMatches({
    key, directory, credential,
    profile: pSnap.exists ? pSnap.data() : null,
    adminExists: aSnap.exists, authUser,
  })) throw new Error("manual-pin-owner-mismatch");

  const oldPin = credential.pin;
  const newPin = generatePin();
  if (!validPin(newPin) || newPin === oldPin) {
    throw new Error("manual-pin-generator-invalid");
  }

  // Reserve one account across multiple devices and recovery requests.
  // Keep the lock if Auth or Firestore completion is ambiguous.
  await db.runTransaction(async (tx) => {
    const [lock, req, dir, cred] = await Promise.all([
      tx.get(lockRef), tx.get(requestRef),
      tx.get(directoryRef), tx.get(credentialRef),
    ]);
    if (lock.exists || !req.exists || req.data().status !== "approved" ||
        req.data().accountKey !== key ||
        req.data().requesterUid !== request.requesterUid ||
        !dir.exists || dir.data().createdUid !== uid ||
        !cred.exists || cred.data().createdUid !== uid ||
        cred.data().pin !== oldPin) {
      throw new Error("manual-pin-concurrent-or-changed");
    }
    tx.create(lockRef, {
      requestId, originalUid: uid, accountKey: key, phase: "reserved",
      createdAt: Timestamp.fromMillis(nowMs),
    });
  });

  // Auth first, while new token verification is denied by the account lock.
  // A failed/uncertain Auth mutation deliberately leaves the lock in place.
  await auth.updateUser(uid, {password: newPin});

  try {
    await db.runTransaction(async (tx) => {
      const [lock, req, dir, cred] = await Promise.all([
        tx.get(lockRef), tx.get(requestRef),
        tx.get(directoryRef), tx.get(credentialRef),
      ]);
      if (!lock.exists || lock.data().requestId !== requestId ||
          lock.data().originalUid !== uid ||
          !req.exists || req.data().status !== "approved" ||
          req.data().requesterUid !== request.requesterUid ||
          !dir.exists || dir.data().createdUid !== uid ||
          !cred.exists || cred.data().createdUid !== uid ||
          cred.data().pin !== oldPin) {
        throw new Error("manual-pin-completion-conflict");
      }
      const timestamp = Timestamp.fromMillis(nowMs);
      tx.update(credentialRef, {
        pin: newPin, pinSyncVersion: 1,
        updatedAt: timestamp, pinSyncedAt: timestamp,
        recoveryUpdatedBy: "deda-manual-server-compat-v1",
      });
      tx.update(requestRef, {
        status: "ready", recoveryPin: newPin,
        recoveryPinExpiresAt: Timestamp.fromMillis(nowMs + 30 * 60 * 1000),
        resolvedAt: timestamp, updatedAt: timestamp, processingError: null,
      });
      tx.delete(lockRef);
    });
  } catch (error) {
    // A transaction may commit even if its acknowledgment is lost. Never
    // roll Firebase Auth back without checking canonical readback first.
    const [cNow, rNow, lNow] = await Promise.all([
      credentialRef.get(), requestRef.get(), lockRef.get(),
    ]);
    if (cNow.exists && rNow.exists && !lNow.exists &&
        cNow.data().pin === newPin &&
        syncMarkerMatches(cNow.data()) &&
        rNow.data().status === "ready" &&
        rNow.data().recoveryPin === newPin) {
      return {outcome: "ready", originalUid: uid, recoveredAfterAckLoss: true};
    }
    // Leave the lock for explicit manual reconciliation on ANY ambiguity.
    // Automatic password rollback could re-enable an old compromised PIN.
    throw new Error("manual-pin-pending-reconciliation");
  }

  // No client token, UID migration, diamonds, social or admin permissions.
  return {outcome: "ready", originalUid: uid, recoveredAfterAckLoss: false};
}

module.exports = {
  validPin, syncMarkerMatches, accountMatches,
  completeApprovedManualPinRecovery,
};
