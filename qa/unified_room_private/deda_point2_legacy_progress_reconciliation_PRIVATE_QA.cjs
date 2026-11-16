"use strict";
/*
 * DEDA Point 2: historic local-progress readback candidate, PRIVATE QA ONLY.
 * Mirrors three original SharedPreferences raw keys and the pre-existing
 * deda_progress_evidence/{accountKey}/captures/{captureId} envelope.
 * Source capture IS NOT ownership proof, credited diamonds, or restored XP.
 * Never writes device, Firestore, admin, Auth, grant, or reward data.
 */
const {createHash}=require("node:crypto");
const keys=Object.freeze(["taskPoints","socialCoinsAndXp","earnedDiamonds"]);
const accountOk=s=>typeof s==="string"&&/^(?:07\d{9}|9647\d{9})$/.test(s);
const uidOk=s=>typeof s==="string"&&/^[A-Za-z0-9_-]{6,128}$/.test(s);
const hash=s=>createHash("sha256").update(s).digest("hex");
const hold=reason=>Object.freeze({decision:"HOLD",reason,
 dataLossPrevented:true,canWriteToDevice:false,canRestoreBalances:false,
 canAwardPoints:false,canReissuePrizes:false,canOpenHistoricalUid:false,
 restoresLegacyProgress:false,fullyRestored:false});
const candidate=(sourceDigest)=>Object.freeze({
 ...hold("REQUIRES_INDEPENDENT_OWNER_AND_SERVER_AUTHORIZATION"),
 decision:"QA_LOSSLESS_ARCHIVE_REVIEW_CANDIDATE",archiveDigest:sourceDigest
});
function inspectLegacyProgressReadback({accountKey,originalId,
 canonicalAccountId,originalSourceUid,room,session,captures,
 existingLocal,nowMs}={}){
 if(!accountOk(accountKey)||!/^@DEDA-[A-Z0-9]{6}$/.test(originalId||"")||
   !uidOk(originalSourceUid)||typeof canonicalAccountId!=="string"||
   canonicalAccountId.length<12||!Number.isSafeInteger(nowMs)||
   nowMs<=0)return hold("INVALID_SCOPE_OR_TIME");
 if(room?.accountKey!==accountKey||room?.originalId!==originalId||
   room?.canonicalAccountId!==canonicalAccountId||
   !Array.isArray(room.historicalUids)||room.historicalUids.length!==3||
   new Set(room.historicalUids).size!==3||
   !room.historicalUids.every(uidOk)||
   !room.historicalUids.includes(originalSourceUid)||
   !room.historicalUids.includes(session?.uid)||
   session?.canonicalAccountId!==canonicalAccountId||
   session?.active!==true||
   !Number.isSafeInteger(session.revision)||
   session.revision<=0||
   typeof session.sessionNonce!=="string"||
   session.sessionNonce.length<12)return hold("ROOM_OR_SESSION_NOT_AUTHORITATIVE");
 if(!Array.isArray(captures)||captures.length===0||
   captures.length>25)return hold("NO_UNAMBIGUOUS_ORIGINAL_BACKUP");
 let reference=null,previousInstall=null;
 const ids=new Set();
 for(const row of captures){
   if(!row||row.format!==1||row.kind!=="legacy-local-evidence"||
      row.accountKey!==accountKey||row.sourceUid!==originalSourceUid||
      typeof row.captureId!=="string"||
      !/^[A-Za-z0-9_-]{20,80}$/.test(row.captureId)||
      row.documentId!==row.captureId||ids.has(row.captureId)||
      !/^[0-9a-f]{48}$/.test(row.installId||"")||
      row.fromCache!==false||row.pendingWrites!==false||
      !Number.isSafeInteger(row.createdAtMs)||row.createdAtMs<=0||
      row.createdAtMs>nowMs||
      !row.records||typeof row.records!=="object"||
      Array.isArray(row.records)||
      Object.keys(row.records).length!==keys.length||
      !keys.every(k=>Object.hasOwn(row.records,k)&&
       (row.records[k]===null||
        typeof row.records[k]==="string"&&
        Buffer.byteLength(row.records[k],"utf8")<=200000)))
     return hold("ARCHIVE_PROVENANCE_OR_SCHEMA_CONFLICT");
   ids.add(row.captureId);
   // Preserve exact UTF-8 bytes; malformed legacy JSON is still evidence,
   // NEVER silently coerce it to an empty object or zero balance.
   const exact=JSON.stringify(keys.map(k=>row.records[k]));
   if(reference!==null&&
      (reference!==exact||previousInstall!==row.installId))
      return hold("OLD_DEVICE_SNAPSHOTS_DISAGREE");
   reference=exact;
   previousInstall=row.installId;
 }
 const values=captures[0].records;
 if(keys.every(k=>values[k]===null))
   return hold("ALL_LOCAL_PROGRESS_SOURCES_MISSING");
 // Existing local values on a replacement phone take precedence; an
 // incompatible existing blob is not overwritten.
 if(existingLocal!==undefined){
   if(!existingLocal||typeof existingLocal!=="object"||
     Array.isArray(existingLocal)||
     Object.keys(existingLocal).some(k=>!keys.includes(k))||
     Object.keys(existingLocal).some(k=>existingLocal[k]!==null&&
       typeof existingLocal[k]!=="string"))
     return hold("EXISTING_DEVICE_STATE_UNTRUSTED");
   for(const k of keys){
     const onDevice=existingLocal[k];
     if(onDevice!==undefined&&onDevice!==null&&
        onDevice!==values[k])
       return hold("NEW_DEVICE_LOCAL_STATE_CONFLICT_PRESERVED");
   }
 }
 // This validates evidence shape and continuity only. No keys, amounts,
 // points, payouts, Firebase logins, or privilege changes are returned.
 return candidate(hash(reference));
}
module.exports={inspectLegacyProgressReadback,keys};
