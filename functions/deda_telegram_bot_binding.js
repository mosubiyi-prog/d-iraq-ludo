"use strict";

const {randomBytes, timingSafeEqual} = require("node:crypto");
const {Timestamp, FieldValue} = require("firebase-admin/firestore");

const MAX_AGE_MS = 15 * 60 * 1000;
const MIN_RETRY_MS = 60 * 1000;

function sameSecret(received, expected) {
  const left = Buffer.from(String(received || ""));
  const right = Buffer.from(String(expected || ""));
  return left.length > 0 && left.length === right.length &&
    timingSafeEqual(left, right);
}

function telegramId(value) {
  const id = String(value ?? "");
  return /^\d{1,20}$/.test(id) ? id : "";
}

async function getBotUsername(botToken) {
  const response = await fetch(
      "https://api.telegram.org/bot" + botToken + "/getMe",
      {signal: AbortSignal.timeout(7000)});
  if (!response.ok) throw Error("telegram-bot-not-ready");
  const data = await response.json();
  const name = String(data?.result?.username || "");
  if (!data.ok || !data.result?.is_bot ||
      !/^[A-Za-z0-9_]{5,32}$/.test(name)) {
    throw Error("telegram-bot-has-no-username");
  }
  return name;
}

async function startVerification(db, {
  uid, nowMs = Date.now(), botToken,
  botUsernameLookup = getBotUsername,
  nonceGenerator = () => randomBytes(24).toString("base64url"),
}) {
  if (!/^[A-Za-z0-9_-]{6,128}$/.test(String(uid || ""))) {
    return {outcome: "unauthenticated"};
  }
  // Resolving the bot identity on the trusted server removes the need for
  // a hard-coded guessed bot handle in the Flutter APK.
  const username = await botUsernameLookup(botToken);
  if (!/^[A-Za-z0-9_]{5,32}$/.test(String(username))) {
    return {outcome: "bot-username-invalid"};
  }
  const nonce = nonceGenerator();
  if (!/^[A-Za-z0-9_-]{32}$/.test(nonce)) {
    throw Error("invalid-generated-telegram-challenge");
  }
  const tokenRef = db.collection("deda_telegram_start_tokens").doc(nonce);
  const userRef = db.collection("users").doc(uid);
  const sessionRef = db.collection("deda_sessions").doc(uid);
  return db.runTransaction(async (tx) => {
    const [userSnap, sessionSnap] = await Promise.all([
      tx.get(userRef), tx.get(sessionRef)]);
    const user = userSnap.data() || {};
    const session = sessionSnap.data() || {};
    const accountKey = String(session.accountKey || "");
    if (!userSnap.exists || !sessionSnap.exists ||
        !/^\d{10,15}$/.test(accountKey) ||
        user.accountKey !== accountKey) {
      return {outcome: "not-a-verified-deda-session"};
    }
    const directory = await tx.get(
      db.collection("deda_account_directory").doc(accountKey));
    if (!directory.exists || directory.data()?.active !== true) {
      return {outcome: "inactive-deda-account"};
    }
    const throttleRef = db.collection("deda_telegram_start_throttle")
        .doc(accountKey);
    const throttle = await tx.get(throttleRef);
    const last = throttle.data()?.lastStartedAt;
    if (last && typeof last.toMillis === "function" &&
        nowMs - last.toMillis() < MIN_RETRY_MS) {
      return {outcome: "wait-before-new-link"};
    }
    const existing = await tx.get(tokenRef);
    if (existing.exists) throw Error("telegram-challenge-collision");
    tx.create(tokenRef, {
      accountKey, uid,
      consumed: false,
      createdAt: Timestamp.fromMillis(nowMs),
      expiresAt: Timestamp.fromMillis(nowMs + MAX_AGE_MS),
    });
    tx.set(throttleRef, {lastStartedAt: Timestamp.fromMillis(nowMs)},
        {merge: true});
    return {outcome: "started",
      botLink: `https://t.me/${username}?start=${nonce}`,
      expiresSeconds: MAX_AGE_MS / 1000};
  }, {maxAttempts: 5});
}

async function acceptBotStart(db, {
  update, receivedSecret, expectedSecret, nowMs = Date.now(),
}) {
  if (!sameSecret(receivedSecret, expectedSecret)) {
    return {outcome: "invalid-telegram-webhook-secret"};
  }
  const msg = update?.message;
  const chatId = telegramId(msg?.chat?.id);
  const userId = telegramId(msg?.from?.id);
  if (!msg || msg.chat?.type !== "private" ||
      msg.from?.is_bot === true || !chatId || userId !== chatId) {
    return {outcome: "not-a-private-user-start"};
  }
  const start = String(msg.text || "").match(
      /^\/start ([A-Za-z0-9_-]{32})$/);
  if (!start) return {outcome: "unrecognized-bot-command"};
  const tokenRef = db.collection("deda_telegram_start_tokens")
      .doc(start[1]);
  return db.runTransaction(async (tx) => {
    const challenge = await tx.get(tokenRef);
    const data = challenge.data() || {};
    const expires = data.expiresAt &&
      typeof data.expiresAt.toMillis === "function" ?
      data.expiresAt.toMillis() : NaN;
    if (!challenge.exists || data.consumed === true ||
        !Number.isFinite(expires) || expires < nowMs) {
      return {outcome: "challenge-expired-or-replayed"};
    }
    const uid = String(data.uid || "");
    const accountKey = String(data.accountKey || "");
    if (!/^[A-Za-z0-9_-]{6,128}$/.test(uid) ||
        !/^\d{10,15}$/.test(accountKey)) {
      return {outcome: "invalid-bound-account"};
    }
    const accountRef = db.collection("deda_telegram_bot_accounts")
        .doc(accountKey);
    const telegramRef = db.collection("deda_telegram_bot_identities")
        .doc(userId);
    const [accountSnap, telegramSnap] = await Promise.all([
      tx.get(accountRef), tx.get(telegramRef)]);
    const savedAccount = accountSnap.data() || {};
    const savedTelegram = telegramSnap.data() || {};
    if ((accountSnap.exists &&
      savedAccount.telegramUserId !== userId) ||
      (telegramSnap.exists &&
      savedTelegram.accountKey !== accountKey)) {
      return {outcome: "identity-already-linked-elsewhere"};
    }

    // One-click /start cannot bind an arbitrary DEDA account: the nonce
    // was created only by a verified Firebase/DEDA session; nobody can read
    // the nonce from Firestore as client rules prohibit this collection.
    const stamp = FieldValue.serverTimestamp();
    if (!accountSnap.exists) {
      tx.create(accountRef, {
        accountKey, uid, telegramUserId: userId,
        source: "telegram-bot-private-start",
        linkedAt: stamp,
      });
    }
    if (!telegramSnap.exists) {
      tx.create(telegramRef, {
        accountKey, telegramUserId: userId,
        linkedAt: stamp,
      });
    }
    tx.update(tokenRef, {
      consumed: true, consumedAt: stamp,
      // Avoid persisting Telegram message text / user profile.
    });
    return {outcome: "linked", chatId, telegramUserId: userId};
  }, {maxAttempts: 5});
}

module.exports = {startVerification, acceptBotStart, getBotUsername,
  sameSecret, MAX_AGE_MS};
