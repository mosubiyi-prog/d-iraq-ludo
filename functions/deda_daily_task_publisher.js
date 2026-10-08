"use strict";

/**
 * DEDA stage 3: UNEXPORTED prototype for scheduled task CONFIG publication.
 *
 * Do not wire into functions/index.js, deploy Firebase, or interpret a
 * published config as a verified point/coin/diamond entitlement yet.
 * A future onSchedule entrypoint may call publishDueDailySlots with
 * a trusted Cloud Functions clock, AFTER the user client and reward ledger
 * have been integrated and tested together.
 */
const HOURS_3_MS = 3 * 60 * 60 * 1000;
const PUBLICATION_GRACE_MS = 15 * 60 * 1000;

const SLOT_DEFAULTS = Object.freeze({
  share_personal_location: "شارك مكانك الشخصي",
  open_map: "افتح الخريطة",
  share_registered_place: "شارك إدارة مكانك إن وجد",
  open_saved_place: "زيارة مكان محفوظ",
  open_received_place: "افتح أي مكان تمت مشاركته معك",
  review_added_place: "مراجعة مكان مضاف",
  traffic_skills: "اختبر مهاراتك",
  long_trip: "استفد من رحلتك الطويلة إن وجدت",
});
const SLOTS = Object.freeze(Object.keys(SLOT_DEFAULTS));
const ACTIONS = new Set([...SLOTS, "visit_telegram"]);
const VALID_UNITS = new Set(["points", "diamonds"]);

function iraqDayId(instant) {
  const value = instant instanceof Date ? instant.getTime() : Number(instant);
  if (!Number.isFinite(value)) throw Error("invalid-trusted-time");
  return new Date(value + HOURS_3_MS).toISOString().slice(0, 10);
}

function midnightUtcForIraqDay(dayId) {
  if (typeof dayId !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(dayId)) {
    throw Error("invalid-iraq-day");
  }
  const midnightAtUtc = Date.parse(dayId + "T00:00:00.000Z");
  if (!Number.isFinite(midnightAtUtc) ||
      new Date(midnightAtUtc).toISOString().slice(0, 10) !== dayId) {
    throw Error("invalid-iraq-day");
  }
  return new Date(midnightAtUtc - HOURS_3_MS);
}

function millis(timestamp) {
  if (timestamp && typeof timestamp.toMillis === "function") {
    return timestamp.toMillis();
  }
  if (timestamp instanceof Date) return timestamp.getTime();
  return NaN;
}

function validTelegramUrl(value) {
  if (typeof value !== "string" || value.length > 220) return false;
  try {
    const parsed = new URL(value);
    return parsed.protocol === "https:" &&
      ["t.me", "telegram.me"].includes(parsed.hostname) &&
      parsed.username === "" && parsed.password === "" &&
      parsed.port === "" && !parsed.search && !parsed.hash &&
      /^\/[A-Za-z0-9_/-]{1,180}$/.test(parsed.pathname);
  } catch (_) {
    return false;
  }
}

function publicationDecision(preview, slotId, trustedNow) {
  if (!Object.prototype.hasOwnProperty.call(SLOT_DEFAULTS, slotId)) {
    return {eligible: false, reason: "unknown-slot"};
  }
  if (!preview || preview.status !== "pending" ||
      preview.slotId !== slotId) {
    return {eligible: false, reason: "not-pending"};
  }
  if (!ACTIONS.has(preview.action) ||
      !VALID_UNITS.has(preview.rewardUnit) ||
      !Number.isInteger(preview.targetCount) || preview.targetCount < 1 ||
      preview.targetCount > 100 ||
      !Number.isInteger(preview.rewardAmount) || preview.rewardAmount < 1 ||
      preview.rewardAmount > 5000 ||
      !Number.isInteger(preview.revision) || preview.revision < 1 ||
      typeof preview.titleAr !== "string" ||
      preview.titleAr.trim().length < 3 ||
      preview.titleAr.trim().length > 80 ||
      preview.titleEn !== preview.titleAr ||
      typeof preview.url !== "string" ||
      (preview.action === "visit_telegram"
        ? !validTelegramUrl(preview.url)
        : preview.url !== "")) {
    return {eligible: false, reason: "invalid-config"};
  }

  const instant = trustedNow instanceof Date ? trustedNow : new Date(trustedNow);
  const now = instant.getTime();
  if (!Number.isFinite(now)) throw Error("invalid-trusted-time");
  const dayId = iraqDayId(now);
  const expectedStart = midnightUtcForIraqDay(dayId).getTime();
  if (millis(preview.effectiveAt) !== expectedStart) {
    return {eligible: false, reason: "not-today-midnight"};
  }
  if (now < expectedStart || now >= expectedStart + PUBLICATION_GRACE_MS) {
    return {eligible: false, reason: "outside-midnight-window"};
  }
  return {eligible: true, dayId, expectedStart};
}

/**
 * Run by future privileged scheduler only. Firestore transaction ensures
 * atomic versioning, immutable publication history, and same-day dedupe.
 *
 * No Cloud Function is exported; no automatic runtime execution occurs.
 * This code does not award balances and sets 'rewardsEnabled' to false.
 */
async function publishDueDailySlots(db, trustedNow) {
  if (!db || typeof db.runTransaction !== "function") {
    throw Error("server-firestore-required");
  }
  const instant = trustedNow instanceof Date ? trustedNow : new Date(trustedNow);
  if (!Number.isFinite(instant.getTime())) throw Error("invalid-trusted-time");
  const results = [];
  for (const slotId of SLOTS) {
    const source = db.collection("admin_daily_schedule_previews")
        .doc("preview_" + slotId);
    const published = db.collection("deda_daily_published_task_slots").doc(slotId);
    const dayId = iraqDayId(instant);
    const historyId = dayId.replace(/-/g, "") + "__" + slotId;
    const history = db.collection("deda_daily_task_publication_history")
        .doc(historyId);

    const outcome = await db.runTransaction(async (tx) => {
      // All Firestore transaction reads come before any writes.
      const [src, current, priorHistory] = await Promise.all([
        tx.get(source), tx.get(published), tx.get(history),
      ]);
      if (!src.exists) return "no-preview";
      const preview = src.data();
      const decision = publicationDecision(preview, slotId, instant);
      if (!decision.eligible) return decision.reason;
      if (priorHistory.exists ||
          (current.exists && current.data().effectiveDay === dayId)) {
        return "already-published";
      }
      const previous = current.exists
        ? {
            action: current.data().action,
            titleAr: current.data().titleAr,
            targetCount: current.data().targetCount,
            rewardUnit: current.data().rewardUnit,
            rewardAmount: current.data().rewardAmount,
            url: current.data().url,
          }
        : {
            action: slotId, titleAr: SLOT_DEFAULTS[slotId],
            targetCount: 1, rewardUnit: "points",
            rewardAmount: 5, url: "",
          };
      const publicationId = historyId;
      const values = {
        slotId,
        action: preview.action,
        titleAr: preview.titleAr,
        titleEn: preview.titleAr,
        targetCount: preview.targetCount,
        rewardUnit: preview.rewardUnit,
        rewardAmount: preview.rewardAmount,
        url: preview.url,
        effectiveDay: dayId,
        effectiveAt: preview.effectiveAt,
        sourcePreviewRevision: preview.revision,
        publicationId,
        // NEVER enable from configuration alone. Server-side completion
        // verification and a separate atomic reward ledger are still missing.
        rewardsEnabled: false,
        rewardClaimMode: "disabled_until_verified_server_ledger",
        publishedAt: dbTimestamp(db),
      };
      tx.set(published, values);
      tx.create(history, {
        publicationId,
        slotId,
        effectiveDay: dayId,
        sourcePreviewRevision: preview.revision,
        priorConfig: previous,
        newConfig: {
          action: preview.action,
          titleAr: preview.titleAr,
          targetCount: preview.targetCount,
          rewardUnit: preview.rewardUnit,
          rewardAmount: preview.rewardAmount,
          url: preview.url,
        },
        createdAt: dbTimestamp(db),
      });
      return "published-config-only";
    });
    results.push({slotId, outcome});
  }
  return results;
}

function dbTimestamp(db) {
  // Timestamp helper injected by Admin SDK calling code (not by the user).
  if (!db.FieldValue || typeof db.FieldValue.serverTimestamp !== "function") {
    throw Error("firestore-server-timestamp-required");
  }
  return db.FieldValue.serverTimestamp();
}

module.exports = {
  SLOTS,
  iraqDayId,
  midnightUtcForIraqDay,
  publicationDecision,
  publishDueDailySlots,
};
