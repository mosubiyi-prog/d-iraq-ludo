"use strict";

const {randomInt} = require("node:crypto");
const {Timestamp, FieldValue} = require("firebase-admin/firestore");
const {decide} = require("./deda_pin_auto_recovery_policy.js");

function normalizeName(value) {
  return String(value || "").trim().replace(/\s+/g," ").toLocaleLowerCase("ar");
}

/**
 * Backend-only replacement of the existing manual recovery transaction.
 * The existing random 48-hex installation secret is verified against the
 * account's SERVER-STORED trustedInstallIds. A phone/name alone NEVER resets
 * anybody's PIN. Fresh/untrusted phones continue with the manual flow.
 *
 * No SMS and no added user-facing form. DEDA already watches the recovery
 * request document and displays its new recoveryPin to requesterUid only.
 */
async function autoRecoverForgottenPin(firestore, {
  requestId, nowMs=Date.now(),
}) {
  if (!requestId || typeof requestId !== "string") {
    return {outcome:"invalid-request-id"};
  }
  return firestore.runTransaction(async (tx)=>{
    const reqRef=firestore.collection("recovery_requests").doc(requestId);
    const settingsRef=firestore.collection("deda_automation_settings")
        .doc("pin_auto_recovery");
    const [reqSnap,settingSnap]=await Promise.all([
      tx.get(reqRef),tx.get(settingsRef),
    ]);
    const req=reqSnap.data();
    const setting=settingSnap.data();
    if (!reqSnap.exists || !settingSnap.exists || setting.enabled!==true) {
      return {outcome:"manual-off-or-missing"};
    }
    const key=String(req.accountKey || "").trim();
    const uid=String(req.requesterUid || "").trim();
    const install=String(req.requesterInstallId || "").trim();
    if (!/^\d{10,15}$/.test(key) ||
        !/^([a-zA-Z0-9_-]{6,128})$/.test(uid) ||
        !/^[a-f0-9]{48}$/.test(install)) {
      return {outcome:"manual-bad-identifiers"};
    }
    const directoryRef=firestore.collection("deda_account_directory").doc(key);
    const profileRef=firestore.collection("deda_account_profiles").doc(key);
    const credentialRef=firestore.collection("deda_credentials").doc(key);
    const limitRef=firestore.collection("deda_recovery_auto_limit").doc(key);
    const auditRef=firestore.collection("admin_automation_audit")
        .doc("pin_"+requestId);
    const [directorySnap,profileSnap,credentialSnap,limitSnap]=
      await Promise.all([
        tx.get(directoryRef),tx.get(profileRef),
        tx.get(credentialRef),tx.get(limitRef),
      ]);
    const profile=profileSnap.data()||{};
    const directory=directorySnap.data()||{};
    const credential=credentialSnap.data()||{};
    const last=limitSnap.data()||{};
    const matched=directory.active === true &&
      credential.active === true &&
      credential.accountKey === key &&
      Array.isArray(profile.trustedInstallIds) &&
      profile.trustedInstallIds.includes(install) &&
      normalizeName(profile.name) === normalizeName(req.fullName);
    const proof=matched?{
      valid:true,uid,accountKey:key,revoked:false,
      kind:"trusted-install-secret-verified-by-server",
    }:null;
    const lastMs=last.issuedAt&&typeof last.issuedAt.toMillis==="function" ?
      last.issuedAt.toMillis():NaN;
    const oneAttempt= !Number.isFinite(lastMs) ||
      nowMs-lastMs >= 60*60*1000 ? 1:2;
    const res=decide({
      request:{...req,requestId},setting,ready:true,
      serverNow:Timestamp.fromMillis(nowMs),
      serverProof:proof,attemptCountLastHour:oneAttempt,
      latestRequestId:requestId,
    });
    if (!res.eligible) {
      return {outcome:"manual-review",reason:res.reason};
    }

    // A newly issued PIN must differ from the current credential.
    let newPin;
    do {
      newPin = String(randomInt(100000,1000000));
    } while (newPin === String(credential.pin || ""));
    const timestamp=FieldValue.serverTimestamp();
    // All three changes happen as one transaction. No full account
    // takeover from arbitrary number/name knowledge.
    tx.update(credentialRef,{
      pin:newPin,updatedAt:timestamp,
      recoveryUpdatedBy:"deda-auto-trusted-device",
    });
    tx.update(reqRef,{
      status:"ready",recoveryPin:newPin,
      recoveryPinExpiresAt:Timestamp.fromMillis(nowMs+30*60*1000),
      approvedBy:"deda-auto-trusted-device",approvedAt:timestamp,
      updatedAt:timestamp,autoIssued:true,
    });
    tx.set(limitRef,{
      issuedAt:Timestamp.fromMillis(nowMs),
      requestId,requesterUid:uid,
    });
    tx.set(auditRef,{
      action:"trusted_device_pin_auto_reissue",
      sourceCollection:"recovery_requests",sourceId:requestId,
      accountKey:key,requesterUid:uid,createdAt:timestamp,
      // NEVER LOG THE PIN
    });
    return {outcome:"issued",requestId};
  },{maxAttempts:5});
}

module.exports={autoRecoverForgottenPin};
