"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  XP_PER_TASK_CLAIM, previewWeeklyLevelXp, previewEndedWeekPrizes,
} = require("../deda_weekly_level_xp_shadow_policy.js");
const START = Date.UTC(2026, 9, 27, 0);
const WEEK = 7 * 86400000;
const week = {weekId: "week-proven-xp", startMs: START, endMs: START + WEEK};

function dateIraq(when) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone:"Asia/Baghdad", year:"numeric", month:"2-digit", day:"2-digit",
  }).formatToParts(new Date(when));
  const p=Object.fromEntries(parts.map(x=>[x.type,x.value]));
  return p.year+"-"+p.month+"-"+p.day;
}
function receipt(accountKey, taskId, verifiedAtMs = START+5000) {
  return {
    fixtureSource:"stage5_emulator_only",
    verifiedByServer:true, eventType:"task_claim",
    taskPointsAwarded:true, levelXpApplied:true,
    weekId:week.weekId, accountKey, taskId, verifiedAtMs,
    iraqDay:dateIraq(verifiedAtMs),
  };
}

test("original 100387 grants 20 LEVEL XP on claimed task, distinct from normal 5", () => {
  assert.equal(XP_PER_TASK_CLAIM,20);
  const r=previewWeeklyLevelXp(week,[receipt("07711111111","map")]);
  assert.equal(r.ranks.length,1);
  assert.equal(r.ranks[0].weeklyPoints,20);
  assert.equal(r.scoreUnit,"level_xp_earned_from_verified_weekly_task_claims");
  assert.equal(r.shadowOnly,true);
});

test("task completion without successful separate XP write cannot rank", () => {
  const r = receipt("07711111111","map");
  assert.throws(() => previewWeeklyLevelXp(week, [
    {...r, levelXpApplied: false},
  ]), /xp_not_applied/);
  assert.throws(() => previewWeeklyLevelXp(week, [
    {...r, taskPointsAwarded: false},
  ]), /ordinary_task_not_claimed/);
});

test("daily login normal points or each correct answer do NOT become level XP", () => {
  for (const type of ["daily_login","traffic_answer","point_tier_claim","admin_bonus"]) {
    assert.throws(()=>previewWeeklyLevelXp(week,[
      {...receipt("07711111111","task"),eventType:type},
    ]),/not_task_claim/);
  }
  assert.equal(previewWeeklyLevelXp(week,[]).ranks.length,0);
});

test("duplicate claim on second phone is counted once for same canonical account", () => {
  const r=receipt("07711111111","share_location");
  const v=previewWeeklyLevelXp(week,[r,{...r},{...r}]);
  assert.equal(v.uniqueTaskClaims,1);
  assert.equal(v.ranks[0].weeklyPoints,20);
});

test("twenty XP updates standings dynamically when previous leader stops", () => {
  const a="07711111111",b="07722222222";
  const before=previewWeeklyLevelXp(week,[
    receipt(a,"task1",START+1000),
    receipt(a,"task2",START+2000),
    receipt(b,"task1",START+3000),
  ]);
  assert.equal(before.ranks[0].accountKey,a);
  const after=previewWeeklyLevelXp(week,[
    receipt(a,"task1",START+1000),
    receipt(a,"task2",START+2000),
    receipt(b,"task1",START+3000),
    receipt(b,"task2",START+4000),
    receipt(b,"task3",START+5000),
  ]);
  assert.equal(after.ranks[0].accountKey,b);
  assert.equal(after.ranks[0].weeklyPoints,60);
  assert.equal(after.ranks[1].weeklyPoints,40);
});

test("protect weekly reset and server clock, never use client phone timestamps", () => {
  const account="07711111111";
  const one=receipt(account,"task");
  assert.throws(()=>previewWeeklyLevelXp(week,[{...one,deviceTimeMs:START}]),
    /untrusted_deviceTimeMs/);
  assert.throws(()=>previewWeeklyLevelXp(week,[{...one,iraqDay:"2026-10-28"}]),
    /client_day_mismatch/);
  assert.throws(()=>previewWeeklyLevelXp(week,[{...one,verifiedAtMs:week.endMs}]),
    /outside_week/);
  assert.throws(()=>previewWeeklyLevelXp(week,[{...one,weekId:"week-future"}]),
    /week_mismatch/);
});

test("admin bonus, user-editable totals and untrusted receipts cannot win", () => {
  const normal=receipt("07711111111","task");
  for (const field of ["adminBonus","clientXp","level","clientPoints",
    "walletBalance","publicId","uid","loginPoints","diamonds"]) {
    assert.throws(()=>previewWeeklyLevelXp(week,[{...normal,[field]:1000000}]),
      new RegExp("untrusted_"+field));
  }
  assert.throws(()=>previewWeeklyLevelXp(week,[{...normal,verifiedByServer:false}]),
    /unverified/);
});

test("300? no; exactly 370 diamond proposals for ten winners, zero disbursement", () => {
  const events=Array.from({length:12},(_,i)=>receipt(
    "077"+String(i+1).padStart(8,"0"),"map",START+i*1000));
  const leaderboard=previewWeeklyLevelXp(week,events);
  assert.equal(leaderboard.ranks.length,12);
  assert.equal(leaderboard.ranks[10].prizeDiamondsIfFinalWinner,0);
  assert.throws(()=>previewEndedWeekPrizes(week,leaderboard,week.endMs-1),
    /week_not_complete/);
  const plan=previewEndedWeekPrizes(week,leaderboard,week.endMs);
  assert.equal(plan.proposals.length,10);
  assert.equal(plan.proposedDiamonds,370);
  assert.equal(plan.creditedDiamonds,0);
  assert.equal(plan.previewOnly,true);
  const retry=previewEndedWeekPrizes(week,leaderboard,week.endMs+1000,
    plan.proposals.map(x=>x.proposalKey));
  assert.equal(retry.proposedDiamonds,0);
  assert.equal(retry.creditedDiamonds,0);
});

test("account-specific identity survives client UID and public ID rotations", () => {
  // The fixture intentionally requires ONLY the server-mapped immutable
  // account key; uid and changeable publicId are rejected.
  const claims=[
    receipt("07711111111","a",START+1000),
    receipt("07711111111","b",START+2000),
  ];
  const r=previewWeeklyLevelXp(week,claims);
  assert.equal(r.ranks.length,1);
  assert.equal(r.ranks[0].weeklyPoints,40);
  assert.throws(()=>previewWeeklyLevelXp(week,[{
    ...claims[0],uid:"untrusted-new-device-uid",
  }]),/untrusted_uid/);
});
