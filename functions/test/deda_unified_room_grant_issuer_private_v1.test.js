"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {makeRoomGrantIssuer}=require("../deda_unified_room_grant_issuer_private_v1.js");
const {createRoomReadonlyGuard}=require("../deda_unified_room_readonly_guard_v1.js");
const now=1800000000000,uid="QA_CURRENT_VERIFIED_READER_UID";
const A="QA_HISTORIC_UID_A", B="QA_HISTORIC_UID_B", C="QA_HISTORIC_UID_C";
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
  historicalUids:[A,B,C],approvedAtMs:now-10000,expiresAtMs:now-10000+24*60*60*1000}],
 ["deda_unified_room_owner_directory/"+uid,{
  uid,accountKey:account,originalId:original,canonicalAccountId,
  historicalUids:[A,B,C]}],
 ["deda_unified_room_sessions/"+uid,{uid,accountKey:account,canonicalAccountId,
  active:true,revision:1,sessionNonce:"QA_CANONICAL_SESSION_NONCE_2026"}],
 ["deda_account_directory/"+account,{active:true,createdUid:B,accountKey:account}],
 ["deda_credentials/"+account,{active:true,createdUid:B,accountKey:account}],
 ["deda_share_ids/"+original,{active:true,kind:"personal",publicId:original,ownerUid:A}],
 ["deda_social_profiles/"+original,{publicId:original,ownerUid:C}]
 ]);
 const evidence={status:"INDEPENDENTLY_ATTESTED",
  independentEvidenceSource:"verified_offline_authority",readerUid:uid,
  domain,accountKey:account,originalId:original,canonicalAccountId,
  evidenceDigest:digest,uidA:A,uidB:B,uidC:C,
  reviewers:["reviewerOne","reviewerTwo"],verifiedAtMs:now-1000};
 const projection={profile:{displayName:"QA owner",level:8},
  original_id:{publicId:original},premium_id:{displayId:"@DEDA-1234",color:"gold"},
  friends:{friendCount:1},league:{weeklyPoints:40},gifts:{giftCount:2},
  wallet:{balanceDisplay:10},places:{publishedPlaceCount:1}}[domain];
 let clockMs=now;
 const stats={writes:[],auth:0,reviews:0,projects:0};
 const db={doc:p=>({path:p}),runTransaction:async fn=>{
  const pending=[];
  const tx={get:async ref=>({exists:docs.has(ref.path),data:()=>docs.get(ref.path)}),
   create:(ref,record)=>pending.push([ref.path,record]),
   update:(ref,patch)=>pending.push([ref.path,{...docs.get(ref.path),...patch},"update"])};
  const result=await fn(tx);
  for(const [path,record,kind] of pending){if(kind!=="update"&&docs.has(path))throw Error("create-conflict");
   if(kind==="update"&&!docs.has(path))throw Error("missing-update");
   docs.set(path,record);stats.writes.push(path);}
  return result;
 }};
 const auth={getUser:async()=>{stats.auth++;return {uid,disabled:false,
  providerData:[{providerId:"password"}]}}};
 const independentlyVerified=async()=>{stats.reviews++;return evidence};
 const projector=async()=>{stats.projects++;return projection};
 const build=(enabled=true)=>makeRoomGrantIssuer({
  db,auth,clock:()=>clockMs,independentReview:independentlyVerified,
  projectDomain:projector,toTimestamp:stamp,enabled});
 return {build,db,auth,evidence,docs,stats,setTime:t=>{clockMs=t}};
}
const no=async(p,reason)=>{const x=await p;assert.equal(x.status,"HOLD");if(reason)assert.equal(x.reason,reason);
 assert.equal(x.grantIssued,false)};
test("default OFF prevents any reads, proof lookup and write",async()=>{
 const f=fixture();await no(f.build(false).issue({uid,domain:"profile"}),"ISSUER_NOT_ENABLED");
 assert.deepEqual(f.stats,{writes:[],auth:0,reviews:0,projects:0});
});
test("new verified reader works without historical B session",async()=>{
 const f=fixture();
 assert.notEqual(uid,B);
 assert.equal(f.docs.has("deda_unified_room_sessions/"+B),false);
 const out=await f.build(true).issue({uid,domain:"profile"});
 assert.equal(out.status,"ISSUED_READ_ONLY");
 assert.equal(f.docs.get("deda_unified_room_read_grants/"+uid+"/domains/profile")
  .sourceUid,B);
 assert.equal(f.docs.has("deda_unified_room_sessions/"+B),false);
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
  assert.equal(grant.sessionRevision,1);
  assert.equal(grant.sessionNonce,"QA_CANONICAL_SESSION_NONCE_2026");
  const view=f.docs.get("deda_unified_room_private_views/"+uid+"/domains/"+domain);
  assert.equal(view.sessionRevision,1);
  assert.equal(view.sessionNonce,"QA_CANONICAL_SESSION_NONCE_2026");
  assert.equal(grant.issuedAt.toMillis(),now);assert.ok(grant.expiresAt.toMillis()<=now+5*60*1000);
  assert.equal(JSON.stringify([...f.docs].slice(0,7)),before);
  const reader=createRoomReadonlyGuard({db:f.db,auth:f.auth,clock:()=>now,enabled:true});
  const response=await reader({auth:{uid,token:{firebase:{sign_in_provider:"password"}}},
   app:{appId:"QA_FIREBASE_APP_123456"},input:{domain}});
  assert.equal(response.status,"VERIFIED_READ_ONLY",response.reason);
 }
});
test("one independently approved reviewer may issue, but no caller-provided proof",async()=>{
  const f=fixture();
  f.evidence.reviewers=["trustedIndependentAuthority"];
  f.docs.get("deda_unified_room_owner_authorizations/"+uid).reviewers=
    ["trustedIndependentAuthority"];
  const result=await f.build(true).issue({uid,domain:"profile"});
  assert.equal(result.status,"ISSUED_READ_ONLY");
  const guard=createRoomReadonlyGuard({db:f.db,auth:f.auth,clock:()=>now,enabled:true});
  assert.equal((await guard({auth:{uid,token:{firebase:{sign_in_provider:"password"}}},
    app:{appId:"QA_FIREBASE_APP_123456"},input:{domain:"profile"}})).authorized,true);
});
test("expired scope renews under same owner, new attestation, no legacy writes",async()=>{
  const f=fixture(),issuer=f.build(true);
  const sourceBefore=new Map([...f.docs].filter(([path])=>!path.startsWith("deda_unified_room_")));
  assert.equal((await issuer.issue({uid,domain:"profile"})).status,"ISSUED_READ_ONLY");
  const later=now+5*60*1000+1000;
  f.setTime(later);
  await no(issuer.issue({uid,domain:"profile"}),"INDEPENDENT_ATTESTATION_REQUIRED");
  f.evidence.verifiedAtMs=later-500;
  const result=await issuer.issue({uid,domain:"profile"});
  assert.equal(result.status,"RENEWED_READ_ONLY");
  assert.equal(result.grantIssued,true);
  const guard=createRoomReadonlyGuard({db:f.db,auth:f.auth,clock:()=>later,enabled:true});
  const read=await guard({auth:{uid,token:{firebase:{sign_in_provider:"password"}}},
    app:{appId:"QA_FIREBASE_APP_123456"},input:{domain:"profile"}});
  assert.equal(read.status,"VERIFIED_READ_ONLY");
  assert.deepEqual([...f.docs].filter(([path])=>!path.startsWith("deda_unified_room_")),
    [...sourceBefore]);
  assert.ok(f.docs.has("deda_unified_room_grant_renewals/"+uid+"/domains/profile/events/"+later));
  await no(issuer.issue({uid,domain:"profile"}),"EXISTING_GRANT_REQUIRES_EXPLICIT_REVOCATION");
  assert.equal(f.stats.writes.length,6); // three initial, three renewal
});
test("revoked and rotated sessions cannot renew after token expiry",async()=>{
  for(const kind of ["revoked","rotated"]){
    const f=fixture(),issuer=f.build(true);
    assert.equal((await issuer.issue({uid,domain:"friends"})).grantIssued,true);
    if(kind==="revoked")assert.equal(
      (await issuer.revoke({uid,domain:"friends"})).status,"REVOKED_READ_ONLY");
    else f.docs.get("deda_unified_room_sessions/"+uid).sessionNonce="QA_REPLACED_SESSION_NONCE";
    const writes=f.stats.writes.length;
    const later=now+5*60*1000+1000;f.setTime(later);
    f.evidence.verifiedAtMs=later-500;
    await no(issuer.issue({uid,domain:"friends"}),"EXISTING_GRANT_REQUIRES_EXPLICIT_REVOCATION");
    assert.equal(f.stats.writes.length,writes);
  }
});
test("cannot issue from PIN, phone or claimed sourceUid as client inputs",async()=>{
 const f=fixture();await no(f.build(true).issue({accountKey:account,pin:"123456",domain:"profile"}),"INVALID_SCOPE");
 assert.equal(f.stats.writes.length,0);
});
test("trusted independent recovery authority is allowed WITHOUT telephone papers",async()=>{
 const f=fixture("profile");
 f.evidence.independentEvidenceSource="trusted_independent_recovery_service";
 f.docs.get("deda_unified_room_owner_authorizations/"+uid)
  .independentEvidenceSource="trusted_independent_recovery_service";
 const out=await f.build(true).issue({uid,domain:"profile"});
 assert.equal(out.status,"ISSUED_READ_ONLY");
 assert.equal(f.docs.has("deda_unified_room_sessions/"+B),false);
});
test("unverified client declaration of telephone ownership never issues grants",async()=>{
 const f=fixture("profile");
 f.evidence.independentEvidenceSource="phone_document_only";
 f.docs.get("deda_unified_room_owner_authorizations/"+uid)
  .independentEvidenceSource="phone_document_only";
 await no(f.build(true).issue({uid,domain:"profile"}),"INDEPENDENT_ATTESTATION_REQUIRED");
 assert.equal(f.stats.writes.length,0);
});
test("absent independent attestation or synthetic proof never grants",async()=>{
 const f=fixture();f.evidence.syntheticQaOnly=true;
 await no(f.build(true).issue({uid,domain:"profile"}),"INDEPENDENT_ATTESTATION_REQUIRED");
 assert.equal(f.stats.writes.length,0);
 const g=fixture();g.evidence.status="PENDING";
 await no(g.build(true).issue({uid,domain:"profile"}),"INDEPENDENT_ATTESTATION_REQUIRED");
});
test("fake historical B or another reader cannot acquire grant",async()=>{
 const f=fixture();
 f.docs.get("deda_credentials/"+account).createdUid="QA_UNRELATED_UID_X";
 await no(f.build(true).issue({uid,domain:"profile"}),"AUTHORITATIVE_HISTORY_CONFLICT");
 const g=fixture();g.evidence.uidB="QA_UNRELATED_UID_X";
 await no(g.build(true).issue({uid,domain:"profile"}),"INDEPENDENT_OWNER_RECORD_NOT_APPROVED");
 const h=fixture();h.evidence.readerUid=B;
 await no(h.build(true).issue({uid,domain:"profile"}),"INDEPENDENT_ATTESTATION_REQUIRED");
 assert.deepEqual([f.stats.writes.length,g.stats.writes.length,h.stats.writes.length],[0,0,0]);
});
test("historical UID conflict or stale canonical session denies atomically",async()=>{
 const f=fixture();f.docs.get("deda_share_ids/"+original).ownerUid=C;
 await no(f.build(true).issue({uid,domain:"profile"}),"AUTHORITATIVE_HISTORY_CONFLICT");
 const g=fixture();g.docs.get("deda_unified_room_sessions/"+uid).active=false;
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

test("revocation blocks reader immediately and never touches historic source",async()=>{
 const f=fixture("original_id"),issuer=f.build(true);
 const issue=await issuer.issue({uid,domain:"original_id"});
 assert.equal(issue.grantIssued,true);
 const before=f.docs.get("deda_share_ids/"+original);
 const revoked=await issuer.revoke({uid,domain:"original_id"});
 assert.equal(revoked.status,"REVOKED_READ_ONLY");
 assert.equal(f.docs.get("deda_unified_room_read_grants/"+uid+
    "/domains/original_id").status,"revoked");
 assert.equal(f.docs.get("deda_share_ids/"+original),before);
 assert.equal(f.stats.writes.length,5); // three issuance writes, two revocation writes
 const reader=createRoomReadonlyGuard({db:f.db,auth:f.auth,clock:()=>now,enabled:true});
 const res=await reader({auth:{uid,token:{firebase:{sign_in_provider:"password"}}},
   app:{appId:"QA_FIREBASE_APP_123456"},input:{domain:"original_id"}});
 assert.equal(res.status,"HOLD");
 assert.equal(res.reason,"SPECIFIC_DOMAIN_PROOF_NOT_VERIFIED");
 assert.equal((await issuer.revoke({uid,domain:"original_id"})).status,"REVOKED_READ_ONLY");
 assert.equal(f.stats.writes.length,5);
});
test("unknown or disabled revocation never creates any grant",async()=>{
 const f=fixture();
 await no(f.build(false).revoke({uid,domain:"profile"}),"ISSUER_NOT_ENABLED");
 await no(f.build(true).revoke({uid,domain:"profile"}),"TRUSTED_GRANT_NOT_FOUND");
 assert.equal(f.stats.writes.length,0);
});

test("grant issuer remains bounded to the current reader session and domain source",async()=>{
 for(const domain of ["profile","league","friends","original_id"]){
  const f=fixture(domain);
  const out=await f.build(true).issue({uid,domain});
  assert.equal(out.grantIssued,true);
  const grant=f.docs.get("deda_unified_room_read_grants/"+uid+"/domains/"+domain);
  const expected=domain==="friends"?C:["profile","league"].includes(domain)?B:A;
  assert.equal(grant.sourceUid,expected);
  f.docs.get("deda_unified_room_sessions/"+uid).sessionNonce="QA_NEW_SESSION_NONCE_REPLAY_BLOCK";
  const reader=createRoomReadonlyGuard({db:f.db,auth:f.auth,clock:()=>now,enabled:true});
  const response=await reader({auth:{uid,token:{firebase:{sign_in_provider:"password"}}},
   app:{appId:"QA_FIREBASE_APP_123456"},input:{domain}});
  assert.equal(response.status,"HOLD");
  assert.equal(response.reason,"SPECIFIC_DOMAIN_PROOF_NOT_VERIFIED");
 }
});
