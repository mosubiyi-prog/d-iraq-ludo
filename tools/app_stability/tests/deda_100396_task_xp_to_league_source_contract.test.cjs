"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const root = path.resolve(__dirname, "../../..");
const app = fs.readFileSync(path.join(root, "lib/main.dart"), "utf8");
const slots = fs.readFileSync(path.join(root, "lib/deda_daily_task_slots.dart"), "utf8");
const stage28 = fs.readFileSync(path.join(root,
  "tools/app_stability/app_package/bind_weekly_tasks_cta_stage28.py"), "utf8");
const policy = require("../../../functions/deda_weekly_original_eight_task_source_gate_NOT_EXPORTED.js");
const score = require("../../../functions/deda_weekly_canonical_daily_xp_top10_NOT_EXPORTED.js");

test("100396 original eight task IDs and order equal server allowlist exactly", () => {
  const section = app.match(/class DedaTaskIds \{([\s\S]*?)\n\}/);
  assert.ok(section, "Missing original DedaTaskIds");
  const declarations = [...section[1].matchAll(
    /static const String (\w+) = '([a-z_]+)';/g)];
  assert.equal(declarations.length, 8);
  const array = section[1].match(
    /static const List<String> weekly = <String>\[([\s\S]*?)\];/);
  assert.ok(array, "Original weekly ID list missing");
  const orderedNames = array[1].split(",").map(s => s.trim()).filter(Boolean);
  assert.equal(orderedNames.length, 8);
  const lookup = new Map(declarations.map(m => [m[1], m[2]]));
  const originals = orderedNames.map(name => {
    assert.ok(lookup.has(name), "Unrecognized 100396 original task constant");
    return lookup.get(name);
  });
  assert.deepEqual(policy.TASK_IDS, originals);
  for (const id of originals) {
    assert.ok(slots.includes("id: '" + id + "'"), "Missing slot " + id);
    assert.equal(policy.allowlistedTaskId(id), true);
  }
});
test("100396 preserves ordinary 5 task points and private XP contract 20", () => {
  assert.ok(app.includes("static const int pointsPerTask = 5;"));
  assert.ok(app.includes("static const int pointsPerDailyLogin = 10;"));
  assert.ok(app.includes("static const int generalManagerBonusPoints = 1000000;"));
  assert.equal(policy.ORIGINAL_TASK_POINTS, 5);
  assert.equal(policy.ORIGINAL_LEVEL_XP_PER_TASK, 20);
  const receipt = policy.originalTaskReceiptShape({
    accountKey: "07701234567", dayId: "2026-10-30",
    taskId: "open_map",
  });
  assert.deepEqual(receipt.delta, {
    points: 5, coins: 10, xp: 20, earnedDiamonds: 0,
  });
  assert.equal(receipt.source, "task-claim-v1");
  assert.equal(score.PROJECT, "demo-deda-restore-readiness");
});
test("source remains completely nonproduction and never uses local balances", () => {
  const report = policy.privateCoverageSummary();
  assert.equal(report.expectedOriginalTaskIds, 8);
  assert.equal(report.productionVerifiedProducerCount, 0);
  assert.equal(report.readyForActualWeeklyStandings, false);
  assert.equal(report.readyForRealPrizes, false);
  assert.equal(report.rows.every(row => !row.canAwardUserXp &&
    !row.canAddDiamonds && !row.canRankProductionUsers), true);
  const source = fs.readFileSync(path.join(root,
    "functions/deda_weekly_canonical_daily_xp_top10_NOT_EXPORTED.js"), "utf8");
  assert.ok(source.includes('DEDA_CANONICAL_LEAGUE_EMULATOR_ONLY'));
  assert.ok(!source.includes("SharedPreferences"));
  assert.ok(!source.includes("functions/index.js"));
});
test("original 100396 signed package builder and two league home routes unchanged", () => {
  assert.ok(stage28.includes("VERSION = 100396"));
  assert.ok(stage28.includes("DedaWeeklyLeaderboardSafeScreen("));
  assert.ok(stage28.includes("DedaLeaderboardHomeCard("));
  assert.ok(stage28.includes("if (code.count(ORIGINAL_ROUTE) != 2"));
  assert.ok(stage28.includes("if {p for p,h in previous.items()"));
  assert.ok(stage28.includes("stage28"));
});
test("no new real score source from copying a local checkbox or manager bonus", () => {
  assert.equal(policy.allowlistedTaskId("daily_login"), false);
  assert.equal(policy.allowlistedTaskId("admin_bonus"), false);
  assert.equal(policy.allowlistedTaskId("foo"), false);
  assert.throws(() => policy.originalTaskReceiptShape({
    accountKey: "07701234567", dayId: "2026-10-30",
    taskId: "admin_bonus",
  }));
});
