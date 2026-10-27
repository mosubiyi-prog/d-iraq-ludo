"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  WEEK_MS, PRIZE_DIAMONDS, EVENT_POINTS,
  verifiedWeek, previewWeeklyRanking, previewClosedWeekPrizePlan,
} = require("../deda_weekly_leaderboard_shadow_policy.js");

const START = Date.UTC(2026, 9, 27, 0);
const END = START + WEEK_MS;
const week = Object.freeze({weekId: "server-week-a", startMs: START, endMs: END});
const weekB = Object.freeze({weekId: "server-week-b", startMs: END, endMs: END + WEEK_MS});

function receipt(accountKey, eventType, subject, instant = START + 1000, cfg = week) {
  const dateParts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Baghdad", year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(new Date(instant));
  const byName = Object.fromEntries(dateParts.map((p) => [p.type, p.value]));
  const day = byName.year + "-" + byName.month + "-" + byName.day;
  return {
    accountKey, eventType, weekId: cfg.weekId, verifiedAtMs: instant,
    iraqDay: day, provenance: "stage3_emulator_fixture_only",
    confirmedByServer: true,
    ...(eventType === "task_claim" ? {taskId: subject} : {}),
    ...(eventType === "traffic_answer" ? {questionId: subject} : {}),
  };
}

test("stage3 strictly models seven-day authoritative week bounds, no fixed weekday", () => {
  assert.deepEqual(verifiedWeek(week), week);
  assert.equal(verifiedWeek(weekB).startMs, END);
  assert.equal(EVENT_POINTS.task_claim, 5);
  assert.equal(EVENT_POINTS.daily_login, 10);
  assert.equal(EVENT_POINTS.traffic_answer, 5);
  assert.equal(PRIZE_DIAMONDS.reduce((a,b)=>a+b, 0), 370);
  assert.throws(() => verifiedWeek({...week, endMs: END - 1}),
    /week_duration/);
  assert.throws(() => verifiedWeek({...week, weekId: " a "}),
    /week_id/);
});

test("one new task point can overtake: no inactivity penalty", () => {
  const base = [
    receipt("leader", "daily_login"),
    receipt("challenger", "task_claim", "shared_location"),
  ];
  const first = previewWeeklyRanking(week, base);
  assert.deepEqual(first.ranks.map(x => [x.accountKey, x.weeklyPoints]),
    [["leader", 10], ["challenger", 5]]);
  const next = previewWeeklyRanking(week, [
    ...base, receipt("challenger", "traffic_answer", "correct-q-a", START + 4000),
    receipt("challenger", "task_claim", "open_map", START + 5000),
  ]);
  assert.equal(next.ranks[0].accountKey, "challenger");
  assert.equal(next.ranks[0].weeklyPoints, 15);
  assert.equal(next.ranks[1].weeklyPoints, 10);
  // Across DEDA real 5-point events, a one-point delta may arise from other
  // trusted level/XP sources; ordering is numeric and not locked to winner.
  const trusted = previewWeeklyRanking(week, [
    receipt("leader", "task_claim", "t1"),
    receipt("challenger", "daily_login"),
  ]);
  assert.equal(trusted.ranks[0].accountKey, "challenger");
});

test("replayed duplicate receipts from TWO devices count once per account and day", () => {
  const a = receipt("account-key-1", "task_claim", "search_map");
  const b = receipt("account-key-1", "daily_login", null);
  const answer = receipt("account-key-1", "traffic_answer", "q-001");
  const view = previewWeeklyRanking(week, [
    a, {...a}, b, {...b}, answer, {...answer},
  ]);
  assert.equal(view.uniqueApprovedReceipts, 3);
  assert.equal(view.ranks.length, 1);
  assert.equal(view.ranks[0].weeklyPoints, 20);
  assert.equal(view.ranks[0].verifiedTaskCompletions, 1);
});

test("not counted: general-manager bonus, point-tier refunds or client XP", () => {
  const allowed = [receipt("gmanager", "task_claim", "open_map")];
  assert.equal(previewWeeklyRanking(week, allowed).ranks[0].weeklyPoints, 5);
  assert.throws(() => previewWeeklyRanking(week, [
    {...allowed[0], adminBonus: 1000000},
  ]), /client_financial_field/);
  assert.throws(() => previewWeeklyRanking(week, [
    {...allowed[0], eventType: "point_tier_claim"},
  ]), /ineligible_event/);
  assert.throws(() => previewWeeklyRanking(week, [
    {...allowed[0], clientPoints: 10000},
  ]), /client_financial_field/);
  assert.throws(() => previewWeeklyRanking(week, [
    {...allowed[0], confirmedByServer: false},
  ]), /unverified_receipt/);
});

test("Iraq local day must match trusted event instant, not phone date", () => {
  const atNight = Date.UTC(2026, 9, 27, 22, 30);
  assert.equal(receipt("a", "daily_login", null, atNight).iraqDay, "2026-10-28");
  assert.throws(() => previewWeeklyRanking(week, [
    {...receipt("a", "daily_login", null, atNight), iraqDay: "2026-10-27"},
  ]), /client_day_mismatch/);
  assert.throws(() => previewWeeklyRanking(week, [
    receipt("a", "daily_login", null, END),
  ]), /event_outside_week/);
});

test("weekly points isolated; user's historical total or level not a score input", () => {
  const thisWeek = previewWeeklyRanking(week, [
    receipt("new", "daily_login"),
    receipt("old", "task_claim", "open_map"),
  ]);
  const later = previewWeeklyRanking(weekB, [
    receipt("old", "daily_login", null, END + 5000, weekB),
    receipt("new", "task_claim", "open_map", END + 5000, weekB),
  ]);
  assert.equal(thisWeek.ranks[0].accountKey, "new");
  assert.equal(later.ranks[0].accountKey, "old");
  assert.equal(thisWeek.ranks[0].weeklyPoints, 10);
  assert.equal(later.ranks[0].weeklyPoints, 10);
  assert.throws(() => previewWeeklyRanking(week,
    [receipt("a", "daily_login", null, END + 1, weekB)]), /mixed_week/);
});

test("tie-breaks use task count, then authoritative time then canonical account", () => {
  const inputs = [
    receipt("z", "traffic_answer", "q3", START + 3000),
    receipt("b", "task_claim", "t1", START + 2000),
    receipt("a", "task_claim", "t1", START + 1000),
    receipt("c", "task_claim", "t1", START + 1000),
  ];
  const rows = previewWeeklyRanking(week, inputs).ranks;
  assert.deepEqual(rows.map(x=>x.accountKey), ["a", "c", "b", "z"]);
});

test("top ten 370-diamond shadow plan; 11th receives nothing", () => {
  const receipts = Array.from({length:12}, (_, i) =>
    receipt("user" + (i+1), "task_claim", "event_" + (i+1),
      START + i * 1000));
  const result = previewWeeklyRanking(week, receipts);
  assert.equal(result.ranks.length, 12);
  assert.equal(result.ranks[10].prizeDiamondsIfFinalWinner, 0);
  const proposal = previewClosedWeekPrizePlan(week, result, END);
  assert.equal(proposal.proposals.length, 10);
  assert.equal(proposal.proposedDiamonds, 370);
  assert.equal(proposal.creditedDiamonds, 0);
  assert.equal(proposal.previewOnly, true);
  assert.deepEqual(proposal.proposals.map(x=>x.diamonds), PRIZE_DIAMONDS);
  assert.ok(proposal.proposals.every(x=>x.proposalKey.startsWith("server-week-a:")));
});

test("never grant early; preview dedupes already-paid grant IDs but never writes", () => {
  const ranks = previewWeeklyRanking(week, [receipt("x", "daily_login", null)]);
  assert.throws(
    () => previewClosedWeekPrizePlan(week, ranks, END - 1),
    /week_not_complete/);
  const first = previewClosedWeekPrizePlan(week, ranks, END);
  assert.equal(first.proposedDiamonds, 150);
  const simulatedRetry = previewClosedWeekPrizePlan(
    week, ranks, END + 10000, [first.proposals[0].proposalKey]);
  assert.equal(simulatedRetry.proposals.length, 0);
  assert.equal(simulatedRetry.creditedDiamonds, 0);
  assert.equal(first.proposals[0].proposalKey, "server-week-a:x");
});

test("reject any bogus client-clock, nil account, duplicate sources outside week", () => {
  const a = receipt("a", "task_claim", "new_place");
  assert.throws(() => previewWeeklyRanking(week,
    [{...a, deviceClockMs: START}]), /client_financial_field/);
  assert.throws(() => previewWeeklyRanking(week,
    [{...a, accountKey: ""}]), /account_key/);
  assert.throws(() => previewWeeklyRanking(week,
    [{...a, provenance: "device_claim"}]), /unverified_receipt/);
  assert.throws(() => previewWeeklyRanking(week, "not-array"), /invalid_receipt_set/);
});
