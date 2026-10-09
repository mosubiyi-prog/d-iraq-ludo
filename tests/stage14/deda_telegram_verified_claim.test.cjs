"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const {claimVerifiedTelegramFollow, iraqDayId} =
  require("../../functions/deda_telegram_verified_claim.js");

const NOW = Date.parse("2026-10-10T09:00:00Z");
const TOKEN = "123456:abcdefghijklmnopqrstuvwxyzABCDEFGHIJ";
const TG_ID = "77351191";
const ACCOUNT = "07712345678";
const UID = "fbaPublicUserUid1234";
const PUBLIC_ID = "@DEDA-Z2AB38";

function signedTelegramLogin({id = TG_ID, nowMs = NOW} = {}) {
  const payload = {
    id, first_name: "Verified User",
    auth_date: String(Math.floor(nowMs / 1000)),
  };
  const body = Object.entries(payload)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, value]) => `${key}=${value}`).join("\n");
  const key = crypto.createHash("sha256").update(TOKEN).digest();
  return {...payload, hash: crypto.createHmac("sha256", key)
    .update(body).digest("hex")};
}

function fakeFirestore(init) {
  const data = new Map(Object.entries(init));
  const writes = [];
  const db = {
    _data: data, _writes: writes,
    collection(name) {
      return {doc(id) {
        const key = `${name}/${id}`;
        return {key};
      }};
    },
    async runTransaction(body) {
      const commands = [];
      const tx = {
        async get(ref) {
          const value = data.get(ref.key);
          return {
            exists: data.has(ref.key),
            data: () => value,
          };
        },
        create(ref, value) {commands.push({op: "create", key: ref.key, value});},
        update(ref, value) {commands.push({op: "update", key: ref.key, value});},
      };
      const result = await body(tx);
      for (const item of commands) {
        if (item.op === "create" && data.has(item.key)) {
          throw Error("precondition-already-exists");
        }
        data.set(item.key,
          item.op === "update" ?
            {...data.get(item.key), ...item.value} :
            {...item.value});
        writes.push(item);
      }
      return result;
    },
  };
  return db;
}

function seeded({rewardEnabled = true, userId = PUBLIC_ID,
  ownerUid = UID, balance = null} = {}) {
  const day = iraqDayId(NOW);
  const start = Date.parse("2026-10-09T21:00:00Z");
  const docs = {
    [`deda_social_direct_days/${day}`]: {
      platform: "telegram", action: "follow",
      url: "https://t.me/DEDA_Iraq",
      activateAt: {toMillis: () => start},
      status: "scheduled", rewardUnit: "diamonds",
      rewardAmount: 10, rewardsEnabled: rewardEnabled,
      rewardClaimMode: "server-verified-telegram-membership",
    },
    [`users/${UID}`]: {
      accountKey: ACCOUNT, sharePersonalId: userId,
    },
    [`deda_sessions/${UID}`]: {accountKey: ACCOUNT},
    [`deda_account_directory/${ACCOUNT}`]: {active: true},
    [`deda_share_ids/${PUBLIC_ID}`]: {
      publicId: PUBLIC_ID, kind: "personal",
      ownerUid, active: true,
    },
  };
  if (balance !== null) {
    docs[`deda_diamond_gift_balances/${PUBLIC_ID}`] =
      {publicId: PUBLIC_ID, balance};
  }
  return fakeFirestore(docs);
}

const member = async (_token, id) =>
  ({user: {id: Number(id)}, status: "member"});
const input = {uid: UID, telegramLogin: signedTelegramLogin(),
  botToken: TOKEN, nowMs: NOW, getMember: member};

test("real verified Telegram membership credits 10 spendable gifts once", async () => {
  const db = seeded();
  const first = await claimVerifiedTelegramFollow(db, input);
  assert.equal(first.outcome, "awarded");
  assert.equal(first.diamonds, 10);
  assert.equal(first.spendableGiftBalance, 10);
  const wallet = db._data.get(`deda_diamond_gift_balances/${PUBLIC_ID}`);
  assert.equal(wallet.balance, 10);
  assert.equal(db._data.get(`deda_telegram_account_claims/${ACCOUNT}`).telegramUserId, TG_ID);
  assert.equal(db._data.get(`deda_telegram_identity_claims/${TG_ID}`).accountKey, ACCOUNT);
  assert.equal(db._data.get(`deda_telegram_reward_audit/${ACCOUNT}`).balanceAfter, 10);
  assert.equal(db._writes.some(x => x.key.startsWith("deda_admin_diamond_wallets/")), false);
  assert.equal(db._writes.some(x => x.key.startsWith("deda_diamond_gifts/")), false);

  const again = await claimVerifiedTelegramFollow(db, input);
  assert.equal(again.outcome, "already-rewarded");
  assert.equal(db._data.get(`deda_diamond_gift_balances/${PUBLIC_ID}`).balance, 10);
  assert.equal(db._writes.length, 4, "wallet + two unique ledgers + audit only");
});

test("credit adds to preexisting spendable personal gifts, never replaces them", async () => {
  const db = seeded({balance: 38});
  const result = await claimVerifiedTelegramFollow(db, input);
  assert.equal(result.outcome, "awarded");
  assert.equal(result.spendableGiftBalance, 48);
  assert.equal(db._data.get(`deda_diamond_gift_balances/${PUBLIC_ID}`).balance, 48);
});

test("same real Telegram ID cannot claim using another DEDA account", async () => {
  const db = seeded();
  await claimVerifiedTelegramFollow(db, input);
  const secondUid = "anotherDedaUid1515";
  const secondAccount = "07812345678";
  const secondPublic = "@DEDA-G2GH53";
  db._data.set(`users/${secondUid}`, {
    accountKey: secondAccount, sharePersonalId: secondPublic});
  db._data.set(`deda_sessions/${secondUid}`, {accountKey: secondAccount});
  db._data.set(`deda_account_directory/${secondAccount}`, {active: true});
  db._data.set(`deda_share_ids/${secondPublic}`, {
    kind: "personal", ownerUid: secondUid, active: true});
  const result = await claimVerifiedTelegramFollow(db,
    {...input, uid: secondUid});
  assert.equal(result.outcome, "already-rewarded");
  assert.equal(db._data.has(`deda_diamond_gift_balances/${secondPublic}`), false);
});

test("unsigned/altered Telegram identity never reaches Bot API or wallet", async () => {
  const db = seeded();
  let botCalls = 0;
  const telegramLogin = {...signedTelegramLogin(), id: "999999999"};
  const result = await claimVerifiedTelegramFollow(db, {...input,
    telegramLogin, getMember: async () => {botCalls++; return {};}});
  assert.equal(result.outcome, "telegram-login-not-verified");
  assert.equal(botCalls, 0);
  assert.equal(db._writes.length, 0);
});

test("not a channel member -> no reward even with valid Telegram login", async () => {
  const db = seeded();
  const result = await claimVerifiedTelegramFollow(db, {...input,
    getMember: async (_, id) => ({user: {id: Number(id)}, status: "left"})});
  assert.equal(result.outcome, "not-eligible");
  assert.equal(db._writes.length, 0);
});

test("published-but-unrewarded task remains inert until trusted backend activation", async () => {
  const db = seeded({rewardEnabled: false});
  const result = await claimVerifiedTelegramFollow(db, input);
  assert.equal(result.outcome, "not-eligible");
  assert.equal(db._writes.length, 0);
});

test("cannot credit wallet linked to a different user's DEDA ID", async () => {
  const db = seeded({ownerUid: "differentUserShouldNotGetCredit"});
  const result = await claimVerifiedTelegramFollow(db, input);
  assert.equal(result.outcome, "unverified-personal-wallet-owner");
  assert.equal(db._writes.length, 0);
});

test("no registered personal DEDA ID -> no shadow wallet credit", async () => {
  const db = seeded({userId: ""});
  const result = await claimVerifiedTelegramFollow(db, input);
  assert.equal(result.outcome, "personal-deda-id-not-registered");
  assert.equal(db._writes.length, 0);
});

test("Gregorian UTC day converts to correct Iraqi day for publication", () => {
  assert.equal(iraqDayId(Date.parse("2026-10-09T21:00:00Z")),
    "2026-10-10");
  assert.equal(iraqDayId(Date.parse("2026-10-10T20:59:59Z")),
    "2026-10-10");
  assert.equal(iraqDayId(Date.parse("2026-10-10T21:00:00Z")),
    "2026-10-11");
});
