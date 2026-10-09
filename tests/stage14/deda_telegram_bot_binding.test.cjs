"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {startVerification, acceptBotStart} =
  require("../../functions/deda_telegram_bot_binding.js");
const {claimVerifiedTelegramFollow} =
  require("../../functions/deda_telegram_verified_claim.js");

const NOW = Date.parse("2026-10-10T09:00:00Z");
const UID = "dedaUserUid5etW32";
const ACCOUNT = "07712345678";
const PUBLIC = "@DEDA-Z2AB38";
const TG_ID = "77351191";
const NONCE = "A".repeat(32);
const BOT_TOKEN = "123456:abcdefghijklmnopqrstuvwxyzABCDEFGHIJ";
const HOOK_SECRET = "OnlyOwnerTelegramWebhookSecret37";

function fakeDb(init) {
  const docs = new Map(Object.entries(init));
  const writes = [];
  return {
    docs, writes,
    collection(name) {return {doc(id) {
      const key = name+"/"+id;
      return {key, async get() {
        return {exists: docs.has(key), data: () => docs.get(key)};
      }};
    }};},
    async runTransaction(callback) {
      const changes = [];
      const tx = {
        async get(ref) {
          return {exists: docs.has(ref.key), data: () => docs.get(ref.key)};
        },
        create(ref, value) {
          changes.push(["create", ref.key, value]);
        },
        set(ref, value) {
          changes.push(["set", ref.key, value]);
        },
        update(ref, value) {
          changes.push(["update", ref.key, value]);
        },
      };
      const value = await callback(tx);
      for (const [kind, key, v] of changes) {
        if (kind === "create" && docs.has(key)) throw Error("already-exists");
        docs.set(key, kind === "create" ? {...v} :
          {...(docs.get(key) || {}), ...v});
        writes.push({kind, key});
      }
      return value;
    },
  };
}

const day = "2026-10-10";
function initial() {
  return fakeDb({
    [`users/${UID}`]: {accountKey: ACCOUNT, sharePersonalId: PUBLIC},
    [`deda_sessions/${UID}`]: {accountKey: ACCOUNT},
    [`deda_account_directory/${ACCOUNT}`]: {active: true},
    [`deda_share_ids/${PUBLIC}`]: {
      publicId: PUBLIC, kind: "personal", ownerUid: UID, active: true,
    },
    [`deda_social_direct_days/${day}`]: {
      platform: "telegram", action: "follow",
      url: "https://t.me/DEDA_Iraq",
      activateAt: {toMillis: () => Date.parse("2026-10-09T21:00:00Z")},
      status: "scheduled", rewardUnit: "diamonds",
      rewardAmount: 10, rewardsEnabled: true,
      rewardClaimMode: "server-verified-telegram-membership",
    },
  });
}

async function begun(db) {
  return startVerification(db, {
    uid: UID, nowMs: NOW, botToken: BOT_TOKEN,
    botUsernameLookup: async () => "DEDA_Verify_Bot",
    nonceGenerator: () => NONCE,
  });
}

function botMessage({text = `/start ${NONCE}`, id = Number(TG_ID),
  type = "private"} = {}) {
  return {message: {
    text, from: {id, is_bot: false},
    chat: {id, type},
  }};
}

async function accept(db, update = botMessage(), {
  receivedSecret = HOOK_SECRET, nowMs = NOW,
} = {}) {
  return acceptBotStart(db, {
    update, receivedSecret, expectedSecret: HOOK_SECRET, nowMs,
  });
}

test("DEDA Firebase session creates 15-minute bot start link (no guessed handle)", async () => {
  const db = initial();
  const result = await begun(db);
  assert.equal(result.outcome, "started");
  assert.equal(result.expiresSeconds, 900);
  assert.equal(result.botLink,
    `https://t.me/DEDA_Verify_Bot?start=${NONCE}`);
  const token = db.docs.get(`deda_telegram_start_tokens/${NONCE}`);
  assert.equal(token.accountKey, ACCOUNT);
  assert.equal(token.uid, UID);
  assert.equal(token.consumed, false);
  assert.equal(token.expiresAt.toMillis(), NOW + 15 * 60 * 1000);
});

test("authenticated private /start binds real Telegram user only once", async () => {
  const db = initial();
  await begun(db);
  const response = await accept(db);
  assert.equal(response.outcome, "linked");
  const byAccount = db.docs.get(`deda_telegram_bot_accounts/${ACCOUNT}`);
  assert.equal(byAccount.telegramUserId, TG_ID);
  assert.equal(byAccount.uid, UID);
  assert.equal(db.docs.get(`deda_telegram_bot_identities/${TG_ID}`).accountKey, ACCOUNT);
  assert.equal(db.docs.get(`deda_telegram_start_tokens/${NONCE}`).consumed, true);
  const before = db.writes.length;
  assert.equal((await accept(db)).outcome, "challenge-expired-or-replayed");
  assert.equal(db.writes.length, before);
});

test("forged webhook or group chat cannot bind identity", async () => {
  const db = initial();
  await begun(db);
  const wrong = await accept(db, botMessage(), {receivedSecret: "wrong"});
  assert.equal(wrong.outcome, "invalid-telegram-webhook-secret");
  const group = await accept(db, botMessage({type: "supergroup"}));
  assert.equal(group.outcome, "not-a-private-user-start");
  assert.equal(db.docs.has(`deda_telegram_bot_accounts/${ACCOUNT}`), false);
});

test("expired token and invalid session fail closed", async () => {
  const db = initial();
  await begun(db);
  const expired = await accept(db, botMessage(), {
    nowMs: NOW + 15 * 60 * 1000 + 1,
  });
  assert.equal(expired.outcome, "challenge-expired-or-replayed");
  const other = initial();
  other.docs.delete(`deda_sessions/${UID}`);
  assert.equal((await begun(other)).outcome, "not-a-verified-deda-session");
  assert.equal(other.docs.has(`deda_telegram_start_tokens/${NONCE}`), false);
});

test("revoked DEDA session after nonce issue cannot bind Telegram identity", async () => {
  for (const doc of [
    `deda_sessions/${UID}`,
    `users/${UID}`,
    `deda_account_directory/${ACCOUNT}`,
  ]) {
    const db = initial();
    await begun(db);
    if (doc.startsWith("deda_account_directory/")) {
      db.docs.set(doc, {active: false});
    } else {
      db.docs.delete(doc);
    }
    const result = await accept(db);
    assert.equal(result.outcome, "deda-session-revoked-before-telegram-binding");
    assert.equal(db.docs.has(`deda_telegram_bot_accounts/${ACCOUNT}`), false);
    assert.equal(db.docs.has(`deda_telegram_bot_identities/${TG_ID}`), false);
    assert.equal(db.docs.get(`deda_telegram_start_tokens/${NONCE}`).consumed,
      false);
  }
});

test("same Telegram account cannot silently link a different DEDA identity", async () => {
  const db = initial();
  await begun(db);
  await accept(db);
  const newUid = "otherDedaUid2Px9";
  const account = "07812345678";
  const nonce = "B".repeat(32);
  db.docs.set(`users/${newUid}`, {accountKey: account});
  db.docs.set(`deda_sessions/${newUid}`, {accountKey: account});
  db.docs.set(`deda_account_directory/${account}`, {active: true});
  await startVerification(db, {uid: newUid, nowMs: NOW,
    botUsernameLookup: async () => "DEDA_Verify_Bot",
    nonceGenerator: () => nonce});
  const attempt = await accept(db, botMessage({text: `/start ${nonce}`}));
  assert.equal(attempt.outcome, "identity-already-linked-elsewhere");
  assert.equal(db.docs.has(`deda_telegram_bot_accounts/${account}`), false);
});

test("bot-linked member can receive 10 spendable diamonds without Login Widget", async () => {
  const db = initial();
  await begun(db);
  await accept(db);
  const args = {
    uid: UID, botToken: BOT_TOKEN, nowMs: NOW,
    getMember: async (_, id) =>
      ({user: {id: Number(id)}, status: "member"}),
  };
  const earned = await claimVerifiedTelegramFollow(db, args);
  assert.equal(earned.outcome, "awarded");
  assert.equal(earned.spendableGiftBalance, 10);
  assert.equal(db.docs.get(`deda_diamond_gift_balances/${PUBLIC}`).balance, 10);
  assert.equal((await claimVerifiedTelegramFollow(db, args)).outcome, "already-rewarded");
  assert.equal(db.docs.get(`deda_diamond_gift_balances/${PUBLIC}`).balance, 10);
});

test("no verified bot linkage means no reward, even on day of challenge", async () => {
  const db = initial();
  await begun(db);
  const v = await claimVerifiedTelegramFollow(db, {
    uid: UID, botToken: BOT_TOKEN, nowMs: NOW,
    getMember: async () => {throw Error("should not ask Telegram");},
  });
  assert.equal(v.outcome, "telegram-bot-not-linked");
  assert.equal(db.docs.has(`deda_diamond_gift_balances/${PUBLIC}`), false);
});

test("new start links are throttled per DEDA account", async () => {
  const db = initial();
  assert.equal((await begun(db)).outcome, "started");
  const second = await startVerification(db, {uid: UID, nowMs: NOW + 10000,
    botUsernameLookup: async () => "DEDA_Verify_Bot",
    nonceGenerator: () => "B".repeat(32)});
  assert.equal(second.outcome, "wait-before-new-link");
});
