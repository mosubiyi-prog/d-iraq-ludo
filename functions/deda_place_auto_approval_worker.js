"use strict";

const {assess} = require("./deda_place_auto_approval_policy.js");
const {FieldValue} = require("firebase-admin/firestore");

/**
 * Iraq uses fixed UTC+03:00 with no daylight-saving changes. The automatic
 * approval stamp must match the manual Iraqi DD/MM/YYYY certificate date.
 */
function iraqApprovalDate(nowMs) {
  if (!Number.isFinite(nowMs)) throw Error("invalid-server-clock");
  const date = new Date(nowMs + 3 * 60 * 60 * 1000);
  const dd = String(date.getUTCDate()).padStart(2, "0");
  const mm = String(date.getUTCMonth() + 1).padStart(2, "0");
  const year = date.getUTCFullYear();
  return {year, day: `${dd}/${mm}/${year}`};
}

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
    const sessionRef = firestore.collection("deda_sessions").doc(ownerUid);
    const [directorySnap, ownerSnap, sessionSnap] = await Promise.all([
      tx.get(directoryRef), tx.get(ownerRef), tx.get(sessionRef),
    ]);
    const directory = directorySnap.data() || {};
    const owner = ownerSnap.data() || {};
    const session = sessionSnap.data() || {};
    // Firestore session is issued ONLY after credential proof or a trusted
    // device secret; a self-entered phone/name is not account ownership.
    const verifiedOwner = directorySnap.exists && ownerSnap.exists &&
      sessionSnap.exists && directory.active === true &&
      owner.accountKey === accountKey && session.accountKey === accountKey;

    // The owner explicitly chose publication without manual content or
    // duplicate moderation. Basic validated fields/account binding only.
    const decision = assess({
      request,
      settings: setting,
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
    const {year, day} = iraqApprovalDate(nowMs);
    const number = `DEDA-${year}-${String(next).padStart(7, "0")}`;
    const message = `تم اعتماد: ${request.placeName}\nرقم الاعتماد: ${number}\nتاريخ الاعتماد: ${day}\nDEDA - الدليل الدقيق`;
    const admin = {uid: "deda-system", name: "DEDA", role: "system"};
    const stamp = FieldValue.serverTimestamp();

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

module.exports = {processNewPlace, iraqApprovalDate};
