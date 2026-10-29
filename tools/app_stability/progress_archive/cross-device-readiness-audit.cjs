"use strict";
/**
 * PRIVATE READ-ONLY server-ledger preflight for a second DEDA phone.
 * Intentionally NOT exported from functions/index.js or reachable by a client.
 * Original receipts and local captures are NOT payment, entitlement or
 * account-ownership authority. Never issue rewards or update wallets here.
 * This audit is limited to synthetic emulator data until the old APK is fenced,
 * production authentication/App Check is independently proven, and all
 * purchases and premium IDs have authoritative settlement records.
 */
const core=require("./reconcile-core.cjs");
const ACCOUNT=/^[0-9]{10,16}$/;
const UID=/^[A-Za-z0-9_-]{8,128}$/;
const HEX=/^[0-9a-f]{64}$/;
const fail=code=>{throw new Error("DEDA_READONLY_RESTORE_AUDIT_"+code);};
const safeGet=(reader,path)=>reader.get(path);
function validOptions(options){
 if(!options||Object.keys(options).sort().join(",")!==
    ["accountKey","newUid","oldUid","reader"].sort().join(",")||
    process.env.GCLOUD_PROJECT!=="demo-deda-restore-readiness"||
    process.env.DEDA_RESTORE_AUDIT_EMULATOR_ONLY!=="true"||
    process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
    !options.reader||typeof options.reader.get!=="function")
   fail("EMULATOR_ONLY");
 const {accountKey,oldUid,newUid}=options;
 if(!ACCOUNT.test(accountKey||"")||!UID.test(oldUid||"")||
    !UID.test(newUid||"")||oldUid===newUid)
   fail("INVALID_ACCOUNT_OR_DEVICE_UID");
}
function result(checks,blockers){
 // Never return account numbers, UIDs, balances, receipts, installed IDs
 // or privileged approval fields in this read-only diagnostic.
 return Object.freeze({
  stage:"SERVER_LEDGER_RECONCILIATION_READONLY_EMULATOR",
  status:"HOLD",
  emulatorOnly:true,
  ...Object.fromEntries(Object.entries(checks).map(([k,v])=>[k,v===true])),
  blockers:Object.freeze([...new Set(blockers)]),
  canRestoreAccount:false,canRestoreXp:false,canRestoreDiamonds:false,
  canRestoreFrames:false,canRestorePremiumId:false,canIssueLeagueGift:false,
  canWriteVerifiedProgress:false,canSettlePurchase:false,
  oldApkWriterFenced:false,productionAuthAttested:false,
  productionAppCheckVerified:false,
 });
}
async function auditCrossDeviceServerReadiness(options){
 validOptions(options);
 const {reader,accountKey,oldUid,newUid}=options;
 const get=p=>safeGet(reader,p);
 const [directory,profile,oldUser,newUser,migration,progress]=
   await Promise.all([
    get("deda_account_directory/"+accountKey),
    get("deda_account_profiles/"+accountKey),
    get("users/"+oldUid),
    get("users/"+newUid),
    get("deda_progress_migrations/"+accountKey),
    get("deda_verified_progress/"+accountKey),
   ]);
 const blockers=[];
 const accountChain=!!directory&&directory.accountKey===accountKey&&
   directory.active===true&&directory.createdUid===oldUid&&
   !!profile&&profile.accountKey===accountKey&&
   !!oldUser&&oldUser.accountKey===accountKey&&
   !!newUser&&newUser.accountKey===accountKey;
 if(!accountChain)blockers.push("ORIGINAL_ACCOUNT_UID_CHAIN_UNVERIFIED");
 let verifiedState=null;
 try{verifiedState=core.parseState(progress,accountKey);}
 catch(_){blockers.push("VERIFIED_SERVER_PROGRESS_MISSING_OR_INVALID");}
 const migrationReviewed=!!migration&&migration.accountKey===accountKey&&
   migration.phase==="cutover-complete"&&
   typeof migration.migrationId==="string"&&
   typeof migration.settlementId==="string"&&
   HEX.test(migration.baselineEventKey||"")&&
   HEX.test(migration.evidenceDigest||"");
 if(!migrationReviewed)blockers.push("REVIEWED_SERVER_MIGRATION_UNVERIFIED");
 let baselineLedgerConsistent=false;
 if(verifiedState&&migrationReviewed&&
    verifiedState.initializedBy===migration.baselineEventKey){
   const key=migration.baselineEventKey;
   const [source,applied]=await Promise.all([
     get("deda_progress_receipts/"+accountKey+"/events/"+key),
     get("deda_verified_progress/"+accountKey+"/events/"+key),
   ]);
   try{
     const receipt=core.parseReceipt(source,accountKey);
     const appliedReceipt=core.parseReceipt(applied?.receipt,accountKey);
     baselineLedgerConsistent=receipt.kind==="baseline"&&
       receipt.source==="legacy-baseline-v1"&&
       core.eventKey(receipt)===key&&core.eventKey(appliedReceipt)===key&&
       core.sameEvent(receipt,appliedReceipt)&&
       applied.accountKey===accountKey&&applied.eventKey===key&&
       Number.isSafeInteger(applied.appliedVersion)&&
       applied.appliedVersion>=1&&
       applied.appliedVersion<=verifiedState.version;
   }catch(_){baselineLedgerConsistent=false;}
 }
 if(!baselineLedgerConsistent)
   blockers.push("INDEPENDENT_BASELINE_RECEIPT_CHAIN_UNVERIFIED");
 // These must remain mandatory even when every synthetic progress fixture
 // is internally consistent. A server state is not a frame purchase receipt,
 // an old-APK write fence, or proof of physical-device account ownership.
 blockers.push("PRODUCTION_AUTH_APP_CHECK_NOT_ATTESTED");
 blockers.push("OLD_APK_FINANCIAL_WRITER_NOT_SERVER_FENCED");
 blockers.push("PAYMENT_GIFT_FRAME_AND_PREMIUM_ID_PROOFS_NOT_SETTLED");
 return result({
   originalAccountChainConsistent:accountChain,
   parsedServerProgressState:verifiedState!==null,
   reviewedMigrationPresent:migrationReviewed,
   baselineLedgerConsistent,
 },blockers);
}
module.exports={auditCrossDeviceServerReadiness};
