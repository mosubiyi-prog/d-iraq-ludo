"use strict";
/*
 * DEDA POINT 3: REAL-SCHEMA SOURCE READBACK, SYNTHETIC QA ONLY.
 * NOT EXPORTED in functions/index.js; no Auth, no cross-UID grant, no
 * writes, no spend/claim/credit. A review token from the isolated gateway
 * is mandatory. Never interpret legacy local diamonds as server balance.
 */
const domains=new Set(["wallet","places"]);
const uid=x=>typeof x==="string"&&/^[A-Za-z0-9:_-]{6,128}$/.test(x);
const id=x=>typeof x==="string"&&/^@DEDA-[A-Z0-9]{6}$/.test(x);
const account=x=>typeof x==="string"&&/^[0-9]{10,16}$/.test(x);
const nonnegative=x=>Number.isSafeInteger(x)&&x>=0&&x<=1000000000;
async function projectDedaThirdSchema(plan,read,query){
  if(!plan||!domains.has(plan.domain)||!uid(plan.readerUid)||
     !uid(plan.sourceUid)||!id(plan.originalId)||
     typeof plan.canonicalAccountId!=="string"||
     plan.canonicalAccountId.length<12||
     typeof read!=="function"||typeof query!=="function")return null;
  const [room,user,session,route]=await Promise.all([
    read("qa_room_accounts/"+plan.canonicalAccountId),
    read("users/"+plan.sourceUid),
    read("deda_sessions/"+plan.sourceUid),
    read("deda_share_ids/"+plan.originalId)
  ]);
  if(!room||!user||!session||!route||
     room.canonicalAccountId!==plan.canonicalAccountId||
     room.originalId!==plan.originalId||!account(room.accountKey)||
     !Array.isArray(room.historicalUids)||
     !room.historicalUids.includes(plan.readerUid)||
     !room.historicalUids.includes(plan.sourceUid)||
     !room.historicalUids.includes(route.ownerUid)||
     !uid(route.ownerUid)||route.publicId!==plan.originalId||
     route.active!==true||route.kind!=="personal"||
     user.accountKey!==room.accountKey||
     session.accountKey!==room.accountKey||
     session.uid!==plan.sourceUid||
     (user.sharePersonalId!=null&&user.sharePersonalId!==plan.originalId))
    return null;

  if(plan.domain==="wallet"){
    // ONLY server-side gift wallet, not total diamonds, ad earnings or spent
    // historic balance. Missing server record is UNKNOWN, never 0.
    if(plan.sourceUid!==route.ownerUid)return null;
    const gift=await read("deda_diamond_gift_balances/"+plan.originalId);
    if(!gift||gift.publicId!==plan.originalId||
       (gift.ownerUid!=null&&gift.ownerUid!==plan.sourceUid)||
       !nonnegative(gift.balance))return null;
    // Explicitly labelled by key: do not substitute balanceDisplay,
    // which could be mistaken for the user's entire spendable diamonds.
    return Object.freeze({giftWalletBalance:gift.balance});
  }

  // Published place is keyed by accountKey, not the personal original ID.
  // Count ONLY records owned by the separately reviewed sourceUid. If an
  // account has historical owners across A/B/C this narrow scope HALTS,
  // instead of silently omitting places or transferring them.
  const rows=await query("deda_published_places_by_account",room.accountKey);
  if(!Array.isArray(rows)||rows.length>100)return null;
  const seen=new Set();
  for(const row of rows){
    const d=row?.data;
    if(typeof row?.id!=="string"||!row.id||row.id.includes("/")||
       seen.has(row.id)||!d||d.published!==true||
       d.accountKey!==room.accountKey||d.ownerUid!==plan.sourceUid)
      return null;
    seen.add(row.id);
  }
  return Object.freeze({publishedPlaceCount:rows.length});
}
module.exports={domains,projectDedaThirdSchema};