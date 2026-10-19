"use strict";

/**
 * DEDA «جمال التطبيق المتكاملة» Stage22 — ISOLATED GOOGLE-SSV-SHAPED PROTOTYPE.
 * NOT imported/exported by production functions/index.js. NO real Google
 * public key fetch or network calls, NO real ad or wallet deployment.
 *
 * The ECDSA-signed URL contract MUST be validated against Google's current
 * official AdMob SSV specification before ANY real callback deployment.
 * In CI, a generated EC key pair acts as a FAKE provider to exercise crypto.
 * Only provider-authenticated messages may ever trigger a server-side credit.
 */
const {createHash, randomBytes, verify:verifyEcdsa}=require("node:crypto");

const ACCOUNT=/^[A-Za-z0-9_-]{4,160}$/;
const UID=/^[A-Za-z0-9_-]{1,160}$/;
const ORIGINAL=/^@DEDA-[A-Z0-9]{6}$/;
const TOKEN=/^[A-Za-z0-9_-]{32}$/;
const TRANSACTION=/^[A-Za-z0-9_-]{8,180}$/;
const KEY_ID=/^[0-9]{1,16}$/;
const MAX_BALANCE=1073741824;
const REWARD_DIAMONDS=3;
const MAX_DAILY_ADS=5;
const CLOCK_SKEW_MS=120000;
const PENDING_LIFETIME_MS=24*3600000;
const MAX_RAW_QUERY_LENGTH=4096;
const KNOWN_KEYS=new Set([
  "ad_network","ad_unit","custom_data","key_id","reward_amount",
  "reward_item","signature","timestamp","transaction_id","user_id",
]);
const REQUIRED=[
  "ad_unit","custom_data","reward_amount","reward_item",
  "timestamp","transaction_id","signature","key_id",
];

function stop(code,reason){
  const e=new Error(reason);e.code=code;throw e;
}
function row(s){return s.exists ? s.data()||{} : {};}
function digest(s){return createHash("sha256").update(s,"utf8").digest("hex");}
function capBalance(v){
  if(!Number.isSafeInteger(v)||v<0||v>MAX_BALANCE)
    stop("failed-precondition","untrusted-personal-wallet");
  return v;
}
function iraqDay(ms){
  if(!Number.isSafeInteger(ms)||ms<=0)
    stop("failed-precondition","trusted-server-time-required");
  return new Date(ms+3*3600000).toISOString().slice(0,10);
}
function requireStagedRuntime(db){
  // Stage22 signed callback shape is NOT certified against official Google
  // AdMob SSV yet. Hard stop unless BOTH local emulator and exact demo project.
  // The module must not be reusable against real Firestore by accident.
  if(!process.env.FIRESTORE_EMULATOR_HOST ||
      !/^(127[.]0[.]0[.]1|localhost):[0-9]+$/.test(
        process.env.FIRESTORE_EMULATOR_HOST) ||
      process.env.GCLOUD_PROJECT!=="demo-deda-stage22-ssv-fakeprovider" ||
      !db||typeof db.runTransaction!=="function"){
    stop("unavailable","STAGE22_OFFLINE_ECDSA_EMULATOR_ONLY");
  }
}
function approvedPolicy(policy){
  if(!policy||typeof policy!=="object" ||
      policy.verifiedForProduction!==false ||
      typeof policy.adUnitId!=="string" ||
      !/^ca-app-pub-[0-9]{16}\/[0-9]{10}$/.test(policy.adUnitId) ||
      typeof policy.expectedRewardItem!=="string" ||
      !/^[A-Za-z0-9_-]{1,60}$/.test(policy.expectedRewardItem) ||
      !Number.isSafeInteger(policy.expectedRewardAmount) ||
      policy.expectedRewardAmount<1||policy.expectedRewardAmount>1000 ||
      policy.rewardDiamonds!==REWARD_DIAMONDS) {
    stop("unavailable","owner-reviewed-staged-ad-unit-policy-required");
  }
  return policy;
}
function validPemKeys(pinnedKeyMap){
  if(!pinnedKeyMap||typeof pinnedKeyMap!=="object" ||
      Object.keys(pinnedKeyMap).length<1 ||
      Object.keys(pinnedKeyMap).length>6 ||
      !Object.entries(pinnedKeyMap).every(([id,pem])=>
        KEY_ID.test(id)&&typeof pem==="string"&&
        pem.startsWith("-----BEGIN PUBLIC KEY-----"))) {
    stop("unavailable","trusted-provider-public-keys-required");
  }
}

/**
 * Provisional canonicalization. Verifies RAW query bytes, not a reconstructed
 * or sorted query. Query must terminate signature=<url-safe Base64> & key_id.
 * Public keys MUST come from independently validated Google-managed source;
 * NEVER trust a callback-supplied PEM or remote arbitrary URL.
 */
function verifyProviderSignedCallback(rawQuery,pinnedKeyMap){
  validPemKeys(pinnedKeyMap);
  if(typeof rawQuery!=="string" || rawQuery.length>MAX_RAW_QUERY_LENGTH ||
      rawQuery.length<50 || rawQuery.includes("#") ||
      rawQuery.startsWith("?") ||
      rawQuery.includes("\r")||rawQuery.includes("\n")) {
    stop("permission-denied","invalid-signed-callback-query");
  }
  const match=/^(.+)&signature=([A-Za-z0-9_-]+)&key_id=([0-9]{1,16})$/.exec(rawQuery);
  if(!match) stop("permission-denied","invalid-signed-query-layout");
  const [,message,rawSignature,keyId]=match;
  if(rawSignature.length>1500)
    stop("permission-denied","invalid-signature-length");
  const params=new URLSearchParams(rawQuery);
  const entries=[...params.entries()];
  if(entries.length!==new Set(entries.map(([name])=>name)).size ||
      entries.some(([name,val])=>!KNOWN_KEYS.has(name)||val.length>1024) ||
      REQUIRED.some(name=>params.getAll(name).length!==1)) {
    stop("permission-denied","duplicate-or-unknown-signed-field");
  }
  if(params.get("key_id")!==keyId ||
      params.get("signature")!==rawSignature ||
      !Object.prototype.hasOwnProperty.call(pinnedKeyMap,keyId)) {
    stop("permission-denied","untrusted-provider-signature-key");
  }
  const signature=Buffer.from(rawSignature,"base64url");
  if(signature.length<50||signature.length>128||
      signature.toString("base64url")!==rawSignature) {
    stop("permission-denied","malformed-ecdsa-signature");
  }
  let valid=false;
  try {
    valid=verifyEcdsa("sha256",Buffer.from(message,"utf8"),
      pinnedKeyMap[keyId],signature);
  }catch(_){stop("permission-denied","invalid-pinned-provider-public-key");}
  if(!valid) stop("permission-denied","callback-signature-not-verified");

  const transactionId=params.get("transaction_id");
  const adUnitId=params.get("ad_unit");
  const customData=params.get("custom_data");
  const rewardItem=params.get("reward_item");
  const rewardAmountText=params.get("reward_amount");
  const ts=params.get("timestamp");
  if(!TRANSACTION.test(transactionId||"") ||
      !TOKEN.test(customData||"") ||
      !/^ca-app-pub-[0-9]{16}\/[0-9]{10}$/.test(adUnitId||"") ||
      !/^[A-Za-z0-9_-]{1,60}$/.test(rewardItem||"") ||
      !/^[1-9][0-9]{0,3}$/.test(rewardAmountText||"") ||
      !/^[1-9][0-9]{11,13}$/.test(ts||"")) {
    stop("permission-denied","signed-callback-content-malformed");
  }
  return Object.freeze({
    transactionId,adUnitId,customData,rewardItem,
    rewardAmount:Number(rewardAmountText),signedTimestampMs:Number(ts),
    verifiedProviderKeyId:keyId,
  });
}

/** User callable must supply authUid from request.auth.uid and enforce AppCheck.
 * Do NOT accept a client selected original ID, diamonds or GM role.
 * Starts a single-use opaque nonce, so the provider never sees phone/UID.
 */
async function createPendingRewardChallenge(db,{
  authUid,policy,trustedNowMs,randomToken=randomBytes,
}={}){
  requireStagedRuntime(db);approvedPolicy(policy);
  if(typeof authUid!=="string"||!UID.test(authUid))
    stop("unauthenticated","trusted-app-account-required");
  iraqDay(trustedNowMs);
  // Dependency injection is FOR TESTS ONLY: production should always call
  // node:crypto.randomBytes and should NOT expose randomToken to app clients.
  const entropy=randomToken(24);
  if(!Buffer.isBuffer(entropy)||entropy.length!==24)
    stop("unavailable","secure-server-nonce-required");
  const nonce=entropy.toString("base64url");
  if(!TOKEN.test(nonce)) stop("unavailable","untrusted-randomness");
  return db.runTransaction(async tx=>{
    const userRef=db.collection("users").doc(authUid);
    const sessionRef=db.collection("deda_sessions").doc(authUid);
    const [us,ss]=await Promise.all([tx.get(userRef),tx.get(sessionRef)]);
    const u=row(us),s=row(ss),key=u.accountKey,orig=u.sharePersonalId;
    if(!us.exists||!ss.exists||typeof key!=="string"||!ACCOUNT.test(key)||
      typeof orig!=="string"||!ORIGINAL.test(orig)||
      s.uid!==authUid||s.accountKey!==key) {
      stop("permission-denied","verified-account-session-required");
    }
    const shareSnap=await tx.get(db.collection("deda_share_ids").doc(orig));
    const share=row(shareSnap);
    if(!shareSnap.exists||share.kind!=="personal"||share.active!==true||
      share.publicId!==orig||typeof share.ownerUid!=="string"||
      !UID.test(share.ownerUid))
      stop("permission-denied","original-personal-identifier-required");
    const priorOwner=await tx.get(db.collection("users").doc(share.ownerUid));
    if(!priorOwner.exists||row(priorOwner).accountKey!==key)
      stop("permission-denied","original-personal-owner-mismatch");

    const pendingRef=db.collection("deda_stage22_ssv_pending")
      .doc(digest(nonce));
    const prev=await tx.get(pendingRef);
    if(prev.exists) stop("already-exists","secure-nonce-collision");
    tx.create(pendingRef,{
      nonceDigest:digest(nonce),accountKey:key,originalId:orig,
      adUnitId:policy.adUnitId,rewardDiamonds:REWARD_DIAMONDS,
      createdAtMs:trustedNowMs,expiresAtMs:trustedNowMs+PENDING_LIFETIME_MS,
      status:"pending",
    });
    return {customData:nonce,expiresAtMs:trustedNowMs+PENDING_LIFETIME_MS,
      adUnitId:policy.adUnitId,productionRewardActivation:false};
  },{maxAttempts:5});
}

/** This callback is a SERVER endpoint handling authenticated provider SSV,
 * never a mobile callable. Production requires official key rotation review.
 */
async function acceptProviderVerifiedReward(db,{
  rawQuery,pinnedProviderKeys,policy,trustedNowMs,
}={}){
  requireStagedRuntime(db);approvedPolicy(policy);
  iraqDay(trustedNowMs);
  const signed=verifyProviderSignedCallback(rawQuery,pinnedProviderKeys);
  if(signed.adUnitId!==policy.adUnitId ||
      signed.rewardItem!==policy.expectedRewardItem ||
      signed.rewardAmount!==policy.expectedRewardAmount ||
      signed.signedTimestampMs>trustedNowMs+CLOCK_SKEW_MS ||
      signed.signedTimestampMs<trustedNowMs-PENDING_LIFETIME_MS){
    stop("permission-denied","signed-ad-unit-or-reward-mismatch");
  }
  return db.runTransaction(async tx=>{
    const receiptRef=db.collection("deda_stage22_ssv_receipts")
      .doc(digest(signed.transactionId));
    const pendingRef=db.collection("deda_stage22_ssv_pending")
      .doc(digest(signed.customData));
    const [receiptSnap,pendingSnap]=await Promise.all([
      tx.get(receiptRef),tx.get(pendingRef),
    ]);
    const pending=row(pendingSnap);
    if(!pendingSnap.exists ||
        pending.nonceDigest!==digest(signed.customData) ||
        typeof pending.accountKey!=="string" ||
        !ACCOUNT.test(pending.accountKey) ||
        !ORIGINAL.test(pending.originalId||"") ||
        pending.adUnitId!==policy.adUnitId ||
        pending.rewardDiamonds!==REWARD_DIAMONDS ||
        !Number.isSafeInteger(pending.createdAtMs) ||
        !Number.isSafeInteger(pending.expiresAtMs) ||
        signed.signedTimestampMs<pending.createdAtMs-CLOCK_SKEW_MS ||
        trustedNowMs>pending.expiresAtMs){
      stop("permission-denied","unknown-or-expired-server-ad-challenge");
    }
    if(receiptSnap.exists){
      const prior=row(receiptSnap);
      if(prior.accountKey!==pending.accountKey ||
          prior.originalId!==pending.originalId ||
          prior.adUnitId!==policy.adUnitId ||
          prior.transactionId!==signed.transactionId ||
          prior.nonceDigest!==digest(signed.customData)) {
        stop("permission-denied","replayed-transaction-across-accounts");
      }
      return {outcome:"already-recorded",diamondsAwarded:0};
    }
    if(pending.status!=="pending"||
        pending.transactionId!==undefined){
      stop("already-exists","ad-challenge-already-consumed");
    }
    const shareRef=db.collection("deda_share_ids").doc(pending.originalId);
    const shareSnap=await tx.get(shareRef),share=row(shareSnap);
    if(!shareSnap.exists||share.kind!=="personal"||share.active!==true||
        share.publicId!==pending.originalId ||
        typeof share.ownerUid!=="string" || !UID.test(share.ownerUid)){
      stop("permission-denied","registered-original-id-revoked");
    }
    const ownerSnap=await tx.get(db.collection("users").doc(share.ownerUid));
    if(!ownerSnap.exists||row(ownerSnap).accountKey!==pending.accountKey){
      stop("permission-denied","registered-owner-changed");
    }
    const day=iraqDay(signed.signedTimestampMs);
    const dailyRef=db.collection("deda_stage22_ssv_daily")
      .doc(digest(pending.accountKey+"|"+day));
    const walletRef=db.collection("deda_diamond_gift_balances")
      .doc(pending.originalId);
    const [dailySnap,walletSnap]=await Promise.all([
      tx.get(dailyRef),tx.get(walletRef),
    ]);
    const daily=row(dailySnap),wallet=row(walletSnap);
    let count=0;
    if(dailySnap.exists){
      if(daily.accountKey!==pending.accountKey ||
          daily.dayId!==day ||
          !Number.isSafeInteger(daily.count) ||
          daily.count<0 || daily.count>MAX_DAILY_ADS){
        stop("failed-precondition","corrupted-ad-daily-ledger");
      }
      count=daily.count;
    }
    if(count>=MAX_DAILY_ADS)
      stop("resource-exhausted","provider-verified-daily-ads-cap");
    if(walletSnap.exists && wallet.publicId!==pending.originalId)
      stop("failed-precondition","personal-wallet-owner-mismatch");
    const old=walletSnap.exists?capBalance(wallet.balance):0;
    if(old>MAX_BALANCE-REWARD_DIAMONDS)
      stop("resource-exhausted","personal-wallet-cap-reached");
    const now=new Date(trustedNowMs);
    const next=old+REWARD_DIAMONDS;
    if(walletSnap.exists)
      tx.update(walletRef,{balance:next,updatedAt:now});
    else
      tx.create(walletRef,{
        publicId:pending.originalId,balance:next,
        createdAt:now,updatedAt:now,
      });
    if(dailySnap.exists)
      tx.update(dailyRef,{count:count+1,updatedAt:now});
    else
      tx.create(dailyRef,{
        accountKey:pending.accountKey,dayId:day,count:1,
        createdAt:now,updatedAt:now,
      });
    tx.update(pendingRef,{
      status:"claimed",transactionId:signed.transactionId,
      creditedAt:now,
    });
    tx.create(receiptRef,{
      transactionId:signed.transactionId,
      nonceDigest:digest(signed.customData),
      accountKey:pending.accountKey,originalId:pending.originalId,
      adUnitId:policy.adUnitId,diamondsAwarded:REWARD_DIAMONDS,
      providerKeyId:signed.verifiedProviderKeyId,
      providerTimestampMs:signed.signedTimestampMs,
      provenance:"STAGE22_STAGED_ECDSA_OFFLINE_KEY_TEST_NOT_REAL_ADMOB",
      creditedAt:now,
    });
    return {outcome:"awarded",diamondsAwarded:REWARD_DIAMONDS,
      balanceAfter:next};
  },{maxAttempts:7});
}

module.exports={
  verifyProviderSignedCallback,createPendingRewardChallenge,
  acceptProviderVerifiedReward,iraqDay,
};
