"use strict";

/**
 * Pure audited plan for weekly 06:00-after-freeze gifts.
 * NO Firestore client/admin writes. The real gift worker MUST use deterministic
 * gift ID in a transaction and verify the source documents have not changed.
 * 100405 must NOT pay any live diamonds until source->Hadaya integration QA.
 */
const ORIGIN = Date.UTC(2026, 9, 31, 3); // 06:00 Baghdad on Oct 31.
const WEEK_MS = 7 * 24 * 60 * 60 * 1000;
const ID = /^@DEDA-[A-Z0-9]{4,12}$/;
const PRIZES = Object.freeze([150, 100, 50, 10, 10, 10, 10, 10, 10, 10]);

function weekStart(weekId) {
  if (typeof weekId !== "string" ||
      !/^20[0-9]{2}-[0-9]{2}-[0-9]{2}$/.test(weekId)) {
    throw Error("INVALID_WEEK_ID");
  }
  const [year, month, day] = weekId.split("-").map(Number);
  const begin = Date.UTC(year, month - 1, day, 3);
  const dt = new Date(begin);
  const iraq = new Date(begin + 3 * 3600000);
  if (iraq.getUTCFullYear() !== year ||
      iraq.getUTCMonth() + 1 !== month ||
      iraq.getUTCDate() !== day ||
      (begin - ORIGIN) % WEEK_MS !== 0 || begin < ORIGIN) {
    throw Error("NOT_A_DEDA_WEEK");
  }
  return begin;
}

function safeMs(value) {
  if (Number.isSafeInteger(value) && value >= 0) return value;
  if (value && typeof value.toMillis === "function") {
    const n = value.toMillis();
    if (Number.isSafeInteger(n) && n >= 0) return n;
  }
  throw Error("INVALID_RECEIPT_TIME");
}

function plan({weekId, atMs, records, freezes = new Map()}) {
  const start = weekStart(weekId);
  if (!Number.isSafeInteger(atMs) || atMs < start + WEEK_MS) {
    throw Error("AWARDS_BEFORE_NEXT_SATURDAY_06");
  }
  if (!Array.isArray(records) || records.length > 100) {
    throw Error("INVALID_WEEKLY_SOURCE_SIZE");
  }
  if (!(freezes instanceof Map)) throw Error("INVALID_REVIEW_SOURCE");
  const names = new Set();
  const eligible = records.map((entry) => {
    if (!entry || typeof entry !== "object") throw Error("INVALID_SCORE_ROW");
    const {id, data} = entry;
    if (!ID.test(id) || names.has(id) || data?.publicId !== id ||
        data.weekId !== weekId || !Number.isSafeInteger(data.weeklyXp) ||
        !Number.isSafeInteger(data.completedTasks) ||
        data.completedTasks < 1 || data.completedTasks > 56 ||
        data.weeklyXp !== 20 * data.completedTasks ||
        typeof data.displayName !== "string" ||
        data.displayName.trim().length < 2 ||
        data.displayName.trim().length > 60) {
      throw Error("UNTRUSTED_SCORE_ROW");
    }
    names.add(id);
    return {
      publicId:id, name:data.displayName.trim(), weeklyXp:data.weeklyXp,
      timestamp:safeMs(data.updatedAt),
    };
  }).sort((a, b) => b.weeklyXp - a.weeklyXp ||
    a.timestamp - b.timestamp || a.publicId.localeCompare(b.publicId));

  const winners = [];
  for (const [index, row] of eligible.entries()) {
    if (index >= 10) break;
    if (freezes.get(row.publicId) === true) {
      // The original place is held; no reallocation without an owner decision.
      continue;
    }
    const amount=PRIZES[index];
    winners.push(Object.freeze({
      place:index + 1,
      publicId:row.publicId,
      name:row.name,
      amount,
      weekId,
      // Safe repeat: must be created atomically only when absent.
      giftId:'deda-weekly-' + weekId + '-' + row.publicId.slice(1),
    }));
  }
  return Object.freeze({
    weekId, closedAtMs:start + WEEK_MS,
    totalDiamonds: winners.reduce((sum, a)=>sum + a.amount,0),
    winners:Object.freeze(winners),
  });
}

module.exports = Object.freeze({weekStart, plan, PRIZES, ORIGIN, WEEK_MS});
