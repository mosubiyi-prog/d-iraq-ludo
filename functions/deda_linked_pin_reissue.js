"use strict";

const {randomInt} = require("node:crypto");
const {Timestamp, FieldValue} = require("firebase-admin/firestore");

// Server-only DEDA forgotten-PIN issuance. This module NEVER creates a
// Firebase Auth user or changes a user's UID/profile, points, or entitlements.
// Callable caller must be verified as an active general manager in index.js.
function validRequestId(id) {
  return typeof id === "string" && /^[A-Za-z0-9_-]{10,128}$/.test(id);
}

function assertOwner(record, key, uid) {
  if (!record || record.uid !== uid || record.disabled) {
    throw Error("original-auth-uid-unavailable");
  }
  const expected = key + "@deda-login.invalid";
  // An anonymous 100340 original owner can still use the legacy PIN.
  // A linked account can ONLY be reset on its exact existing Auth user.
  if (record.email && record.email !== expected) {
    throw Error("original-auth-email-conflict");
  }
  return record.email === expected;
}

function originalDocuments(request, directory, credential, profile, user, key) {
  const uid = directory && directory.createdUid;
  if (!request || !["new","review","issuing"].includes(request.status) ||
      request.accountKey !== key || !/^\d{10,16}$/.test(key) ||
      !request.requesterUid || !request.requesterInstallId ||
      !directory || directory.accountKey !== key ||
      directory.active !== true || typeof uid !== "string" || !uid ||
      !credential || credential.accountKey !== key ||
      credential.createdUid !== uid ||
      credential.active !== true ||
      !/^\d{6}$/.test(String(credential.pin || "")) ||
      !profile || profile.accountKey !== key ||
      !user || user.accountKey !== key) {
    throw Error("original-account-recovery-source-not-verified");
  }
  return uid;
}

async function stageReset(db, requestId, actor, generatePin) {
  const reqRef = db.collection("recovery_requests").doc(requestId);
  const first = await reqRef.get();
  const key = String(first.data()?.accountKey || "");
  if (!/^\d{10,16}$/.test(key)) {
    throw Error("invalid-recovery-account");
  }
  const dirRef = db.collection("deda_account_directory").doc(key);
  const credRef = db.collection("deda_credentials").doc(key);
  const profileRef = db.collection("deda_account_profiles").doc(key);
  const head = await dirRef.get();
  const uid = head.data()?.createdUid;
  if (!uid || typeof uid !== "string") throw Error("original-uid-absent");
  const userRef = db.collection("users").doc(uid);

  return db.runTransaction(async (tx) => {
    const [r,d,c,p,u] = await Promise.all([
      tx.get(reqRef),tx.get(dirRef),tx.get(credRef),tx.get(profileRef),
      tx.get(userRef),
    ]);
    const request = r.data(), directory = d.data(), credential = c.data();
    const originalUid = originalDocuments(request,directory,credential,
        p.data(),u.data(),key);
    if (originalUid !== uid) throw Error("original-uid-changed");
    const pending = credential.pendingRecovery;
    if (pending) {
      if (pending.requestId !== requestId ||
          pending.uid !== uid || pending.actorUid !== actor.uid ||
          request.status !== "issuing" ||
          !/^\d{6}$/.test(pending.pin || "")) {
        throw Error("another-or-unverified-recovery-pending");
      }
      return {key,uid,pin:pending.pin};
    }
    if (!["new","review"].includes(request.status)) {
      throw Error("recovery-already-processed");
    }
    const pin = generatePin(String(credential.pin || ""));
    if (!/^\d{6}$/.test(pin) || pin === credential.pin) {
      throw Error("new-recovery-pin-not-valid");
    }
    tx.update(credRef,{
      pendingRecovery:{requestId,uid,pin,actorUid:actor.uid,
        issuedAt:Timestamp.now()},
    });
    tx.update(reqRef,{
      status:"issuing",approvedBy:actor.uid,approvedAt:Timestamp.now(),
      updatedAt:FieldValue.serverTimestamp(),
    });
    return {key,uid,pin};
  });
}

async function finishStagedReset(db, auth, requestId) {
  if (!validRequestId(requestId)) throw Error("invalid-recovery-request-id");
  const reqRef = db.collection("recovery_requests").doc(requestId);
  const requestSnap = await reqRef.get();
  const req = requestSnap.data();
  if (!req) throw Error("recovery-request-missing");
  if (req.status === "ready") return {status:"ready"};
  if (req.status !== "issuing" || !req.approvedBy) {
    throw Error("recovery-not-approved-for-issuance");
  }
  const key = String(req.accountKey || "");
  const credRef = db.collection("deda_credentials").doc(key);
  const [credSnap,dirSnap] = await Promise.all([
    credRef.get(),db.collection("deda_account_directory").doc(key).get(),
  ]);
  const cred = credSnap.data(), dir = dirSnap.data();
  const pending = cred?.pendingRecovery;
  if (!pending || pending.requestId !== requestId ||
      pending.actorUid !== req.approvedBy ||
      pending.uid !== dir?.createdUid ||
      !/^\d{6}$/.test(pending.pin || "")) {
    throw Error("pending-recovery-does-not-match-original-owner");
  }
  const record = await auth.getUser(pending.uid);
  const linked = assertOwner(record,key,pending.uid);
  // This is the only Firebase Auth mutation, ALWAYS the existing UID.
  // In a transient Firestore failure, the durable denied-to-client pending
  // PIN is retained, and a retry/same-request trigger completes with SAME PIN.
  if (linked) await auth.updateUser(pending.uid,{password:pending.pin});

  await db.runTransaction(async (tx) => {
    const [r,c,d] = await Promise.all([
      tx.get(reqRef),tx.get(credRef),
      tx.get(db.collection("deda_account_directory").doc(key)),
    ]);
    const latest = r.data(), latestCred = c.data();
    if (latest?.status === "ready" &&
        latest.recoveryPin === pending.pin) return;
    if (latest?.status !== "issuing" ||
        latest.approvedBy !== pending.actorUid ||
        latestCred?.pendingRecovery?.requestId !== requestId ||
        latestCred?.pendingRecovery?.uid !== pending.uid ||
        latestCred?.pendingRecovery?.pin !== pending.pin ||
        d.data()?.createdUid !== pending.uid ||
        latestCred.createdUid !== pending.uid ||
        latestCred.accountKey !== key) {
      throw Error("recovery-identity-changed-before-commit");
    }
    tx.update(credRef,{
      pin:pending.pin,
      updatedAt:FieldValue.serverTimestamp(),
      recoveryUpdatedBy:pending.actorUid,
      pendingRecovery:FieldValue.delete(),
    });
    tx.update(reqRef,{
      status:"ready",recoveryPin:pending.pin,
      recoveryPinExpiresAt:Timestamp.fromMillis(Date.now()+30*60*1000),
      resolvedAt:FieldValue.serverTimestamp(),
      updatedAt:FieldValue.serverTimestamp(),
      processingError:FieldValue.delete(),
    });
    // Deterministic audit ID; repeated retries cannot add duplicate awards.
    tx.set(db.collection("admin_audit").doc("pin_reissue_"+requestId),{
      action:"recovery_approved_original_uid_preserved",
      adminUid:pending.actorUid,
      targetAccountKey:key,targetUid:pending.uid,
      sourceCollection:"recovery_requests",sourceId:requestId,
      linkedAuthPasswordSynced:linked,
      createdAt:FieldValue.serverTimestamp(),
      // NEVER audit the actual PIN, wallet, scores or purchase data.
    });
  });
  return {status:"ready",linkedUidPreserved:true};
}

async function approveForgottenPin(db, auth, {requestId,actor,
  generatePin = (old) => {
    let pin;
    do {pin=String(randomInt(100000,1000000));} while(pin === old);
    return pin;
  },
}) {
  if (!validRequestId(requestId) || !actor ||
      !actor.uid || actor.role !== "general_manager") {
    throw Error("authenticated-general-manager-required");
  }
  const staged = await stageReset(db,requestId,actor,generatePin);
  const originalRecord = await auth.getUser(staged.uid);
  assertOwner(originalRecord,staged.key,staged.uid);
  return finishStagedReset(db,auth,requestId);
}

module.exports = {approveForgottenPin,finishStagedReset,
  assertOwner,originalDocuments};
