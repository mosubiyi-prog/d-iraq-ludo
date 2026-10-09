import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {before, after, test} from "node:test";
import {initializeTestEnvironment, assertSucceeds, assertFails}
  from "@firebase/rules-unit-testing";
import {doc, getDoc, setDoc, updateDoc,
  serverTimestamp, Timestamp} from "firebase/firestore";

const PROJECT = "demo-deda-next-telegram-verified";
const DAY_MS = 24 * 3600 * 1000;
const TZ_MS = 3 * 3600 * 1000;
const now = Date.now();
const iraqToday = new Date(now + TZ_MS).toISOString().slice(0, 10);
const startMs = Date.parse(iraqToday + "T00:00:00Z") - TZ_MS;

let env, gm, staff, user, stranger, guest;
const at = (db, collection, id) => doc(db, collection, id);

before(async () => {
  assert.equal(process.env.GCLOUD_PROJECT, PROJECT);
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST,
    "refuse to run against live Firebase");
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: {rules: readFileSync("firestore.rules", "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(at(db,"admins","gm"),
      {active:true,status:"active",role:"general_manager"});
    await setDoc(at(db,"admins","staff"),
      {active:true,status:"active",role:"employee"});
    await setDoc(at(db,"deda_social_direct_days",iraqToday),{
      dayId:iraqToday, activateAt:Timestamp.fromMillis(startMs),
      status:"scheduled",platform:"telegram",action:"follow",
      url:"https://t.me/DEDA_Iraq",
      rewardUnit:"diamonds",rewardAmount:10,
      rewardsEnabled:true,
      rewardClaimMode:"server-verified-telegram-membership",
    });
  });
  gm = env.authenticatedContext("gm").firestore();
  staff = env.authenticatedContext("staff").firestore();
  user = env.authenticatedContext("member").firestore();
  stranger = env.authenticatedContext("anotherMember").firestore();
  guest = env.unauthenticatedContext().firestore();
});

after(async () => { if(env) await env.cleanup(); });

const hiddenCollections = [
  "deda_telegram_start_tokens",
  "deda_telegram_start_throttle",
  "deda_telegram_bot_accounts",
  "deda_telegram_bot_identities",
  "deda_telegram_account_claims",
  "deda_telegram_identity_claims",
];

test("10-diamond verified task readable by signed-in members only when due", async()=>{
  const result = await assertSucceeds(
    getDoc(at(user,"deda_social_direct_days",iraqToday)));
  assert.equal(result.data().rewardAmount,10);
  assert.equal(result.data().rewardClaimMode,
    "server-verified-telegram-membership");
  await assertFails(getDoc(at(guest,"deda_social_direct_days",iraqToday)));
  await assertFails(updateDoc(
    at(user,"deda_social_direct_days",iraqToday), {rewardAmount:100}));
  await assertFails(updateDoc(
    at(gm,"deda_social_direct_days",iraqToday), {
      rewardsEnabled:false, updatedAt: serverTimestamp()}));
});

test("clients including general manager cannot forge Telegram bot nonce or identity", async()=>{
  for(const collection of hiddenCollections) {
    await env.withSecurityRulesDisabled(async ctx => {
      await setDoc(at(ctx.firestore(),collection,"private-test-record"), {
        uid:"member",telegramUserId:"12345678",
        accountKey:"07712345678",createdAt:Timestamp.now(),
      });
    });
    for(const client of [gm,staff,user,stranger,guest]) {
      const entry = at(client,collection,"private-test-record");
      await assertFails(getDoc(entry));
      await assertFails(updateDoc(entry,{telegramUserId:"99999999"}));
      await assertFails(setDoc(at(client,collection,"forged"),{
        uid:"member",accountKey:"07712345678",telegramUserId:"99999999",
      }));
    }
  }
});

test("only active general manager may read server-write-only reward audit", async()=>{
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(at(ctx.firestore(),"deda_telegram_reward_audit","07712345678"),
      {balanceAfter:10,telegramUserId:"12345678"});
    await setDoc(at(ctx.firestore(),"deda_telegram_reward_activation_audit","a1"),
      {action:"telegram_real_rewards_enabled",managerUid:"gm"});
  });
  for(const collection of ["deda_telegram_reward_audit",
      "deda_telegram_reward_activation_audit"]) {
    const id=collection.endsWith("_activation_audit") ? "a1" : "07712345678";
    await assertSucceeds(getDoc(at(gm,collection,id)));
    for(const client of [staff,user,stranger,guest]) {
      await assertFails(getDoc(at(client,collection,id)));
    }
    for(const client of [gm,staff,user,guest]) {
      await assertFails(setDoc(at(client,collection,"forged"),{
        action:"telegram_real_rewards_enabled",createdAt:serverTimestamp(),
      }));
      await assertFails(updateDoc(at(client,collection,id),{
        balanceAfter:9999999}));
    }
  }
});

test("non-manager cannot forge spendable diamond credit", async()=>{
  await env.withSecurityRulesDisabled(async ctx => {
    const db=ctx.firestore();
    await setDoc(at(db,"users","member"),
      {sharePersonalId:"@DEDA-G7XY2Z",accountKey:"07712345678"});
    await setDoc(at(db,"deda_sessions","member"),
      {accountKey:"07712345678"});
    await setDoc(at(db,"deda_share_ids","@DEDA-G7XY2Z"),{
      publicId:"@DEDA-G7XY2Z",kind:"personal",
      active:true,ownerUid:"member",
    });
    // A separate real DEDA session MUST NOT read/spend another member's
    // wallet merely by writing their publicId to their OWN users doc.
    await setDoc(at(db,"users","anotherMember"),
      {sharePersonalId:"@DEDA-G7XY2Z",accountKey:"07822222222"});
    await setDoc(at(db,"deda_sessions","anotherMember"),
      {accountKey:"07822222222"});
    await setDoc(at(db,"deda_diamond_gift_balances","@DEDA-G7XY2Z"),
      {publicId:"@DEDA-G7XY2Z",balance:7,
      createdAt:Timestamp.now(),updatedAt:Timestamp.now()});
  });
  await assertSucceeds(getDoc(
    at(user,"deda_diamond_gift_balances","@DEDA-G7XY2Z")));
  await assertFails(updateDoc(
    at(user,"deda_diamond_gift_balances","@DEDA-G7XY2Z"),{
      balance:17,updatedAt:serverTimestamp()}));
  await assertFails(getDoc(
    at(stranger,"deda_diamond_gift_balances","@DEDA-G7XY2Z")));
  await assertFails(updateDoc(
    at(stranger,"deda_diamond_gift_balances","@DEDA-G7XY2Z"),{
      balance:17,updatedAt:serverTimestamp()}));
});

test("a non-10-diamond or future server task is not readable by members", async()=>{
  const tomorrow = new Date(now+TZ_MS+DAY_MS).toISOString().slice(0,10);
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(at(ctx.firestore(),"deda_social_direct_days",tomorrow),{
      dayId:tomorrow,activateAt:Timestamp.fromMillis(startMs+DAY_MS),
      status:"scheduled",platform:"telegram",action:"follow",
      url:"https://t.me/DEDA_Iraq",rewardUnit:"diamonds",
      rewardAmount:10,rewardsEnabled:true,
      rewardClaimMode:"server-verified-telegram-membership",
    });
    await setDoc(at(ctx.firestore(),"deda_social_direct_days","fake-day"),{
      dayId:"fake-day",activateAt:Timestamp.fromMillis(startMs),
      status:"scheduled",platform:"telegram",action:"follow",
      url:"https://t.me/DEDA_Iraq",rewardUnit:"diamonds",
      rewardAmount:50,rewardsEnabled:true,
      rewardClaimMode:"server-verified-telegram-membership",
    });
  });
  await assertFails(getDoc(at(user,"deda_social_direct_days",tomorrow)));
  await assertFails(getDoc(at(user,"deda_social_direct_days","fake-day")));
  await assertSucceeds(getDoc(at(gm,"deda_social_direct_days",tomorrow)));
});
