"use strict";

/**
 * DEDA STAGE 3: UNDEPLOYED, IN-MEMORY, SERVER-SIDE POLICY CONTRACT ONLY.
 *
 * NOT imported/exported by functions/index.js; no Firestore, Auth, wallet,
 * scheduler, Cloud Functions, device/local points, permissions or network I/O.
 * A verified fixture below is NOT real proof of task completion.
 * DO NOT call these functions directly on user-supplied data or use output
 * for a real diamond grant. Real authoritative receipt verification, cross-
 * device account resolution, backend wallet transactions, rules and audits
 * are separate, currently UNIMPLEMENTED security gates.
 */

const WEEK_MS = 7 * 24 * 60 * 60 * 1000;
const EVENT_POINTS = Object.freeze({
  task_claim: 5,
  daily_login: 10,
  traffic_answer: 5,
});
const PRIZE_DIAMONDS = Object.freeze([150, 100, 50, 10, 10, 10, 10, 10, 10, 10]);
const MAX_RECEIPTS_PER_WEEK = 50000;

function fail(message) {
  throw new Error("DEDA_WEEKLY_SHADOW_" + message);
}
function requireText(value, label, pattern = /^[A-Za-z0-9_-]{1,160}$/) {
  if (typeof value !== "string" || !pattern.test(value)) fail(label);
  return value;
}
function requireInteger(n, label) {
  if (!Number.isSafeInteger(n)) fail(label);
  return n;
}

function iraqDayOfServerInstant(milliseconds) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Baghdad",
    year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(new Date(milliseconds));
  const fields = Object.fromEntries(parts.map((p) => [p.type, p.value]));
  return fields.year + "-" + fields.month + "-" + fields.day;
}

/**
 * Server-configured seven-day epoch bounds. No fixed start weekday and no
 * client-provided clock; a server-defined Iraq timezone resolver must supply
 * canonical instants in a future production implementation.
 */
function verifiedWeek(config) {
  if (!config || typeof config !== "object") fail("week_missing");
  const weekId = requireText(config.weekId, "week_id", /^[A-Za-z0-9_-]{1,80}$/);
  const startMs = requireInteger(config.startMs, "week_start");
  const endMs = requireInteger(config.endMs, "week_end");
  if (startMs < 0 || endMs - startMs !== WEEK_MS) fail("week_duration");
  return Object.freeze({weekId, startMs, endMs});
}

/**
 * Trusted fixture shape for POLICY TESTS ONLY:
 * accountKey is resolved by a future server-owned DEDA session-to-account
 * mapping, NOT the current device's phone, public ID or a mutable Firebase UID.
 * confirmedByServer and provenance below can be forged in raw JSON. Never
 * treat their presence as real authorization. Actual backend adapter required.
 */
function validateFixtureReceipt(week, receipt) {
  if (!receipt || typeof receipt !== "object" || Array.isArray(receipt)) {
    fail("receipt_shape");
  }
  if (receipt.provenance !== "stage3_emulator_fixture_only" ||
      receipt.confirmedByServer !== true) fail("unverified_receipt");
  if ("clientPoints" in receipt || "deviceClockMs" in receipt ||
      "adminBonus" in receipt || "diamondBalance" in receipt ||
      "spentPoints" in receipt) fail("client_financial_field");
  const accountKey = requireText(receipt.accountKey, "account_key");
  const eventType = receipt.eventType;
  if (!Object.prototype.hasOwnProperty.call(EVENT_POINTS, eventType)) {
    fail("ineligible_event");
  }
  if (receipt.weekId !== week.weekId) fail("mixed_week");
  const verifiedAtMs = requireInteger(receipt.verifiedAtMs, "server_event_time");
  if (verifiedAtMs < week.startMs || verifiedAtMs >= week.endMs) {
    fail("event_outside_week");
  }
  const iraqDay = requireText(receipt.iraqDay, "iraq_day",
      /^20\d{2}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])$/);
  if (iraqDay !== iraqDayOfServerInstant(verifiedAtMs)) {
    fail("client_day_mismatch");
  }

  // For one server Iraq day: one login; one credit per task ID; one credit per
  // correct question ID. Different phones yield the SAME protected event key.
  let target = "";
  if (eventType === "task_claim") {
    target = requireText(receipt.taskId, "task_id");
  } else if (eventType === "traffic_answer") {
    target = requireText(receipt.questionId, "question_id");
  } else {
    if (receipt.taskId != null || receipt.questionId != null) {
      fail("unexpected_login_subject");
    }
    target = "login";
  }
  // The actual backend must prove each task and correct traffic answer. This
  // stage only models already-server-verified event receipts with test input.
  return Object.freeze({
    accountKey,
    eventType,
    verifiedAtMs,
    verifiedDay: iraqDay,
    dedupeKey: [accountKey, iraqDay, eventType, target].join("|"),
    points: EVENT_POINTS[eventType],
    isTaskCompletion: eventType === "task_claim",
  });
}

function previewWeeklyRanking(weekConfig, serverVerifiedFixtures) {
  const week = verifiedWeek(weekConfig);
  if (!Array.isArray(serverVerifiedFixtures) ||
      serverVerifiedFixtures.length > MAX_RECEIPTS_PER_WEEK) {
    fail("invalid_receipt_set");
  }
  const dedupe = new Set();
  const totals = new Map();
  const sorted = serverVerifiedFixtures
      .map((receipt) => validateFixtureReceipt(week, receipt))
      .sort((a, b) => a.verifiedAtMs - b.verifiedAtMs ||
          a.dedupeKey.localeCompare(b.dedupeKey, "en"));

  for (const receipt of sorted) {
    if (dedupe.has(receipt.dedupeKey)) continue;
    dedupe.add(receipt.dedupeKey);
    const existing = totals.get(receipt.accountKey) || {
      accountKey: receipt.accountKey,
      weeklyPoints: 0,
      verifiedTaskCompletions: 0,
      lastReachedAtMs: 0,
    };
    existing.weeklyPoints += receipt.points;
    if (receipt.isTaskCompletion) existing.verifiedTaskCompletions++;
    if (!Number.isSafeInteger(existing.weeklyPoints)) fail("score_overflow");
    existing.lastReachedAtMs = Math.max(
        existing.lastReachedAtMs, receipt.verifiedAtMs);
    totals.set(receipt.accountKey, existing);
  }

  const sortedUsers = [...totals.values()].sort((a, b) =>
      b.weeklyPoints - a.weeklyPoints ||
      b.verifiedTaskCompletions - a.verifiedTaskCompletions ||
      a.lastReachedAtMs - b.lastReachedAtMs ||
      a.accountKey.localeCompare(b.accountKey, "en"));
  const ranks = sortedUsers.map((row, i) => Object.freeze({
    place: i + 1,
    accountKey: row.accountKey,
    weeklyPoints: row.weeklyPoints,
    verifiedTaskCompletions: row.verifiedTaskCompletions,
    lastReachedAtMs: row.lastReachedAtMs,
    prizeDiamondsIfFinalWinner: PRIZE_DIAMONDS[i] || 0,
  }));
  return Object.freeze({
    weekId: week.weekId,
    ranks: Object.freeze(ranks),
    uniqueApprovedReceipts: dedupe.size,
  });
}

/**
 * PREVIEW ONLY, never disburse. Idempotence in this in-memory preview is not
 * durable transaction security. A future writer must atomically check/create
 * a unique week+canonical-account ledger entry and update the EXISTING
 * verified ordinary diamond wallet exactly once from privileged backend.
 */
function previewClosedWeekPrizePlan(
    weekConfig, standings, trustedServerNowMs, alreadyCreditedKeys = []) {
  const week = verifiedWeek(weekConfig);
  const now = requireInteger(trustedServerNowMs, "trusted_now");
  if (now < week.endMs) fail("week_not_complete");
  if (!standings || standings.weekId !== week.weekId ||
      !Array.isArray(standings.ranks)) fail("ranking_week_mismatch");
  if (!Array.isArray(alreadyCreditedKeys)) fail("existing_grants_shape");
  const already = new Set(alreadyCreditedKeys.map(
      (x) => requireText(x, "existing_grant_key", /^[A-Za-z0-9_-]{1,80}:[A-Za-z0-9_-]{1,160}$/)));
  const eligible = standings.ranks.filter(
      (r) => Number.isInteger(r.place) && r.place >= 1 && r.place <= 10);
  if (new Set(eligible.map((r) => r.accountKey)).size !== eligible.length) {
    fail("duplicate_winning_account");
  }
  if (eligible.some((r) => r.prizeDiamondsIfFinalWinner !==
      PRIZE_DIAMONDS[r.place - 1])) fail("invalid_prize_amount");

  const proposals = eligible.map((row) => Object.freeze({
    proposalKey: week.weekId + ":" + row.accountKey,
    accountKey: row.accountKey,
    place: row.place,
    diamonds: PRIZE_DIAMONDS[row.place - 1],
  })).filter((proposal) => !already.has(proposal.proposalKey));
  return Object.freeze({
    weekId: week.weekId,
    proposals: Object.freeze(proposals),
    previewOnly: true,
    creditedDiamonds: 0,
    proposedDiamonds: proposals.reduce((n, p) => n + p.diamonds, 0),
  });
}

module.exports = Object.freeze({
  WEEK_MS, PRIZE_DIAMONDS, EVENT_POINTS, verifiedWeek,
  previewWeeklyRanking, previewClosedWeekPrizePlan,
});
