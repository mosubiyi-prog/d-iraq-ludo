"use strict";

/**
 * Owner approved November 7, 2026: one 100m TOTAL administrative gift budget,
 * preserving previously spent diamonds and existing individual manager wallets.
 * Funding selected currently-used manager login = existingBalance + 99m.
 * This is a one-time server-only GitHub Actions job, NOT a callable/mobile API.
 * The two extant "general_manager" admin records share one adminId; select
 * ONLY the uniquely recently used account, and fail closed on any ambiguity.
 */
const {createHash} = require("node:crypto");
const admin = require("firebase-admin");
const {allocateApprovedManagerCompensation,OLD_CAP,NEW_CAP,ADDITION} =
  require("./deda_gm_admin_compensation_100m_server_only_100439.js");

const PROJECT="deda-25b88";
const SCOPE="gm_admin_compensation_only";
const MAX_RECENT_HOURS=24;
const MIN_OTHER_STALE_HOURS=72;

function stop(reason) {
  const err=new Error("SAFE_STOP_GM100M_OWNER_ALLOCATION_"+reason);
  err.code="failed-precondition";throw err;
}
function dateOf(value) {
  if(!value || typeof value.toDate!=="function") return null;
  const date=value.toDate();
  return date instanceof Date && Number.isFinite(date.getTime())?date:null;
}
function hoursSince(value,now) {
  const date=dateOf(value);
  if(!date)return Number.POSITIVE_INFINITY;
  const delta=(now.getTime()-date.getTime())/3600000;
  return delta>=0?delta:Number.POSITIVE_INFINITY;
}
function only2(list) {
  if(list.length!==2)stop("EXACTLY_TWO_CURRENT_ADMIN_SESSIONS_REQUIRED");
  const [a,b]=list.map(s=>s.data());
  if(typeof a.adminId!=="string" || a.adminId.length<4 ||
     a.adminId!==b.adminId)stop("OWNER_ADMIN_IDENTIFIER_IS_NOT_UNIQUE");
}
function checkOldWallet(snap,uid) {
  const d=snap.exists?snap.data()||{}:{};
  if(!snap.exists || d.adminUid!==uid ||
     d.initialBalance!==OLD_CAP || !Number.isSafeInteger(d.balance) ||
     d.balance<0 || d.balance>OLD_CAP)stop("ORIGINAL_ADMIN_WALLET_NOT_VERIFIED");
  return d;
}

async function main() {
  if(process.env.DEDA_100439_OWNER_APPROVED_GM100M_FUNDS!=="YES")
    stop("EXPLICIT_OWNER_SCOPE_NOT_APPROVED");
  const text=process.env.DEDA_SERVICE_ACCOUNT ||
    process.env.DEDA_FALLBACK_ACCOUNT;
  if(!text)stop("NO_SERVICE_ACCOUNT");
  const account=JSON.parse(text);
  if(account.type!=="service_account" || account.project_id!==PROJECT)
    stop("FIREBASE_PROJECT_OR_SERVICE_ACCOUNT_INVALID");
  admin.initializeApp({credential:admin.credential.cert(account),
    projectId:PROJECT});
  const db=admin.firestore();
  const now=new Date();
  const all=await db.collection("admins").where("role","==","general_manager")
    .limit(10).get();
  const active=all.docs.filter(s=>{
    const d=s.data()||{};
    return d.active===true && d.status==="active";
  });
  only2(active);
  const eligible=active.filter(s=>{
    const d=s.data();
    return hoursSince(d.lastSeenAt,now)<MAX_RECENT_HOURS &&
      hoursSince(d.lastLoginAt,now)<MAX_RECENT_HOURS &&
      d.mustChangePassword!==true;
  });
  if(eligible.length!==1)stop("CURRENT_ACTIVE_MANAGER_NOT_UNIQUE");
  const chosen=eligible[0];
  const other=active.find(s=>s.id!==chosen.id);
  if(!other || hoursSince(other.data().lastSeenAt,now)<MIN_OTHER_STALE_HOURS ||
     hoursSince(other.data().lastLoginAt,now)<MIN_OTHER_STALE_HOURS)
    stop("SECOND_MANAGER_SESSION_NOT_PROVEN_STALE");

  const chosenWalletRef=db.collection("deda_admin_diamond_wallets").doc(chosen.id);
  const otherWalletRef=db.collection("deda_admin_diamond_wallets").doc(other.id);
  const [wallet,otherWallet]=await Promise.all([
    chosenWalletRef.get(),otherWalletRef.get()]);
  const before=checkOldWallet(wallet,chosen.id);
  const untouched=checkOldWallet(otherWallet,other.id);
  console.log("PREALLOC_OWNER_ADMIN_ID_CHECK", "one-current-login-one-stale-login");
  console.log("PREALLOC_SELECTED_GM_WALLET_OLD_BALANCE",before.balance);
  console.log("PREALLOC_OTHER_ADMIN_WALLET_OLD_BALANCE",untouched.balance);
  console.log("PREALLOC_ADDITIONAL_99M_DIAMONDS_OWNER_APPROVED",ADDITION);

  // Approval and immutable receipt are server-only collections. No app user
  // can create or modify either doc under existing live Firestore rules.
  const approvalRef=db.collection("deda_gm_admin_compensation_approvals")
    .doc(chosen.id);
  const auditRef=db.collection("deda_gm_admin_compensation_allocations")
    .doc(chosen.id);
  await db.runTransaction(async tx=>{
    const [existingApproval,existingAudit,currentWallet,currentAdmin]=
      await Promise.all([tx.get(approvalRef),tx.get(auditRef),
        tx.get(chosenWalletRef),tx.get(chosen.ref)]);
    if(!currentAdmin.exists || currentAdmin.data().role!=="general_manager" ||
       currentAdmin.data().active!==true ||
       currentAdmin.data().status!=="active")
      stop("MANAGER_ROLE_ROTATED_BEFORE_APPROVAL");
    const fresh=currentAdmin.data();
    if(hoursSince(fresh.lastSeenAt,now)>=MAX_RECENT_HOURS ||
       hoursSince(fresh.lastLoginAt,now)>=MAX_RECENT_HOURS)
      stop("MANAGER_SESSION_EXPIRED_BEFORE_APPROVAL");
    if(existingAudit.exists) {
      const prior=existingAudit.data();
      if(!prior || prior.addDiamonds!==ADDITION ||
         prior.toCapDiamonds!==NEW_CAP)stop("PREEXISTING_AUDIT_MISMATCH");
      return;
    }
    checkOldWallet(currentWallet,chosen.id);
    if(existingApproval.exists) {
      const a=existingApproval.data();
      if(!a || a.adminUid!==chosen.id || a.ownerApproved!==true ||
         a.status!=="approved" || a.scope!==SCOPE ||
         a.addDiamonds!==ADDITION || a.toCapDiamonds!==NEW_CAP)
        stop("UNEXPECTED_PRIOR_APPROVAL");
      return;
    }
    tx.create(approvalRef,{
      adminUid:chosen.id,scope:SCOPE,
      ownerApproved:true,provenanceReviewed:true,status:"approved",
      fromCapDiamonds:OLD_CAP,toCapDiamonds:NEW_CAP,
      addDiamonds:ADDITION,approvedBy:"DEDA_OWNER_2026_11_07",
      approvedAt:now,
      ownerVerifiedBy:"unique-recent-manager-and-original-one-million-wallet",
    });
  });
  const result=await allocateApprovedManagerCompensation(db,{
    uid:chosen.id,now:new Date()});
  if(!result.serverProofOnly || result.capDiamonds!==NEW_CAP)
    stop("FUNDING_TRANSACTION_NOT_SERVER_CONFIRMED");

  // Server readback. One, and ONLY ONE, administrative wallet was funded.
  const [readback,audit,otherAgain]=await Promise.all([
    chosenWalletRef.get(),auditRef.get(),otherWalletRef.get()]);
  const updated=readback.data()||{};
  const entry=audit.data()||{};
  const unchanged=otherAgain.data()||{};
  if(!audit.exists || updated.initialBalance!==NEW_CAP ||
     updated.balance!==result.balance || updated.adminUid!==chosen.id ||
     entry.addDiamonds!==ADDITION || entry.toCapDiamonds!==NEW_CAP ||
     entry.balanceAfter!==updated.balance ||
     unchanged.balance!==untouched.balance ||
     unchanged.initialBalance!==OLD_CAP)
    stop("CRITICAL_FUNDING_READBACK_OR_OTHER_WALLET_MISMATCH");
  console.log("SUCCESS_GM100M_ADMIN_GIFT_WALLET_FUNDED_ON_CURRENT_MANAGER",
    updated.balance);
  console.log("SUCCESS_ALLOCATED_ONCE",result.diamondsAdded,
    "other_manager_untouched",unchanged.balance);
  console.log("PASS_NO_USER_BALANCES_NO_PERSONAL_GM_WALLET_NO_APK_NO_PLAY");
  await admin.app().delete();
}
main().catch(e=>{
  // Only local static denial labels may be shown, never credentials,
  // Firebase SDK errors, account UIDs, accountKeys or PII.
  const safe=typeof e?.message==="string" &&
    (e.message.startsWith("SAFE_STOP_GM100M_OWNER_ALLOCATION_") ||
     e.message.startsWith("gm-compensation-100m-denied:"))
    ? e.message : (e?.code||"unknown");
  console.error("SAFE_STOP_GM100M_ALLOCATION",safe);
  process.exitCode=2;
});
