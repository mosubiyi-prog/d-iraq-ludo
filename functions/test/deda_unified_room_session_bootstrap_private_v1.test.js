"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {makeRoomSessionBootstrap}=require(
  "../deda_unified_room_session_bootstrap_private_v1.js");
const {makeRoomGrantIssuer}=require("../deda_unified_room_grant_issuer_private_v1.js");
const {createRoomReadonlyGuard}=require("../deda_unified_room_readonly_guard_v1.js");
const NOW=1800000000000,uid="QA_VERIFIED_CURRENT_READER",
  A="QA_HISTORIC_A",B="QA_HISTORIC_B",C="QA_HISTORIC_C",
  key="9647712345678",original="@DEDA-ABC123",
  canonical="QA_CANONICAL_OWNER_ACCOUNT_2026",digest="a".repeat(64),
  nonce="a".repeat(48);
function fixture(){
  const docs=new Map([
    ["deda_account_directory/"+key,{accountKey:key,active:true,createdUid:B}],
    ["deda_credentials/"+key,{accountKey:key,active:true,createdUid:B}],
    ["deda_share_ids/"+original,{publicId:original,kind:"personal",active:true,ownerUid:A}],
    ["deda_social_profiles/"+original,{publicId:original,ownerUid:C}]
  ]);
  const proof={status:"INDEPENDENTLY_ATTESTED",
    independentEvidenceSource:"trusted_independent_recovery_service",
    readerUid:uid,accountKey:key,originalId:original,
    canonicalAccountId:canonical,evidenceDigest:digest,
    uidA:A,uidB:B,uidC:C,
    reviewers:["reviewerAlpha","reviewerBeta"],verifiedAtMs:NOW-1000};
  const stats={writes:[],authCalls:0,reviewCalls:0};
  const db={doc:p=>({path:p}),runTransaction:async fn=>{
    const pending=[];
    const tx={get:async ref=>({exists:docs.has(ref.path),
      data:()=>docs.get(ref.path)}),
      create:(ref,row)=>pending.push([ref.path,row])};
    const out=await fn(tx);
    for(const [path,row] of pending){
      if(docs.has(path))throw Error("duplicate doc");
      docs.set(path,row);stats.writes.push(path);
    }
    return out;
  }};
  const auth={getUser:async reader=>{
    stats.authCalls++;
    return {uid:reader,disabled:false,providerData:[{providerId:"password"}]};
  }};
  const independentReview=async()=>{
    stats.reviewCalls++;
    return proof;
  };
  const make=(enabled=true)=>makeRoomSessionBootstrap({
    db,auth,independentReview,clock:()=>NOW,
    nonceFactory:()=>nonce,enabled
  });
  return {docs,proof,stats,make,db,auth};
}
test("disabled bootstrap makes NO auth, proof, database or UID calls",async()=>{
  const f=fixture();
  const result=await f.make(false).prepare({uid});
  assert.equal(result.status,"HOLD");
  assert.equal(result.reason,"SESSION_BOOTSTRAP_GATE_OFF");
  assert.deepEqual(f.stats,{writes:[],authCalls:0,reviewCalls:0});
});
test("verified independent owner creates 4 protected records, no legacy writes",async()=>{
  const f=fixture();
  const originals=new Map(f.docs);
  const result=await f.make(true).prepare({uid});
  assert.equal(result.status,"ROOM_SESSION_PREPARED");
  assert.equal(result.bootstrapped,true);
  assert.equal(result.uidChanged,false);
  assert.equal(result.accountRestored,false);
  assert.equal(result.financialRestore,false);
  assert.equal(result.adminAccess,false);
  assert.equal(f.stats.writes.length,4);
  assert.equal(f.docs.has("deda_sessions/"+uid),false);
  assert.equal(f.docs.has("deda_sessions/"+B),false);
  for(const [path,row] of originals)assert.deepEqual(f.docs.get(path),row);
  const session=f.docs.get("deda_unified_room_sessions/"+uid);
  assert.equal(session.active,true);
  assert.equal(session.revision,1);
  assert.equal(session.sessionNonce,nonce);
  assert.deepEqual(f.docs.get("deda_unified_room_owner_directory/"+uid)
    .historicalUids,[A,B,C]);
  const owner=f.docs.get("deda_unified_room_owner_authorizations/"+uid);
  assert.equal(owner.status,"independently_verified");
  assert.equal(owner.expiresAtMs,NOW+600000);
  assert.equal(f.docs.has("deda_unified_room_read_grants/"+uid),false);
});
test("old anonymous B session not required; new reader UID must be durable",async()=>{
  const f=fixture();
  assert.equal(f.docs.has("deda_sessions/"+B),false);
  const result=await f.make(true).prepare({uid});
  assert.equal(result.bootstrapped,true);
});
test("synthetic or phone-only proof never creates anything",async()=>{
  for(const bad of [
    p=>{p.syntheticQaOnly=true;},
    p=>{p.independentEvidenceSource="phone_document_only";},
    p=>{p.status="QA_APPROVED";},
    p=>{p.reviewers=["samePerson","samePerson"];}
  ]){
    const f=fixture();bad(f.proof);
    const result=await f.make(true).prepare({uid});
    assert.equal(result.status,"HOLD");
    assert.equal(f.stats.writes.length,0);
  }
});
test("wrong A B or C authoritative source blocks all four room records",async()=>{
  for(const path of ["deda_account_directory/"+key,
    "deda_share_ids/"+original,"deda_social_profiles/"+original]){
    const f=fixture();
    const row=f.docs.get(path);
    if(path.includes("directory"))row.createdUid=A;
    else row.ownerUid=B;
    const result=await f.make(true).prepare({uid});
    assert.equal(result.reason,"AUTHORITATIVE_HISTORY_NOT_CONFIRMED");
    assert.equal(f.stats.writes.length,0);
  }
});
test("room cannot be overwritten or bootstrapped twice",async()=>{
  const f=fixture(),bootstrap=f.make(true);
  assert.equal((await bootstrap.prepare({uid})).bootstrapped,true);
  const count=f.stats.writes.length;
  const second=await bootstrap.prepare({uid});
  assert.equal(second.status,"HOLD");
  assert.equal(second.reason,"EXISTING_ROOM_REQUIRES_REVIEW_NOT_OVERWRITE");
  assert.equal(f.stats.writes.length,count);
});
test("untrusted nonce and reader UID are rejected before writing",async()=>{
  const f=fixture();
  const bad=makeRoomSessionBootstrap({
    db:{doc:x=>({path:x}),runTransaction:async()=>{throw Error("should not be called")}},
    auth:{getUser:async x=>({uid:x,providerData:[{providerId:"password"}]})},
    independentReview:async()=>f.proof,
    nonceFactory:()=>"" ,clock:()=>NOW,enabled:true
  });
  const result=await bad.prepare({uid});
  assert.equal(result.reason,"NONCE_NOT_TRUSTWORTHY");
  assert.equal((await f.make(true).prepare({uid:B})).status,"HOLD");
  assert.equal(f.stats.writes.length,0);
});
test("private bootstrap is never exported by production Cloud Functions",()=>{
  const fs=require("node:fs"),path=require("node:path");
  const index=fs.readFileSync(path.join(__dirname,"../index.js"),"utf8");
  assert.equal(index.includes("deda_unified_room_session_bootstrap_private_v1"),false);
});

test("one protected session bootstraps A/B/C and READS three scopes end to end",async()=>{
  const f=fixture();
  const immutable=new Map([...f.docs].map(([k,v])=>[k,JSON.stringify(v)]));
  const ready=await f.make(true).prepare({uid});
  assert.equal(ready.status,"ROOM_SESSION_PREPARED");
  const issuer=makeRoomGrantIssuer({
    db:f.db,auth:f.auth,clock:()=>NOW,
    independentReview:async({domain})=>({...f.proof,domain}),
    projectDomain:async({domain})=>({
      friends:{friendCount:3},
      league:{weeklyPoints:40},
      original_id:{publicId:original}
    })[domain],
    toTimestamp:ms=>({toMillis:()=>ms}),enabled:true
  });
  const reader=createRoomReadonlyGuard({
    db:f.db,auth:f.auth,clock:()=>NOW,enabled:true
  });
  const input=domain=>({auth:{uid,token:{firebase:{sign_in_provider:"password"}}},
    app:{appId:"QA_FIREBASE_APP_SESSION"},input:{domain}});
  for(const [domain,sourceUid] of [
    ["friends",C],["league",B],["original_id",A]]){
    const issued=await issuer.issue({uid,domain});
    assert.equal(issued.status,"ISSUED_READ_ONLY",domain);
    const grant=f.docs.get("deda_unified_room_read_grants/"+uid+"/domains/"+domain);
    assert.equal(grant.sourceUid,sourceUid);
    const viewed=await reader(input(domain));
    assert.equal(viewed.status,"VERIFIED_READ_ONLY",domain);
    assert.equal(viewed.authorized,true);
  }
  assert.equal(f.docs.has("deda_sessions/"+uid),false);
  assert.equal(f.docs.has("deda_sessions/"+B),false);
  for(const [path,encoded] of immutable){
    assert.equal(JSON.stringify(f.docs.get(path)),encoded,
      "legacy source changed: "+path);
  }
  // The same Firebase UID after a session rotation has NO inherited grants.
  f.docs.get("deda_unified_room_sessions/"+uid).revision=2;
  for(const domain of ["friends","league","original_id"]){
    const viewed=await reader(input(domain));
    assert.equal(viewed.status,"HOLD");
    assert.equal(viewed.authorized,false);
  }
  assert.equal(f.stats.writes.length,13);
});
