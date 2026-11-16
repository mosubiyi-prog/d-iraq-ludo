"use strict";
/*
 * POINT 2 / PRIVATE QA: read REAL DEDA COLLECTION SCHEMAS in the Emulator.
 * Friends: deda_friendships + deda_social_profiles.
 * Weekly league: deda_weekly_direct_accounts and weekly score documents.
 * Identifier gifts ONLY: Stage71 grants, Stage74 received receipts.
 * No friend mutations, XP awards, prize payouts, gift claims, ownership
 * transfers, Auth changes, or user data writes. Not a production grantor.
 *
 * Historical source UIDs A/B/C are selected by a separately reviewed
 * per-domain scope in the lab; this module does not prove true ownership.
 */
const domains=new Set(["friends","league","gifts"]);
const uid=x=>typeof x==="string" && /^[A-Za-z0-9:_-]{6,128}$/.test(x);
const original=x=>typeof x==="string" && /^@DEDA-[A-Z0-9]{6}$/.test(x);
const anyId=x=>typeof x==="string" && /^@DEDA-[A-Z0-9]{4,12}$/.test(x);
const colors=new Set(["gold","diamond","royal","pink"]);
const kinds=new Set(["gifted","self_used"]);
const weekOrigin=Date.UTC(2026,9,31,3,0,0);
const weekMillis=7*24*60*60*1000;
function weekId(nowMs){
  if(!Number.isSafeInteger(nowMs)||nowMs<weekOrigin) return null;
  const weekStart=new Date(weekOrigin+
    Math.floor((nowMs-weekOrigin)/weekMillis)*weekMillis+3*3600000);
  return weekStart.toISOString().slice(0,10);
}
async function projectDedaSecondSchema(plan,read,query,nowMs){
  if(!plan || !domains.has(plan.domain) ||
    !uid(plan.readerUid)||!uid(plan.sourceUid)||
    !original(plan.originalId)||
    typeof plan.canonicalAccountId!=="string"||
    plan.canonicalAccountId.length<12||
    typeof read!=="function"||typeof query!=="function")return null;
  const [room,sourceUser,sourceSession,route]=await Promise.all([
    read("qa_room_accounts/"+plan.canonicalAccountId),
    read("users/"+plan.sourceUid),
    read("deda_sessions/"+plan.sourceUid),
    read("deda_share_ids/"+plan.originalId)
  ]);
  if(!room || !sourceUser||!sourceSession||!route ||
    room.canonicalAccountId!==plan.canonicalAccountId||
    room.originalId!==plan.originalId||
    !Array.isArray(room.historicalUids)||
    !room.historicalUids.includes(plan.sourceUid)||
    !room.historicalUids.includes(plan.readerUid)||
    !room.historicalUids.includes(route.ownerUid)||
    !uid(route.ownerUid)||
    sourceUser.accountKey!==room.accountKey||
    sourceSession.accountKey!==room.accountKey||
    sourceSession.uid!==plan.sourceUid||
    route.publicId!==plan.originalId||
    route.active!==true||route.kind!=="personal"||
    (sourceUser.sharePersonalId!=null &&
      sourceUser.sharePersonalId!==plan.originalId))return null;

  if(plan.domain==="friends"){
    // Social records can belong to C while the original ID route belongs to
    // A. Do NOT require the two UIDs to match: require separate reviewed scope
    // and an authoritative social profile tied to C.
    const social=await read("deda_social_profiles/"+plan.originalId);
    if(!social||social.publicId!==plan.originalId||
      social.ownerUid!==plan.sourceUid)return null;
    const records=await query("deda_friendships_members",plan.sourceUid);
    if(!Array.isArray(records)||records.length>200)return null;
    let accepted=0;
    for(const row of records){
      const d=row?.data, first=d?.requesterUid, second=d?.recipientUid;
      if(!uid(first)||!uid(second)||first===second||
        !Array.isArray(d?.members)||d.members.length!==2||
        !d.members.includes(first)||!d.members.includes(second)||
        !d.members.includes(plan.sourceUid)||
        row.id!==[first,second].sort().join("__")||
        d.pairKey!==row.id||
        !["accepted","pending","rejected"].includes(d.status)||
        !anyId(d.requesterPublicId)||!anyId(d.recipientPublicId)||
        (first===plan.sourceUid?
          d.requesterPublicId!==plan.originalId:
          d.recipientPublicId!==plan.originalId))return null;
      if(d.status==="accepted")accepted++;
    }
    return Object.freeze({friendCount:accepted});
  }
  if(plan.domain==="league"){
    // This is the direct-weekly score, NOT level XP and NOT prize delivery.
    const w=weekId(nowMs);
    if(!w)return null;
    const binding=await read("deda_weekly_direct_accounts/"+plan.originalId);
    if(!binding || binding.createdByUid!==plan.sourceUid ||
      binding.accountKey!==room.accountKey ||
      binding.publicId!==plan.originalId)return null;
    const score=await read(
      "deda_weekly_direct_weeks/"+w+"/scores/"+plan.originalId);
    if(!score)return Object.freeze({weeklyPoints:0});
    if(score.weekId!==w||score.publicId!==plan.originalId||
      !Array.isArray(score.claimedKeys)||
      !Number.isSafeInteger(score.completedTasks)||
      score.completedTasks<0||score.completedTasks>56||
      score.completedTasks!==score.claimedKeys.length||
      new Set(score.claimedKeys).size!==score.claimedKeys.length||
      !score.claimedKeys.every(x=>typeof x==="string"&&
        x.length>=3&&x.length<=100)||
      !Number.isSafeInteger(score.weeklyXp)||
      score.weeklyXp!==score.completedTasks*20)return null;
    return Object.freeze({weeklyPoints:score.weeklyXp});
  }
  // Identifier gifts only. Other "هداياي" gifts/prizes/diamonds remain out
  // of scope until independent server sources and ownership are reviewed.
  if(route.ownerUid!==plan.sourceUid)return null;
  const grants=await query("deda_stage71_grants_by_recipient",
    plan.originalId);
  if(!Array.isArray(grants)||grants.length>200)return null;
  let gifts=0;
  for(const row of grants){
    const d=row?.data;
    if(!anyId(row?.id)||!d||d.identifier!==row.id||
      d.recipientOriginalId!==plan.originalId||
      !["001","002"].includes(d.group)||
      !colors.has(d.baseColor)||!kinds.has(d.kind))return null;
    if(d.kind!=="gifted")continue;
    const receipt=await read("deda_stage74_id_gift_receipts/"+row.id);
    if(receipt){
      if(receipt.identifier!==row.id||
        receipt.originalId!==plan.originalId||
        receipt.group!==d.group||
        typeof receipt.receivedAt?.toMillis!=="function"||
        !Number.isFinite(receipt.receivedAt.toMillis())||
        receipt.receivedAt.toMillis()<=0)return null;
    }
    // Pending gifts are shown in Hadaya before claiming; received gifts
    // remain as history. This count does not claim/award anything.
    gifts++;
  }
  return Object.freeze({giftCount:gifts});
}
module.exports={projectDedaSecondSchema,domains,weekId};
