"use strict";

// DEDA «جمال التطبيق المتكاملة» Stage26.
// READ-ONLY status of an OFFLINE DEMO signed-ad receipt.
// NOT OFFICIAL GOOGLE ADMOB SSV; no exports from functions/index.js.
// The user's existing rewarded-ad/SharedPreferences balance is NEVER read,
// changed, auto-imported, or replaced. No production wallet is accessed.
const {createHash} = require("node:crypto");
const DEMO_PROJECT="demo-deda-stage22-ssv-fakeprovider";
const UID=/^[A-Za-z0-9_-]{1,160}$/;
const ACCOUNT=/^[A-Za-z0-9_-]{4,160}$/;
const ORIGINAL=/^@DEDA-[A-Z0-9]{6}$/;
const TOKEN=/^[A-Za-z0-9_-]{32}$/;
const TX=/^[A-Za-z0-9_-]{8,180}$/;
const PROVENANCE="STAGE22_STAGED_ECDSA_OFFLINE_KEY_TEST_NOT_REAL_ADMOB";

function deny(code,message){
  const e=new Error(message);e.code=code;throw e;
}
function snapData(doc){return doc.exists?doc.data()||{}:{};}
function hash(value){
  return createHash("sha256").update(value,"utf8").digest("hex");
}
function requireOfflineOnly(db){
  if(!/^(127[.]0[.]0[.]1|localhost):[0-9]+$/.test(
      process.env.FIRESTORE_EMULATOR_HOST||"") ||
      process.env.GCLOUD_PROJECT!==DEMO_PROJECT ||
      !db || typeof db.runTransaction!=="function") {
    deny("unavailable","STAGE26_NOT_A_PRODUCTION_GOOGLE_ADMOB_PROOF");
  }
}
function show(status,diamonds=0) {
  return Object.freeze({
    status,
    demoOnly:true,
    officialGoogleAdMobSSVVerified:false,
    serverVerifiedPurchasableDiamonds:0,
    demoReceiptDiamonds:diamonds,
    existingLocalAdBalancePreserved:true,
    existingProfileBalanceOverridden:false,
    historicalLocalAdsAutomaticallyMigrated:false,
    canPurchase:false,
    realRewardPaymentEnabled:false,
  });
}

/**
 * Backend only: uid from authenticated request context; nonce must be
 * opaque and originally minted by the server, no wallet/accountKey input.
 * This reads exactly the current account's pending challenge+receipt, and
 * cannot turn locally displayed historic diamonds into spendable funds.
 */
async function getOfflineRewardStatus(db,{uid,customData,trustedNowMs}={}){
  requireOfflineOnly(db);
  if(typeof uid!=="string" || !UID.test(uid))
    deny("unauthenticated","current-authenticated-uid-required");
  if(typeof customData!=="string" || !TOKEN.test(customData))
    deny("invalid-argument","server-created-nonce-required");
  if(!Number.isSafeInteger(trustedNowMs) || trustedNowMs<=0)
    deny("invalid-argument","trusted-server-clock-required");
  return db.runTransaction(async tx=>{
    const userRef=db.collection("users").doc(uid);
    const sessionRef=db.collection("deda_sessions").doc(uid);
    const [userSnap,sessionSnap]=await Promise.all([
      tx.get(userRef),tx.get(sessionRef),
    ]);
    const user=snapData(userSnap),session=snapData(sessionSnap);
    const key=user.accountKey,original=user.sharePersonalId;
    if(!userSnap.exists || !sessionSnap.exists ||
       typeof key!=="string" || !ACCOUNT.test(key) ||
       typeof original!=="string" || !ORIGINAL.test(original) ||
       session.uid!==uid || session.accountKey!==key) {
      deny("permission-denied","verified-current-account-session-required");
    }
    const shareSnap=await tx.get(db.collection("deda_share_ids")
      .doc(original));
    const share=snapData(shareSnap);
    if(!shareSnap.exists || share.kind!=="personal" ||
        share.active!==true || share.publicId!==original ||
        typeof share.ownerUid!=="string" || !UID.test(share.ownerUid)) {
      deny("permission-denied","original-personal-deda-id-required");
    }
    const ownerSnap=await tx.get(db.collection("users").doc(share.ownerUid));
    if(!ownerSnap.exists || snapData(ownerSnap).accountKey!==key) {
      deny("permission-denied","original-deda-identity-not-verified");
    }

    const nonceDigest=hash(customData);
    const pendingSnap=await tx.get(db.collection("deda_stage22_ssv_pending")
      .doc(nonceDigest));
    const pending=snapData(pendingSnap);
    if(!pendingSnap.exists || pending.accountKey!==key ||
        pending.originalId!==original ||
        pending.nonceDigest!==nonceDigest ||
        typeof pending.adUnitId!=="string" ||
        !/^ca-app-pub-[0-9]{16}\/[0-9]{10}$/.test(pending.adUnitId) ||
        pending.rewardDiamonds!==3 ||
        !Number.isSafeInteger(pending.createdAtMs) ||
        !Number.isSafeInteger(pending.expiresAtMs) ||
        pending.createdAtMs<=0 ||
        pending.expiresAtMs<=pending.createdAtMs ||
        pending.expiresAtMs-pending.createdAtMs>24*3600000) {
      deny("permission-denied","unknown-or-unauthorized-ad-nonce");
    }
    if(pending.status==="pending") {
      if(pending.transactionId!==undefined)
        deny("failed-precondition","untrusted-pending-claim-state");
      return show(trustedNowMs>pending.expiresAtMs?
        "demo_challenge_expired":"awaiting_offline_demo_callback");
    }
    if(pending.status!=="claimed" ||
        typeof pending.transactionId!=="string" ||
        !TX.test(pending.transactionId)) {
      deny("failed-precondition","invalid-demo-claim-status");
    }

    const receiptRef=db.collection("deda_stage22_ssv_receipts")
      .doc(hash(pending.transactionId));
    const receiptSnap=await tx.get(receiptRef),receipt=snapData(receiptSnap);
    if(!receiptSnap.exists ||
       receipt.transactionId!==pending.transactionId ||
       receipt.nonceDigest!==nonceDigest ||
       receipt.accountKey!==key ||
       receipt.originalId!==original ||
       receipt.adUnitId!==pending.adUnitId ||
       receipt.diamondsAwarded!==3 ||
       receipt.provenance!==PROVENANCE ||
       typeof receipt.providerKeyId!=="string" ||
       !/^[0-9]{1,16}$/.test(receipt.providerKeyId) ||
       !Number.isSafeInteger(receipt.providerTimestampMs)) {
      deny("failed-precondition","missing-or-inconsistent-demo-provider-receipt");
    }
    // A past TEST receipt shows a demo credit, not the current spendable
    // wallet, real Google proof, or a locally rewarded ad conversion.
    return show("offline_demo_receipt_recorded",3);
  },{maxAttempts:5});
}

module.exports={getOfflineRewardStatus};
