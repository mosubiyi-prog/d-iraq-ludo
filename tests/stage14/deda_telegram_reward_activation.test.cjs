"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {manageVerifiedTelegramReward} =
  require("../../functions/deda_telegram_reward_activation.js");

const NOW = Date.parse("2026-10-10T09:00:00Z");
const DAY = "2026-10-10";
const ADMIN = {uid: "generalManager999", role: "general_manager", active: true};
const BOT = "12345:TEST_SECRET_NOT_REAL";

function dbWithTask(patch = {}) {
  const docs = new Map();
  docs.set(`deda_social_direct_days/${DAY}`, {
    platform: "telegram", action: "follow",
    url: "https://t.me/DEDA_Iraq",
    rewardUnit: "diamonds", rewardAmount: 10,
    rewardsEnabled: false,
    rewardClaimMode: "blocked-until-trusted-proof-and-ssv-ledger",
    activateAt: {toMillis: () => Date.parse("2026-10-09T21:00:00Z")},
    status: "scheduled", ...patch,
  });
  let audit = 0;
  const writes = [];
  return {docs, writes,
    collection(name) {
      return {doc(id) {return {key: `${name}/${id || 'audit-'+ ++audit}`};}};
    },
    async runTransaction(fn) {
      const operations = [];
      const tx = {
        get: async (ref) => ({
          exists: docs.has(ref.key), data: () => docs.get(ref.key),
        }),
        update: (ref, data) => operations.push(["update",ref.key,data]),
        create: (ref, data) => operations.push(["create",ref.key,data]),
      };
      const result = await fn(tx);
      for (const [type, id, data] of operations) {
        if (type === "create" && docs.has(id)) throw Error("already-created");
        docs.set(id, {...docs.get(id), ...data});
        writes.push({type, id});
      }
      return result;
    },
  };
}

const allowed = {actor: ADMIN, botToken: BOT, nowMs: NOW,
  botAdminCheck: async () => true};

test("GM activates only today's 10-diamond verified membership reward", async () => {
  const db = dbWithTask();
  const res = await manageVerifiedTelegramReward(db, {...allowed,op:"enable"});
  assert.equal(res.outcome, "activated");
  const day = db.docs.get(`deda_social_direct_days/${DAY}`);
  assert.equal(day.rewardsEnabled, true);
  assert.equal(day.rewardClaimMode, "server-verified-telegram-membership");
  assert.equal(db.writes.length, 2, "day switch and immutable audit only");
  assert.equal(db.writes.some(x=>x.id.startsWith("deda_admin_diamond_wallets/")),false);
});

test("manager can disable immediately without Telegram network availability", async () => {
  const db = dbWithTask({rewardsEnabled: true,
    rewardClaimMode: "server-verified-telegram-membership"});
  const res = await manageVerifiedTelegramReward(db, {
    ...allowed, op: "disable",
    botAdminCheck: async () => {throw Error("Telegram unavailable");},
  });
  assert.equal(res.outcome, "deactivated");
  assert.equal(db.docs.get(`deda_social_direct_days/${DAY}`).rewardsEnabled,false);
});

test("non-GM and non-admin bot NEVER activate rewards", async () => {
  const db = dbWithTask();
  assert.equal((await manageVerifiedTelegramReward(db, {
    ...allowed,op:"enable", actor:{...ADMIN, role:"employee"},
  })).outcome,"general-manager-required");
  assert.equal((await manageVerifiedTelegramReward(db, {
    ...allowed,op:"enable", botAdminCheck: async () => false,
  })).outcome,"bot-not-admin-in-official-channel");
  assert.equal(db.writes.length, 0);
});

test("wrong currency or amount cannot be enabled even by GM", async () => {
  for (const patch of [{rewardAmount: 25},{rewardUnit:"points"},
    {status:"cancelled"},{url:"https://t.me/another_channel"}]) {
    const db = dbWithTask(patch);
    assert.equal((await manageVerifiedTelegramReward(db,
      {...allowed,op:"enable"})).outcome,
    "day-not-approved-for-10-diamonds");
    assert.equal(db.writes.length,0);
  }
});

test("already-activated and disabled operations are idempotent", async () => {
  const db = dbWithTask();
  assert.equal((await manageVerifiedTelegramReward(db,
    {...allowed,op:"disable"})).outcome, "already-disabled");
  assert.equal((await manageVerifiedTelegramReward(db,
    {...allowed,op:"enable"})).outcome, "activated");
  const previous = db.writes.length;
  assert.equal((await manageVerifiedTelegramReward(db,
    {...allowed,op:"enable"})).outcome, "already-enabled");
  assert.equal(db.writes.length, previous);
});
