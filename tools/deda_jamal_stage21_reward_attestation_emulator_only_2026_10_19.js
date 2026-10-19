"use strict";

/**
 * DEDA جمال التطبيق المتكاملة Stage21 — EMULATOR ONLY.
 * Synthetic HMAC tickets demonstrate proof-binding, atomic one-time payouts
 * and stable original-account wallet behavior. Synthetic tickets are NOT
 * Google AdMob SSV, not a real ad verification method, and not deployable.
 * A real launch requires a provider-specific verified callback with trusted
 * Google public keys / provider receipts AND owner approval.
 */
const {createHmac,createHash,timingSafeEqual}=require("node:crypto");

const PROJECT="demo-deda-stage21-earned-rewards";
const UID=/^[A-Za-z0-9_-]{1,160}$/;
const KEY=/^[A-Za-z0-9_-]{4,160}$/;
const ORIGINAL=/^@DEDA-[A-Z0-9]{6}$/;
const EVENT=/^[A-Za-z0-9_-]{8,80}$/;
const MAX_BALANCE=1073741824;
const MAX_AGE_MS=15*60*1000;
const MAX_FUTURE_MS=120000;
const SOURCE=Object.freeze({
  ad_demo:Object.freeze({diamonds:3,maxDaily:5}),
  task_demo:Object.freeze({diamonds:5,maxDaily:6}),
});
const MAX_DAILY_REWARDS=50;

function denied(code,reason) {
  const e=new Error(reason);e.code=code;throw e;
}
function snapData(s) {return s.exists ? s.data()||{} : {};}
function hash(s) {return createHash("sha256").update(s,"utf8").digest("hex");}
function dayBaghdad(timestamp) {
  if(!Number.isSafeInteger(timestamp)|| timestamp<0) {
    denied("invalid-argument","invalid-trusted-timestamp");
  }
  return new Date(timestamp+3*3600000).toISOString().slice(0,10);
}
function requireNamedEmulator(db,secret) {
  if(!process.env.FIRESTORE_EMULATOR_HOST ||
      process.env.GCLOUD_PROJECT!==PROJECT ||
      !db || typeof db.runTransaction!=="function" ||
      !Buffer.isBuffer(secret) || secret.length<32) {
    denied("unavailable","STAGE21_EMULATOR_ONLY_DO_NOT_PAY");
  }
}
function payloadString(p) {
  return [
    "DEDA_STAGE21_EMULATOR_FAKE_ATTESTATION_v1",
    p.source,p.eventId,p.accountKey,p.issuedForOriginalId,
    String(p.verifiedAtMs),p.dayId,String(p.amount),
  ].join("|");
}
function verifyDemoTicket(p,secret,now) {
  if(!p || typeof p!=="object" || Array.isArray(p) ||
      Object.keys(p).length!==8 ||
      !Object.keys(p).every(k=>[
        "source","eventId","accountKey","issuedForOriginalId",
        "verifiedAtMs","dayId","amount","signatureHex",
      ].includes(k)) ||
      !Object.prototype.hasOwnProperty.call(SOURCE,p.source) ||
      typeof p.eventId!=="string" || !EVENT.test(p.eventId) ||
      typeof p.accountKey!=="string" || !KEY.test(p.accountKey) ||
      typeof p.issuedForOriginalId!=="string" ||
        !ORIGINAL.test(p.issuedForOriginalId) ||
      !Number.isSafeInteger(p.verifiedAtMs) ||
      p.verifiedAtMs<0 || p.verifiedAtMs>now+MAX_FUTURE_MS ||
      now-p.verifiedAtMs>MAX_AGE_MS ||
      typeof p.dayId!=="string" ||
      p.dayId!==dayBaghdad(p.verifiedAtMs) ||
      p.dayId!==dayBaghdad(now) ||
      p.amount!==SOURCE[p.source].diamonds ||
      typeof p.signatureHex!=="string" ||
      !/^[a-f0-9]{64}$/.test(p.signatureHex)) {
    denied("permission-denied","invalid-demo-attestation");
  }
  const expected=createHmac("sha256",secret).update(
    payloadString(p),"utf8").digest();
  const given=Buffer.from(p.signatureHex,"hex");
  if(given.length!==expected.length ||
      !timingSafeEqual(given,expected)) {
    denied("permission-denied","invalid-demo-attestation");
  }
}
function validBalance(v) {
  if(!Number.isSafeInteger(v)||v<0||v>MAX_BALANCE) {
    denied("failed-precondition","untrusted-wallet-balance");
  }
  return v;
}
function dailyData(s,key,day) {
  if(!s.exists) {
    return {accountKey:key,dayId:day,count:0,amount:0,
      ad_demo:0,task_demo:0};
  }
  const d=snapData(s);
  if(d.accountKey!==key || d.dayId!==day ||
      !Number.isSafeInteger(d.count) || d.count<0 ||
      !Number.isSafeInteger(d.amount) || d.amount<0 ||
      !Number.isSafeInteger(d.ad_demo) || d.ad_demo<0 ||
      !Number.isSafeInteger(d.task_demo) || d.task_demo<0 ||
      d.ad_demo+d.task_demo!==d.count ||
      d.amount!==d.ad_demo*3+d.task_demo*5 ||
      d.count>11 || d.amount>MAX_DAILY_REWARDS) {
    denied("failed-precondition","invalid-prior-reward-daily-ledger");
  }
  return d;
}

/**
 * Stage21 emulator-only Admin SDK transaction. Caller auth UID must be
 * server-verified, fake proof secret must stay TEST-only; no client callable.
 * No attempt to read/migrate old SharedPreferences rewarded-ad balances.
 */
async function simulateAttestedRewardOnEmulator(db, {
  authUid, ticket, testOnlyHmacSecret, trustedNowMs,
}={}) {
  requireNamedEmulator(db,testOnlyHmacSecret);
  if(typeof authUid!=="string" || !UID.test(authUid)) {
    denied("unauthenticated","verified-current-login-required");
  }
  if(!Number.isSafeInteger(trustedNowMs) || trustedNowMs<=0) {
    denied("invalid-argument","trusted-demo-clock-required");
  }
  verifyDemoTicket(ticket,testOnlyHmacSecret,trustedNowMs);
  const p=ticket;
  return db.runTransaction(async(tx)=>{
    const users=db.collection("users");
    const uref=users.doc(authUid);
    const sessionRef=db.collection("deda_sessions").doc(authUid);
    const [userSnap,sessionSnap]=await Promise.all([
      tx.get(uref),tx.get(sessionRef),
    ]);
    const u=snapData(userSnap),s=snapData(sessionSnap);
    const key=u.accountKey,orig=u.sharePersonalId;
    if(!userSnap.exists || !sessionSnap.exists ||
        typeof key!=="string" || !KEY.test(key) ||
        typeof orig!=="string" || !ORIGINAL.test(orig) ||
        s.uid!==authUid || s.accountKey!==key ||
        key!==p.accountKey || orig!==p.issuedForOriginalId) {
      denied("permission-denied","verified-permanent-account-proof-missing");
    }
    const shareRef=db.collection("deda_share_ids").doc(orig);
    const shareSnap=await tx.get(shareRef),share=snapData(shareSnap);
    if(!shareSnap.exists || share.kind!=="personal" ||
        share.active!==true || share.publicId!==orig ||
        typeof share.ownerUid!=="string" || !UID.test(share.ownerUid)) {
      denied("permission-denied","valid-original-personal-id-required");
    }
    const first=await tx.get(users.doc(share.ownerUid));
    if(!first.exists || snapData(first).accountKey!==key) {
      denied("permission-denied","original-registration-proof-missing");
    }

    const receiptRef=db.collection("deda_stage21_emulator_reward_claims")
      .doc(hash(p.eventId));
    const dailyRef=db.collection("deda_stage21_emulator_reward_daily")
      .doc(hash(key+"|"+p.dayId));
    const walletRef=db.collection("deda_diamond_gift_balances").doc(orig);
    const [receiptSnap,dailySnap,walletSnap]=await Promise.all([
      tx.get(receiptRef),tx.get(dailyRef),tx.get(walletRef),
    ]);
    if(receiptSnap.exists) {
      const r=snapData(receiptSnap);
      if(r.accountKey!==key || r.originalId!==orig ||
          r.source!==p.source || r.eventId!==p.eventId ||
          r.amount!==p.amount) {
        denied("permission-denied","reward-event-used-by-another-account");
      }
      return {outcome:"already-recorded",awarded:0,
        eventReceiptId:hash(p.eventId)};
    }
    const previous=dailyData(dailySnap,key,p.dayId);
    if(previous[p.source]>=SOURCE[p.source].maxDaily ||
        previous.amount+p.amount>MAX_DAILY_REWARDS) {
      denied("resource-exhausted","verified-daily-reward-cap-reached");
    }
    const wallet=snapData(walletSnap);
    if(walletSnap.exists && wallet.publicId!==orig) {
      denied("failed-precondition","verified-personal-wallet-identity-mismatch");
    }
    const old=walletSnap.exists?validBalance(wallet.balance):0;
    if(old>MAX_BALANCE-p.amount) {
      denied("resource-exhausted","reward-wallet-overflow");
    }
    const now=new Date(trustedNowMs),next=old+p.amount;
    // No GM admin pool, manager PERSONAL test-wallet, profile/local diamonds,
    // user points, level, task bonus or Telegram claim document is touched.
    if(walletSnap.exists) {
      tx.update(walletRef,{balance:next,updatedAt:now});
    }else{
      tx.create(walletRef,{
        publicId:orig,balance:next,createdAt:now,updatedAt:now,
      });
    }
    const counters={
      accountKey:key,dayId:p.dayId,
      count:previous.count+1,
      amount:previous.amount+p.amount,
      ad_demo:previous.ad_demo+(p.source==="ad_demo"?1:0),
      task_demo:previous.task_demo+(p.source==="task_demo"?1:0),
      updatedAt:now,
    };
    if(dailySnap.exists){tx.update(dailyRef,counters);}
    else{tx.create(dailyRef,{...counters,createdAt:now});}
    tx.create(receiptRef,{
      eventId:p.eventId,accountKey:key,originalId:orig,
      source:p.source,amount:p.amount,dayId:p.dayId,
      verifiedAt:new Date(p.verifiedAtMs),creditedAt:now,
      provenance:"emulator_fake_HMAC_DO_NOT_PAY_PRODUCTION",
    });
    return {outcome:"awarded",awarded:p.amount,balanceAfter:next,
      eventReceiptId:hash(p.eventId)};
  },{maxAttempts:7});
}

module.exports={
  simulateAttestedRewardOnEmulator,dayBaghdad,payloadString,PROJECT,
};
