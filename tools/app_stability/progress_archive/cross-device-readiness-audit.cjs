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
const {isDeepStrictEqual}=require("node:util");
const {parseMigration,validateSettlement}=require("./migration-gate.cjs");
const {parseDeployment,validateFence,deploymentPath}=
  require("./activate-reviewed-baseline.cjs");
const validId=v=>typeof v==="string"&&/^[A-Za-z0-9_-]{20,80}$/.test(v);
const stamp=v=>v&&Number.isSafeInteger(v.seconds)&&
  Number.isSafeInteger(v.nanoseconds)&&v.nanoseconds>=0&&v.nanoseconds<1000000000;
const ACCOUNT=/^[0-9]{10,16}$/;
const UID=/^[A-Za-z0-9_-]{8,128}$/;
const HEX=/^[0-9a-f]{64}$/;
const fail=code=>{throw new Error("DEDA_READONLY_RESTORE_AUDIT_"+code);};
const safeGet=(reader,path)=>reader.get(path);
function validOptions(options){
 if(!options||Object.keys(options).sort().join(",")!==
    ["accountKey","newUid","oldUid","reader","auth","idToken"].sort().join(",")||
    process.env.GCLOUD_PROJECT!=="demo-deda-restore-readiness"||
    process.env.DEDA_RESTORE_AUDIT_EMULATOR_ONLY!=="true"||
    process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
    !options.reader||typeof options.reader.get!=="function"||
    !options.auth||typeof options.auth.verifyIdToken!=="function"||
    typeof options.auth.getUser!=="function"||
    typeof options.idToken!=="string"||options.idToken.length<16)
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

// Verify the ENTIRE original server progress projection, not merely the
// baseline receipt. The canonical state may otherwise be a forged total even
// when its baseline receipt remains unchanged. Still consistency QA ONLY:
// no event is authoritative without independent server-issued provenance.
async function replayServerLedger(reader,accountKey,expected){
 if(typeof reader.list!=="function")return false;
 const prefix="deda_verified_progress/"+accountKey+"/events";
 const limit=256;
 const rows=await reader.list(prefix,{limit});
 if(!Array.isArray(rows)||rows.length===0||rows.length>=limit||
    rows.length!==expected.version)return false;
 const events=[];
 const usedKeys=new Set(),usedReceipts=new Set(),usedVersions=new Set();
 for(const row of rows){
   if(!row||typeof row.id!=="string"||!HEX.test(row.id)||
      !row.data||typeof row.data!=="object")return false;
   const e=row.data;
   if(e.format!==1||e.accountKey!==accountKey||
      e.eventKey!==row.id||
      !Number.isSafeInteger(e.appliedVersion)||
      e.appliedVersion<1||e.appliedVersion>expected.version||
      typeof e.receiptId!=="string"||!validId(e.receiptId)||
      !stamp(e.createdAt)||!e.afterBalances||
      usedKeys.has(row.id)||usedVersions.has(e.appliedVersion)||
      usedReceipts.has(e.receiptId))return false;
   usedKeys.add(row.id);usedVersions.add(e.appliedVersion);
   usedReceipts.add(e.receiptId);
   events.push(e);
 }
 events.sort((a,b)=>a.appliedVersion-b.appliedVersion);
 let projected=null;
 for(let i=0;i<events.length;i++){
   const e=events[i];
   if(e.appliedVersion!==i+1)return false;
   const canonical=core.parseReceipt(e.receipt,accountKey);
   if(core.eventKey(canonical)!==e.eventKey)return false;
   const independent=core.parseReceipt(
     await reader.get("deda_progress_receipts/"+accountKey+"/events/"+e.receiptId),
     accountKey);
   if(!core.sameEvent(independent,canonical))return false;
   // A second baseline is never a legitimate replay, and spend after an
   // award must retain the original event order and nonnegative balances.
   projected=core.applyEvent(projected,canonical);
   if(!isDeepStrictEqual(projected.balances,e.afterBalances))return false;
 }
 return projected!==null&&
   isDeepStrictEqual(projected.balances,expected.balances)&&
   projected.version===expected.version&&
   projected.initializedBy===expected.initializedBy;
}

async function auditCrossDeviceServerReadiness(options){
 validOptions(options);
 const {reader,accountKey,oldUid,newUid,auth,idToken}=options;
 // Verify the CURRENT authenticated second-device UID with the Admin SDK,
 // rather than trusting a number, anonymous UID or install ID claimed by the
 // new phone. A revoked/disabled or non-anonymous Firebase token is denied
 // BEFORE reading Firestore account records. App Check remains NOT PROVEN.
 let caller,record;
 try{
   caller=await auth.verifyIdToken(idToken,true);
   if(caller?.uid!==newUid||
      caller?.firebase?.sign_in_provider!=="anonymous")
     fail("UNVERIFIED_NEW_DEVICE_AUTH");
   record=await auth.getUser(newUid);
   if(record?.uid!==newUid||record.disabled===true||
      !!record.email||record.providerData?.length>0)
     fail("UNVERIFIED_NEW_DEVICE_AUTH");
 }catch(_){fail("UNVERIFIED_NEW_DEVICE_AUTH");}
 const get=p=>safeGet(reader,p);
 const [directory,profile,oldUser,newUser,migration,progress,
   oldBinding,newBinding]=await Promise.all([
    get("deda_account_directory/"+accountKey),
    get("deda_account_profiles/"+accountKey),
    get("users/"+oldUid),
    get("users/"+newUid),
    get("deda_progress_migrations/"+accountKey),
    get("deda_verified_progress/"+accountKey),
    // These are SERVER-OWNED Stage54 outputs from the authenticated
    // anonymous-Firebase + correct-PIN, account-wide-throttled emulator
    // function. Sessions, users and copied install IDs are client-writable
    // under old rules and are NOT standalone proofs of account ownership.
    get("deda_stage54_private_account_bindings/"+oldUid),
    get("deda_stage54_private_account_bindings/"+newUid),
   ]);
 const blockers=[];
 const accountChain=!!directory&&directory.accountKey===accountKey&&
   directory.active===true&&directory.createdUid===oldUid&&
   !!profile&&profile.accountKey===accountKey&&
   !!oldUser&&oldUser.accountKey===accountKey&&
   !!newUser&&newUser.accountKey===accountKey;
 if(!accountChain)blockers.push("ORIGINAL_ACCOUNT_UID_CHAIN_UNVERIFIED");
 const validBinding=(record,uid)=>!!record&&
   Object.keys(record).sort().join(",")===
     ["uid","accountKey","authProvider","state","emulatorOnly",
      "canMigrate","canGrant","createdAt"].sort().join(",")&&
   record.uid===uid&&record.accountKey===accountKey&&
   record.authProvider==="anonymous"&&
   record.state==="LOCAL_VERIFIED_HOLD_ONLY"&&
   record.emulatorOnly===true&&
   record.canMigrate===false&&record.canGrant===false&&
   stamp(record.createdAt);
 const serverOwnedDualPinBindingConsistent=
   validBinding(oldBinding,oldUid)&&validBinding(newBinding,newUid)&&
   directory?.createdUid===oldUid;
 if(!serverOwnedDualPinBindingConsistent)
   blockers.push("SERVER_OWNED_DUAL_PIN_BINDING_UNVERIFIED");
 let verifiedState=null;
 try{verifiedState=core.parseState(progress,accountKey);}
 catch(_){blockers.push("VERIFIED_SERVER_PROGRESS_MISSING_OR_INVALID");}
 let migrationReviewed=false;
 try {
   const parsed=parseMigration(migration,accountKey);
   migrationReviewed=parsed.phase==="cutover-complete"&&
     HEX.test(parsed.baselineEventKey)&&validId(parsed.settlementId);
 } catch (_) {migrationReviewed=false;}
 if(!migrationReviewed)blockers.push("REVIEWED_SERVER_MIGRATION_UNVERIFIED");
 let baselineLedgerConsistent=false,cutoverRecordsConsistent=false;
 if(verifiedState&&migrationReviewed&&
    verifiedState.initializedBy===migration.baselineEventKey){
   const key=migration.baselineEventKey;
   // Original activation writes a prefixed receipt document, while the
   // applied event marker is keyed by eventKey: never interchange them.
   const receiptId="baseline_"+key,root="deda_progress_migrations/"+accountKey;
   const [source,applied,settlement,activation,resolution,deployment]=
     await Promise.all([
       get("deda_progress_receipts/"+accountKey+"/events/"+receiptId),
       get("deda_verified_progress/"+accountKey+"/events/"+key),
       get(root+"/settlements/"+migration.settlementId),
       get(root+"/activations/"+migration.migrationId),
       get(root+"/settlementReviews/"+migration.settlementId),
       get(deploymentPath),
     ]);
   try {
     const receipt=core.parseReceipt(source,accountKey);
     const appliedReceipt=core.parseReceipt(applied?.receipt,accountKey);
     baselineLedgerConsistent=receipt.kind==="baseline"&&
       receipt.source==="legacy-baseline-v1"&&
       receipt.sourceId==="legacy-review|"+migration.migrationId+"|"+migration.evidenceDigest&&
       core.eventKey(receipt)===key&&core.eventKey(appliedReceipt)===key&&
       core.sameEvent(receipt,appliedReceipt)&&
       applied.format===1&&applied.accountKey===accountKey&&
       applied.eventKey===key&&applied.receiptId===receiptId&&
       applied.appliedVersion===1&&stamp(applied.createdAt)&&
       isDeepStrictEqual(applied.afterBalances,receipt.delta)&&
       verifiedState.version>=1;
   } catch (_) {baselineLedgerConsistent=false;}
   if(baselineLedgerConsistent){
     try {
       validateSettlement(settlement,migration);
       const deploy=parseDeployment(deployment);
       if(!resolution||resolution.format!==1||
          resolution.accountKey!==accountKey||
          resolution.migrationId!==migration.migrationId||
          resolution.settlementId!==migration.settlementId||
          resolution.evidenceDigest!==migration.evidenceDigest||
          resolution.baselineEventKey!==key||
          resolution.status!=="resolved"||
          resolution.decision!=="preserve-reviewed-balances-and-carried-rights"||
          resolution.pendingPurchases!==0||resolution.pendingReservations!==0||
          !validId(resolution.legacyFenceId)||
          !validId(resolution.policyRevision)||
          !HEX.test(resolution.operationReviewDigest||"")||
          !stamp(resolution.createdAt))
         throw Error("unreviewed-settlement");
       const fence=await get(root+"/fences/"+resolution.legacyFenceId);
       validateFence(fence,migration,resolution,deploy);
       if(!activation||activation.format!==1||
          activation.accountKey!==accountKey||
          activation.migrationId!==migration.migrationId||
          activation.settlementId!==migration.settlementId||
          activation.evidenceDigest!==migration.evidenceDigest||
          activation.baselineEventKey!==key||
          activation.receiptId!==receiptId||
          activation.legacyFenceId!==resolution.legacyFenceId||
          activation.operationReviewDigest!==resolution.operationReviewDigest||
          activation.deploymentRevision!==deploy.revision||
          activation.enforcementRevision!==deploy.enforcementRevision||
          activation.policyRevision!==resolution.policyRevision||
          !stamp(activation.createdAt))
         throw Error("activation-chain-incomplete");
       cutoverRecordsConsistent=true;
     }catch(_){cutoverRecordsConsistent=false;}
   }
 }
 if(!baselineLedgerConsistent)
   blockers.push("INDEPENDENT_BASELINE_RECEIPT_CHAIN_UNVERIFIED");
 if(!cutoverRecordsConsistent)
   blockers.push("REVIEWED_CUTOVER_DOCUMENT_CHAIN_INCOMPLETE");
 let fullLedgerReconciled=false;
 if(verifiedState&&baselineLedgerConsistent&&cutoverRecordsConsistent){
   try{fullLedgerReconciled=await replayServerLedger(reader,accountKey,verifiedState);}
   catch(_){fullLedgerReconciled=false;}
 }
 if(!fullLedgerReconciled)
   blockers.push("FULL_SERVER_RECEIPT_REPLAY_UNVERIFIED");
 // These must remain mandatory even when every synthetic progress fixture
 // is internally consistent. A server state is not a frame purchase receipt,
 // an old-APK write fence, or proof of physical-device account ownership.
 blockers.push("PRODUCTION_AUTH_APP_CHECK_NOT_ATTESTED");
 blockers.push("OLD_APK_FINANCIAL_WRITER_NOT_SERVER_FENCED");
 blockers.push("PAYMENT_GIFT_FRAME_AND_PREMIUM_ID_PROOFS_NOT_SETTLED");
 return result({
   originalAccountChainConsistent:accountChain,
   serverOwnedDualPinBindingConsistent,
   parsedServerProgressState:verifiedState!==null,
   reviewedMigrationPresent:migrationReviewed,
   baselineLedgerConsistent,
   cutoverRecordsConsistent,
   fullLedgerReconciled,
 },blockers);
}
module.exports={auditCrossDeviceServerReadiness};
