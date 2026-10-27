"use strict";

/**
 * Stage21: READ-ONLY private backend bridge. NO EXPORT from functions/index.js.
 *
 * Enriches only a genuine future Stage11 current+previous ranked response
 * with an authentic, server-signed proof of CURRENT owned/equipped appearance
 * tied to the SAME canonical account. No client-writable social cosmetics,
 * local selected styles, anonymous UID, profile phone or private balances.
 *
 * The production proof issuer, privileged XP claims and audited Firestore
 * ownership rules do not yet exist. This function MUST NOT be deployed;
 * a correctly shaped object or HMAC fixture alone is no proof of production
 * readiness. Missing proof => no frame, NO false profile/friend actions.
 */
const crypto=require("node:crypto");
const ACCOUNT=/^[0-9]{10,16}$/;
const ACTIVE=/^@DEDA-[A-Z0-9]{4,12}$/;
const ORIGINAL=/^@DEDA-[A-Z0-9]{6}$/;
const PARTICIPANT=/^[A-Za-z0-9_-]{16,90}$/;
const NAME=/^[^\u0000-\u001f\u007f@]{2,60}$/u;
const ISSUER="privileged_server_owned_equipped_appearance_v1";
const ROOT="deda_weekly_verified_equipped_public";
const MAX_AGE=24*60*60*1000;
function fail(reason) {throw Error("DEDA_STAGE21_PUBLIC_APPEARANCE_BLOCK_"+reason);}
function safeInt(x){return Number.isSafeInteger(x)&&x>=0;}
function hmac(key,input) {
  if(!Buffer.isBuffer(key)||key.length<32)fail("backend_hmac_secret_required");
  return crypto.createHmac("sha256",key).update(input,"utf8").digest("hex");
}
function profileDocId(accountKey,key) {
  if(!ACCOUNT.test(accountKey))fail("canonical_account_invalid");
  return hmac(key,"equip-proof|"+accountKey);
}
function serial(p) {
  return JSON.stringify([
    p.issuer,p.status,p.accountKey,p.publicCompetitorId,
    p.originalPublicId,p.activePublicId,p.displayName,
    p.avatarStyle,p.equippedFrameStyle,p.equipmentOwnedVerified,
    p.verifiedAtMs,
  ]);
}
function validateProof(proof,row,account,now,key) {
  if(!proof ||typeof proof!=="object"||Array.isArray(proof) ||
      proof.issuer!==ISSUER ||proof.status!=="verified"||
      proof.accountKey!==account||!ACCOUNT.test(account)||
      proof.publicCompetitorId!==row.participantId||
      !PARTICIPANT.test(proof.publicCompetitorId||"")||
      !ORIGINAL.test(proof.originalPublicId||"")||
      !ACTIVE.test(proof.activePublicId||"")||
      proof.activePublicId!==row.activePublicId||
      proof.displayName!==row.displayName||
      !NAME.test(proof.displayName||"")||
      /\b0[0-9]{10}\b/.test(proof.displayName)||
      /\S+@\S+/.test(proof.displayName)||
      !safeInt(proof.avatarStyle)||proof.avatarStyle>18||
      !safeInt(proof.equippedFrameStyle)||proof.equippedFrameStyle>18||
      proof.equipmentOwnedVerified!==true||
      !safeInt(proof.verifiedAtMs)||proof.verifiedAtMs>now||
      now-proof.verifiedAtMs>MAX_AGE||
      typeof proof.signature!=="string"||
      !/^[a-f0-9]{64}$/.test(proof.signature))fail("invalid_signed_equipment");
  const expected=hmac(key,serial(proof));
  if(!crypto.timingSafeEqual(
       Buffer.from(expected,"hex"),Buffer.from(proof.signature,"hex"))) {
    fail("equipment_proof_tampered");
  }
  return Object.freeze({
    originalPublicId:proof.originalPublicId,
    activePublicId:proof.activePublicId,
    displayName:proof.displayName,
    avatarStyle:proof.avatarStyle,
    equippedFrameStyle:proof.equippedFrameStyle,
    publicOwnerVerified:true,
    equippedAppearanceVerified:true,
  });
}
function rawIdentity(raw,week) {
  if(!raw||raw.weekId!==week.weekId||!Array.isArray(raw.rows)||
      raw.rows.length>5000)fail("raw_verified_week_required");
  const map=new Map();
  for(const rank of raw.rows) {
    if(!rank||!ACCOUNT.test(rank.accountKey||"")||
        !PARTICIPANT.test(rank.publicCompetitorId||"")||
        map.has(rank.publicCompetitorId))fail("raw_owner_identity_invalid");
    map.set(rank.publicCompetitorId,rank);
  }
  return map;
}
async function enrichVerifiedWeek({db,visible,raw,now,key,cache}) {
  if(!visible ||visible.verified!==true||
      !Array.isArray(visible.rows)||visible.rows.length>11||
      visible.weekId!==raw.weekId)fail("verified_view_required");
  const original=rawIdentity(raw,visible);
  const rows=[];
  for(const row of visible.rows) {
    const account=original.get(row.participantId);
    if(!account||
        row.place!==account.place||
        row.activePublicId!==account.activePublicId||
        row.displayName!==account.displayName||
        row.weeklyPoints!==account.earnedLevelXp||
        row.verifiedTaskCompletions!==account.taskClaims||
        row.diamondsIfFinalWinner!==account.potentialDiamonds)
      fail("raw_display_owner_mismatch");
    const accountKey=account.accountKey;
    let proof=cache.get(accountKey);
    if(proof===undefined) {
      const id=profileDocId(accountKey,key);
      const ref=db.doc(ROOT+"/"+id);
      if(!ref||typeof ref.get!=="function")fail("server_read_permission");
      const document=await ref.get();
      proof=document&&document.exists&&typeof document.data==="function"
        ?document.data():null;
      cache.set(accountKey,proof);
    }
    if(proof===null){
      rows.push(Object.freeze({...row}));
      continue; // never pretend this competitor has a verified frame or profile
    }
    // A player can legitimately change name / premium ID between weeks.
    // The CURRENT equipped proof must not repaint historical weeks with a
    // different identity; leave the old row without interactive cosmetics.
    if(proof.activePublicId!==row.activePublicId ||
       proof.displayName!==row.displayName) {
      rows.push(Object.freeze({...row}));
      continue;
    }
    const safe=validateProof(proof,row,accountKey,now,key);
    rows.push(Object.freeze({...row,publicAppearance:safe}));
  }
  return Object.freeze({...visible,rows:Object.freeze(rows)});
}
/**
 * Server-only internal composition; never accepts request data, mock ranked
 * names from the phone or "isOwned" booleans from the client.
 */
async function enrichVerifiedPairWithPublicAppearance({
  db,serverPair,rawCurrent,rawPrevious,serverNowMs,serverSecret,
}) {
  if(!db||typeof db.doc!=="function"||
      !safeInt(serverNowMs)||serverNowMs<=0||
      !serverPair||serverPair.readOnly!==true||
      serverPair.source!=="future_server_issued_only"||
      Object.keys(serverPair).some(x=>!["source","readOnly","current","previous"].includes(x)))
    fail("privileged_verified_pair_required");
  hmac(serverSecret,"validate");
  const cache=new Map();
  const current=await enrichVerifiedWeek({
    db,visible:serverPair.current,raw:rawCurrent,now:serverNowMs,
    key:serverSecret,cache});
  const previous=await enrichVerifiedWeek({
    db,visible:serverPair.previous,raw:rawPrevious,now:serverNowMs,
    key:serverSecret,cache});
  return Object.freeze({
    source:"future_server_issued_only",readOnly:true,current,previous,
  });
}
module.exports=Object.freeze({
  enrichVerifiedPairWithPublicAppearance,
});
