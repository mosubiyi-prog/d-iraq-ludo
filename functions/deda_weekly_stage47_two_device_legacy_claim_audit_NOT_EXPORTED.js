"use strict";
/**
 * Stage47 — actual ORIGINAL local-archive evidence from TWO phones.
 *
 * Every source is UNTRUSTED account-local SharedPreferences, even when
 * perfectly matching across two devices. The ONLY allowed result is a
 * PRIVATE MANUAL-REVIEW HOLD (NEVER an XP/coin grant or approved migration).
 * It detects different +5 task point award / +20 XP claim history / +10
 * social coin snapshots, disappearing historical claims, truncated
 * histories and unsettled purchased items. It never merges or overwrites.
 *
 * Real Firestore Emulator ONLY. NOT EXPORTED in functions/index.js.
 * No real account, original wallet, diamonds, monthly/prize code or APK.
 */
const {createHmac}=require("node:crypto");
const {assessLegacyEvidence,hasDuplicateJsonKeys}=require(
  "../tools/app_stability/progress_archive/legacy-assessment.cjs");
const {PROJECT,dayInIraq}=require(
  "./deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const ACCOUNT=/^[0-9]{10,16}$/;
const CAPTURE=/^[A-Za-z0-9_-]{20,80}$/;
const TASK=/^daily-task\|20\d{2}-\d\d-\d\d\|[A-Za-z0-9_-]{2,80}$/;
const ROOT="deda_weekly_stage47_private_two_device_legacy_audit_HOLD_ONLY";
const ISSUER="stage47_server_read_two_original_local_archives_UNTRUSTED";
const MAX_JSON=200000;
function fail(label){throw Error("DEDA_STAGE47_LEGACY_AUDIT_BLOCK_"+label);}
function safeInt(n){return Number.isSafeInteger(n)&&n>=0;}
function emu(db,secret){
  if(process.env.GCLOUD_PROJECT!==PROJECT||
     !process.env.FIRESTORE_EMULATOR_HOST||
     !db||typeof db.runTransaction!=="function"||
     !Buffer.isBuffer(secret)||secret.length<32)
    fail("private_emulator_only");
}
function exactObject(obj,keys,label){
  if(!obj||typeof obj!=="object"||Array.isArray(obj)||
     Object.keys(obj).length!==keys.length||
     !keys.every(k=>Object.hasOwn(obj,k)))fail(label);
}
function parseRaw(raw,account,captureId){
  const a=assessLegacyEvidence(raw,account,captureId);
  // Parse original archive payloads only; NEVER use local values as authority.
  const parsed={};
  for(const k of ["taskPoints","socialCoinsAndXp","earnedDiamonds"]){
    const text=raw.records[k];
    if(typeof text!=="string"||text.length>MAX_JSON||
       hasDuplicateJsonKeys(text))fail("missing_or_duplicate_original_"+k);
    try{parsed[k]=JSON.parse(text);}
    catch(_){fail("invalid_original_"+k);}
  }
  const p=parsed.taskPoints,s=parsed.socialCoinsAndXp,
    d=parsed.earnedDiamonds;
  if(p.version!==1||!p.awards||typeof p.awards!=="object"||
     Array.isArray(p.awards)||!Array.isArray(p.ledger)||
     !p.completions||typeof p.completions!=="object"||
     !Array.isArray(s.taskClaims)||!safeInt(s.coins)||
     !safeInt(s.xp)||!safeInt(d.balance))
    fail("unsupported_or_corrupt_original_wallet");
  if(p.ledger.length>=600||s.taskClaims.length>=180)
    fail("truncated_original_history_requires_manual_capture");
  const awards=new Map();
  for(const [id,value] of Object.entries(p.awards)){
    if(!value||typeof value!=="object"||Array.isArray(value)||
       !Number.isSafeInteger(value.points))
      fail("invalid_task_points_award");
    if(id.startsWith("task|")){
      const key=id.slice(5);
      if(!TASK.test(key)||awards.has(key))fail("bad_original_task_id");
      if(value.points!==5)fail("nonstandard_task_reward_needs_review");
      awards.set(key,value.points);
    }
  }
  const claims=new Set();
  for(const id of s.taskClaims){
    if(typeof id!=="string"||!TASK.test(id)||claims.has(id))
      fail("duplicate_or_invalid_original_social_claim");
    claims.add(id);
  }
  // A matched task key is evidence of ORIGINAL local claims, not an
  // independently server-certified grant or a complete phone history.
  const taskIds=new Set([...awards.keys(),...claims]);
  const gaps=[...taskIds].filter(id=>!awards.has(id)||!claims.has(id));
  const issueSet=new Set(a.issues);
  if(gaps.length)issueSet.add("same_device_task_award_social_claim_mismatch");
  // Deterministic sorting allows independent reviewer audits to be replayed.
  return Object.freeze({
    accountKey:account,captureId,installId:raw.installId,
    evidenceDigest:a.evidenceDigest,
    claims:claims,awards:awards,issues:[...issueSet].sort(),
    originalBalances:a.observedBalances,
    taskIds:Object.freeze([...taskIds].sort()),
  });
}
function recordTag(secret,part,text){
  return createHmac("sha256",secret)
    .update("DEDA-STAGE47-PRIVATE-REPORT|"+part+"|"+text)
    .digest("hex");
}
function compareTwoOriginalCaptures({
  accountKey,firstCaptureId,firstRaw,secondCaptureId,secondRaw,
  targetDayId,backendAuditKey
}){
  if(!ACCOUNT.test(accountKey||"")||
     !CAPTURE.test(firstCaptureId||"")||
     !CAPTURE.test(secondCaptureId||"")||
     firstCaptureId===secondCaptureId||
     typeof targetDayId!=="string"||
     !/^20\d{2}-\d\d-\d\d$/.test(targetDayId)||
     !Buffer.isBuffer(backendAuditKey)||backendAuditKey.length<32)
    fail("canonical_account_or_review_target");
  const a=parseRaw(firstRaw,accountKey,firstCaptureId);
  const b=parseRaw(secondRaw,accountKey,secondCaptureId);
  if(!a.installId||!b.installId||a.installId===b.installId||
     a.evidenceDigest===b.evidenceDigest)
    fail("two_independent_original_installs_required");
  const task="daily-task|"+targetDayId+"|share_personal_location";
  if(!TASK.test(task))fail("target_day_not_valid");
  const allTaskIds=[...new Set([...a.taskIds,...b.taskIds])].sort();
  const conflicts=[];
  for(const id of allTaskIds){
    const pa=a.awards.has(id),pb=b.awards.has(id),
      ca=a.claims.has(id),cb=b.claims.has(id);
    if(pa!==pb||ca!==cb){
      conflicts.push({taskRef:recordTag(backendAuditKey,"task",id),
        reason:"between_device_history_mismatch"});
    }
    if(pa!==ca||pb!==cb){
      conflicts.push({taskRef:recordTag(backendAuditKey,"task",id),
        reason:"within_device_points_social_mismatch"});
    }
  }
  for(const unit of ["points","coins","xp","earnedDiamonds"]){
    const left=a.originalBalances[unit],right=b.originalBalances[unit];
    if(!safeInt(left)||!safeInt(right))
      fail("incomplete_original_balances_"+unit);
    if(left!==right)
      conflicts.push({unit,reason:"different_untrusted_device_balance"});
  }
  const reasons=new Set([
    "original_local_data_never_proves_independent_server_grant",
    "real_old_apk_server_cutover_not_verified",
    "all_pending_purchases_and_gifts_not_server_reconciled",
    ...a.issues,...b.issues
  ]);
  if(conflicts.length)reasons.add("two_device_original_snapshot_conflict");
  const leftHasTask=a.awards.has(task)||a.claims.has(task);
  const rightHasTask=b.awards.has(task)||b.claims.has(task);
  if(leftHasTask||rightHasTask)
    reasons.add("target_task_seen_in_at_least_one_local_archive");
  else
    reasons.add("target_absence_in_truncated_local_window_cannot_prove_not_paid");
  const evidenceDigests=[a.evidenceDigest,b.evidenceDigest].sort();
  const report={
    schema:1,issuer:ISSUER,emulatorOnly:true,
    canAuthorizeProduction:false,
    decision:"HOLD_FOR_INDEPENDENT_SERVER_REVIEW",
    canIssueServerClaim:false,canApproveMigration:false,
    canApplyXp:false,canCreditDiamonds:false,
    comparedDeviceCount:2,
    accountToken:recordTag(backendAuditKey,"account",accountKey),
    targetTaskToken:recordTag(backendAuditKey,"task",task),
    targetDayId,
    bothOriginalDevicesHaveTask:leftHasTask&&rightHasTask,
    neitherOriginalDeviceHasTask:!leftHasTask&&!rightHasTask,
    conflictCount:conflicts.length,
    conflicts:Object.freeze(conflicts),
    reasons:Object.freeze([...reasons].sort()),
    evidenceToken:recordTag(backendAuditKey,"pair",evidenceDigests.join("|")),
  };
  return Object.freeze(report);
}
/** PRIVATE read-only Firestore original captures + one new HOLD audit record.
 * Never alter any original capture, local/user wallet, existing migration,
 * real XP or prize ledger. Report is keyed by HMAC and replayable.
 */
async function auditTwoPhoneCapturesOnEmulator({
  db,accountKey,firstCaptureId,secondCaptureId,targetDayId,
  backendAuditKey
}){
  emu(db,backendAuditKey);
  if(!ACCOUNT.test(accountKey||"")||!CAPTURE.test(firstCaptureId||"")||
     !CAPTURE.test(secondCaptureId||"")||
     firstCaptureId===secondCaptureId)fail("invalid_capture_refs");
  const base="deda_progress_evidence/"+accountKey+"/captures/";
  const [f,s]=await Promise.all([
    db.doc(base+firstCaptureId).get(),
    db.doc(base+secondCaptureId).get(),
  ]);
  if(!f.exists||!s.exists)fail("missing_original_device_capture");
  const report=compareTwoOriginalCaptures({
    accountKey,firstCaptureId,firstRaw:f.data(),
    secondCaptureId,secondRaw:s.data(),
    targetDayId,backendAuditKey
  });
  const reportKey=recordTag(backendAuditKey,"report",
    accountKey+"|"+targetDayId);
  const out=db.doc(ROOT+"/"+reportKey);
  return db.runTransaction(async tx=>{
    // Re-read source INSIDE transaction so a competing capture change
    // cannot be approved by a stale previous check.
    const [one,two,previous]=await Promise.all([
      tx.get(f.ref),tx.get(s.ref),tx.get(out)
    ]);
    if(!one.exists||!two.exists)
      fail("original_capture_changed_or_missing");
    const fresh=compareTwoOriginalCaptures({
      accountKey,firstCaptureId,firstRaw:one.data(),
      secondCaptureId,secondRaw:two.data(),
      targetDayId,backendAuditKey
    });
    if(JSON.stringify(report)!==JSON.stringify(fresh))
      fail("evidence_changed_during_review");
    if(previous.exists){
      if(JSON.stringify(previous.data())!==JSON.stringify(fresh))
        fail("prior_report_conflict_preserve_old");
      return Object.freeze({outcome:"already_held",
        ...fresh,stillUnapproved:true});
    }
    tx.create(out,fresh);
    return Object.freeze({outcome:"held_for_review",
      ...fresh,stillUnapproved:true});
  });
}
module.exports=Object.freeze({
  PROJECT,ROOT,ISSUER,
  compareTwoOriginalCaptures,auditTwoPhoneCapturesOnEmulator
});
