"use strict";

// DEDA Heartbeat STAGED ONLY. No deployment, no customer data backfill.
// A trusted Firestore status transition, not client-generated UI text,
// creates an idempotent owner bell notice for first-time approvals.
function approvalNoticeFields(before, after, requestId) {
  if (!before || !after || before.status === "approved" ||
      after.status !== "approved") return null;
  const clean = (v) => String(v == null ? "" : v).trim();
  const id = clean(requestId);
  const ownerUid = clean(after.ownerUid);
  const accountKey = clean(after.accountKey);
  const placeName = clean(after.placeName);
  const approvalNumber = clean(after.approvalNumber);
  const approvalDate = clean(after.approvalDate);
  if (!/^[A-Za-z0-9_-]{8,160}$/.test(id) ||
      !ownerUid || !accountKey || !placeName ||
      !approvalNumber || !approvalDate) return null;
  const type = clean(after.requestType) === "update"
      ? "edit_approved" : "approved";
  // Owner/admin cannot supply the document ID: it is deterministic from
  // the actual approved request ID. A retried trigger cannot duplicate it.
  return {
    id: "heartbeat_approval_" + id,
    data: {
      type,
      accountKey,
      ownerUid,
      placeId: clean(after.originalPlaceId) || id,
      placeName,
      approvalNumber,
      governorate: clean(after.governorate),
      titleAr: type === "edit_approved" ?
          "تم اعتماد تعديل المكان" : "تم اعتماد مكانك",
      titleEn: type === "edit_approved" ?
          "Place changes approved" : "Your place was approved",
      bodyAr: "تم اعتماد مكان «" + placeName + "» برقم " + approvalNumber + ".",
      bodyEn: "Place “" + placeName + "” approved as " + approvalNumber + ".",
      sourceType: "place_requests",
      sourceId: id,
      createdByUid: "deda-system",
      createdByName: "DEDA",
      createdByRole: "system",
    },
  };
}

async function recordApprovalBellNotice(db, {before, after, requestId, stamp}) {
  const item = approvalNoticeFields(before, after, requestId);
  if (!item) return {outcome: "ignored"};
  const ref = db.collection("owner_place_notifications").doc(item.id);
  try {
    // Create-only is atomic in Firestore. Never update/delete old notices.
    await ref.create({...item.data, createdAt: stamp});
    return {outcome: "created"};
  } catch (err) {
    // Firestore gRPC ALREADY_EXISTS and admin SDK conflict.
    if (err && (err.code === 6 || err.code === "already-exists")) {
      return {outcome: "already-created"};
    }
    throw err;
  }
}
module.exports = {approvalNoticeFields, recordApprovalBellNotice};
