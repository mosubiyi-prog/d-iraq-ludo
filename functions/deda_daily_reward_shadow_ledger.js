"use strict";

/**
 * DEDA stage 9 — SHADOW REWARD LEDGER PROTOTYPE. EMULATOR ONLY.
 * NOT a payable wallet, NOT exported from index.js, never mutates users,
 * local Flutter points, admin wallets, gifts, or task configuration.
 * A verified event is a TEST FIXTURE, not real evidence of user completion.
 */
const {FieldValue} = require("firebase-admin/firestore");
const {SLOTS, iraqDayId, midnightUtcForIraqDay} =
    require("./deda_daily_task_publisher.js");

const PROJECT = "demo-deda-stage9-shadow-rewards";
const MAX_PER_CLAIM = 5000;
const MAX_DAILY_PER_UNIT = 10000;
const UNIT_KEYS = Object.freeze(["points", "diamonds"]);
const SHADOW_COLLECTIONS = Object.freeze({
  events: "deda_stage9_shadow_verified_events",
  balances: "deda_stage9_shadow_balances",
  ledger: "deda_stage9_shadow_ledger",
  dailyTotals: "deda_stage9_shadow_daily_totals",
});

function requireEmulator(db) {
  // Hard-fail outside a named local Firebase demo project.
  if (!process.env.FIRESTORE_EMULATOR_HOST ||
      process.env.GCLOUD_PROJECT !== PROJECT ||
      !db || typeof db.runTransaction !== "function") {
    throw Error("STAGE9_EMULATOR_ONLY_DO_NOT_PAY");
  }
}

function eventId(uid, day, slot) {
  return Buffer.from(uid, "utf8").toString("base64url") + "__" +
    day.replace(/-/g, "") + "__" + slot;
}

function ledgerId(uid, day, slot, revision) {
  return eventId(uid, day, slot) + "__r" + revision;
}

function asMillis(value) {
  return value && typeof value.toMillis === "function" ?
    value.toMillis() : NaN;
}

function validBalance(data) {
  return data && UNIT_KEYS.every((key) =>
    Number.isSafeInteger(data[key]) && data[key] >= 0);
}

function eligiblePublishedTask(config, slotId, dayId, trustedNow) {
  if (!config || config.slotId !== slotId ||
      !SLOTS.includes(slotId) || config.action !== slotId ||
      config.effectiveDay !== dayId ||
      config.publicationId !== dayId.replace(/-/g, "") + "__" + slotId ||
      !Number.isSafeInteger(config.sourcePreviewRevision) ||
      config.sourcePreviewRevision < 1 ||
      !Number.isSafeInteger(config.targetCount) ||
      config.targetCount !== 1 ||
      !UNIT_KEYS.includes(config.rewardUnit) ||
      !Number.isSafeInteger(config.rewardAmount) ||
      config.rewardAmount < 1 || config.rewardAmount > MAX_PER_CLAIM ||
      config.rewardsEnabled !== false ||
      config.rewardClaimMode !== "disabled_until_verified_server_ledger") {
    return false;
  }
  const start = midnightUtcForIraqDay(dayId).getTime();
  const effective = asMillis(config.effectiveAt);
  const published = asMillis(config.publishedAt);
  return effective === start &&
    Number.isFinite(published) &&
    published >= start &&
    published < start + 15 * 60 * 1000 &&
    published <= trustedNow.getTime();
}

function validFixture(event, config, uid, slotId, dayId, trustedNow) {
  if (!event || event.uid !== uid || event.slotId !== slotId ||
      event.dayId !== dayId || event.action !== slotId ||
      event.publicationId !== config.publicationId ||
      event.sourcePreviewRevision !== config.sourcePreviewRevision ||
      event.eventState !== "verified" ||
      event.fixtureSource !== "stage9_emulator_server_fixture" ||
      event.serverVerified !== true) return false;
  const at = asMillis(event.verifiedAt);
  return Number.isFinite(at) &&
    at >= asMillis(config.publishedAt) &&
    at <= trustedNow.getTime();
}

/**
 * Hypothetical balance for a demo emulator only, NOT real reward payment.
 * Ledger key = (UID, Iraq day, slot, published revision). All reads occur
 * before writes, with a daily per-unit cap and an atomic ledger create.
 */
async function simulateVerifiedDailyReward(db, {
  uid, slotId, trustedNow,
} = {}) {
  requireEmulator(db);
  if (typeof uid !== "string" ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(uid) ||
      !SLOTS.includes(slotId)) {
    return {outcome: "invalid-identity-or-slot"};
  }
  const now = trustedNow instanceof Date ? trustedNow : new Date(trustedNow);
  if (!Number.isFinite(now.getTime())) throw Error("invalid-trusted-server-time");
  const dayId = iraqDayId(now);
  const key = eventId(uid, dayId, slotId);

  const configRef = db.collection("deda_daily_published_task_slots").doc(slotId);
  const eventRef = db.collection(SHADOW_COLLECTIONS.events).doc(key);
  const balanceRef = db.collection(SHADOW_COLLECTIONS.balances).doc(uid);
  const dailyRef = db.collection(SHADOW_COLLECTIONS.dailyTotals)
      .doc(Buffer.from(uid).toString("base64url") + "__" +
           dayId.replace(/-/g, ""));

  return db.runTransaction(async (tx) => {
    // All Firestore transaction reads must occur before ANY write.
    const [publishedSnap, eventSnap, balanceSnap, dailySnap] = await Promise.all([
      tx.get(configRef), tx.get(eventRef), tx.get(balanceRef), tx.get(dailyRef),
    ]);
    if (!publishedSnap.exists) return {outcome: "unpublished"};
    const config = publishedSnap.data();
    if (!eligiblePublishedTask(config, slotId, dayId, now)) {
      return {outcome: "invalid-or-inactive-config"};
    }
    if (!eventSnap.exists ||
        !validFixture(eventSnap.data(), config, uid, slotId, dayId, now)) {
      return {outcome: "unverified-event"};
    }

    const entry = db.collection(SHADOW_COLLECTIONS.ledger)
        .doc(ledgerId(uid, dayId, slotId, config.sourcePreviewRevision));
    const entrySnap = await tx.get(entry);
    if (entrySnap.exists) return {outcome: "already-recorded"};

    const balances = balanceSnap.exists ? balanceSnap.data() :
      {points: 0, diamonds: 0};
    const daily = dailySnap.exists ? dailySnap.data() :
      {points: 0, diamonds: 0};
    if (!validBalance(balances) || !validBalance(daily)) {
      return {outcome: "invalid-shadow-balance"};
    }
    const unit = config.rewardUnit;
    const amount = config.rewardAmount;
    if (daily[unit] + amount > MAX_DAILY_PER_UNIT ||
        !Number.isSafeInteger(balances[unit] + amount)) {
      return {outcome: "shadow-limit-reached"};
    }

    tx.set(balanceRef, {
      points: balances.points + (unit === "points" ? amount : 0),
      diamonds: balances.diamonds + (unit === "diamonds" ? amount : 0),
      shadowOnly: true,
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.set(dailyRef, {
      points: daily.points + (unit === "points" ? amount : 0),
      diamonds: daily.diamonds + (unit === "diamonds" ? amount : 0),
      shadowOnly: true, dayId, uid,
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.create(entry, {
      uid, dayId, slotId,
      publicationId: config.publicationId,
      sourcePreviewRevision: config.sourcePreviewRevision,
      unit, amount, verifiedEventId: key,
      shadowOnly: true,
      createdAt: FieldValue.serverTimestamp(),
    });
    return {outcome: "shadow-recorded", unit, amount, dayId};
  });
}

module.exports = {
  PROJECT,
  SHADOW_COLLECTIONS,
  eventId,
  ledgerId,
  eligiblePublishedTask,
  simulateVerifiedDailyReward,
};
