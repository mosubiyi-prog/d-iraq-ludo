"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {inspectLegacyProgressReadback:inspect,keys}=
 require("./deda_point2_legacy_progress_reconciliation_PRIVATE_QA.cjs");
const nowMs=Date.now();
const A="QA_HISTORIC_ORIGINAL_UID_A";
const B="QA_HISTORIC_CREATED_UID_B";
const C="QA_HISTORIC_SOCIAL_UID_C";
const accountKey="9647712345678",originalId="@DEDA-ABC123";
const canonicalAccountId="QA_CANONICAL_PROGRESS_ACCOUNT_01";
const room={accountKey,originalId,canonicalAccountId,
 historicalUids:[A,B,C]};
const session={uid:B,canonicalAccountId,active:true,revision:42,
 sessionNonce:"QA_PROGRESS_SESSION_NONCE_42"};
const installId="0123456789abcdef".repeat(3);
const saved={
 taskPoints:'{"version":1,"completions":{},"awards":{},"ledger":[]}',
 socialCoinsAndXp:'{"level":13,"xp":1240,"coins":2112}',
 earnedDiamonds:'{"earned":501,"spent":33,"claims":[]}'
};
const fixture=()=>({
 accountKey,originalId,canonicalAccountId,originalSourceUid:A,
 room:structuredClone(room),session:structuredClone(session),nowMs,
 captures:[{
  format:1,kind:"legacy-local-evidence",accountKey,
  sourceUid:A,captureId:"QA_PROGRESS_CAP_000000001",
  documentId:"QA_PROGRESS_CAP_000000001",
  installId,createdAtMs:nowMs-10000,
  fromCache:false,pendingWrites:false,
  records:structuredClone(saved)
 }]
});
const forbidden=["canWriteToDevice","canRestoreBalances",
 "canAwardPoints","canReissuePrizes","canOpenHistoricalUid",
 "restoresLegacyProgress","fullyRestored"];
async function hold(testcase,reason){
 const out=inspect(testcase);
 assert.equal(out.decision,"HOLD");
 if(reason)assert.equal(out.reason,reason);
 assert.equal(out.dataLossPrevented,true);
 for(const field of forbidden)assert.equal(out[field],false);
}
test("original legacy keys exactly match DEDA SharedPreferences domain",()=>{
 assert.deepEqual(keys,["taskPoints","socialCoinsAndXp","earnedDiamonds"]);
});
test("matching archival raw bytes are review candidate ONLY, never restoration",()=>{
 const out=inspect(fixture());
 assert.equal(out.decision,"QA_LOSSLESS_ARCHIVE_REVIEW_CANDIDATE");
 assert.equal(out.archiveDigest.length,64);
 assert.equal(out.dataLossPrevented,true);
 for(const field of forbidden)assert.equal(out[field],false);
 assert.equal(JSON.stringify(out).includes("2112"),false);
});
test("missing server original backup never becomes zero",()=>{
 const f=fixture();f.captures=[];
 return hold(f,"NO_UNAMBIGUOUS_ORIGINAL_BACKUP");
});
test("multiple discrepant snapshots do not choose higher level or diamonds",()=>{
 const f=fixture();const newer=structuredClone(f.captures[0]);
 newer.captureId="QA_PROGRESS_CAP_000000002";
 newer.documentId=newer.captureId;
 newer.records.socialCoinsAndXp='{"level":20,"xp":2000,"coins":9000}';
 f.captures.push(newer);
 return hold(f,"OLD_DEVICE_SNAPSHOTS_DISAGREE");
});
test("cache and pending writes cannot be presented as trusted server readback",()=>{
 const f=fixture();f.captures[0].fromCache=true;
 hold(f,"ARCHIVE_PROVENANCE_OR_SCHEMA_CONFLICT");
 const g=fixture();g.captures[0].pendingWrites=true;
 hold(g,"ARCHIVE_PROVENANCE_OR_SCHEMA_CONFLICT");
});
test("wrong owner source C or later different room is blocked",()=>{
 const f=fixture();f.captures[0].sourceUid=C;
 hold(f,"ARCHIVE_PROVENANCE_OR_SCHEMA_CONFLICT");
 const g=fixture();g.room.historicalUids=[A,B,"QA_DIFFERENT_ACCOUNT_D"];
 g.originalSourceUid=C;
 hold(g,"ROOM_OR_SESSION_NOT_AUTHORITATIVE");
});
test("changed session, missing member B, and mismatched account blocked",()=>{
 const f=fixture();f.session.active=false;
 hold(f,"ROOM_OR_SESSION_NOT_AUTHORITATIVE");
 const g=fixture();g.room.historicalUids=[A,"QA_NOT_B",C];
 hold(g,"ROOM_OR_SESSION_NOT_AUTHORITATIVE");
 const h=fixture();h.captures[0].accountKey="9647900000000";
 hold(h,"ARCHIVE_PROVENANCE_OR_SCHEMA_CONFLICT");
});
test("missing raw XP/coins with a points snapshot stays candidate, not success",()=>{
 const f=fixture();
 f.captures[0].records.socialCoinsAndXp=null;
 f.captures[0].records.earnedDiamonds=null;
 const out=inspect(f);
 assert.equal(out.decision,"QA_LOSSLESS_ARCHIVE_REVIEW_CANDIDATE");
 assert.equal(out.fullyRestored,false);
});
test("all three missing is HOLD, not empty balance",()=>{
 const f=fixture();f.captures[0].records={
 taskPoints:null,socialCoinsAndXp:null,earnedDiamonds:null};
 hold(f,"ALL_LOCAL_PROGRESS_SOURCES_MISSING");
});
test("already present device state is never overwritten by older source",()=>{
 const f=fixture();f.existingLocal={
 taskPoints:saved.taskPoints,socialCoinsAndXp:'{"xp":9999,"coins":15}'};
 hold(f,"NEW_DEVICE_LOCAL_STATE_CONFLICT_PRESERVED");
});
test("identical local raw source is safe readback candidate but NO write",()=>{
 const f=fixture();f.existingLocal={
 taskPoints:saved.taskPoints,
 socialCoinsAndXp:saved.socialCoinsAndXp,
 earnedDiamonds:saved.earnedDiamonds};
 const out=inspect(f);
 assert.equal(out.decision,"QA_LOSSLESS_ARCHIVE_REVIEW_CANDIDATE");
 for(const field of forbidden)assert.equal(out[field],false);
});
test("malformed historical JSON preserved as raw evidence, not spendable",()=>{
 const f=fixture();f.captures[0].records.socialCoinsAndXp="{broken old data";
 const out=inspect(f);
 assert.equal(out.decision,"QA_LOSSLESS_ARCHIVE_REVIEW_CANDIDATE");
 assert.equal(out.canRestoreBalances,false);
});
test("duplicate capture ID or install mismatch rejected",()=>{
 const f=fixture();f.captures.push(structuredClone(f.captures[0]));
 hold(f,"ARCHIVE_PROVENANCE_OR_SCHEMA_CONFLICT");
 const g=fixture();const duplicate=structuredClone(g.captures[0]);
 duplicate.captureId="QA_PROGRESS_CAP_000000003";
 duplicate.documentId=duplicate.captureId;
 duplicate.installId="f".repeat(48);
 g.captures.push(duplicate);
 hold(g,"OLD_DEVICE_SNAPSHOTS_DISAGREE");
});
test("unknown fields and oversized payload blocked",()=>{
 const f=fixture();f.captures[0].records.extra="bad";
 hold(f,"ARCHIVE_PROVENANCE_OR_SCHEMA_CONFLICT");
 const g=fixture();g.captures[0].records.taskPoints="x".repeat(200001);
 hold(g,"ARCHIVE_PROVENANCE_OR_SCHEMA_CONFLICT");
});
test("more than 25 captures, future timestamp or malformed existing local blocked",()=>{
 const f=fixture();f.captures=Array.from({length:26},(_,i)=>({
  ...structuredClone(f.captures[0]),
  captureId:"QA_PROGRESS_CAP_"+String(i).padStart(12,"0"),
  documentId:"QA_PROGRESS_CAP_"+String(i).padStart(12,"0")}));
 hold(f,"NO_UNAMBIGUOUS_ORIGINAL_BACKUP");
 const g=fixture();g.captures[0].createdAtMs=nowMs+1;
 hold(g,"ARCHIVE_PROVENANCE_OR_SCHEMA_CONFLICT");
 const h=fixture();h.existingLocal={coins:100};
 hold(h,"EXISTING_DEVICE_STATE_UNTRUSTED");
});
