"use strict";
/*
 * DEDA real Firestore-schema reader for FIRST approved scope only:
 * profile, original_id, premium_id.
 *
 * PRIVATE QA ONLY: import into emulator gateway, never into production
 * functions/index.js, never export an HTTP callable, never touch an Auth UID.
 * Reads the ORIGINAL DEDA COLLECTION NAMES and checks their schemas.
 * Source of truth:
 *   lib/deda_backend.dart -> users/{uid}.name/accountKey
 *   lib/deda_stage71_free_owned_use_profile.dart -> original route/active ID
 *   lib/deda_stage71_free_manager_200_service.dart -> granted registry
 *   lib/deda_stage74_id_gift_service.dart -> received gifted ID receipt
 *
 * A reviewed cross-UID scope is simulated separately in the QA gateway. This
 * reader is NOT an independent ownership proof and MUST NOT be used to
 * authorize production reads or copy full account documents to the client.
 */
const validId=x=>typeof x==="string" && /^@DEDA-[A-Z0-9]{6}$/.test(x);
const validAlias=x=>typeof x==="string" && /^@DEDA-[A-Z0-9]{4,12}$/.test(x);
const validUid=x=>typeof x==="string" && /^[A-Za-z0-9:_-]{6,128}$/.test(x);
const palette=new Set(["gold","diamond","royal","pink"]);
const groups=new Set(["001","002"]);
const reviewedDomains=new Set(["profile","original_id","premium_id"]);
function safeName(name){
  return typeof name==="string" && name.trim().length>0 &&
    name.trim().length<=96 && !/[<>]/.test(name);
}
function fail(){return null;}
async function projectDedaRealSchema(plan,read) {
  if(!plan || !reviewedDomains.has(plan.domain) ||
     !validUid(plan.readerUid) || !validUid(plan.sourceUid) ||
     !validId(plan.originalId) ||
     typeof plan.canonicalAccountId!=="string" ||
     plan.canonicalAccountId.length<12 ||
     typeof read!=="function") return fail();
  // Caller (existing emulator gateway) establishes independent reviewed
  // scope. Read only *the source UID* from that reviewed domain proof.
  const sourceUid=plan.sourceUid;
  const [user,session,route,room]=await Promise.all([
    read("users/"+sourceUid),
    read("deda_sessions/"+sourceUid),
    read("deda_share_ids/"+plan.originalId),
    read("qa_room_accounts/"+plan.canonicalAccountId),
  ]);
  if(!user || !session || !route || !room ||
     room.canonicalAccountId!==plan.canonicalAccountId ||
     room.originalId!==plan.originalId ||
     !Array.isArray(room.historicalUids) ||
     !room.historicalUids.includes(sourceUid) ||
     !room.historicalUids.includes(route.ownerUid) ||
     user.accountKey!==room.accountKey ||
     !validUid(route.ownerUid) ||
     route.publicId!==plan.originalId ||
     route.kind!=="personal" || route.active!==true ||
     user.accountKey!==session.accountKey ||
     typeof user.accountKey!=="string" ||
     user.accountKey.length<11 ||
     // A missing sharePersonalId is allowed for legacy DEDA accounts;
     // a conflicting sharePersonalId is NEVER silently repaired.
     (user.sharePersonalId!==undefined &&
       user.sharePersonalId!==plan.originalId)) return fail();

  if(plan.domain==="profile"){
    // A social or registration owner UID may differ from route owner; the
    // independently reviewed per-domain proof must decide which UID is
    // authoritative. The source reader does not silently change that UID.
    if(!safeName(user.name)) return fail();
    const payload={displayName:user.name.trim()};
    if(user.level!==undefined){
      if(!Number.isSafeInteger(user.level) || user.level<0 ||
         user.level>1000000000) return fail();
      payload.level=user.level;
    }
    return Object.freeze(payload);
  }

  // Original routing ID + premium selection belong to route.ownerUid
  // (A in the synthetic split). Never take B's self-projected alias as proof.
  if(route.ownerUid!==sourceUid) return fail();
  if(plan.domain==="original_id")
    return Object.freeze({publicId:plan.originalId});

  const active=await read("deda_stage71_active_identifier/"+plan.originalId);
  // Absent selection => safe original display, no invented premium.
  if(active==null) return Object.freeze({displayId:plan.originalId});
  if(active.originalId!==plan.originalId ||
     !validAlias(active.activeId)) return fail();
  if(active.activeId===plan.originalId)
    return Object.freeze({displayId:plan.originalId});

  const item=await read("deda_stage71_granted_registry/"+active.activeId);
  if(!item || item.identifier!==active.activeId ||
     item.recipientOriginalId!==plan.originalId ||
     !groups.has(item.group) || !palette.has(item.baseColor) ||
     !new Set(["gifted","self_used"]).has(item.kind)) return fail();
  if(item.kind==="gifted"){
    const receipt=await read("deda_stage74_id_gift_receipts/"+active.activeId);
    // Firestore Admin Timestamp has .toMillis(); fake string/client ack is
    // never sufficient to mark a gifted identifier as received.
    if(!receipt || receipt.identifier!==active.activeId ||
       receipt.originalId!==plan.originalId ||
       receipt.group!==item.group ||
       !receipt.receivedAt ||
       typeof receipt.receivedAt.toMillis!=="function" ||
       !Number.isFinite(receipt.receivedAt.toMillis()) ||
       receipt.receivedAt.toMillis()<=0) return fail();
  }
  return Object.freeze({displayId:active.activeId,color:item.baseColor});
}
module.exports={projectDedaRealSchema,reviewedDomains};
