"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const trial = require("../../functions/deda_social_trial_runtime.js");

class MemoryDB {
  constructor() { this.values = new Map(); this.count = 0; }
  collection(name) {
    return {doc: (id) => {
      const key = name + "/" + (id || "audit-" + (++this.count));
      return {key, get: async () => this.snap(key)};
    }};
  }
  snap(key) {
    const value = this.values.get(key);
    return {exists: value !== undefined, data: () => value};
  }
  async runTransaction(callback) {
    const pending = [];
    const tx = {
      get: (ref) => Promise.resolve(this.snap(ref.key)),
      create: (ref, data) => pending.push(["create", ref.key, data]),
      update: (ref, data) => pending.push(["update", ref.key, data]),
      set: (ref, data) => pending.push(["set", ref.key, data]),
    };
    const outcome = await callback(tx);
    for (const [op, key, value] of pending) {
      if (op === "create" && this.values.has(key)) throw Error("exists");
      if (op === "update" && !this.values.has(key)) throw Error("missing");
      this.values.set(key, {...(op === "update" ? this.values.get(key) : {}), ...value});
    }
    return outcome;
  }
}
const manager = {uid: "owner", role:"general_manager",
  active:true, serverVerified:true};
const employee = {...manager, uid: "employee", role:"employee"};
const start = new Date("2026-10-09T19:00:00.000Z");
const midnight = new Date("2026-10-09T21:03:00.000Z");
const sample = {
  platform:"telegram", action:"follow",
  title:"تابع قناة DEDA الرسمية على تليجرام",
  url:"https://t.me/DEDA_Iraq", rewardUnit:"diamonds",
  rewardAmount:10, doubleWithRewardedAd:false,
};
test("non-manager and invalid input cannot publish or save", async() => {
  const db = new MemoryDB();
  await assert.rejects(trial.command(db, {
    actor:employee, input:{op:"save", expectedRevision:0,draft:sample},
    now:start,
  }), /general-manager/);
  await assert.rejects(trial.command(db, {
    actor:manager, input:{op:"save", expectedRevision:1,draft:sample},
    now:start,
  }), /revision-conflict/);
  assert.equal(db.values.size,0);
});
test("manager stages tomorrow only; deadline uses server time", async() => {
  const db = new MemoryDB();
  const one = await trial.command(db, {
    actor:manager, input:{op:"save", expectedRevision:0,draft:sample},
    now:start,
  });
  assert.equal(one.revision,1);
  assert.equal(one.rewardsEnabled,false);
  await assert.rejects(trial.command(db, {
    actor:manager,
    input:{op:"schedule",expectedRevision:one.revision,day:"2026-10-09"},
    now:start,
  }), /future-iraq-day-required/);
  const two = await trial.command(db, {
    actor:manager,
    input:{op:"schedule",expectedRevision:one.revision,day:"2026-10-10"},
    now:start,
  });
  assert.equal(two.status,"scheduled");
  assert.equal(two.effectiveAtUtc,"2026-10-09T21:00:00.000Z");
  assert.deepEqual(await trial.publishDue(db,
    new Date("2026-10-09T20:59:59Z")),
    {outcome:"outside-midnight-window"});
  const published = await trial.publishDue(db, midnight);
  assert.equal(published.outcome,"published-config-only");
  const publicConfig = db.values.get(trial.PUBLIC+"/featured");
  assert.equal(publicConfig.title,sample.title);
  assert.equal(publicConfig.url,sample.url);
  assert.equal(publicConfig.rewardAmount,10);
  assert.equal(publicConfig.rewardUnit,"diamonds");
  assert.equal(publicConfig.rewardsEnabled,false);
  assert.equal(publicConfig.rewardClaimMode,
    "blocked-until-trusted-proof-and-ssv-ledger");
  assert.equal([...db.values.keys()].filter(k =>
    /wallet|gems|diamond_balance|users\//i.test(k)).length,0);
  assert.equal((await trial.publishDue(db, midnight)).outcome,"not-due");
  const savedAgain = await trial.command(db, {
    actor:manager,
    input:{op:"save",expectedRevision:3,draft:{...sample,title:"مهمة ثانية"}},
    now:new Date("2026-10-10T08:00:00Z"),
  });
  assert.equal(savedAgain.status,"draft");
  assert.equal(savedAgain.revision,4);
});
test("cancelled future task cannot publish", async() => {
  const db = new MemoryDB();
  const one = await trial.command(db, {
    actor:manager, input:{op:"save",expectedRevision:0,draft:sample},
    now:start,
  });
  const two = await trial.command(db, {
    actor:manager,
    input:{op:"schedule",expectedRevision:one.revision,day:"2026-10-10"},
    now:start,
  });
  const cancelled = await trial.command(db, {
    actor:manager,
    input:{op:"cancel",expectedRevision:two.revision},
    now:new Date("2026-10-09T20:00:00Z"),
  });
  assert.equal(cancelled.status,"cancelled");
  assert.equal((await trial.publishDue(db, midnight)).outcome,"not-due");
  assert.equal(db.values.has(trial.PUBLIC+"/featured"),false);
});
