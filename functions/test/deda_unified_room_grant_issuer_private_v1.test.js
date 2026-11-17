"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {makeRoomGrantIssuer}=require("../deda_unified_room_grant_issuer_private_v1.js");
const {createRoomReadonlyGuard}=require("../deda_unified_room_readonly_guard_v1.js");
const now=1800000000000,uid="QA_CANONICAL_AUTH_UID_B";
const A="QA_HISTORIC_UID_A", C="QA_HISTORIC_UID_C";
const account="9647712345678",original="@DEDA-ABC123";
const canonicalAccountId="DEDA_QA_CANONICAL_OWNER_ROOM_01";
const digest="f".repeat(64);
const stamp=n=>({toMillis:()=>n});
function fixture(domain="profile"){
 const docs=new Map([
 ["deda_unified_room_owner_authorizations/"+uid,{
  uid,readerUid:uid,status:"independently_verified",
  independentEvidenceSource:"verified_offline_authority",
  evidenceDigest:digest,reviewers:["reviewerOne","reviewerTwo"],
  accountKey:account,originalId:original,canonicalAccountId,
  approvedAtMs:now-10000,expiresAtMs:now+60000}],
 ["deda_unified_room_owner_directory/"+uid,{
  uid,accountKey:account,originalId:original,canonicalAccountId,
  historicalUids:[A,uid,C]}],
 ["deda_sessions/"+uid,{uid,accountKey:account,canonicalAccountId,
  active:true,revision:1,sessionNonce:"QA_CANONICAL_SESSION_NONCE_2026"}],
 ["deda_account_directory/"+account,{active:true,createdUid:uid,accountKey:account}],
 ["deda_credentials/"+account,{active:true,createdUid:uid,accountKey:account}],
 ["deda_share_ids/"+original,{active:true,kind:"personal",publicId:original,ownerUid:A}],
 ["deda_social_profiles/"+original,{publicId:original,ownerUid:C}]
 ]);
 const evidence={status:"INDEPENDENTLY_ATTESTED",
  independentEvidenceSource:"verified_offline_authority",readerUid:uid,
  domain,accountKey:account,originalId:original,canonicalAccountId,
  evidenceDigest:digest,uidA:A,uidB:uid,uidC:C,
  reviewers:["reviewerOne","reviewerTwo"],verifiedAtMs:now-1000};
 const projection={profile:{displayName:"QA owner",level:8},
  original_id:{publicId:original},premium_id:{displayId:"@DEDA-1234",color:"gold"},
  friends:{friendCount:1},league:{weeklyPoints:40},gifts:{giftCount:2},
  wallet:{balanceDisplay:10},places:{publishedPlaceCount:1}}[domain];
 const stats={writes:[],auth:0,reviews:0,projects:0};
 const db={doc:p=>({path:p}),runTransaction:async fn=>{
  const pending=[];
  const tx={get:async ref=>({exists:docs.has(ref.path),data:()=>docs.get(ref.path)}),
   create:(ref,record)=>pending.push([ref.path,record])};
  const result=await fn(tx);
  for(const [path,record] of pending){if(docs.has(path))throw Error("create-conflict");
   docs.set(path,record);stats.writes.push(path);}
  return result;
 }};
 const auth={getUser:async()=>{stats.auth++;return {uid,disabled:false,
  providerData:[{providerId:"password"}]}}};
 const independentlyVerified=async()=>{stats.reviews++;return evidence};
 const projector=async()=>{stats.projects++;return projection};
 const build=(enabled=true)=>makeRoomGrantIssuer({
  db,auth,clock:()=>now,independentReview:independentlyVerified,
  projectDomain:projector,toTimestamp:stamp,enabled});
 return {build,db,auth,evidence,docs,stats};
}
const no=async(p,reason)=>{const x=await p;assert.equal(x.status,"HOLD");if(reason)assert.equal(x.reason,reason);
 assert.equal(x.grantIssued,false)};
test("default OFF prevents any reads, proof lookup and write",async()=>{
 const f=fixture();await no(f.build(false).issue({uid,domain:"profile"}),"ISSUER_NOT_ENABLED");
 assert.deepEqual(f.stats,{writes:[],auth:0,reviews:0,projects:0});
});
test("eight scoped domains are issued atomically, no historic records mutated",async()=>{
 for(const domain of ["profile","original_id","premium_id","friends","league","gifts","wallet","places"]){
  const f=fixture(domain);
  const before=JSON.stringify([...f.docs]);
  const issued=await f.build(true).issue({uid,domain});
  assert.equal(issued.status,"ISSUED_READ_ONLY");
  assert.equal(issued.grantIssued,true);
  assert.equal(f.stats.writes.length,3);
  const grant=f.docs.get("deda_unified_room_read_grants/"+uid+"/domains/"+domain);
  assert.equal(grant.canWrite,false);assert.equal(grant.canCredit,false);
  assert.equal(grant.issuedAt.toMillis(),now);assert.ok(grant.expiresAt.toMillis()<=now+60000);
  assert.equal(JSON.stringify([...f.docs].slice(0,7)),before);
  const reader=createRoomReadonlyGuard({db:f.db,auth:f.auth,clock:()=>now,enabled:true});
  const response=await reader({auth:{uid,token:{firebase:{sign_in_provider:"password"}}},
   app:{appId:"QA_FIREBASE_APP_123456"},input:{domain}});
  assert.equal(response.status,"VERIFIED_READ_ONLY",response.reason);
 }
});
test("cannot issue from PIN, phone or claimed sourceUid as client inputs",async()=>{
 const f=fixture();await no(f.build(true).issue({accountKey:account,pin:"123456",domain:"profile"}),"INVALID_SCOPE");
 assert.equal(f.stats.writes.length,0);
});
test("absent independent attestation or synthetic proof never grants",async()=>{
 const f=fixture();f.evidence.syntheticQaOnly=true;
 await no(f.build(true).issue({uid,domain:"profile"}),"INDEPENDENT_ATTESTATION_REQUIRED");
 assert.equal(f.stats.writes.length,0);
 const g=fixture();g.evidence.status="PENDING";
 await no(g.build(true).issue({uid,domain:"profile"}),"INDEPENDENT_ATTESTATION_REQUIRED");
});
test("historical UID conflict or stale canonical session denies atomically",async()=>{
 const f=fixture();f.docs.get("deda_share_ids/"+original).ownerUid=C;
 await no(f.build(true).issue({uid,domain:"profile"}),"AUTHORITATIVE_HISTORY_CONFLICT");
 const g=fixture();g.docs.get("deda_sessions/"+uid).active=false;
 await no(g.build(true).issue({uid,domain:"profile"}),"CURRENT_CANONICAL_SESSION_NOT_READY");
 assert.equal(f.stats.writes.length,0);assert.equal(g.stats.writes.length,0);
});
test("no duplicate issue; expired or forged review; no financial or UID changes",async()=>{
 const f=fixture("wallet");const issuer=f.build(true);
 assert.equal((await issuer.issue({uid,domain:"wallet"})).grantIssued,true);
 await no(issuer.issue({uid,domain:"wallet"}),"EXISTING_GRANT_REQUIRES_EXPLICIT_REVOCATION");
 assert.equal(f.stats.writes.length,3);
 const g=fixture();g.evidence.verifiedAtMs=now-400000;
 await no(g.build(true).issue({uid,domain:"profile"}),"INDEPENDENT_ATTESTATION_REQUIRED");
 const h=fixture();h.evidence.reviewers=["reviewerOne","reviewerOne"];
 await no(h.build(true).issue({uid,domain:"profile"}),"INDEPENDENT_ATTESTATION_REQUIRED");
});
test("private issuer is not callable / exported by production index",()=>{
 const fs=require("node:fs"),path=require("node:path");
 const index=fs.readFileSync(path.join(__dirname,"../index.js"),"utf8");
 assert.equal(index.includes("deda_unified_room_grant_issuer_private_v1"),false);
});
