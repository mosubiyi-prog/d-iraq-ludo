"use strict";

// Stage56: PRIVATE GM personal-wallet midnight refill — NO DEPLOY.
// Agreed rule: top up to 1,000,000 at the next 00:00 Asia/Baghdad,
// not every rolling 24 hours. Never exceed cap or touch donation pool.
// The existing GM million is unproven TEST credit (Stage55). Release
// remains prohibited without independent owner/provenance approval.
const {createHash}=require("node:crypto");
const MAX=1000000,ZONE="Asia/Baghdad";
const UID=/^[A-Za-z0-9_-]{1,160}$/;
const KEY=/^[A-Za-z0-9_-]{4,160}$/;
const ORIGINAL=/^@DEDA-[A-Z0-9]{6}$/;
const ISO_DAY=/^20[0-9]{2}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$/;
const sha=x=>createHash("sha256").update(x,"utf8").digest("hex");
const row=s=>s.exists?s.data()||{}:{};
function stop(code="failed-precondition"){
  const error=new Error("deda-stage56-midnight-refill-protected");
  error.code=code;throw error;
}
function validDay(day){
  if(typeof day!=="string"||!ISO_DAY.test(day))stop();
  const d=new Date(day+"T00:00:00Z");
  if(!Number.isFinite(d.getTime())||d.toISOString().slice(0,10)!==day)stop();
  return day;
}
function baghdadDay(now){
  const d=now instanceof Date?now:new Date(now);
  if(!Number.isFinite(d.getTime()))stop("invalid-argument");
  const parts=new Intl.DateTimeFormat("en-US",{
    timeZone:ZONE,year:"numeric",month:"2-digit",day:"2-digit",
  }).formatToParts(d);
  const value=k=>parts.find(p=>p.type===k)?.value;
  return validDay([value("year"),value("month"),value("day")].join("-"));
}

// Caller must be trusted server; uid is from Firebase Auth or a vetted
// scheduler approval, never client-supplied accountKey or wallet amount.
// Independent approval is in a separate SERVER-ONLY document because
// older GM wallet Firestore rules permitted client edits.
async function refillGMPersonalToMillion(db,{uid,now=new Date()}={}){
  if(!db||typeof db.runTransaction!=="function")stop("unavailable");
  if(typeof uid!=="string"||!UID.test(uid))stop("unauthenticated");
  const today=baghdadDay(now);
  return db.runTransaction(async tx=>{
    const userRef=db.collection("users").doc(uid);
    const sessionRef=db.collection("deda_sessions").doc(uid);
    const [us,ss]=await Promise.all([tx.get(userRef),tx.get(sessionRef)]);
    const user=row(us),session=row(ss),key=user.accountKey,orig=user.sharePersonalId;
    if(!us.exists||!ss.exists||
       typeof key!=="string"||!KEY.test(key)||
       typeof orig!=="string"||!ORIGINAL.test(orig)||
       session.uid!==uid||session.accountKey!==key)stop("permission-denied");
    const shareRef=db.collection("deda_share_ids").doc(orig);
    const entryRef=db.collection("admin_entry_access").doc(key);
    const adminRef=db.collection("admins").doc(uid);
    const walletRef=db.collection("deda_gm_personal_diamond_wallets").doc(key);
    const approvalRef=db.collection("deda_gm_personal_refill_approvals").doc(sha(key));
    const [sh,en,ad,wa,ap]=await Promise.all([
      tx.get(shareRef),tx.get(entryRef),tx.get(adminRef),
      tx.get(walletRef),tx.get(approvalRef),
    ]);
    const share=row(sh),entry=row(en),admin=row(ad),wallet=row(wa),approval=row(ap);
    if(!sh.exists||share.kind!=="personal"||share.active!==true||
       share.publicId!==orig||typeof share.ownerUid!=="string"||
       !UID.test(share.ownerUid)||
       !en.exists||entry.accountKey!==key||entry.active!==true||
       entry.status!=="active"||entry.allowedRole!=="general_manager"||
       entry.accessType!=="general_manager_gateway"||
       !ad.exists||admin.role!=="general_manager"||
       admin.active!==true||admin.status!=="active")stop("permission-denied");
    const registered=await tx.get(db.collection("users").doc(share.ownerUid));
    if(!registered.exists||row(registered).accountKey!==key)stop("permission-denied");
    if(!wa.exists||!ap.exists||wallet.accountKey!==key||
       wallet.initialBalance!==MAX||
       approval.accountKey!==key||approval.originalId!==orig||
       approval.approved!==true||approval.status!=="active"||
       approval.ownerApprovedMidnightRefill!==true||
       approval.serverAuditedMintProvenance!==true||
       approval.walletType!=="gm_personal_test"||
       approval.capDiamonds!==MAX)stop();
    const anchor=validDay(approval.refillAnchorBaghdadDay);
    const previous=wallet.lastDailyRefillBaghdadDay==null?
      anchor:validDay(wallet.lastDailyRefillBaghdadDay);
    const balance=wallet.balance;
    if(!Number.isSafeInteger(balance)||balance<0||balance>MAX||
       anchor>today||previous<anchor||previous>today)stop();
    if(previous===today){
      return Object.freeze({
        serverConfirmed:true,alreadyRefilledToday:true,
        baghdadDay:today,diamondsRestored:0,balance,
        capDiamonds:MAX,testWalletOnly:true,
      });
    }
    const restored=MAX-balance;
    tx.update(walletRef,{
      balance:MAX,lastDailyRefillBaghdadDay:today,
      lastDailyRefillAmount:restored,lastDailyRefillAt:new Date(now),
    });
    return Object.freeze({
      serverConfirmed:true,alreadyRefilledToday:false,
      baghdadDay:today,diamondsRestored:restored,balance:MAX,
      capDiamonds:MAX,testWalletOnly:true,
    });
  },{maxAttempts:7});
}

// Scheduled at Baghdad midnight; includes only separately approved managers.
// Avoids scanning or changing customers, friends, or donation pool.
async function refillApprovedAtMidnight(db,{now=new Date(),maxAccounts=10}={}){
  if(!db||typeof db.collection!=="function"||
     !Number.isInteger(maxAccounts)||maxAccounts<1||maxAccounts>25)stop();
  const approvals=await db.collection("deda_gm_personal_refill_approvals")
    .where("approved","==",true).where("status","==","active")
    .limit(maxAccounts+1).get();
  if(approvals.size>maxAccounts)stop("resource-exhausted");
  const outcomes=[];
  for(const entry of approvals.docs){
    const record=entry.data();
    if(record.ownerApprovedMidnightRefill!==true||
       record.serverAuditedMintProvenance!==true||
       !UID.test(record.lastVerifiedGmUid||""))stop();
    outcomes.push(await refillGMPersonalToMillion(db,{
      uid:record.lastVerifiedGmUid,now,
    }));
  }
  return Object.freeze(outcomes);
}
function buildStage56MidnightSchedule({onSchedule,db,enabled=false}={}){
  if(typeof onSchedule!=="function"||!db)stop("unavailable");
  return onSchedule({
    schedule:"0 0 * * *",timeZone:ZONE,
    timeoutSeconds:120,retryCount:0,
  },async()=>{
    if(!enabled)return {skipped:true,reason:"owner-release-not-approved"};
    return refillApprovedAtMidnight(db);
  });
}
module.exports={MAX,baghdadDay,refillGMPersonalToMillion,
  refillApprovedAtMidnight,buildStage56MidnightSchedule};
