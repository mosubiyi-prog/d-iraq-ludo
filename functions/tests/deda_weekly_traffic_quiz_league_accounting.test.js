"use strict";

/** Read-only shadow-score contract; NO real user/task/XP/diamond writes. */
const test = require("node:test");
const assert = require("node:assert/strict");
const {XP_PER_TASK_CLAIM,previewWeeklyLevelXp} =
  require("../deda_weekly_level_xp_shadow_policy.js");

const DAY = "2026-10-27";
const START = Date.UTC(2026,9,26,21); // Iraq 2026-10-27 00:00
const week = {weekId:"server-qa-league",startMs:START,endMs:START+7*86400000};
const ACCOUNT="07712345678";
const XP_BEFORE=460;
const POINTS_BEFORE=125;

function taskClaim(accountKey=ACCOUNT,taskId="traffic_skills",verifiedAtMs=START+5000) {
  return {
    fixtureSource:"stage5_emulator_only",verifiedByServer:true,
    eventType:"task_claim",taskPointsAwarded:true,
    levelXpApplied:true,weekId:week.weekId,
    accountKey,taskId,verifiedAtMs,iraqDay:DAY,
  };
}

function rank(input) {
  return previewWeeklyLevelXp(week,input);
}

test("5 correct traffic answers only affect preexisting NORMAL points",()=>{
  const correct=5;
  const normalAfter=POINTS_BEFORE+5*correct;
  const xpAfter=XP_BEFORE;
  assert.equal(normalAfter,150);
  assert.equal(xpAfter,XP_BEFORE);
  assert.equal(rank([]).ranks.length,0);
  // Reader of weekly XP must NOT use the ordinary current points total.
  for(let i=0;i<correct;i++){
    assert.throws(()=>rank([{...taskClaim(),
      eventType:"traffic_answer",questionId:"q_"+i}]),/not_task_claim/);
  }
});

test("quiz completion without task CLAIM does not add any league XP",()=>{
  assert.throws(()=>rank([{
    ...taskClaim(),eventType:"traffic_quiz_completed",
  }]),/not_task_claim/);
  assert.equal(rank([]).uniqueTaskClaims,0);
});

test("one claimed traffic daily TASK yields exactly 20 weekly LEVEL XP",()=>{
  assert.equal(XP_PER_TASK_CLAIM,20);
  const result=rank([taskClaim()]);
  assert.equal(result.uniqueTaskClaims,1);
  assert.equal(result.ranks.length,1);
  assert.equal(result.ranks[0].weeklyPoints,20);
  assert.equal(result.ranks[0].verifiedTaskCompletions,1);
  assert.equal(result.scoreUnit,
    "level_xp_earned_from_verified_weekly_task_claims");
  // Existing total levels/ordinary points never enter league computation.
  assert.equal(XP_BEFORE,460);
  assert.equal(POINTS_BEFORE,125);
});

test("multiple correct answers, a reopened page, and two phones cannot mint extra XP",()=>{
  const claim=taskClaim();
  const result=rank([claim,{...claim},{...claim}]);
  assert.equal(result.ranks[0].weeklyPoints,20);
  assert.equal(result.uniqueTaskClaims,1);
});

test("successful 5-point ordinary task credit without 20 XP does not affect league",()=>{
  assert.throws(()=>rank([{...taskClaim(),levelXpApplied:false}]),
    /xp_not_applied/);
  assert.throws(()=>rank([{...taskClaim(),taskPointsAwarded:false}]),
    /ordinary_task_not_claimed/);
});

test("second different completed mission adds 20 XP without changing lifetime balances",()=>{
  const result=rank([taskClaim(),taskClaim(ACCOUNT,"open_map",START+8000)]);
  assert.equal(result.ranks[0].weeklyPoints,40);
  assert.equal(result.ranks[0].verifiedTaskCompletions,2);
  assert.equal(POINTS_BEFORE,125);
  assert.equal(XP_BEFORE,460);
});

test("another account, another day and another week cannot mix their earnings",()=>{
  const result=rank([taskClaim(),taskClaim("07799998888","traffic_skills")]);
  assert.equal(result.ranks.length,2);
  assert.equal(result.ranks[0].weeklyPoints,20);
  assert.equal(result.ranks[1].weeklyPoints,20);
  assert.throws(()=>rank([{...taskClaim(),weekId:"another_week"}]),/week_mismatch/);
  assert.throws(()=>rank([{...taskClaim(),iraqDay:"2026-10-28"}]),
    /client_day_mismatch/);
});

test("no league source accepts hand-entered 5-point quiz rewards as XP or wallet money",()=>{
  for(const extra of [
    {clientXp:999999},{clientPoints:25},{walletBalance:200},
    {adminBonus:1000000},{diamonds:10},{trafficAnswerPoints:5},
  ]){
    assert.throws(()=>rank([{...taskClaim(),...extra}]),/untrusted_/);
  }
});
