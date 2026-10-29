"use strict";
/*
 * Read-only weekly top-10 API. Hard requirement: an independently verified,
 * signed active publication must exist. This file NEVER synthesizes standings
 * from legacy local task points, XP totals, UID guesses or device claims.
 *
 * Publication issuer is deliberately NOT part of this release. Until full
 * original-task source proofs, old APK writer fencing, and owner approval
 * exist, the callable only denies with a generic pending response.
 */
const {createHmac, timingSafeEqual} = require("node:crypto");
const ACCOUNT = /^[0-9]{8,15}$/;
const UID = /^[A-Za-z0-9_-]{6,128}$/;
const PART = /^[A-Za-z0-9_-]{16,90}$/;
const NAME = /^[^\x00-\x1f\x7f@]{2,60}$/;
const PUBLIC = /^@DEDA-[A-Z0-9]{4,12}$/;
const HEX = /^[a-f0-9]{64}$/;
const MAX_AGE_MS = 10 * 60 * 1000;
const WEEK_MS = 7 * 24 * 3600 * 1000;
const WEEK_SCORED_MS = WEEK_MS - 6 * 3600 * 1000;
class WeeklyNotReady extends Error {
  constructor() {super("verified-weekly-source-not-ready"); this.name = "WeeklyNotReady";}
}
const block = () => {throw new WeeklyNotReady();};
const value = s => s.exists ? s.data() : null;
const validInt = (n) => Number.isSafeInteger(n) && n >= 0;
const owned = (o, key) => Object.prototype.hasOwnProperty.call(o, key);
function checkSecret(secret) {
  if (typeof secret !== "string" || Buffer.byteLength(secret, "utf8") < 32) {
    throw Error("DEDA_WEEKLY_READER_SECRET_UNAVAILABLE");
  }
}
function serverSeal(secret, publication) {
  checkSecret(secret);
  return createHmac("sha256", secret)
    .update("DEDA_APPROVED_WEEKLY_STANDINGS_READ_V1\n")
    .update(JSON.stringify([
      publication.schema, publication.issuer, publication.issuedAtMs,
      publication.sourceVerified, publication.oldApkWriterFenced,
      publication.canonicalAccountProofsVerified, publication.payoutsAllowed,
      publication.current, publication.previous,
    ])).digest("hex");
}
function viewerParticipantId(secret, accountKey) {
  return "leader-participant-" + createHmac("sha256", secret)
    .update("DEDA_WEEKLY_ACCOUNT|" + accountKey)
    .digest("base64url").slice(0,30);
}
function validateWeek(raw, expectedStatus) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw) ||
      raw.status !== expectedStatus ||
      typeof raw.weekId !== "string" ||
      !/^[A-Za-z0-9_-]{8,80}$/.test(raw.weekId) ||
      !validInt(raw.openedAtMs) || !validInt(raw.closeAtMs) ||
      !validInt(raw.nextOpenMs) ||
      raw.closeAtMs - raw.openedAtMs !== WEEK_SCORED_MS ||
      raw.nextOpenMs - raw.closeAtMs !== 6 * 3600 * 1000 ||
      !Array.isArray(raw.rows) || raw.rows.length > 10) block();
  const seen = new Set(), publicIds = new Set();
  const rows = [];
  for (const [i, row] of raw.rows.entries()) {
    if (!row || typeof row !== "object" || Array.isArray(row) ||
        row.place !== i + 1 ||
        !PART.test(row.participantId || "") ||
        !PUBLIC.test(row.activePublicId || "") ||
        !NAME.test(row.displayName || "") ||
        /\b0[0-9]{10}\b/.test(row.displayName) ||
        /\S+@\S+/.test(row.displayName) ||
        !validInt(row.weeklyPoints) || row.weeklyPoints === 0 ||
        row.weeklyPoints % 20 !== 0 ||
        !validInt(row.verifiedTaskCompletions) ||
        row.verifiedTaskCompletions !== row.weeklyPoints / 20 ||
        row.weeklyPoints > 56 * 20 ||
        row.diamondsIfFinalWinner !== (i === 0 ? 150 :
          i === 1 ? 100 : i === 2 ? 50 : 10) ||
        owned(row, "accountKey") || owned(row, "authUid") ||
        owned(row, "phone") || owned(row, "diamondBalance") ||
        owned(row, "publicAppearance") ||
        !seen.add(row.participantId) ||
        !publicIds.add(row.activePublicId)) block();
    rows.push({
      place: row.place, participantId: row.participantId,
      displayName: row.displayName, activePublicId: row.activePublicId,
      weeklyPoints: row.weeklyPoints,
      verifiedTaskCompletions: row.verifiedTaskCompletions,
      diamondsIfFinalWinner: row.diamondsIfFinalWinner,
    });
  }
  return {weekId: raw.weekId, rows};
}
function makePayload(publication, accountKey, secret, nowMs) {
  const current = validateWeek(publication.current, "live");
  const previous = validateWeek(publication.previous, "closed");
  if (current.weekId === previous.weekId ||
      publication.previous.nextOpenMs !== publication.current.openedAtMs ||
      nowMs < publication.current.openedAtMs ||
      nowMs >= publication.current.nextOpenMs ||
      nowMs - publication.issuedAtMs > MAX_AGE_MS ||
      nowMs < publication.issuedAtMs) block();
  const viewer = viewerParticipantId(secret, accountKey);
  const decorate = (week, status, remainingMs) => {
    const viewerRow = week.rows.find(r => r.participantId === viewer);
    return {
      verified: true, status, rewardsCredited: false,
      weekId: week.weekId, remainingMs, rows: week.rows,
      viewerParticipantId: viewerRow ? viewer : null,
      viewerPlace: viewerRow ? viewerRow.place : null,
    };
  };
  return {
    source: "future_server_issued_only", readOnly: true,
    current: decorate(current, "live",
      Math.max(0, publication.current.closeAtMs - nowMs)),
    previous: decorate(previous, "closed", 0),
  };
}
async function readVerifiedWeeklyStandings({request, db, auth, secret, nowMs = Date.now()}) {
  checkSecret(secret);
  const uid = request?.auth?.uid;
  const data = request?.data;
  if (!db || !auth || !validInt(nowMs) ||
      typeof uid !== "string" || !UID.test(uid) ||
      request?.auth?.token?.firebase?.sign_in_provider !== "anonymous" ||
      typeof request?.app?.appId !== "string" || !request.app.appId ||
      !data || typeof data !== "object" || Array.isArray(data) ||
      Object.keys(data).length !== 1 || !owned(data, "accountKey") ||
      typeof data.accountKey !== "string" || !ACCOUNT.test(data.accountKey)) block();
  let user;
  try {user = await auth.getUser(uid);} catch (_) {block();}
  if (!user || user.uid !== uid || user.disabled || user.email ||
      (Array.isArray(user.providerData) && user.providerData.length)) block();
  const key = data.accountKey;
  try {
    // Read-only Firestore transaction ensures all identity/publication checks
    // refer to the same consistent server snapshot, never a client cache.
    return await db.runTransaction(async tx => {
      const [bindingSnap, directorySnap, publicationSnap] = await Promise.all([
        tx.get(db.doc("deda_secure_account_bindings/" + uid)),
        tx.get(db.doc("deda_account_directory/" + key)),
        tx.get(db.doc("deda_weekly_approved_publication/active")),
      ]);
      const binding = value(bindingSnap);
      const directory = value(directorySnap);
      const pub = value(publicationSnap);
      if (!binding || binding.uid !== uid ||
          binding.accountKey !== key ||
          binding.status !== "PIN_VERIFIED_HOLD" ||
          binding.canRestoreAssets !== false ||
          binding.canMigrate !== false ||
          !directory || directory.accountKey !== key ||
          directory.active !== true ||
          !pub || pub.schema !== 1 ||
          pub.issuer !== "deda-weekly-reviewed-publisher-v1" ||
          pub.sourceVerified !== true ||
          pub.oldApkWriterFenced !== true ||
          pub.canonicalAccountProofsVerified !== true ||
          pub.payoutsAllowed !== false ||
          !validInt(pub.issuedAtMs) ||
          !HEX.test(pub.signature || "")) block();
      const expected = serverSeal(secret, pub);
      if (!timingSafeEqual(Buffer.from(pub.signature, "hex"),
        Buffer.from(expected, "hex"))) block();
      return makePayload(pub, key, secret, nowMs);
    }, {maxAttempts: 5, readOnly: true});
  } catch (error) {
    if (error instanceof WeeklyNotReady) throw error;
    throw Error("DEDA_WEEKLY_READ_BACKEND_UNAVAILABLE");
  }
}
module.exports = {readVerifiedWeeklyStandings, WeeklyNotReady,
  serverSeal, viewerParticipantId, makePayload, MAX_AGE_MS};
