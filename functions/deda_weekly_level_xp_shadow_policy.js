"use strict";

/**
 * DEDA 100387 original signed-source audit proves 20 level XP on each
 * successful daily-task claim, separate from 5 ordinary task points.
 * This is a TEST-FIXTURE-ONLY, READ-ONLY model, not a cloud deployment.
 * NEVER trust a client-provided verifiedByServer field in production.
 */
const {verifiedWeek, previewClosedWeekPrizePlan} =
    require("./deda_weekly_leaderboard_shadow_policy.js");
const XP_PER_TASK_CLAIM = 20;
const MARKER = "stage5_emulator_only";
const MAX_FIXTURES = 50000;

function error(reason) { throw Error("DEDA_LEVEL_XP_SHADOW_" + reason); }

function textField(value, regex, reason) {
  if (typeof value !== "string" || !regex.test(value)) error(reason);
  return value;
}

function iraqDay(instant) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Baghdad", year: "numeric",
    month: "2-digit", day: "2-digit",
  }).formatToParts(new Date(instant));
  const obj = Object.fromEntries(parts.map(p => [p.type, p.value]));
  return [obj.year, obj.month, obj.day].join("-");
}

function fixture(week, r) {
  if (!r || typeof r !== "object" || Array.isArray(r)) error("shape");
  if (r.fixtureSource !== MARKER || r.verifiedByServer !== true) {
    error("unverified");
  }
  if (r.eventType !== "task_claim") error("not_task_claim");
  // The current app awards ordinary task points, login points and answer
  // points separately. ONLY the task-reward-claim path awards level XP.
  for (const key of ["clientXp", "clientPoints", "adminBonus", "level",
    "loginPoints", "trafficAnswerPoints", "deviceTimeMs", "walletBalance",
    "publicId", "uid", "diamonds"]) {
    if (Object.prototype.hasOwnProperty.call(r, key)) {
      error("untrusted_" + key);
    }
  }
  if (r.weekId !== week.weekId) error("week_mismatch");
  const accountKey = textField(r.accountKey, /^[0-9]{10,16}$/, "account");
  const taskId = textField(r.taskId, /^[A-Za-z0-9_:-]{1,100}$/, "task");
  const instant = r.verifiedAtMs;
  if (!Number.isSafeInteger(instant) ||
      instant < week.startMs || instant >= week.endMs) error("outside_week");
  const dayId = textField(
      r.iraqDay, /^20\d{2}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/,
      "day");
  if (dayId !== iraqDay(instant)) error("client_day_mismatch");
  return Object.freeze({
    accountKey, taskId, instant, key: [accountKey, dayId, taskId].join("|"),
  });
}

/** Sorts ONLY server-fixture task-claim XP, never current spendable balances. */
function previewWeeklyLevelXp(weekConfig, emulatorFixtures) {
  const week = verifiedWeek(weekConfig);
  if (!Array.isArray(emulatorFixtures) || emulatorFixtures.length > MAX_FIXTURES) {
    error("fixtures");
  }
  const events = emulatorFixtures.map(x => fixture(week,x))
      .sort((a,b) => a.instant - b.instant ||
          a.key.localeCompare(b.key, "en"));
  const seen = new Set();
  const accounts = new Map();
  for (const event of events) {
    if (seen.has(event.key)) continue;
    seen.add(event.key);
    const row = accounts.get(event.accountKey) || {
      accountKey: event.accountKey,
      weeklyPoints: 0,
      verifiedTaskCompletions: 0,
      lastReachedAtMs: 0,
    };
    row.weeklyPoints += XP_PER_TASK_CLAIM;
    row.verifiedTaskCompletions++;
    row.lastReachedAtMs = Math.max(row.lastReachedAtMs, event.instant);
    if (!Number.isSafeInteger(row.weeklyPoints)) error("xp_overflow");
    accounts.set(event.accountKey, row);
  }
  const sorted = [...accounts.values()].sort((a,b) =>
      b.weeklyPoints-a.weeklyPoints ||
      b.verifiedTaskCompletions-a.verifiedTaskCompletions ||
      a.lastReachedAtMs-b.lastReachedAtMs ||
      a.accountKey.localeCompare(b.accountKey,"en"));
  const ranks = Object.freeze(sorted.map((r,i) => Object.freeze({
    place: i+1, accountKey: r.accountKey,
    weeklyPoints: r.weeklyPoints,
    verifiedTaskCompletions: r.verifiedTaskCompletions,
    lastReachedAtMs: r.lastReachedAtMs,
    prizeDiamondsIfFinalWinner:
        i===0 ? 150 : i===1 ? 100 : i===2 ? 50 : i<10 ? 10 : 0,
  })));
  return Object.freeze({
    weekId: week.weekId,
    scoreUnit: "level_xp_earned_from_verified_weekly_task_claims",
    ranks, uniqueTaskClaims: seen.size, shadowOnly: true,
  });
}

function previewEndedWeekPrizes(weekConfig,scores,serverNowMs,alreadyPaid=[]) {
  // Returns proposals, NOT transactions or spendable diamond credits.
  return previewClosedWeekPrizePlan(
      weekConfig,scores,serverNowMs,alreadyPaid);
}

module.exports = Object.freeze({
  XP_PER_TASK_CLAIM, previewWeeklyLevelXp, previewEndedWeekPrizes,
});
