"use strict";
/**
 * DEDA weekly leaderboard stage 6: READ-ONLY SERVER CONTRACT / NOT EXPORTED.
 *
 * Never publish this module as a callable or accept arbitrary client-supplied
 * record data. Firebase onCall request.auth and request.app are trusted ONLY
 * after the real runtime has verified auth + enforced App Check.
 *
 * The attestation and XP receipt collections below DO NOT EXIST as approved
 * live backend issuers; the stage-6 fixture tests model the REQUIRED future
 * server-only documents. Their existence/fields alone NEVER prove safety:
 * only a future admin-owned issuer + Firestore rules denying ALL client writes
 * can make them authoritative. No XP/diamond credit path exists here.
 *
 * DO NOT change existing user's UID, PIN, phone, XP, level, account, wallet,
 * task claims, installer trust, or original share ID.
 */
const crypto = require("node:crypto");
const {verifiedWeek} = require("./deda_weekly_leaderboard_shadow_policy.js");

const ACCOUNT = /^[0-9]{10,16}$/;
const UID = /^[A-Za-z0-9_-]{1,128}$/;
const INSTALL = /^[A-Za-z0-9_-]{1,128}$/;
const TASK = /^[A-Za-z0-9_:-]{1,100}$/;
const DAY = /^20\d{2}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/;
const XP = 20;
const ISSUER = "privileged_server_only_task_xp_issuer_v1";
const MAX_AGE_MS = 4*60*60*1000;

function block(code) { throw new Error("WEEKLY_READ_ONLY_BLOCK_" + code); }
function safe(v,re,label) {
  if (typeof v !== "string" || !re.test(v)) block(label);
  return v;
}
function validInt(v) { return Number.isSafeInteger(v) && v >= 0; }
function same(a,b) { return typeof a === "string" && a.length > 0 && a === b; }
function dayInBaghdad(ms) {
  if (!validInt(ms)) block("clock");
  const items = new Intl.DateTimeFormat("en-US",{
    timeZone:"Asia/Baghdad",year:"numeric",month:"2-digit",day:"2-digit",
  }).formatToParts(new Date(ms));
  const x=Object.fromEntries(items.map(p=>[p.type,p.value]));
  return x.year+"-"+x.month+"-"+x.day;
}
function opaqueReceiptId({accountKey,dayId,taskId}) {
  return crypto.createHash("sha256")
      .update(accountKey+"|"+dayId+"|"+taskId, "utf8")
      .digest("hex");
}
async function requiredServerDocument(db,path) {
  if (!db || typeof db.doc !== "function") block("trusted_store_missing");
  const ref=db.doc(path);
  if (!ref || typeof ref.get !== "function") block("server_read_missing");
  const snap=await ref.get();
  if (!snap || snap.exists !== true ||
      typeof snap.data !== "function") block("verified_document_missing");
  const data=snap.data();
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    block("invalid_server_document");
  }
  return data;
}

/**
 * No accountKey, public ID, UID, score, or prize may be accepted from
 * request.data. The account is derived from authenticated UID's server
 * session + profile + FRESH, privileged, future attestation ONLY.
 * Default: blocks everyone until server-owned attestation issuer is built.
 */
async function resolveFutureVerifiedAccount({db,request,serverNowMs}) {
  if (!validInt(serverNowMs)) block("server_clock_required");
  const uid=safe(request?.auth?.uid,UID,"authenticated_uid_required");
  if (typeof request?.app?.appId !== "string" ||
      request.app.appId.length < 4) block("app_check_required");
  if (request.data != null &&
      (typeof request.data !== "object" || Array.isArray(request.data) ||
       Object.keys(request.data).length !== 0)) block("client_input_forbidden");

  const user=await requiredServerDocument(db,"users/"+uid);
  const session=await requiredServerDocument(db,"deda_sessions/"+uid);
  const accountKey=safe(user.accountKey,ACCOUNT,"account_unverified");
  const install=safe(session.installId,INSTALL,"install_unverified");
  if (!same(session.uid,uid) ||
      !same(session.accountKey,accountKey) ||
      (user.uid != null && user.uid !== uid)) {
    block("session_account_mismatch");
  }
  const profile=await requiredServerDocument(
      db,"deda_account_profiles/"+accountKey);
  if (profile.accountKey !== accountKey ||
      !Array.isArray(profile.trustedInstallIds) ||
      !profile.trustedInstallIds.includes(install)) {
    block("untrusted_install_or_profile");
  }
  const attest=await requiredServerDocument(
      db,"deda_weekly_identity_attestations/"+uid);
  if (attest.issuer !== "privileged_identity_verifier_v1" ||
      attest.state !== "verified" ||
      attest.uid !== uid || attest.accountKey !== accountKey ||
      attest.installId !== install ||
      !validInt(attest.issuedAtMs) ||
      !validInt(attest.expiresAtMs) ||
      attest.issuedAtMs > serverNowMs ||
      attest.expiresAtMs <= serverNowMs ||
      serverNowMs - attest.issuedAtMs > MAX_AGE_MS) {
    block("fresh_privileged_attestation_required");
  }
  // Return only to authorized future server ranking adapter; never pass the
  // phone-based accountKey to public leaderboard or logs.
  return Object.freeze({
    canonicalAccountKey:accountKey, authenticatedUid:uid,
    checkedAtMs:serverNowMs, readOnly:true,
  });
}

/**
 * Future trusted document schema for server-earned XP event.
 * No live document producer exists yet. This is NOT an issuer and not an
 * authorization/payout endpoint. Server-only write rules REQUIRED.
 */
async function inspectFutureServerXpReceipt({
  db,identity,weekConfig,taskId,dayId,serverNowMs,
}) {
  if (!identity || identity.readOnly !== true ||
      !validInt(serverNowMs) ||
      !validInt(identity.checkedAtMs) ||
      identity.checkedAtMs !== serverNowMs) {
    block("identity_expired");
  }
  const week=verifiedWeek(weekConfig);
  const accountKey=safe(identity.canonicalAccountKey,ACCOUNT,"invalid_identity");
  const task=safe(taskId,TASK,"invalid_task");
  const day=safe(dayId,DAY,"invalid_day");
  if (serverNowMs < week.startMs) block("week_not_started");
  const fingerprint=opaqueReceiptId({accountKey,dayId:day,taskId:task});
  const path="deda_weekly_xp_receipts/"+week.weekId+"/events/"+fingerprint;
  const receipt=await requiredServerDocument(db,path);
  if (receipt.issuer !== ISSUER ||
      receipt.status !== "final_award_committed" ||
      receipt.accountKey !== accountKey ||
      receipt.taskId !== task ||
      receipt.dayId !== day ||
      receipt.weekId !== week.weekId ||
      receipt.receiptId !== fingerprint ||
      receipt.taskPointsAwarded !== true ||
      receipt.levelXpApplied !== true ||
      receipt.levelXpAmount !== XP ||
      !validInt(receipt.verifiedAtMs) ||
      receipt.verifiedAtMs < week.startMs ||
      receipt.verifiedAtMs >= week.endMs ||
      receipt.verifiedAtMs > serverNowMs ||
      dayInBaghdad(receipt.verifiedAtMs) !== day) {
    block("invalid_xp_receipt");
  }
  return Object.freeze({
    weekId:week.weekId, accountKey,
    taskId:task, iraqDay:day, receiptId:fingerprint,
    levelXpEarned:XP, serverVerifiedAtMs:receipt.verifiedAtMs,
    readOnly:true,
  });
}

module.exports=Object.freeze({
  resolveFutureVerifiedAccount, inspectFutureServerXpReceipt,
  opaqueReceiptId,
});
