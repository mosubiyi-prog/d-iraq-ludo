"use strict";
const crypto = require("node:crypto");

/**
 * Telegram verification prerequisites:
 * 1) Telegram bot token SECRET, bot administrator in @DEDA_Iraq.
 * 2) Verified Telegram Login hash bound to the authenticated DEDA UID.
 * 3) Telegram Bot API getChatMember return for channel membership.
 * 4) Trusted callable transaction owns idempotent event and wallet ledger.
 *
 * This module NEVER credits a wallet or claims visiting URL proves follow.
 */
function verifyTelegramLogin(payload, botToken, nowMs = Date.now()) {
  if (!payload || !botToken || !/^\d+:[\w-]{30,}$/.test(botToken)) {
    return {valid: false, reason: "missing-bot-secret-or-telegram-payload"};
  }
  const id = String(payload.id || "");
  const authDate = Number(payload.auth_date);
  const hash = String(payload.hash || "").toLowerCase();
  if (!/^\d{1,20}$/.test(id) || !Number.isSafeInteger(authDate) ||
      !/^[a-f0-9]{64}$/.test(hash) ||
      authDate * 1000 > nowMs + 30000 ||
      nowMs - authDate * 1000 > 5 * 60 * 1000) {
    return {valid: false, reason: "invalid-or-expired-login"};
  }
  const fields = Object.entries(payload)
      .filter(([key]) => key !== "hash")
      .map(([key,value])=>[key,String(value)])
      .sort(([a],[b])=>a.localeCompare(b))
      .map(([key,value])=>`${key}=${value}`)
      .join("\n");
  const secretKey = crypto.createHash("sha256").update(botToken).digest();
  const expected = crypto.createHmac("sha256", secretKey)
      .update(fields).digest();
  const actual = Buffer.from(hash, "hex");
  if (actual.length !== expected.length ||
      !crypto.timingSafeEqual(actual, expected)) {
    return {valid: false, reason: "telegram-hmac-failed"};
  }
  return {valid: true, telegramUserId: id};
}

function memberConfirmed(chatMember, telegramUserId) {
  if (!chatMember || String(chatMember.user?.id) !==
      String(telegramUserId)) return false;
  if (chatMember.status === "creator" ||
      chatMember.status === "administrator" ||
      chatMember.status === "member") return true;
  return chatMember.status === "restricted" && chatMember.is_member === true;
}

function claimEligible({dayTask, now, loginProof, botMember, userUid,
  claimAlreadyExists}) {
  const no = (reason) => ({eligible: false, reason});
  if (!userUid || claimAlreadyExists !== false) return no("not-new-claim");
  if (!loginProof || loginProof.valid !== true) {
    return no("telegram-account-unverified");
  }
  if (!memberConfirmed(botMember, loginProof.telegramUserId)) {
    return no("not-a-verified-channel-member");
  }
  const ms = now instanceof Date ? now.getTime() : NaN;
  const start = dayTask?.activateAt;
  const t = start && typeof start.toMillis === "function" ?
    start.toMillis() : NaN;
  if (!Number.isFinite(ms) || !Number.isFinite(t) ||
      ms < t || ms >= t + 24 * 3600 * 1000 ||
      dayTask.status !== "scheduled" ||
      dayTask.platform !== "telegram" ||
      dayTask.action !== "follow" ||
      dayTask.url !== "https://t.me/DEDA_Iraq") {
    return no("task-not-active-or-wrong-channel");
  }
  if (!["points","coins","diamonds"].includes(dayTask.rewardUnit) ||
      !Number.isSafeInteger(dayTask.rewardAmount) ||
      dayTask.rewardAmount < 1 || dayTask.rewardAmount > 5000) {
    return no("invalid-configured-reward");
  }
  // PAYOUT IS DISABLED in 100327. The future verified server ledger must
  // enable its own payout switch and credit exactly once IN A TRANSACTION.
  if (dayTask.rewardsEnabled !== true ||
      dayTask.rewardClaimMode !== "server-verified-telegram-membership") {
    return no("trusted-wallet-ledger-not-live");
  }
  return {eligible: true, unit: dayTask.rewardUnit,
    amount: dayTask.rewardAmount};
}

module.exports = {verifyTelegramLogin,memberConfirmed,claimEligible};
