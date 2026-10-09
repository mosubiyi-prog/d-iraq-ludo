"use strict";

/**
 * DEDA stage 7: UNEXPORTED server-side prototype for undoing the *latest*
 * published daily task edit at the NEXT Baghdad midnight.
 *
 * Never call this from a client. A future authenticated Callable handler
 * must derive requesterUid from verified request.auth, NOT from user input,
 * and provide a trusted server clock. This module is not deployed/exported.
 *
 * Only admin_daily_schedule_previews and admin_audit are written. Published
 * tasks, historic entitlements, user wallets and admin wallets are untouched.
 */
const {FieldValue, Timestamp} = require("firebase-admin/firestore");
const {
  SLOTS, iraqDayId, midnightUtcForIraqDay, publicationDecision,
} = require("./deda_daily_task_publisher.js");

const ONE_DAY_MS = 24 * 60 * 60 * 1000;
const MIN_LEAD_MS = 60 * 1000;

function nextIraqMidnightUtc(trustedNow) {
  const now = trustedNow instanceof Date ? trustedNow : new Date(trustedNow);
  if (!Number.isFinite(now.getTime())) throw Error("invalid-trusted-time");
  const day = iraqDayId(now);
  return new Date(midnightUtcForIraqDay(day).getTime() + ONE_DAY_MS);
}

function timestampMs(value) {
  return value && typeof value.toMillis === "function" ?
    value.toMillis() : NaN;
}

function sameConfig(record, source) {
  return !!record && [
    "action", "titleAr", "targetCount",
    "rewardUnit", "rewardAmount", "url",
  ].every((key) => record[key] === source[key]);
}

function restoreDecision({
  slotId, publicationId, current, history, previousPreview,
  actor, trustedNow,
}) {
  if (!SLOTS.includes(slotId) ||
      typeof publicationId !== "string" ||
      publicationId.length > 100) return {ok: false, reason: "invalid-source"};

  if (!actor || actor.active !== true ||
      actor.role !== "general_manager" ||
      (actor.status != null && actor.status !== "active")) {
    return {ok: false, reason: "general-manager-required"};
  }

  const now = trustedNow instanceof Date ? trustedNow : new Date(trustedNow);
  if (!Number.isFinite(now.getTime())) throw Error("invalid-trusted-time");
  const next = nextIraqMidnightUtc(now);
  if (next.getTime() - now.getTime() < MIN_LEAD_MS) {
    return {ok: false, reason: "too-close-to-midnight"};
  }

  if (!current || !history ||
      current.slotId !== slotId ||
      history.slotId !== slotId ||
      current.publicationId !== publicationId ||
      history.publicationId !== publicationId ||
      current.effectiveDay !== history.effectiveDay ||
      !history.priorConfig ||
      timestampMs(current.effectiveAt) > now.getTime() ||
      !Number.isFinite(timestampMs(current.effectiveAt))) {
    return {ok: false, reason: "stale-or-missing-publication"};
  }

  const prior = history.priorConfig;
  const expectedPreview = {
    slotId,
    action: prior.action,
    titleAr: prior.titleAr,
    titleEn: prior.titleAr,
    targetCount: prior.targetCount,
    rewardUnit: prior.rewardUnit,
    rewardAmount: prior.rewardAmount,
    url: prior.url,
    revision: (previousPreview?.revision || 0) + 1,
    status: "pending",
    effectiveAt: Timestamp.fromDate(next),
  };
  const valid = publicationDecision(
      expectedPreview, slotId, new Date(next.getTime() + 60000));
  if (!valid.eligible) {
    return {ok: false, reason: "invalid-previous-configuration"};
  }
  if (previousPreview && previousPreview.status === "pending" &&
      timestampMs(previousPreview.effectiveAt) > now.getTime()) {
    if (timestampMs(previousPreview.effectiveAt) === next.getTime() &&
        sameConfig(previousPreview, prior)) {
      return {ok: true, outcome: "already-scheduled", next, preview: null};
    }
    return {ok: false, reason: "conflict-pending-schedule"};
  }
  return {ok: true, outcome: "scheduled", next, preview: expectedPreview};
}

async function schedulePreviousDailyTask(db, {
  slotId, publicationId, requesterUid, trustedNow,
} = {}) {
  if (!db || typeof db.runTransaction !== "function") {
    throw Error("server-firestore-required");
  }
  if (typeof requesterUid !== "string" || requesterUid.length < 1 ||
      requesterUid.length > 128 ||
      !SLOTS.includes(slotId) ||
      typeof publicationId !== "string" ||
      !/^[0-9]{8}__(?:[a-z_]+)$/.test(publicationId) ||
      publicationId !== publicationId.slice(0, 10) + slotId) {
    return {slotId, outcome: "invalid-request"};
  }
  const now = trustedNow instanceof Date ? trustedNow : new Date(trustedNow);
  if (!Number.isFinite(now.getTime())) throw Error("invalid-trusted-time");

  const adminRef = db.collection("admins").doc(requesterUid);
  const publishedRef = db.collection("deda_daily_published_task_slots")
      .doc(slotId);
  const historyRef = db.collection("deda_daily_task_publication_history")
      .doc(publicationId);
  const previewRef = db.collection("admin_daily_schedule_previews")
      .doc("preview_" + slotId);
  const auditRef = db.collection("admin_audit").doc();

  return db.runTransaction(async (tx) => {
    // Read all references before making ANY Firestore write.
    const [adminSnap, currentSnap, historySnap, previewSnap] = await Promise.all([
      tx.get(adminRef), tx.get(publishedRef),
      tx.get(historyRef), tx.get(previewRef),
    ]);
    const actor = adminSnap.exists ? adminSnap.data() : null;
    const result = restoreDecision({
      slotId, publicationId,
      current: currentSnap.exists ? currentSnap.data() : null,
      history: historySnap.exists ? historySnap.data() : null,
      previousPreview: previewSnap.exists ? previewSnap.data() : null,
      actor,
      trustedNow: now,
    });
    if (!result.ok) return {slotId, outcome: result.reason};
    if (result.outcome === "already-scheduled") {
      return {slotId, outcome: "already-scheduled"};
    }

    const values = {
      ...result.preview,
      createdByUid: previewSnap.exists
        ? previewSnap.data().createdByUid : requesterUid,
      createdAt: previewSnap.exists
        ? previewSnap.data().createdAt : FieldValue.serverTimestamp(),
      updatedByUid: requesterUid,
      updatedAt: FieldValue.serverTimestamp(),
    };
    tx.set(previewRef, values);
    tx.create(auditRef, {
      action: "daily_task_previous_version_scheduled",
      adminUid: requesterUid,
      adminName: String(actor.displayName || ""),
      adminRole: "general_manager",
      slotId,
      sourceCollection: "deda_daily_task_publication_history",
      sourceId: publicationId,
      targetCollection: "admin_daily_schedule_previews",
      targetId: previewRef.id,
      revision: result.preview.revision,
      effectiveAt: Timestamp.fromDate(result.next),
      createdAt: FieldValue.serverTimestamp(),
    });
    return {slotId, outcome: "scheduled", effectiveAt: result.next.toISOString()};
  });
}

module.exports = {
  nextIraqMidnightUtc,
  restoreDecision,
  schedulePreviousDailyTask,
};
