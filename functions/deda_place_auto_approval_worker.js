"use strict";

const {assess} = require("./deda_place_auto_approval_policy.js");

/**
 * Privileged backend proposal for NEW place auto-approval.
 * Stage 1 is deliberately OFF unless a deployed, protected manager
 * switch exists. Never invoke from Flutter/browser.
 *
 * WARNING: deploying a changed trigger needs Cloud Build API and
 * working Firebase Functions provisioning. No production deployment.
 */
async function processNewPlace(firestore, {requestId, nowMs = Date.now()}) {
  const requestRef = firestore.collection("place_requests").doc(requestId);
  const settingsRef = firestore.collection("deda_automation_settings")
      .doc("place_auto_approval");
  const counterRef = firestore.collection("system_counters").doc("place_approval");
  const auditRef = firestore.collection("admin_automation_audit").doc(requestId);
  const result = await firestore.runTransaction(async (tx) => {
    const [settingSnap, current] = await Promise.all([
      tx.get(settingsRef), tx.get(requestRef),
    ]);
    if (!settingSnap.exists || !current.exists) {
      return {outcome: "no-settings-or-request"};
    }
    const setting = settingSnap.data() || {};
    const request = current.data() || {};
    if (setting.enabled !== true || request.status !== "pending") {
      return {outcome: "switch-off-or-already-reviewed"};
    }
    const accountKey = String(request.accountKey || "").trim();
    const ownerUid = String(request.ownerUid || "").trim();
    const province = String(request.governorate || "").trim();
    if (!accountKey || !ownerUid || !province) {
      return {outcome: "missing-owner-or-province"};
    }
    const directoryRef = firestore.collection("deda_account_directory")
        .doc(accountKey);
    const ownerRef = firestore.collection("users").doc(ownerUid);
    const [directorySnap, ownerSnap] = await Promise.all([
      tx.get(directoryRef), tx.get(ownerRef),
    ]);
    const directory = directorySnap.data() || {};
    const owner = ownerSnap.data() || {};
    // Account ID must be bound to the same authenticated owner; never
    // treat a user-supplied name, phone or install ID as identity proof.
    const verifiedOwner = directorySnap.exists && ownerSnap.exists &&
      directory.active === true && directory.createdUid === ownerUid &&
      owner.accountKey === accountKey;

    // A bounded exhaustive scan: if over 200 records, defer to manual.
    // Do not approve if we cannot establish whether the location duplicates
    // an existing published record in its governorate.
    const publishedQuery = firestore.collection("published_places")
        .where("governorate", "==", province).limit(201);
    const provinceDocs = await tx.get(publishedQuery);
    const provinceRecords = provinceDocs.docs.map((doc) => doc.data() || {});
    const decision = assess({
      request, settings: setting,
      publishedInProvince: provinceRecords,
      provinceScanComplete: provinceDocs.size < 201,
      serverNowMs: nowMs,
      exactTrustedOwner: verifiedOwner,
    });
    if (!decision.eligible) {
      return {outcome: "manual-review", reason: decision.reason};
    }

    // At most one approval per request. Counter, published record, status
    // and audit are committed in ONE Firestore transaction.
    const counter = await tx.get(counterRef);
    const next = Number(counter.data()?.value || 0) + 1;
    if (!Number.isSafeInteger(next) || next < 1) {
      return {outcome: "invalid-counter"};
    }
    const approvedAt = new Date(nowMs);
    const dd = String(approvedAt.getUTCDate()).padStart(2, "0");
    const mm = String(approvedAt.getUTCMonth() + 1).padStart(2, "0");
    const year = approvedAt.getUTCFullYear();
    const number = `DEDA-${year}-${String(next).padStart(7, "0")}`;
    const day = `${dd}/${mm}/${year}`;
    const message = `تم اعتماد: ${request.placeName}\nرقم الاعتماد: ${number}\nتاريخ الاعتماد: ${day}\nDEDA - الدليل الدقيق`;
    const admin = {uid: "deda-system", name: "DEDA", role: "system"};
    const createdAt = firestore.constructor.FieldValue ?
      firestore.constructor.FieldValue.serverTimestamp() : null;
    // Admin SDK FieldValue comes from firebase-admin/firestore; provide
    // directly as an injection so tests do not emulate a forbidden user write.
    const stamp = typeof firestore._dedaServerTimestamp === "function" ?
      firestore._dedaServerTimestamp() : approvedAt;

    tx.set(counterRef, {value: next, updatedAt: stamp}, {merge: true});
    tx.update(requestRef, {
      status: "approved", approvalNumber: number, approvalDate: day,
      approvalMessage: message, updatedAt: stamp,
      reviewedBy: admin.uid, reviewedByName: admin.name,
      reviewedByRole: admin.role, decisionAction: "approved",
      decisionAt: stamp, decisionByUid: admin.uid,
      decisionByName: admin.name, decisionByRole: admin.role,
      decisionNote: "", automatedAt: stamp,
    });
    tx.set(firestore.collection("published_places").doc(requestId), {
      ...request, requestId, sourceRequestId: requestId,
      lastSourceRequestId: requestId, published: true, status: "approved",
      approvalNumber: number, approvalDate: day,
      approvalMessage: message, approvedByUid: admin.uid,
      approvedByName: admin.name, approvedByRole: admin.role,
      publishedAt: stamp, updatedAt: stamp,
    }, {merge: true});
    tx.set(auditRef, {
      action: "place_auto_approved", requestId, ownerUid, accountKey,
      approvedNumber: number, managerUid: setting.changedByUid || "",
      createdAt: stamp,
    });
    return {outcome: "auto-approved", number};
  }, {maxAttempts: 5});
  return result;
}

module.exports = {processNewPlace};
