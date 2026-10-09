"use strict";

/**
 * Stage 11: EMULATOR-ONLY seasonal daily-login policy.
 *
 * This is a scheduling/configuration prototype, NOT a payout service.
 * It NEVER edits legacy Flutter's 10 local points, users, wallets or rewards.
 * "points", "coins", and "diamonds" are different units: no conversions.
 * The manager identity and clock must come from a future authenticated server
 * endpoint. No callable, scheduler or production export is added now.
 */
const {FieldValue} = require("firebase-admin/firestore");
const {iraqDayId, midnightUtcForIraqDay} =
    require("./deda_daily_task_publisher.js");

const PROJECT = "demo-deda-stage11-seasonal-login";
const CONTROL = "deda_stage11_shadow_login_control";
const AUDIT = "deda_stage11_shadow_login_audit";
const CONTROL_ID = "policy";
const UNITS = new Set(["points", "coins", "diamonds"]);
const DAY_MS = 24 * 60 * 60 * 1000;
const MAX_REWARD = 5000;
const MAX_ENTRIES = 48;
const MAX_DAYS_AHEAD = 366;
const MAX_PROMO_DAYS = 31;
const BASE = Object.freeze({
  unit: "points",
  amount: 10,
  source: "legacy-base",
  isPromotion: false,
  canGrantRewards: false,
});

function ensureEmulator(db) {
  if (!process.env.FIRESTORE_EMULATOR_HOST ||
      process.env.GCLOUD_PROJECT !== PROJECT ||
      !db || typeof db.runTransaction !== "function") {
    throw Error("STAGE11_EMULATOR_ONLY_NO_LIVE_PAYOUT");
  }
}

function midnight(dayId) {
  try {
    return midnightUtcForIraqDay(dayId).getTime();
  } catch (_) {
    return NaN;
  }
}

function nextIraqDay(instant) {
  const day = iraqDayId(instant);
  return iraqDayId(new Date(midnight(day) + DAY_MS + 1000));
}

function validReward(unit, amount) {
  return UNITS.has(unit) &&
    Number.isSafeInteger(amount) && amount >= 1 && amount <= MAX_REWARD;
}

function validEntry(e) {
  if (!e || typeof e !== "object" || Array.isArray(e) ||
      typeof e.id !== "string" || !/^[A-Za-z0-9_-]{3,40}$/.test(e.id) ||
      !["regular", "offer"].includes(e.kind) ||
      !["scheduled", "cancelled"].includes(e.status) ||
      !validReward(e.unit, e.amount)) return false;
  if (e.kind === "regular") {
    return Number.isFinite(midnight(e.effectiveDay)) &&
      e.startDay == null && e.endDay == null;
  }
  const start = midnight(e.startDay);
  const end = midnight(e.endDay);
  return Number.isFinite(start) && Number.isFinite(end) &&
    end >= start && end - start < MAX_PROMO_DAYS * DAY_MS &&
    e.effectiveDay == null;
}

function validPolicy(policy) {
  if (!policy || policy.schemaVersion !== 1 ||
      !Number.isSafeInteger(policy.revision) || policy.revision < 0 ||
      !Array.isArray(policy.entries) || policy.entries.length > MAX_ENTRIES) {
    return false;
  }
  const ids = new Set();
  for (const entry of policy.entries) {
    if (!validEntry(entry) || ids.has(entry.id)) return false;
    ids.add(entry.id);
  }
  return true;
}

/**
 * A pure, deterministic schedule lookup. Effective at 00:00 Baghdad time
 * until 23:59:59.999 on the offer's INCLUSIVE end day. Past daily decisions
 * never change because schedule edits on/after their effective day are denied.
 *
 * No reward claim, side effect or wallet balance is involved.
 */
function selectLoginReward(policy, trustedNow) {
  const now = trustedNow instanceof Date ? trustedNow : new Date(trustedNow);
  if (!Number.isFinite(now.getTime())) throw Error("invalid-trusted-time");
  if (policy != null && !validPolicy(policy)) {
    return {...BASE, policyInvalid: true};
  }
  const dayId = iraqDayId(now);
  const entries = policy?.entries || [];
  const activeRegular = entries
      .filter((e) => e.kind === "regular" && e.status === "scheduled" &&
        e.effectiveDay <= dayId)
      .sort((a, b) => a.effectiveDay.localeCompare(b.effectiveDay))
      .at(-1);
  const regular = activeRegular ? {
    unit: activeRegular.unit, amount: activeRegular.amount,
    source: activeRegular.id, isPromotion: false, canGrantRewards: false,
  } : BASE;
  const currentOffer = entries.find((e) =>
    e.kind === "offer" && e.status === "scheduled" &&
    e.startDay <= dayId && dayId <= e.endDay);
  return {
    ...(currentOffer ? {
      unit: currentOffer.unit,
      amount: currentOffer.amount,
      source: currentOffer.id,
      isPromotion: true,
      canGrantRewards: false,
    } : regular),
    dayId,
  };
}

function fieldsOnly(value, fields) {
  return value && typeof value === "object" && !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype &&
    Object.keys(value).length === fields.length &&
    Object.keys(value).every((k) => fields.includes(k)) &&
    fields.every((k) => Object.prototype.hasOwnProperty.call(value, k));
}

function validateCommand(command, now) {
  if (!command || typeof command !== "object") {
    return "invalid-command";
  }
  const common = ["kind", "id", "expectedRevision"];
  if (command.kind === "regular") {
    if (!fieldsOnly(command, [...common, "effectiveDay", "unit", "amount"])) {
      return "invalid-command";
    }
  } else if (command.kind === "offer") {
    if (!fieldsOnly(command,
        [...common, "startDay", "endDay", "unit", "amount"])) {
      return "invalid-command";
    }
  } else if (command.kind === "cancel") {
    if (!fieldsOnly(command, common)) return "invalid-command";
  } else {
    return "invalid-command";
  }
  if (typeof command.id !== "string" ||
      !/^[A-Za-z0-9_-]{3,40}$/.test(command.id) ||
      !Number.isSafeInteger(command.expectedRevision) ||
      command.expectedRevision < 0) return "invalid-command";
  if (command.kind === "cancel") return null;
  const e = command.kind === "regular" ? {
    ...command, status: "scheduled",
  } : {
    ...command, status: "scheduled",
  };
  if (!validEntry(e)) return "invalid-amount-date-or-unit";
  const tomorrow = midnight(nextIraqDay(now));
  const limit = tomorrow + MAX_DAYS_AHEAD * DAY_MS;
  const start = midnight(command.kind === "regular" ?
    command.effectiveDay : command.startDay);
  if (start < tomorrow || start >= limit) return "must-start-future-day";
  return null;
}

/**
 * Authenticated manager identity must be server-derived in stage 12.
 * All mutations read manager + single policy document before writing.
 * Every success adds an audit record; retries with a stale revision fail.
 */
async function simulateManagerLoginPolicyChange(db, {
  requesterUid, command, trustedNow,
} = {}) {
  ensureEmulator(db);
  const now = trustedNow instanceof Date ? trustedNow : new Date(trustedNow);
  if (!Number.isFinite(now.getTime())) throw Error("invalid-trusted-time");
  if (typeof requesterUid !== "string" ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(requesterUid)) {
    return {outcome: "manager-sign-in-required"};
  }
  const error = validateCommand(command, now);
  if (error) return {outcome: error};

  const adminRef = db.collection("admins").doc(requesterUid);
  const configRef = db.collection(CONTROL).doc(CONTROL_ID);
  const auditRef = db.collection(AUDIT).doc();

  return db.runTransaction(async (tx) => {
    const [adminSnap, currentSnap] = await Promise.all([
      tx.get(adminRef), tx.get(configRef),
    ]);
    const admin = adminSnap.exists ? adminSnap.data() : {};
    if (admin.role !== "general_manager" ||
        admin.active !== true || admin.status !== "active") {
      return {outcome: "general-manager-required"};
    }
    const data = currentSnap.exists ? currentSnap.data() :
      {schemaVersion: 1, revision: 0, entries: []};
    if (!validPolicy(data)) return {outcome: "invalid-existing-policy"};
    if (command.expectedRevision !== data.revision) {
      return {outcome: "stale-policy-revision"};
    }
    const entries = data.entries.map((e) => ({...e}));
    if (command.kind === "cancel") {
      const target = entries.find((e) => e.id === command.id);
      if (!target) return {outcome: "not-found"};
      if (target.status === "cancelled") {
        return {outcome: "already-cancelled"};
      }
      const start = midnight(target.kind === "regular" ?
        target.effectiveDay : target.startDay);
      if (start < midnight(nextIraqDay(now))) {
        return {outcome: "cannot-change-current-or-past"};
      }
      target.status = "cancelled";
    } else {
      if (entries.length >= MAX_ENTRIES) return {outcome: "schedule-full"};
      if (entries.some((e) => e.id === command.id)) {
        return {outcome: "duplicate-schedule-id"};
      }
      if (command.kind === "regular") {
        if (entries.some((e) => e.kind === "regular" &&
            e.status === "scheduled" &&
            e.effectiveDay === command.effectiveDay)) {
          return {outcome: "regular-date-conflict"};
        }
        entries.push({
          id: command.id, kind: "regular", status: "scheduled",
          effectiveDay: command.effectiveDay,
          unit: command.unit, amount: command.amount,
        });
      } else {
        for (const e of entries) {
          if (e.kind === "offer" && e.status === "scheduled" &&
              command.startDay <= e.endDay &&
              command.endDay >= e.startDay) {
            return {outcome: "offer-overlap"};
          }
        }
        entries.push({
          id: command.id, kind: "offer", status: "scheduled",
          startDay: command.startDay, endDay: command.endDay,
          unit: command.unit, amount: command.amount,
        });
      }
    }

    const revision = data.revision + 1;
    tx.set(configRef, {
      schemaVersion: 1, revision, entries,
      updatedByUid: requesterUid,
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.create(auditRef, {
      action: "stage11_shadow_login_" + command.kind,
      adminUid: requesterUid,
      policyRevision: revision,
      scheduleId: command.id,
      sandboxOnly: true,
      createdAt: FieldValue.serverTimestamp(),
    });
    return {outcome: "scheduled-shadow-only", revision};
  });
}

module.exports = {
  PROJECT, CONTROL, AUDIT, CONTROL_ID,
  BASE, MAX_REWARD, nextIraqDay, validPolicy,
  selectLoginReward, simulateManagerLoginPolicyChange,
};
