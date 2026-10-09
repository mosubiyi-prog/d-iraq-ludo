"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const policy = require("../../functions/deda_social_task_stage2.js");

const manager = {uid: "gm-test", role: "general_manager",
  active: true, serverVerified: true};
const now = new Date("2026-10-09T14:00:00Z");
const draft = {
  platform: "telegram", action: "follow",
  title: "تابع قناة DEDA الرسمية", url: "https://t.me/DEDA_Iraq",
  rewardUnit: "diamonds", rewardAmount: 10,
  doubleWithRewardedAd: true,
};
test("all six approved platforms and three reward currencies", () => {
  assert.deepEqual(policy.PLATFORMS, [
    "facebook","telegram","youtube","instagram","tiktok","other"]);
  assert.deepEqual(policy.UNITS, ["points","coins","diamonds"]);
  for (const unit of policy.UNITS) {
    assert.deepEqual(policy.previewReward({
      amount: 10, unit, doubleWithRewardedAd: true,
    }), {
      base: 10, unit, bonusIfVerifiedAd: 10, potentialTotal: 20,
      payable: false,
    });
  }
});
test("Iraq midnight boundary uses trusted server time", () => {
  assert.equal(policy.iraqMidnightUtc("2026-10-10").toISOString(),
      "2026-10-09T21:00:00.000Z");
  assert.equal(policy.dayId(new Date("2026-10-09T20:59:59Z")),
      "2026-10-09");
  assert.equal(policy.dayId(new Date("2026-10-09T21:00:00Z")),
      "2026-10-10");
  assert.equal(policy.validDay("2026-02-30"), false);
});
test("social URL is valid only for selected platform and HTTPS", () => {
  assert.equal(policy.safeUrl("https://t.me/DEDA_Iraq","telegram"),true);
  assert.equal(policy.safeUrl("https://t.me.evil.com/DEDA_Iraq","telegram"),false);
  assert.equal(policy.safeUrl("https://youtube.com/watch?v=x","youtube"),true);
  assert.equal(policy.safeUrl("https://fb.com/post","telegram"),false);
  assert.equal(policy.safeUrl("http://t.me/channel","telegram"),false);
  assert.equal(policy.safeUrl("https://evil.com@t.me/channel","telegram"),false);
  assert.equal(policy.safeUrl("https://127.0.0.1/foo","other"),false);
});
test("general manager is server-verified or operation is rejected", () => {
  assert.throws(() => policy.saveDraft({
    draft, actor: {...manager, serverVerified: false}, now,
  }),/general-manager-server-verification-required/);
  assert.throws(() => policy.saveDraft({
    draft, actor: {...manager, role: "employee"}, now,
  }),/general-manager-server-verification-required/);
});
test("draft is editable but scheduled and published configs are immutable", () => {
  const saved = policy.saveDraft({draft, actor: manager, now});
  assert.equal(saved.status,"draft");
  assert.equal(saved.rewardsEnabled,false);
  assert.equal(saved.revision,1);
  const scheduled = policy.scheduleDraft({
    draft: saved, day: "2026-10-10", actor: manager, now,
  });
  assert.equal(scheduled.status, "scheduled");
  assert.equal(scheduled.effectiveAtUtc, "2026-10-09T21:00:00.000Z");
  assert.throws(() => policy.saveDraft({
    previous: scheduled, draft, actor: manager, now,
  }),/scheduled-or-published-cannot-be-edited/);
});
test("no backdated schedule, cancellation only before effective time", () => {
  const saved = policy.saveDraft({draft, actor: manager, now});
  assert.throws(() => policy.scheduleDraft({
    draft: saved, day: "2026-10-09", actor: manager, now,
  }),/future-iraq-day-required/);
  const scheduled = policy.scheduleDraft({
    draft: saved, day: "2026-10-10", actor: manager, now,
  });
  const cancelled = policy.cancelSchedule({
    task: scheduled, actor: manager,
    now: new Date("2026-10-09T20:59:59Z"),
  });
  assert.equal(cancelled.status,"cancelled");
  assert.equal(cancelled.rewardsEnabled,false);
  assert.throws(() => policy.cancelSchedule({
    task: scheduled, actor: manager,
    now: new Date("2026-10-09T21:00:00Z"),
  }),/too-late-to-cancel/);
  assert.equal(policy.publishDueConfig({
    task: cancelled, now: new Date("2026-10-09T21:00:01Z"),
  }).outcome,"not-scheduled");
});
test("publication at due time is config-only, with no claim or repeat", () => {
  const saved=policy.saveDraft({draft,actor:manager,now});
  const scheduled=policy.scheduleDraft({
    draft:saved,day:"2026-10-10",actor:manager,now});
  const before=policy.publishDueConfig({
    task:scheduled,now:new Date("2026-10-09T20:59:59Z")});
  assert.equal(before.outcome,"not-due");
  const at=policy.publishDueConfig({
    task:scheduled,now:new Date("2026-10-09T21:00:00Z")});
  assert.equal(at.outcome,"published-config-only");
  assert.equal(at.task.rewardsEnabled,false);
  assert.equal(policy.publishDueConfig({
    task:at.task,now:new Date("2026-10-09T21:00:01Z"),
  }).outcome,"not-scheduled");
  assert.equal(policy.rewardDecision({
    task:at.task,completionProof:{serverVerified:true,
      source:"trusted-platform-verifier"},ledgerEntries:new Set(),
  }).outcome,"rewards-disabled");
});
test("even a forged verified completion and ad flag cannot pay without ledger",()=>{
  const suspicious={...draft,status:"published",revision:1,
    rewardsEnabled:true,uid:"owner"};
  assert.equal(policy.rewardDecision({
    task:suspicious,completionProof:{uid:"owner",
      serverVerified:false,source:"user-link-click",taskRevision:1,
      uniqueEventId:"abc"},adProof:{serverVerified:true},
  }).outcome,"completion-not-verified");
  assert.equal(policy.rewardDecision({
    task:suspicious,completionProof:{uid:"owner",
      serverVerified:true,source:"trusted-platform-verifier",
      taskRevision:1,uniqueEventId:"abc"},
    adProof:{serverVerified:true},ledgerEntries:new Set(["abc"]),
  }).outcome,"already-awarded");
  assert.equal(policy.rewardDecision({
    task:suspicious,completionProof:{uid:"owner",
      serverVerified:true,source:"trusted-platform-verifier",
      taskRevision:1,uniqueEventId:"abc"},
    adProof:{serverVerified:true},ledgerEntries:new Set(),
  }).outcome,"live-wallet-ledger-not-ready");
});
