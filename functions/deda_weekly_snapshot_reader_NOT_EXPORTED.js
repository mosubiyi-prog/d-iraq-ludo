"use strict";

/**
 * Stage7: privacy-limited, read-only weekly standings adapter.
 *
 * NOT a Cloud Function and NOT exported from functions/index.js.
 * The privileged attestation and signed weekly snapshot issuers are STILL
 * MISSING in production. Data in a fake snapshot is NEVER proof that XP was
 * actually earned. DO NOT enable this reader without privileged issuers,
 * authenticated App Check, verified Rules and a server-owned task XP ledger.
 *
 * Reads ONLY server-owned fixture documents; never creates or increments XP,
 * points, diamonds, account balances or Firestore records.
 */
const {
  resolveFutureVerifiedAccount,
} = require("./deda_weekly_owner_receipt_gate_NOT_EXPORTED.js");
const {verifiedWeek} = require("./deda_weekly_leaderboard_shadow_policy.js");

const ISSUER = "privileged_server_only_weekly_ranker_v1";
const CONFIG_ISSUER = "privileged_server_only_week_calendar_v1";
const MAX_PARTICIPANTS = 5000;
const NAME = /^[^\u0000-\u001f\u007f]{1,60}$/u;
const ACCOUNT = /^[0-9]{10,16}$/;
const PUBLIC_ID = /^@DEDA-[A-Z0-9]{5,12}$/;
const TOKEN = /^[A-Za-z0-9_-]{16,90}$/;
const WEEK = /^[A-Za-z0-9_-]{1,80}$/;
const SNAPSHOT_MAX_AGE_MS = 5 * 60 * 1000;
const DEFAULT_REWARDS = Object.freeze([150,100,50,10,10,10,10,10,10,10]);

function deny(reason) { throw Error("DEDA_WEEKLY_STAGE7_BLOCK_" + reason); }
function validInteger(x) { return Number.isSafeInteger(x) && x >= 0; }
function ensureField(v,regex,name) {
  if (typeof v !== "string" || !regex.test(v)) deny(name);
  return v;
}
async function readServer(db,path) {
  if (!db || typeof db.doc !== "function") deny("db");
  const doc = db.doc(path);
  if (!doc || typeof doc.get !== "function") deny("read");
  const snap = await doc.get();
  if (!snap || !snap.exists || typeof snap.data !== "function") {
    deny("missing_"+path.split("/")[0]);
  }
  const value = snap.data();
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    deny("invalid_document");
  }
  return value;
}
function validateServerCalendar(config,nowMs) {
  if (config?.issuer !== CONFIG_ISSUER ||
      !validInteger(nowMs) || !WEEK.test(config?.activeWeekId||"") ||
      !WEEK.test(config?.previousWeekId||"") ||
      config.activeWeekId === config.previousWeekId) {
    deny("unapproved_calendar");
  }
  const current = verifiedWeek({
    weekId: config.activeWeekId,
    startMs:config.activeStartMs, endMs:config.activeEndMs,
  });
  const previous = verifiedWeek({
    weekId: config.previousWeekId,
    startMs:config.previousStartMs, endMs:config.previousEndMs,
  });
  if (previous.endMs !== current.startMs ||
      nowMs < current.startMs || nowMs >= current.endMs) {
    deny("week_boundary");
  }
  return {current,previous};
}
function scrubDisplayName(name) {
  const value = ensureField(name,NAME,"name").trim();
  if (value.length < 2 || /\b0[0-9]{10}\b/.test(value) ||
      /[\r\n]/.test(value) || /@/.test(value)) {
    deny("private_or_invalid_name");
  }
  return value;
}
function verifyAndRedactSnapshot(raw,week,accountKey,nowMs,kind) {
  if (raw?.issuer !== ISSUER || raw.weekId !== week.weekId ||
      raw.state !== (kind==="previous"?"closed":"live") ||
      !validInteger(raw.generatedAtMs) ||
      raw.generatedAtMs < week.startMs ||
      raw.generatedAtMs > nowMs ||
      nowMs-raw.generatedAtMs > SNAPSHOT_MAX_AGE_MS && kind==="current" ||
      !Array.isArray(raw.rows) || raw.rows.length > MAX_PARTICIPANTS) {
    deny("snapshot_provenance");
  }
  const all = [];
  const accounts = new Set();
  const tokens = new Set();
  let last = null;
  for (let i=0;i<raw.rows.length;i++) {
    const row = raw.rows[i];
    if (!row || typeof row !== "object" || Array.isArray(row) ||
        row.place !== i+1 ||
        !ACCOUNT.test(row.accountKey||"") ||
        !TOKEN.test(row.publicCompetitorId||"") ||
        !Number.isSafeInteger(row.earnedLevelXp) ||
        row.earnedLevelXp<=0 || row.earnedLevelXp%20!==0 ||
        !Number.isSafeInteger(row.taskClaims) || row.taskClaims<1 ||
        row.taskClaims!==row.earnedLevelXp/20 ||
        !validInteger(row.lastEarnedAtMs) ||
        row.lastEarnedAtMs<week.startMs || row.lastEarnedAtMs>=week.endMs ||
        row.lastEarnedAtMs>nowMs ||
        !PUBLIC_ID.test(row.activePublicId||"") ||
        !accounts.add(row.accountKey) || !tokens.add(row.publicCompetitorId)) {
      deny("rank_invalid");
    }
    const label = scrubDisplayName(row.displayName);
    const expectedDiamonds = DEFAULT_REWARDS[i]||0;
    if (row.potentialDiamonds!==expectedDiamonds) deny("prize_mismatch");
    if (last && (
      last.earnedLevelXp<row.earnedLevelXp ||
      last.earnedLevelXp===row.earnedLevelXp && (
        last.taskClaims<row.taskClaims ||
        last.taskClaims===row.taskClaims &&
        (last.lastEarnedAtMs>row.lastEarnedAtMs ||
          last.lastEarnedAtMs===row.lastEarnedAtMs &&
          last.accountKey>row.accountKey)))) {
      deny("ordering_mismatch");
    }
    last = row;
    // Public result NEVER carries accountKey, phone, auth UID or install ID.
    all.push(Object.freeze({
      place:row.place,
      participantId:row.publicCompetitorId,
      displayName:label,
      activePublicId:row.activePublicId,
      weeklyPoints:row.earnedLevelXp,
      verifiedTaskCompletions:row.taskClaims,
      diamondsIfFinalWinner:expectedDiamonds,
    }));
  }
  const viewerIndex=raw.rows.findIndex(row=>row.accountKey===accountKey);
  const viewerRow=viewerIndex<0?null:all[viewerIndex];
  const visible=all.slice(0,10);
  if(viewerRow && viewerIndex>=10) visible.push(viewerRow);
  return Object.freeze({
    verified:true,weekId:week.weekId,
    status:kind==="previous"?"closed":"live",
    remainingMs:kind==="previous"?0:Math.max(0,week.endMs-nowMs),
    rows:Object.freeze(visible),
    viewerParticipantId:viewerRow?.participantId||null,
    viewerPlace:viewerRow?.place||null,
    // This flag NEVER implies a prize has actually been disbursed.
    rewardsCredited:false,
  });
}

/**
 * Requires future privileged identity + weekly ranker issuers.
 * No user-submitted week, phone, score, public ID, or account.
 * Fail closed while the future issuers do not exist.
 */
async function readFutureWeeklyStandings({db,request,serverNowMs}) {
  const identity = await resolveFutureVerifiedAccount({
    db,request,serverNowMs,
  });
  const config = await readServer(db,"deda_weekly_competition_config/current");
  const {current,previous}=validateServerCalendar(config,serverNowMs);
  const [cur,prev]=await Promise.all([
    readServer(db,"deda_weekly_standings/"+current.weekId),
    readServer(db,"deda_weekly_standings/"+previous.weekId),
  ]);
  return Object.freeze({
    current:verifyAndRedactSnapshot(cur,current,
      identity.canonicalAccountKey,serverNowMs,"current"),
    previous:verifyAndRedactSnapshot(prev,previous,
      identity.canonicalAccountKey,serverNowMs,"previous"),
    readOnly:true,source:"future_server_issued_only",
  });
}
module.exports=Object.freeze({
  readFutureWeeklyStandings,verifyAndRedactSnapshot,validateServerCalendar,
});
