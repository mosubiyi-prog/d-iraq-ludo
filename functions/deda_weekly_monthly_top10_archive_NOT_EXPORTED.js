"use strict";

/**
 * DEDA Stage25: GM MONTHLY TOP-TEN HISTORY PROJECTION — SAFE SHADOW ONLY.
 *
 * Each closed league week is filed under the Baghdad calendar month of its
 * LAST eligible instant (endMs - 1). Preserves ranks 1–10 with special top 3.
 *
 * IMPORTANT: Never display this output as live results. Fixture "issuer" tags
 * and hashes are NOT proof of privileged production issuance. The original
 * server task-XP issuer, canonical profile, real wallet and auth integration
 * remain blocked; this module is NOT exported by functions/index.js.
 * No Firestore write, no admin entrypoint, no live coins/XP/diamonds touched.
 *
 * A month's record consists of the actual closed weekly top tens, NOT an
 * unapproved new monthly points contest, monthly winner or extra payout.
 */
const crypto = require("node:crypto");
const {verifiedWeek} = require("./deda_weekly_leaderboard_shadow_policy.js");
const {
  verifyAndRedactSnapshot,
} = require("./deda_weekly_snapshot_reader_NOT_EXPORTED.js");

const MAX_WEEKS = 6;
const PRIZES = Object.freeze([150, 100, 50, 10, 10, 10, 10, 10, 10, 10]);
const ID = /^20\d{2}-(0[1-9]|1[0-2])$/;

function block(reason) {
  throw Error("DEDA_STAGE25_MONTH_ARCHIVE_BLOCK_" + reason);
}
function safeMs(value) {
  return Number.isSafeInteger(value) && value >= 0;
}
function monthOfBaghdadInstant(ms) {
  if (!safeMs(ms)) block("invalid_server_clock");
  const fields = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Baghdad", year: "numeric", month: "2-digit",
  }).formatToParts(new Date(ms));
  const parts = Object.fromEntries(fields.map(x => [x.type, x.value]));
  return parts.year + "-" + parts.month;
}
function monthCompleted(monthId, nowMs) {
  const [year, month] = monthId.split("-").map(Number);
  // Iraq has UTC+03:00 year-round. This is a presentation boundary only.
  // The server-owned week configuration (not this helper) sets league dates.
  const nextMonthStart = Date.UTC(year, month, 1) - 3 * 3600000;
  return nowMs >= nextMonthStart;
}
function safePublicRows(view) {
  const rows = view.rows.slice(0, 10).map((row, i) => {
    if (row.place !== i + 1 ||
        row.diamondsIfFinalWinner !== PRIZES[i]) block("rank_changed");
    return Object.freeze({
      place: row.place,
      participantId: row.participantId,
      displayName: row.displayName,
      activePublicId: row.activePublicId,
      weeklyPoints: row.weeklyPoints,
      verifiedTaskCompletions: row.verifiedTaskCompletions,
    });
  });
  return Object.freeze(rows);
}
/**
 * Read-only PRIVATE fixture projection. Input is supposed to come ONLY from
 * a future privileged backend's immutable, closed snapshot. Until actual
 * server issuer is approved, all output must remain a shadow preview.
 *
 * A week ending at 00:00 Baghdad is filed in the month of 23:59:59.999
 * on its final eligible day. No resetting prior months, no added diamonds.
 */
function projectShadowMonthlyTopTen({monthId, closedWeeks, serverNowMs, ...rest}) {
  if (Object.keys(rest).length || typeof monthId !== "string" ||
      !ID.test(monthId) || !safeMs(serverNowMs) ||
      !Array.isArray(closedWeeks) || closedWeeks.length > MAX_WEEKS) {
    block("invalid_inputs");
  }
  if (monthOfBaghdadInstant(Date.parse(monthId + "-01T00:00:00Z")) !== monthId) {
    block("invalid_month");
  }
  const history = [];
  const seenWeeks = new Set();
  for (const entry of closedWeeks) {
    if (!entry || typeof entry !== "object" || Array.isArray(entry) ||
        !entry.weekConfig || !entry.snapshot) block("closed_week_required");
    const week = verifiedWeek(entry.weekConfig);
    if (seenWeeks.has(week.weekId)) block("duplicated_closed_week");
    seenWeeks.add(week.weekId);
    if (serverNowMs < week.endMs ||
        monthOfBaghdadInstant(week.endMs - 1) !== monthId) {
      block("incorrect_month_or_unclosed_week");
    }
    const raw = entry.snapshot;
    if (raw.generatedAtMs !== week.endMs - 1) {
      block("not_final_week_close");
    }
    // Future-issuer shape and privacy/order contract only — NOT live proof.
    const view = verifyAndRedactSnapshot(
      raw, week, "__not_a_real_viewer__", serverNowMs, "previous");
    const topTen = safePublicRows(view);
    const publicRecord = {
      weekId: week.weekId,
      startedAtMs: week.startMs,
      endedAtMs: week.endMs,
      topTen,
    };
    const integrityDigest = crypto.createHash("sha256")
      .update(JSON.stringify(publicRecord), "utf8").digest("hex");
    history.push(Object.freeze({
      ...publicRecord,
      topThree: Object.freeze(topTen.slice(0, 3)),
      integrityDigest, // checksum, NOT signature or server authentication
    }));
  }
  history.sort((a, b) => a.endedAtMs - b.endedAtMs ||
      a.weekId.localeCompare(b.weekId, "en"));
  for (let i = 1; i < history.length; i++) {
    if (history[i].startedAtMs < history[i - 1].endedAtMs) {
      block("overlapping_week_windows");
    }
  }
  return Object.freeze({
    monthId,
    status: monthCompleted(monthId, serverNowMs) ? "closed" : "collecting",
    weeks: Object.freeze(history),
    verifiedProduction: false,
    shadowOnly: true,
    readOnly: true,
    grantsDiamonds: false,
    adminAccessValidated: false,
    note: "prototype_monthly_weekly_top_ten_history_only",
  });
}

module.exports = Object.freeze({
  projectShadowMonthlyTopTen, monthOfBaghdadInstant,
});
