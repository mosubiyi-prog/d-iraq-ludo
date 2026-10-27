"use strict";

/**
 * Stage11 — NO EXPORT, NO DEPLOY, NO WRITES.
 *
 * Read-only composition of the Stage6 session gate, Stage7 canonical Iraq
 * week/row redactor and Stage10 verified receipt projector. Its return value
 * matches the Stage8 DedaWeeklyServerSnapshotPair.parse() Flutter contract.
 *
 * Data with the right "issuer" string is NOT production-proof by itself.
 * Do not export this function until a privileged XP issuer, account
 * attestation issuer, calendar writer, public-profile writer and Firestore
 * write-deny policy have ALL been independently audited and deployed.
 *
 * No balances, existing profile XP, diamond wallets or historical progress
 * are accessed or modified; sample fixtures stay in test code only.
 */
const {resolveFutureVerifiedAccount} =
  require("./deda_weekly_owner_receipt_gate_NOT_EXPORTED.js");
const {validateServerCalendar,verifyAndRedactSnapshot} =
  require("./deda_weekly_snapshot_reader_NOT_EXPORTED.js");
const {projectFutureServerWeek} =
  require("./deda_weekly_receipts_to_standings_NOT_EXPORTED.js");

function block(reason) {
  throw Error("DEDA_STAGE11_VERIFIED_PAIR_BLOCK_" + reason);
}
async function readServerCalendar(db) {
  if (!db || typeof db.doc !== "function" ||
      typeof db.collection !== "function") {
    block("privileged_reader_required");
  }
  const record = await db.doc("deda_weekly_competition_config/current").get();
  if (!record || record.exists !== true ||
      typeof record.data !== "function") {
    block("no_approved_week_calendar");
  }
  const config = record.data();
  if (!config || typeof config !== "object" || Array.isArray(config)) {
    block("invalid_week_calendar");
  }
  return config;
}

/**
 * The request carries only Firebase verified auth/AppCheck; its data MUST
 * be an empty object. Canonical account is looked up on the server.
 *
 * rankerKey is backend-only 32+ bytes, never a client argument or public
 * response field. This intentionally has NO onCall or Cloud Function export.
 */
async function projectVerifiedWeekPairForApp({
  db, request, serverNowMs, rankerKey,
}) {
  if (!Number.isSafeInteger(serverNowMs) || serverNowMs <= 0) {
    block("invalid_server_clock");
  }
  const identity = await resolveFutureVerifiedAccount({
    db, request, serverNowMs,
  });
  const calendar = await readServerCalendar(db);
  const {current,previous} = validateServerCalendar(calendar,serverNowMs);

  // Both weeks must be valid. A failed previous-week read does not partially
  // publish a current-week snapshot, and vice versa.
  const [currentRank,previousRank] = await Promise.all([
    projectFutureServerWeek({
      db, weekConfig:current, serverNowMs, rankerKey, kind:"current",
    }),
    projectFutureServerWeek({
      db, weekConfig:previous, serverNowMs, rankerKey, kind:"previous",
    }),
  ]);
  const viewer = identity.canonicalAccountKey;
  const currentView = verifyAndRedactSnapshot(
    currentRank,current,viewer,serverNowMs,"current");
  const previousView = verifyAndRedactSnapshot(
    previousRank,previous,viewer,serverNowMs,"previous");

  // The Dart decoder already validates all fields again and rejects forged
  // or partial input; never leak accountKey/uid/install/phone in response.
  return Object.freeze({
    readOnly:true,
    source:"future_server_issued_only",
    current:currentView,
    previous:previousView,
  });
}
module.exports = Object.freeze({projectVerifiedWeekPairForApp});
