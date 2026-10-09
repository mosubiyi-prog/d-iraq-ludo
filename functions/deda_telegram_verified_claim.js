"use strict";

const {FieldValue} = require("firebase-admin/firestore");
const {verifyTelegramLogin, claimEligible} =
  require("./deda_telegram_reward_policy.js");

const CHANNEL = "@DEDA_Iraq";
const REWARD = 10;
const MAX_BALANCE = 1 << 30;

function iraqDayId(nowMs) {
  if (!Number.isFinite(nowMs)) throw Error("invalid-server-clock");
  return new Date(nowMs + 3 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

async function getTelegramMember(botToken, telegramUserId) {
  if (!/^\d{1,20}$/.test(String(telegramUserId))) {
    throw Error("telegram-id-invalid");
  }
  const url = new URL("https://api.telegram.org/bot" +
      botToken + "/getChatMember");
  url.searchParams.set("chat_id", CHANNEL);
  url.searchParams.set("user_id", String(telegramUserId));
  const response = await fetch(url, {
    method: "GET",
    signal: AbortSignal.timeout(7000),
  });
  if (!response.ok) throw Error("telegram-membership-api-unavailable");
  const payload = await response.json();
  if (payload.ok !== true || !payload.result) {
    throw Error("telegram-membership-not-verifiable");
  }
  return payload.result;
}

/**
 * TRUSTED SERVER ONLY — NOT A CLIENT-SIDE CLAIM.
 *
 * Verify Telegram's signed user login + live channel membership BEFORE a
 * single atomic Admin SDK transaction. Once per real DEDA account AND once
 * per verified Telegram identity, even across dates, users or retries.
 *
 * Credits DEDA's EXISTING spendable personal gifted-diamonds wallet; does not
 * spend or write the manager's administrative gifting budget. Existing
 * publication schema intentionally has rewardsEnabled:false, and this code
 * stays safely INERT until backend, bot admin and explicit activation.
 */
async function claimVerifiedTelegramFollow(firestore, {
  uid, telegramLogin, botToken, nowMs = Date.now(),
  getMember = getTelegramMember,
}) {
  if (!uid || !/^[A-Za-z0-9_-]{6,128}$/.test(String(uid))) {
    return {outcome: "unauthenticated"};
  }
  let proof = verifyTelegramLogin(telegramLogin, botToken, nowMs);
  let botAccount = null;
  if (!telegramLogin) {
    const s = await firestore.collection("deda_sessions").doc(uid).get();
    const accountKey = String(s.data()?.accountKey || "");
    if (!s.exists || !/^\\d{10,15}$/.test(accountKey)) {
      return {outcome: "not-a-verified-deda-session"};
    }
    botAccount = accountKey;
    const b = await firestore.collection("deda_telegram_bot_accounts")
        .doc(accountKey).get();
    if (!b.exists || b.data()?.accountKey !== accountKey ||
        !/^\\d{1,20}$/.test(String(b.data()?.telegramUserId || ""))) {
      return {outcome: "telegram-bot-not-linked"};
    }
    proof = {valid: true, telegramUserId: String(b.data().telegramUserId)};
  }
  if (!proof.valid) return {outcome: "telegram-login-not-verified"};

  // Never trust a client-reported membership flag or reported TG identity.
  const member = await getMember(botToken, proof.telegramUserId);
  const dayId = iraqDayId(nowMs);
  const now = new Date(nowMs);
  const db = firestore;
  const dayRef = db.collection("deda_social_direct_days").doc(dayId);
  const userRef = db.collection("users").doc(uid);
  const sessionRef = db.collection("deda_sessions").doc(uid);
  const telegramClaimRef = db.collection("deda_telegram_identity_claims")
      .doc(proof.telegramUserId);
  const stamp = FieldValue.serverTimestamp();

  return db.runTransaction(async (tx) => {
    const [taskSnap, userSnap, sessionSnap, tgClaimSnap] =
      await Promise.all([
        tx.get(dayRef), tx.get(userRef), tx.get(sessionRef),
        tx.get(telegramClaimRef),
      ]);
    const task = taskSnap.data() || {};
    const user = userSnap.data() || {};
    const session = sessionSnap.data() || {};
    const accountKey = String(session.accountKey || "");
    if (!taskSnap.exists || !userSnap.exists || !sessionSnap.exists ||
        !/^\d{10,15}$/.test(accountKey) ||
        String(user.accountKey || "") !== accountKey) {
      return {outcome: "not-a-verified-deda-session"};
    }
    const [directorySnap, accountClaimSnap] = await Promise.all([
      tx.get(db.collection("deda_account_directory").doc(accountKey)),
      tx.get(db.collection("deda_telegram_account_claims").doc(accountKey)),
    ]);
    if (!directorySnap.exists ||
        directorySnap.data()?.active !== true) {
      return {outcome: "inactive-deda-account"};
    }
    if (accountClaimSnap.exists || tgClaimSnap.exists) {
      return {outcome: "already-rewarded"};
    }

    const eligible = claimEligible({
      dayTask: task, now, loginProof: proof, botMember: member,
      userUid: uid, claimAlreadyExists: false,
    });
    if (!eligible.eligible || eligible.unit !== "diamonds" ||
        eligible.amount !== REWARD) {
      return {outcome: "not-eligible",
        reason: eligible.reason || "reward-not-10-diamonds"};
    }

    // The app's existing spending and profile widgets BOTH read this
    // personal wallet by the stable DEDA personal ID; avoid shadow balances.
    const personalId = String(user.sharePersonalId || "");
    if (!/^@DEDA-[A-Z0-9]{6}$/.test(personalId)) {
      return {outcome: "personal-deda-id-not-registered"};
    }
    const shareRef = db.collection("deda_share_ids").doc(personalId);
    const walletRef = db.collection("deda_diamond_gift_balances")
        .doc(personalId);
    const [shareSnap, walletSnap] = await Promise.all([
      tx.get(shareRef), tx.get(walletRef),
    ]);
    const share = shareSnap.data() || {};
    if (!shareSnap.exists || share.kind !== "personal" ||
        share.ownerUid !== uid || share.active !== true) {
      return {outcome: "unverified-personal-wallet-owner"};
    }
    const balance = walletSnap.exists ? walletSnap.data()?.balance : 0;
    if (!Number.isSafeInteger(balance) || balance < 0 ||
        balance > MAX_BALANCE - REWARD ||
        (walletSnap.exists &&
          walletSnap.data()?.publicId !== personalId)) {
      return {outcome: "invalid-personal-wallet"};
    }

    if (walletSnap.exists) {
      tx.update(walletRef, {balance: balance + REWARD, updatedAt: stamp});
    } else {
      tx.create(walletRef, {
        publicId: personalId, balance: REWARD,
        createdAt: stamp, updatedAt: stamp,
      });
    }
    // Deterministic unique ledgers ensure idempotent exactly-once issuance.
    const proofData = {
      accountKey, uid, telegramUserId: proof.telegramUserId,
      personalId, dayId, rewardUnit: "diamonds",
      rewardAmount: REWARD, createdAt: stamp,
    };
    tx.create(db.collection("deda_telegram_account_claims")
        .doc(accountKey), proofData);
    tx.create(telegramClaimRef, proofData);
    tx.create(db.collection("deda_telegram_reward_audit")
        .doc(accountKey), {
      ...proofData, balanceAfter: balance + REWARD,
      action: "telegram_verified_channel_member_reward",
      // NEVER store the bot secret or login payload/Telegram hash.
    });
    return {outcome: "awarded", diamonds: REWARD,
      personalId, spendableGiftBalance: balance + REWARD};
  }, {maxAttempts: 5});
}

module.exports = {claimVerifiedTelegramFollow, iraqDayId, getTelegramMember};
