"use strict";
/**
 * DEDA A/B/C — OFFLINE, SOURCE-ONLY, NON-EXPORTED domain readback simulator.
 * NOT wired to functions/index.js or deployed. No Admin SDK, Firebase, I/O,
 * Auth/UID transitions, tokens, balances credited, or ownership changes.
 * Caller data is UNTRUSTED MOCK INPUT, not independent ownership proof.
 * Checks shape / internal consistency only. Every result is HOLD.
 */
const {inspectRoomCandidate, DOMAIN_SOURCES} =
    require("./deda_logical_room_offline_preflight_PRIVATE_NOT_EXPORTED.js");
const MAX_SAFE = Number.MAX_SAFE_INTEGER;
const ID = /^@DEDA-[A-Z0-9]{6}$/;
const ACTIVE_ID = /^@DEDA-[A-Z0-9]{4,12}$/;
const WEEK = /^20\d{2}-\d{2}-\d{2}$/;
const UID = /^[A-Za-z0-9:_-]{6,128}$/;
const LIMIT = 5000;

function result(decision,reason,domains=[]) {
  return Object.freeze({
    decision, reason,
    crossUidReadPermitted:false, crossUidWritePermitted:false,
    loginPermitted:false, createUidPermitted:false,
    createTokenPermitted:false, adminEntryPermitted:false,
    financialGrantPermitted:false, createsReceipt:false,
    overwritesSource:false,
    domains:Object.freeze(domains.map(x=>Object.freeze(x))),
  });
}
function goodUnsigned(n) {
  return Number.isSafeInteger(n) && n>=0 && n<=MAX_SAFE;
}
function checkFriends(rows,originalUidSet) {
  if (rows == null) return "SOURCE_ABSENT_UNKNOWN";
  if (!Array.isArray(rows) || rows.length>LIMIT) return null;
  const seen=new Set();
  for(const row of rows) {
    if (!row || typeof row!=="object" || !UID.test(row.requesterUid||"") ||
        !UID.test(row.recipientUid||"") ||
        row.requesterUid===row.recipientUid ||
        !Array.isArray(row.members) || row.members.length!==2 ||
        row.members[0]===row.members[1] ||
        !row.members.includes(row.requesterUid) ||
        !row.members.includes(row.recipientUid) ||
        !row.members.every(x=>typeof x==="string" && UID.test(x)) ||
        !row.members.some(x=>originalUidSet.has(x)) ||
        row.members.every(x=>originalUidSet.has(x)) ||
        !["accepted","pending","rejected"].includes(row.status)) return null;
    const id=[...row.members].sort().join("__");
    if(row.id!==id || row.pairKey!==id || seen.has(id)) return null;
    seen.add(id);
  }
  return rows.length===0?"SOURCE_EMPTY_HISTORICAL_UNKNOWN":
    "FRIEND_UID_PAIRS_SHAPE_MATCHED_NOT_AUTHORIZED";
}
function checkGifts(rows,originalId) {
  if (rows == null) return "SOURCE_ABSENT_UNKNOWN";
  if (!Array.isArray(rows) || rows.length>LIMIT) return null;
  const seen=new Set();
  for(const row of rows) {
    if(!row || typeof row!=="object" || typeof row.id!=="string" ||
       !/^[A-Za-z0-9_-]{5,160}$/.test(row.id) || seen.has(row.id) ||
       row.targetPublicId!==originalId ||
       !Number.isSafeInteger(row.amount) || row.amount<=0 ||
       (row.sourceType==="weekly_league" &&
          (row.giftId!==row.id ||
           !/^deda-weekly-20\d{2}-\d{2}-\d{2}-DEDA-[A-Z0-9]{6}$/.test(row.id) ||
           !row.id.endsWith("-"+originalId.substring(1)) ||
           !["pending","received","claimed"].includes(row.status) ||
           !goodUnsigned(row.createdAtMs) || row.createdAtMs===0))) return null;
    seen.add(row.id);
  }
  return rows.length===0?"SOURCE_EMPTY_HISTORICAL_UNKNOWN":
    "GIFT_RECEIPTS_SHAPE_MATCHED_NO_REISSUE";
}
function checkWallet(row,originalId) {
  if(row==null)return "SOURCE_ABSENT_UNKNOWN_NOT_ZERO";
  if(!row || typeof row!=="object" || row.publicId!==originalId ||
      !goodUnsigned(row.balance))return null;
  return "GIFT_WALLET_SHAPE_MATCHED_NOT_TOTAL_BALANCE";
}
function checkPremium(row,originalId) {
  if(row==null)return "SOURCE_ABSENT_OWNERSHIP_UNKNOWN";
  if(!row || typeof row!=="object" || row.originalId!==originalId ||
      typeof row.activeId!=="string" || !ACTIVE_ID.test(row.activeId))return null;
  return "DISPLAY_SELECTION_SHAPE_MATCHED_NOT_OWNERSHIP";
}
function checkLeague(a,c,s,originalId,accountKey) {
  if(a==null && c==null && s==null)return "SOURCE_ABSENT_UNKNOWN";
  if(a!=null && (!a || a.publicId!==originalId ||
      a.accountKey!==accountKey))return null;
  if(c!=null && (!c || typeof c.weekId!=="string" ||
      !WEEK.test(c.weekId)))return null;
  if(s!=null && (!c || !s || s.weekId!==c.weekId ||
      s.publicId!==originalId || !goodUnsigned(s.weeklyXp)))return null;
  return "LEAGUE_SOURCE_SHAPE_MATCHED_NOT_AWARD_AUTHORITY";
}
function inspectDomainSources({roomSnapshot,sourceRows,sessionUid}={}) {
  const domains=Object.keys(DOMAIN_SOURCES);
  const room=inspectRoomCandidate({
    snapshot:roomSnapshot,sessionUid,domains,
  });
  if(room.domainPlans.length!==domains.length ||
     room.decision!=="HOLD_FOR_INDEPENDENT_PROOF_AND_SERVER_RULES") {
    return result("HOLD","ROOM_SOURCE_CONFLICT");
  }
  if(!sourceRows || typeof sourceRows!=="object" ||
     Array.isArray(sourceRows))return result("HOLD","INVALID_READBACK_INPUT");
  // Structural comparison only. Mock sourceRows do not confer access rights.
  const originalId=roomSnapshot.originalId;
  const accountKey=roomSnapshot.accountKey;
  const ownerSet=new Set([
    roomSnapshot.route.ownerUid,
    roomSnapshot.directory.createdUid,
    roomSnapshot.social.ownerUid,
  ]);
  const checks={
    friends:checkFriends(sourceRows.friends,ownerSet),
    gifts:checkGifts(sourceRows.gifts,originalId),
    diamonds:checkWallet(sourceRows.giftWallet,originalId),
    premium_id:checkPremium(sourceRows.premium,originalId),
    league:checkLeague(sourceRows.leagueAccount,sourceRows.leagueControl,
      sourceRows.leagueScore,originalId,accountKey),
  };
  if(Object.values(checks).some(x=>x===null)) {
    return result("HOLD","DOMAIN_SOURCE_CONFLICT");
  }
  const statuses=domains.map(domain=>({
    domain,
    status:checks[domain] || (domain==="administration"
      ? "SEPARATE_ADMIN_VERIFICATION_REQUIRED"
      : ["registration","original_id","social_profile"].includes(domain)
      ? "HISTORICAL_SHAPE_MATCHED_NOT_OWNER_PROOF"
      : "ADDITIONAL_SCOPED_SOURCE_REQUIRED"),
    authorization:"NOT_GRANTED",
    sourceWrite:false, sourceUidReassignment:false,
    receiptReissue:false,
  }));
  return result("HOLD_FOR_INDEPENDENT_OWNER_PROOF","READBACK_SHAPE_ONLY",statuses);
}
module.exports={inspectDomainSources};