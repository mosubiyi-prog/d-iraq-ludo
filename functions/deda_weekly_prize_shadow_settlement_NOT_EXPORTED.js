"use strict";

/**
 * DEDA Stage12: exactly-once weekly prize settlement in a DEDICATED
 * LOCAL FIRESTORE EMULATOR — NOT EXPORTED AND NEVER FOR PRODUCTION.
 *
 * Only shadow namespaces are writable; NO actual earned/gift/manager wallet,
 * client XP, original account, Firebase rules or published DEDA source
 * is read/edited. The 150/100/50/10x7 grant is modeled as a NEW earned prize
 * from the future privileged server, NOT a deduction from a general manager.
 *
 * A production clone is forbidden until real canonical spendable earned-wallet
 * schema and privileged authenticated issuer are verified independently.
 * Sample snapshot "issuer" fields are mock data, NOT cryptographic proof.
 */
const crypto = require("node:crypto");
const {verifiedWeek} = require("./deda_weekly_leaderboard_shadow_policy.js");
const {verifyAndRedactSnapshot} =
  require("./deda_weekly_snapshot_reader_NOT_EXPORTED.js");

const PROJECT = "demo-deda-weekly-prizes-stage12";
const ROOT = Object.freeze({
  snapshot:"deda_weekly_stage12_shadow_closed_snapshots",
  settlement:"deda_weekly_stage12_shadow_settlements",
  receipt:"deda_weekly_stage12_shadow_prize_receipts",
  wallet:"deda_weekly_stage12_shadow_earned_wallets",
});
const REWARDS = Object.freeze([150,100,50,10,10,10,10,10,10,10]);
const ISSUER = "privileged_server_only_weekly_ranker_v1";
const ACCOUNT = /^[0-9]{10,16}$/;

function fail(reason) { throw Error("DEDA_STAGE12_SHADOW_PAYOUT_BLOCK_"+reason); }
function integer(value) { return Number.isSafeInteger(value) && value >= 0; }
function requireEmulator(db) {
  if (!process.env.FIRESTORE_EMULATOR_HOST ||
      process.env.GCLOUD_PROJECT !== PROJECT ||
      !db || typeof db.runTransaction !== "function" ||
      typeof db.doc !== "function") fail("emulator_only_no_real_wallet");
}
function fingerprint(...parts) {
  return crypto.createHash("sha256").update(parts.join("|"),"utf8")
    .digest("hex");
}
function checkSecret(secret) {
  if (!Buffer.isBuffer(secret) || secret.length < 32)
    fail("backend_only_secret");
}
function privateWalletId(accountKey,secret) {
  return crypto.createHmac("sha256",secret)
    .update(accountKey,"utf8").digest("hex");
}
function canonicalSnapshot(value,week,now) {
  if (!value || typeof value !== "object" || Array.isArray(value) ||
      value.shadowFixtureOnly !== true || value.issuer !== ISSUER ||
      value.weekId !== week.weekId || value.state !== "closed" ||
      value.generatedAtMs !== week.endMs - 1 ||
      !Array.isArray(value.rows)) fail("immutable_closed_fixture_required");
  // Stage7 checks exact rank sequence, XP increments, sorting, ties, awards,
  // deduplicated accounts, safe names, dates and the seven-day window.
  verifyAndRedactSnapshot(value,week,"000000000000",now,"previous");
  const winners = value.rows.slice(0,10).map((r,index)=>{
    if (!ACCOUNT.test(r.accountKey||"") ||
        r.place !== index+1 ||
        r.potentialDiamonds !== REWARDS[index]) {
      fail("unverified_winner");
    }
    return {accountKey:r.accountKey,place:r.place,amount:REWARDS[index]};
  });
  const total=winners.reduce((sum,w)=>sum+w.amount,0);
  if (winners.length===10 && total!==370) fail("prize_budget");
  return {winners,total};
}
function shadowWallet(doc,accountKey) {
  if (!doc.exists) return 0;
  const value=doc.data();
  if (!value || value.shadowOnly!==true ||
      value.accountKey!==accountKey ||
      !integer(value.earnedPrizeDiamonds)) fail("shadow_wallet_conflict");
  return value.earnedPrizeDiamonds;
}

/**
 * One transaction settles ALL eligible ranks atomically. A second or
 * concurrent call reads the same week record and returns already_settled
 * with zero added, not a second prize. Different weeks can award separately.
 *
 * Caller cannot supply rewards, accounts, ranks, phone, wallet, weekId or
 * client records. Only the emulator's internal closed snapshot is read.
 */
async function simulateShadowWeekPrizes({
  db,serverNowMs,weekConfig,backendSecret,...clientOverrides
}) {
  requireEmulator(db);
  if (Object.keys(clientOverrides).length) fail("client_or_unreviewed_input");
  if (!integer(serverNowMs)) fail("server_clock");
  checkSecret(backendSecret);
  const week=verifiedWeek(weekConfig);
  if (serverNowMs < week.endMs) fail("week_not_closed");

  const snapshotRef=db.doc(ROOT.snapshot+"/"+week.weekId);
  const settlementRef=db.doc(ROOT.settlement+"/"+week.weekId);
  return db.runTransaction(async tx=>{
    // Read the server-owned frozen fixture INSIDE the same transaction.
    const snapshotDoc=await tx.get(snapshotRef);
    if (!snapshotDoc.exists) fail("snapshot_missing");
    const snapshot=snapshotDoc.data();
    const {winners,total}=canonicalSnapshot(snapshot,week,serverNowMs);
    const digest=fingerprint(JSON.stringify(snapshot));
    const previous=await tx.get(settlementRef);
    if (previous.exists) {
      const prior=previous.data();
      if (!prior || prior.shadowOnly!==true ||
          prior.weekId!==week.weekId || prior.snapshotDigest!==digest ||
          prior.totalDiamonds!==total ||
          prior.winnerCount!==winners.length ||
          prior.state!=="settled") fail("already_settled_snapshot_changed");
      return Object.freeze({outcome:"already_settled",
        shadowDiamondsAdded:0,winnerCount:0,shadowOnly:true});
    }

    // Firestore transactions read ALL wallet and receipt docs before writes.
    const plans=[];
    for (const winner of winners) {
      const walletId=privateWalletId(winner.accountKey,backendSecret);
      const receiptId=fingerprint(week.weekId,walletId);
      const walletRef=db.doc(ROOT.wallet+"/"+walletId);
      const receiptRef=db.doc(ROOT.receipt+"/"+receiptId);
      const [walletDoc,receiptDoc]=await Promise.all([
        tx.get(walletRef),tx.get(receiptRef),
      ]);
      if (receiptDoc.exists) fail("partial_or_duplicate_prize_receipt");
      const priorBalance=shadowWallet(walletDoc,winner.accountKey);
      const nextBalance=priorBalance+winner.amount;
      if (!integer(nextBalance)) fail("shadow_amount_overflow");
      plans.push({...winner,walletRef,receiptRef,receiptId,nextBalance});
    }

    for (const plan of plans) {
      // These paths are prefixed stage12_shadow — NOT actual DEDA wallets.
      tx.set(plan.walletRef,{
        shadowOnly:true,accountKey:plan.accountKey,
        earnedPrizeDiamonds:plan.nextBalance,
        lastWeekId:week.weekId,updatedAtMs:serverNowMs,
      });
      tx.create(plan.receiptRef,{
        shadowOnly:true,weekId:week.weekId,receiptId:plan.receiptId,
        accountKey:plan.accountKey,place:plan.place,amount:plan.amount,
        snapshotDigest:digest,createdAtMs:serverNowMs,
      });
    }
    tx.create(settlementRef,{
      shadowOnly:true,state:"settled",weekId:week.weekId,
      snapshotDigest:digest,winnerCount:winners.length,
      totalDiamonds:total,createdAtMs:serverNowMs,
    });
    return Object.freeze({outcome:"shadow_settled",
      shadowDiamondsAdded:total,winnerCount:winners.length,
      shadowOnly:true});
  });
}
module.exports=Object.freeze({
  PROJECT,ROOT,simulateShadowWeekPrizes,privateWalletId,
});
