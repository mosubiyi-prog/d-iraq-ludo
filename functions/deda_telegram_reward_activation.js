"use strict";

const {FieldValue} = require("firebase-admin/firestore");
const {iraqDayId, getTelegramMember} =
  require("./deda_telegram_verified_claim.js");

async function checkBotIsChannelAdmin(botToken) {
  const r = await fetch("https://api.telegram.org/bot" + botToken + "/getMe",
      {signal: AbortSignal.timeout(7000)});
  if (!r.ok) throw Error("telegram-bot-me-unavailable");
  const body = await r.json();
  const id = String(body?.result?.id || "");
  if (body.ok !== true || body.result?.is_bot !== true ||
      !/^\d{1,20}$/.test(id)) {
    throw Error("telegram-bot-identity-invalid");
  }
  const member = await getTelegramMember(botToken, id);
  return member.status === "administrator" || member.status === "creator";
}

/**
 * Only the real general manager can enable 10-diamond payouts after the bot
 * itself is confirmed ADMIN of @DEDA_Iraq. The historical 100327 trial keeps
 * rewards disabled. GM may disable immediately without a bot API call.
 *
 * Never enables unknown tasks, currencies, amounts or future date drafts.
 */
async function manageVerifiedTelegramReward(db, {
  actor, botToken, op, nowMs = Date.now(),
  botAdminCheck = checkBotIsChannelAdmin,
}) {
  if (!actor || actor.role !== "general_manager" ||
      actor.active !== true || !actor.uid) {
    return {outcome: "general-manager-required"};
  }
  if (!["enable", "disable"].includes(op)) {
    return {outcome: "unsupported-operation"};
  }
  if (op === "enable" && !await botAdminCheck(botToken)) {
    return {outcome: "bot-not-admin-in-official-channel"};
  }
  const dayId = iraqDayId(nowMs);
  const ref = db.collection("deda_social_direct_days").doc(dayId);
  const audit = db.collection("deda_telegram_reward_activation_audit").doc();
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return {outcome: "no-published-telegram-task-today"};
    const task = snap.data() || {};
    const timestamp = task.activateAt;
    const start = timestamp && typeof timestamp.toMillis === "function" ?
      timestamp.toMillis() : NaN;
    if (task.status !== "scheduled" || task.platform !== "telegram" ||
        task.action !== "follow" ||
        task.url !== "https://t.me/DEDA_Iraq" ||
        task.rewardUnit !== "diamonds" || task.rewardAmount !== 10 ||
        !Number.isFinite(start) ||
        nowMs < start || nowMs >= start + 24 * 60 * 60 * 1000) {
      return {outcome: "day-not-approved-for-10-diamonds"};
    }
    const enabled = task.rewardsEnabled === true &&
      task.rewardClaimMode === "server-verified-telegram-membership";
    if (op === "enable" && enabled) return {outcome: "already-enabled"};
    if (op === "disable" && !enabled) return {outcome: "already-disabled"};
    if (op === "enable" && (task.rewardsEnabled !== false ||
        task.rewardClaimMode !==
        "blocked-until-trusted-proof-and-ssv-ledger")) {
      return {outcome: "unexpected-task-claim-mode"};
    }
    const now = FieldValue.serverTimestamp();
    tx.update(ref, {
      rewardsEnabled: op === "enable",
      rewardClaimMode: op === "enable" ?
        "server-verified-telegram-membership" :
        "blocked-until-trusted-proof-and-ssv-ledger",
      rewardsUpdatedByUid: actor.uid,
      rewardsUpdatedAt: now,
    });
    tx.create(audit, {
      action: op === "enable" ?
        "telegram_real_rewards_enabled" :
        "telegram_real_rewards_disabled",
      managerUid: actor.uid, dayId,
      rewardAmount: 10, rewardUnit: "diamonds",
      createdAt: now,
    });
    return {outcome: op === "enable" ? "activated" : "deactivated", dayId};
  }, {maxAttempts: 5});
}

module.exports = {manageVerifiedTelegramReward, checkBotIsChannelAdmin};
