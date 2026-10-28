"use strict";
/**
 * Stage49 — separate authenticated UID / account / app identity BINDING.
 *
 * PRIVATE FIRESTORE EMULATOR ONLY; NOT exported from functions/index.js.
 * Original deda_sessions.installId and deda_account_profiles.trustedInstallIds
 * are CLIENT WRITABLE (confirmed Stage48 with actual-live-derived Firestore
 * rules). Neither is server-authenticated device attestation.
 *
 * This ADDITIONAL server-HMAC/privileged-namespace binding must be read in
 * the SAME transaction as the Stage46 signed original-task award, and matches
 * the actual authenticated Firebase UID and App Check appId passed to a
 * privileged backend endpoint, NOT client-supplied account/install/version.
 *
 * THE BELOW certificate issuer is an emulator ADMIN-SEEDED FIXTURE: it does
 * NOT verify real phone identity, actual App Check, mobile integrity,
 * prior old phone claims, revoked old APKs or genuine Firebase Auth.
 * This is a testable contract, not deployable account protection.
 */
const crypto=require("node:crypto");
const {PROJECT}=require("./deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const ROOT="deda_weekly_stage49_private_server_uid_bindings";
const ISSUER="stage49_backend_identity_binding_FIXTURE_ONLY";
const UID=/^[A-Za-z0-9_-]{1,128}$/;
const ACCOUNT=/^[0-9]{10,16}$/;
const MIGRATION=/^[A-Za-z0-9_-]{20,80}$/;
const APP=/^test_app_check_fixture$/;
function fail(code){throw Error("DEDA_STAGE49_IDENTITY_BLOCK_"+code);}
function ms(v){return Number.isSafeInteger(v)&&v>=0;}
function local(db,secret){
  if(process.env.GCLOUD_PROJECT!==PROJECT||
     !process.env.FIRESTORE_EMULATOR_HOST||
     !db||typeof db.doc!=="function"||
     !Buffer.isBuffer(secret)||secret.length<32)
    fail("private_emulator_only");
}
function bindingPath(uid){
  if(!UID.test(uid||""))fail("invalid_uid");
  return ROOT+"/"+uid;
}
function payload({uid,accountKey,migrationId,appId,issuedAtMs,
  expiresAtMs,approvalSequence}){
  if(!UID.test(uid||"")||!ACCOUNT.test(accountKey||"")||
     !MIGRATION.test(migrationId||"")||
     !APP.test(appId||"")||!ms(issuedAtMs)||!ms(expiresAtMs)||
     issuedAtMs>=expiresAtMs||
     !Number.isSafeInteger(approvalSequence)||approvalSequence<1)
    fail("invalid_backend_identity_binding");
  return Object.freeze({
    format:1,issuer:ISSUER,
    emulatorOnly:true,canAuthorizeProduction:false,
    uid,accountKey,migrationId,appId,
    issuedAtMs,expiresAtMs,approvalSequence,
    state:"active",
    deviceHardwareVerified:false,
    oldApkRevocationVerified:false,
  });
}
function sign(secret,p){
  return crypto.createHmac("sha256",secret)
    .update("STAGE49_PRIVATE_UID_BOUND_APPROVAL_V1\n")
    .update(JSON.stringify(p)).digest("hex");
}
function checkStored(stored,ctx,secret){
  if(!stored||Object.keys(stored).length!==2||
     !stored.payload||typeof stored.payload!=="object"||
     !/^[0-9a-f]{64}$/.test(stored.signature||""))
    fail("missing_or_invalid_server_binding");
  const p=stored.payload;
  if(p.state!=="active")fail("server_binding_revoked");
  const canonical=payload({
    uid:ctx.uid,accountKey:ctx.accountKey,
    migrationId:ctx.migrationId,appId:ctx.appId,
    issuedAtMs:p.issuedAtMs,
    expiresAtMs:p.expiresAtMs,
    approvalSequence:p.approvalSequence
  });
  const expected=sign(secret,canonical);
  if(JSON.stringify(p)!==JSON.stringify(canonical)||
     !crypto.timingSafeEqual(Buffer.from(stored.signature,"hex"),
       Buffer.from(expected,"hex"))||
     canonical.issuedAtMs>ctx.now||
     canonical.expiresAtMs<=ctx.now)
    fail("server_binding_signature_or_expiry");
  return Object.freeze({
    uid:ctx.uid,accountKey:ctx.accountKey,
    approvalSequence:canonical.approvalSequence,
    emulatorOnly:true,verifiedPhysicalDevice:false,
    verifiedOldApkCutover:false
  });
}
/** privileged test-only fixture writer; no user-facing callable. */
async function seedPrivateServerUidBindingFixture({db,uid,accountKey,
  migrationId,appId,issuedAtMs,expiresAtMs,approvalSequence,
  backendSecret}){
  local(db,backendSecret);
  const p=payload({uid,accountKey,migrationId,appId,
    issuedAtMs,expiresAtMs,approvalSequence});
  const r=db.doc(bindingPath(uid));
  const stored={payload:p,signature:sign(backendSecret,p)};
  return db.runTransaction(async tx=>{
    const old=await tx.get(r);
    if(old.exists){
      const data=old.data();
      if(data?.signature!==stored.signature||
         JSON.stringify(data.payload)!==JSON.stringify(p))
        fail("existing_approval_cannot_be_silently_replaced");
      return Object.freeze({outcome:"already_bound",emulatorOnly:true});
    }
    tx.create(r,stored);
    return Object.freeze({outcome:"private_uid_bound",emulatorOnly:true});
  });
}
/** Read inside *the same* credit Firestore transaction. The established
 * auth UID / checked App Check appId are transport-side request context;
 * user-controlled session.installId is never an authority for this gate.
 */
async function validateServerUidBindingInTransaction({
  reader,request,accountKey,migrationId,serverNowMs,backendSecret
}){
  if(typeof reader?.get!=="function"||
     process.env.GCLOUD_PROJECT!==PROJECT||
     !process.env.FIRESTORE_EMULATOR_HOST||
     !Buffer.isBuffer(backendSecret)||backendSecret.length<32)
    fail("private_emulator_only");
  const uid=request?.auth?.uid;
  const appId=request?.app?.appId;
  if(!UID.test(uid||"")||!APP.test(appId||"")||
     !ACCOUNT.test(accountKey||"")||
     !MIGRATION.test(migrationId||"")||!ms(serverNowMs)||
     request?.auth?.token?.firebase?.sign_in_provider==="anonymous"||
     request?.data==null||typeof request.data!=="object"||
     Array.isArray(request.data)||Object.keys(request.data).length)
    fail("untrusted_authenticated_request");
  const stored=await reader.get(bindingPath(uid));
  return checkStored(stored,{uid,accountKey,migrationId,
    appId,now:serverNowMs},backendSecret);
}
module.exports=Object.freeze({PROJECT,ROOT,ISSUER,bindingPath,
  seedPrivateServerUidBindingFixture,validateServerUidBindingInTransaction});
