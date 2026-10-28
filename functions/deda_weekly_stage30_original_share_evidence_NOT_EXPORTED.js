"use strict";

/**
 * Stage30 next proof source: READ-ONLY INSPECTION of the ORIGINAL DEDA
 * deda_location_shares write shape (as authored by DedaBackend.createLocationShare).
 *
 * A future onDocumentCreated handler must use actual deployed Rules and
 * authenticated creation metadata, and must atomically synchronize original
 * +20 level XP before treating a task as final. For now this function ONLY
 * returns a backend-internal candidate from the real source collection, and
 * only in local demo Firestore Emulator. No live export, grant or write.
 */
const {PROJECT,dayInIraq}=
  require("./deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const {verifiedWeek}=
  require("./deda_weekly_leaderboard_shadow_policy.js");

const SOURCE="deda_location_shares";
const ORIGINAL_ID=/^@DEDA-[A-Z0-9]{6}$/;
const ID=/^[A-Za-z0-9]{20}$/;
const ACCOUNT=/^[0-9]{10,16}$/;
const UID=/^[A-Za-z0-9_-]{1,128}$/;
function fail(code){throw Error("DEDA_ORIGINAL_SHARE_TASK_BLOCK_"+code);}
function goodInt(n){return Number.isSafeInteger(n)&&n>=0;}
function requireEmulator(db) {
  if(process.env.GCLOUD_PROJECT!==PROJECT ||
    !process.env.FIRESTORE_EMULATOR_HOST ||
    !db || typeof db.doc!=="function")
    fail("emulator_only_not_a_live_task_proof");
}
async function read(db,path){
  const snap=await db.doc(path).get();
  if(!snap.exists||typeof snap.data!=="function")
    fail("missing_"+path.split("/")[0]);
  const d=snap.data();
  if(!d||typeof d!=="object"||Array.isArray(d))
    fail("invalid_document");
  return d;
}
function ms(v,label){
  const n=v?.toMillis?.();
  if(!goodInt(n))fail("invalid_"+label+"_timestamp");
  return n;
}
async function inspectOriginalDedaPersonalLocationShare({
  db,shareId,weekConfig,serverNowMs,
}){
  requireEmulator(db);
  if(!ID.test(shareId||"")||!goodInt(serverNowMs))
    fail("invalid_request");
  const week=verifiedWeek(weekConfig);
  const data=await read(db,SOURCE+"/"+shareId);
  // Stage30 supports only one real-shaped task. Other types MUST have a
  // separate authoritative verifier; client raw fields are not proof.
  if(data.shareType!=="current"||data.status!=="pending"||
    !UID.test(data.senderUid||"") ||
    !ORIGINAL_ID.test(data.senderPublicId||"") ||
    !ORIGINAL_ID.test(data.recipientPublicId||"") ||
    data.senderPublicId===data.recipientPublicId||
    data.placeId!==""||data.placeName!==""||
    ![15,30,60].includes(data.durationMinutes)||
    !Number.isFinite(data.latitude)||data.latitude < -90||
    data.latitude > 90||
    !Number.isFinite(data.longitude)||data.longitude < -180||
    data.longitude > 180)
    fail("not_a_verified_personal_share_shape");
  const created=ms(data.createdAt,"created");
  const updated=ms(data.updatedAt,"updated");
  const expires=ms(data.expiresAt,"expires");
  if(created!==updated||created>serverNowMs||
    serverNowMs-created>5*60*1000||
    created<week.startMs||created>=week.endMs||
    expires<=created||expires>created+61*60*1000)
    fail("untrusted_or_outdated_share_clock");

  const user=await read(db,"users/"+data.senderUid);
  if(!ACCOUNT.test(user.accountKey||"")||
    user.uid!=null&&user.uid!==data.senderUid||
    user.sharePersonalId!==data.senderPublicId)
    fail("original_account_mismatch");
  const [sender,recipient,session]=await Promise.all([
    read(db,"deda_share_ids/"+data.senderPublicId),
    read(db,"deda_share_ids/"+data.recipientPublicId),
    read(db,"deda_sessions/"+data.senderUid),
  ]);
  if(sender.kind!=="personal"||sender.active!==true||
    sender.ownerUid!==data.senderUid||
    recipient.kind!=="personal"||recipient.active!==true||
    session.uid!==data.senderUid||
    session.accountKey!==user.accountKey||
    typeof session.installId!=="string"||
    session.installId.length===0)
    fail("session_or_share_ownership");
  const profile=await read(db,"deda_account_profiles/"+user.accountKey);
  if(profile.accountKey!==user.accountKey||
    !Array.isArray(profile.trustedInstallIds)||
    !profile.trustedInstallIds.includes(session.installId))
    fail("untrusted_account_install");

  // This is a CANDIDATE, not original +20 XP confirmation.
  // Never send canonical account/UID to Flutter or public leaderboard.
  return Object.freeze({
    privateServerCandidateOnly:true,sourceCollection:SOURCE,
    shareId,canonicalAccountKey:user.accountKey,
    serverEventAtMs:created,serverDayId:dayInIraq(created),
    taskId:"share_personal_location",weekId:week.weekId,
    originalLevelXpApplied:false,verifiedTaskXpReceipt:false,
    allowedToPay:false,
  });
}
module.exports=Object.freeze({SOURCE,inspectOriginalDedaPersonalLocationShare});
