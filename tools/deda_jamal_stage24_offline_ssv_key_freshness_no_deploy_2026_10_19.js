"use strict";

/**
 * DEDA جمال التطبيق المتكاملة — Stage24 SECURITY TEST ONLY.
 * This models public-key freshness and pinning, NOT Google AdMob authority.
 * Generated test keys cannot establish a key originated at Google.
 * No key is fetched from any network, no callbacks deployed, no payouts live.
 */
const {createHash,createPublicKey} = require("node:crypto");
const {verifyProviderSignedCallback} =
  require("./deda_jamal_stage22_admob_ssv_ecdsa_staged_no_deploy_2026_10_19.js");

const PROJECT="demo-deda-stage22-ssv-fakeprovider";
const MAX_SNAPSHOT_AGE_MS=24*60*60*1000;
const MAX_SKEW_MS=2*60*1000;
const ID=/^[0-9]{1,16}$/;
const PEM=/^-----BEGIN PUBLIC KEY-----\n[A-Za-z0-9+/=\n]+\n-----END PUBLIC KEY-----\n?$/;

function abort(code,reason){
  const err=new Error(reason);err.code=code;throw err;
}
function requireOfflineDemo(){
  if (!/^(127[.]0[.]0[.]1|localhost):[0-9]+$/.test(
      process.env.FIRESTORE_EMULATOR_HOST||"") ||
      process.env.GCLOUD_PROJECT!==PROJECT) {
    abort("unavailable","UNVERIFIED_GOOGLE_KEYS_OFFLINE_EMULATOR_ONLY");
  }
}
function validateSnapshot(snapshot,nowMs){
  requireOfflineDemo();
  if(!Number.isSafeInteger(nowMs)||nowMs<0 ||
      !snapshot||typeof snapshot!=="object" ||
      Array.isArray(snapshot) ||
      snapshot.origin!=="OFFLINE_GENERATED_FAKE_EC_KEYS_NOT_GOOGLE" ||
      !Number.isSafeInteger(snapshot.receivedAtMs) ||
      !Number.isSafeInteger(snapshot.expiresAtMs) ||
      snapshot.receivedAtMs<0 ||
      snapshot.receivedAtMs>nowMs+MAX_SKEW_MS ||
      snapshot.expiresAtMs<=nowMs ||
      snapshot.expiresAtMs<=snapshot.receivedAtMs ||
      snapshot.expiresAtMs-snapshot.receivedAtMs>MAX_SNAPSHOT_AGE_MS ||
      nowMs-snapshot.receivedAtMs>MAX_SNAPSHOT_AGE_MS ||
      !snapshot.keysById ||
      typeof snapshot.keysById!=="object" ||
      Array.isArray(snapshot.keysById)) {
    abort("unavailable","stale-or-untrusted-fake-ssv-key-snapshot");
  }
  const entries=Object.entries(snapshot.keysById);
  if(entries.length<1||entries.length>6)
    abort("unavailable","untrusted-fake-provider-key-count");
  const publicMap=Object.create(null);
  const fingerprints=new Set();
  for(const [id,pem] of entries){
    if(!ID.test(id) || typeof pem!=="string"||
        pem.length>1400||!PEM.test(pem)){
      abort("unavailable","invalid-pinned-ec-key-material");
    }
    let key;
    try{key=createPublicKey(pem);}
    catch(_){abort("unavailable","invalid-pinned-ec-key-material");}
    if(key.asymmetricKeyType!=="ec" ||
        key.asymmetricKeyDetails?.namedCurve!=="prime256v1") {
      abort("unavailable","pinned-ec-key-must-be-nist-p256");
    }
    const fingerprint=createHash("sha256")
      .update(key.export({type:"spki",format:"der"})).digest("hex");
    if(fingerprints.has(fingerprint))
      abort("unavailable","duplicate-public-key-under-different-id");
    fingerprints.add(fingerprint);
    publicMap[id]=pem;
  }
  return Object.freeze({
    origin:"OFFLINE_GENERATED_FAKE_EC_KEYS_NOT_GOOGLE",
    issuedAt:snapshot.receivedAtMs,
    expiresAt:snapshot.expiresAtMs,
    keysById:Object.freeze(publicMap),
    deploymentPermitted:false,
    googleKeyAuthenticityVerified:false,
  });
}
function verifyWithOfflinePinnedKeys(rawQuery,cache,nowMs){
  requireOfflineDemo();
  // Revalidate on EVERY callback, not just when a cache is first created.
  // A key expiring between receipt and retry must fail closed.
  if(!cache || cache.origin!=="OFFLINE_GENERATED_FAKE_EC_KEYS_NOT_GOOGLE" ||
      cache.deploymentPermitted!==false ||
      cache.googleKeyAuthenticityVerified!==false ||
      !Number.isSafeInteger(nowMs) ||
      nowMs>=cache.expiresAt ||
      nowMs<cache.issuedAt-MAX_SKEW_MS ||
      !cache.keysById ||
      !Object.isFrozen(cache.keysById)) {
    abort("unavailable","offline-fake-key-cache-expired-or-bypassed");
  }
  const fresh=validateSnapshot({
    origin:cache.origin,
    receivedAtMs:cache.issuedAt,
    expiresAtMs:cache.expiresAt,
    keysById:cache.keysById,
  },nowMs);
  return verifyProviderSignedCallback(rawQuery,fresh.keysById);
}

module.exports={validateSnapshot,verifyWithOfflinePinnedKeys};
