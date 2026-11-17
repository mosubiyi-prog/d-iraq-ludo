"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {createRoomReadonlyGuard,DOMAINS}=require(
  "../deda_unified_room_readonly_guard_v1.js");
const NOW=1800000000000;
const stamp=ms=>Object.freeze({toMillis:()=>ms});
const uid="QA_CURRENT_VERIFIED_READER_UID",a="QA_HISTORIC_UID_A",
 b="QA_HISTORIC_UID_B",c="QA_HISTORIC_UID_C";
const accountKey="9647712345678",originalId="@DEDA-ABC123";
const canonicalAccountId="DEDA_QA_CANONICAL_OWNER_ROOM_01";
const evidenceDigest="f".repeat(64);
const payloads={
  profile:{displayName:"Original account",level:13},
  original_id:{publicId:originalId},
  premium_id:{displayId:"@DEDA-1234",color:"gold"},
  friends:{friendCount:2},
  league:{weeklyPoints:200},
  gifts:{giftCount:5},
  wallet:{balanceDisplay:100,giftWalletBalance:70},
  places:{publishedPlaceCount:2}
};
function fixture(domain="profile"){
 const base="deda_unified_room_owner_authorizations/"+uid;
 const docs=new Map([
  [base,{uid,readerUid:uid,accountKey,originalId,
   canonicalAccountId,historicalUids:[a,b,c],status:"independently_verified",
   independentEvidenceSource:"verified_offline_authority",
   evidenceDigest,reviewers:["realReviewer1","realReviewer2"],
   approvedAtMs:NOW-3000,expiresAtMs:NOW+60000}],
  ["deda_unified_room_sessions/"+uid,{uid,accountKey,active:true,
    canonicalAccountId,revision:1,sessionNonce:"QA_SESSION_NONCE_1234567890"}],
  ["deda_unified_room_owner_directory/"+uid,{
   uid,accountKey,originalId,canonicalAccountId,
   historicalUids:[a,b,c]}],
  ["deda_unified_room_read_grants/"+uid+"/domains/"+domain,{
   readerUid:uid,domain,status:"active",scopeVersion:1,
   proofKind:"independent_verified",
   ownerEvidenceDigest:evidenceDigest,
   canonicalAccountId,originalId,
   sessionRevision:1,sessionNonce:"QA_SESSION_NONCE_1234567890",
   sourceUid:domain==="friends"?c:["profile","league"].includes(domain)?b:a,
   issuedAt:stamp(NOW-2000),expiresAt:stamp(NOW+10000),
   canWrite:false,canCredit:false}],
  ["deda_unified_room_private_views/"+uid+"/domains/"+domain,{
   readerUid:uid,domain,sourceUid:domain==="friends"?c:["profile","league"].includes(domain)?b:a,
   canonicalAccountId,originalId,scopeVersion:1,
   sessionRevision:1,sessionNonce:"QA_SESSION_NONCE_1234567890",
   payload:payloads[domain]}]
 ]);
 let reads=0,writes=0,authCalls=0;
 const db={
  doc:p=>({path:p}),
  runTransaction:async fn=>fn({
   get:async ref=>{reads++;const found=docs.get(ref.path);
    return {exists:found!==undefined,data:()=>found};},
   set:()=>writes++,create:()=>writes++,update:()=>writes++,delete:()=>writes++
  })
 };
 const auth={getUser:async target=>{
   authCalls++;return {uid:target,disabled:false};
 }};
 const request={
  auth:{uid,token:{firebase:{sign_in_provider:"password"}}},
  app:{appId:"QA_FIREBASE_APP_123456"},input:{domain}
 };
 const guard=(enabled=true)=>createRoomReadonlyGuard({
  db,auth,clock:()=>NOW,enabled});
 return {docs,guard,request,stats:()=>({reads,writes,authCalls})};
}
const hold=async(f,code)=>{const x=await f();assert.equal(x.status,"HOLD");
 if(code)assert.equal(x.reason,code);
 assert.equal(x.authorized,false);assert.equal(x.accountRestored,false);
 assert.equal(x.uidChanged,false);assert.equal(x.financialRestore,false);};
test("mandatory OFF flag holds without a single backend read",async()=>{
 const f=fixture();
 await hold(()=>f.guard(false)(f.request),"UNIFIED_ROOM_PRODUCTION_GATE_OFF");
 assert.deepEqual(f.stats(),{reads:0,writes:0,authCalls:0});
});
test("eight domain server-only projection contracts, NO account/financial restore",async()=>{
 for(const domain of Object.keys(DOMAINS)){
  const f=fixture(domain);
  const out=await f.guard(true)(f.request);
  assert.equal(out.status,"VERIFIED_READ_ONLY");
  assert.equal(out.domain,domain);
  assert.deepEqual(out.payload,payloads[domain]);
  assert.equal(out.accountRestored,false);
  assert.equal(out.financialRestore,false);
  assert.equal(out.uidChanged,false);
  assert.equal(f.stats().writes,0);
 }
});
test("missing or guessed proof, accountKey or only a PIN is not a grant",async()=>{
 const f=fixture();f.docs.delete("deda_unified_room_owner_authorizations/"+uid);
 await hold(()=>f.guard(true)(f.request),"SERVER_OWNER_SCOPE_VIEW_MISSING");
 const g=fixture();g.request.input={domain:"profile",pin:"123456"};
 await hold(()=>g.guard(true)(g.request),"EXACT_SINGLE_DOMAIN_REQUIRED");
});
test("auth UID and App Check mandatory; anonymous provider refused",async()=>{
 const f=fixture();f.request.app=null;
 await hold(()=>f.guard(true)(f.request),"AUTH_AND_APPCHECK_REQUIRED");
 const g=fixture();g.request.auth.token.firebase.sign_in_provider="anonymous";
 await hold(()=>g.guard(true)(g.request),"DURABLE_UNSPLIT_SESSION_REQUIRED");
});
test("client cannot request historic A or C as a different reader",async()=>{
 const f=fixture();f.request.auth.uid=a;
 await hold(()=>f.guard(true)(f.request),"SERVER_OWNER_SCOPE_VIEW_MISSING");
 const g=fixture();g.request.input={domain:"original_id",readerUid:a};
 await hold(()=>g.guard(true)(g.request),"EXACT_SINGLE_DOMAIN_REQUIRED");
});
test("trusted independent recovery-service owner authorization passes",async()=>{
 const f=fixture("profile");
 f.docs.get("deda_unified_room_owner_authorizations/"+uid)
  .independentEvidenceSource="trusted_independent_recovery_service";
 const result=await f.guard(true)(f.request);
 assert.equal(result.status,"VERIFIED_READ_ONLY");
});
test("an asserted telephone document alone never approves owner access",async()=>{
 const f=fixture("profile");
 f.docs.get("deda_unified_room_owner_authorizations/"+uid)
  .independentEvidenceSource="phone_document_only";
 await hold(()=>f.guard(true)(f.request),"INDEPENDENT_OWNER_AUTHORIZATION_NOT_VERIFIED");
});
test("review source must be independent, two reviewers distinct, not QA",async()=>{
 const f=fixture();const x=f.docs.get("deda_unified_room_owner_authorizations/"+uid);
 x.independentEvidenceSource="isolated-fake-only";
 await hold(()=>f.guard(true)(f.request),"INDEPENDENT_OWNER_AUTHORIZATION_NOT_VERIFIED");
 const g=fixture();const r=g.docs.get("deda_unified_room_owner_authorizations/"+uid);
 r.reviewers=["qaReviewer","qaReviewer"];
 await hold(()=>g.guard(true)(g.request),"INDEPENDENT_OWNER_AUTHORIZATION_NOT_VERIFIED");
});
test("revoked or expired independent review is HOLD",async()=>{
 const f=fixture();f.docs.get("deda_unified_room_owner_authorizations/"+uid).expiresAtMs=NOW-1;
 await hold(()=>f.guard(true)(f.request),"INDEPENDENT_OWNER_AUTHORIZATION_NOT_VERIFIED");
});
test("missing historical B session is not required for authorized current reader",async()=>{
 const f=fixture("profile");
 assert.equal(f.docs.has("deda_unified_room_sessions/"+b),false);
 assert.notEqual(uid,b);
 const result=await f.guard(true)(f.request);
 assert.equal(result.status,"VERIFIED_READ_ONLY",result.reason);
 assert.equal(result.payload.level,13);
 assert.equal(f.stats().writes,0);
});
test("tampered independently reviewed historical B route fails closed",async()=>{
 const f=fixture();
 f.docs.get("deda_unified_room_owner_authorizations/"+uid)
  .historicalUids=[a,"QA_UNRELATED_UID_X",c];
 await hold(()=>f.guard(true)(f.request),"ROOM_SESSION_HISTORY_NOT_AUTHORIZED");
});
test("session and room cannot change canonical identity or A/B/C route",async()=>{
 const f=fixture();f.docs.get("deda_unified_room_sessions/"+uid).accountKey="9647999999999";
 await hold(()=>f.guard(true)(f.request),"ROOM_SESSION_HISTORY_NOT_AUTHORIZED");
 const g=fixture();g.docs.get("deda_unified_room_owner_directory/"+uid)
  .historicalUids=[a,c,"QA_OUTSIDER_UID_D"];
 await hold(()=>g.guard(true)(g.request),"ROOM_SESSION_HISTORY_NOT_AUTHORIZED");
});
test("wrong scope or source UID refuses sanitized profile",async()=>{
 const f=fixture();const path="deda_unified_room_read_grants/"+uid+"/domains/profile";
 f.docs.get(path).sourceUid="QA_OUTSIDER_UID_D";
 await hold(()=>f.guard(true)(f.request),"SPECIFIC_DOMAIN_PROOF_NOT_VERIFIED");
 const g=fixture();g.docs.get(path).canCredit=true;
 await hold(()=>g.guard(true)(g.request),"SPECIFIC_DOMAIN_PROOF_NOT_VERIFIED");
});
test("invalid balance or leaked phone/UID field never leaves backend",async()=>{
 const f=fixture();f.docs.get("deda_unified_room_private_views/"+uid+"/domains/profile").payload={
  displayName:"Hi",accountKey};
 await hold(()=>f.guard(true)(f.request),"SANITIZED_SERVER_VIEW_NOT_TRUSTED");
 const g=fixture("wallet");g.docs.get("deda_unified_room_private_views/"+uid+"/domains/wallet").payload={balanceDisplay:-100};
 await hold(()=>g.guard(true)(g.request),"SANITIZED_SERVER_VIEW_NOT_TRUSTED");
});
test("stale or mismatched Firestore view, no content downgrade",async()=>{
 const f=fixture();f.docs.get("deda_unified_room_private_views/"+uid+"/domains/profile").originalId="@DEDA-OTHER1";
 await hold(()=>f.guard(true)(f.request),"SANITIZED_SERVER_VIEW_NOT_TRUSTED");
 const g=fixture();g.docs.delete("deda_unified_room_private_views/"+uid+"/domains/profile");
 await hold(()=>g.guard(true)(g.request),"SERVER_OWNER_SCOPE_VIEW_MISSING");
});
test("disabled Auth record or unavailable backend never fails open",async()=>{
 const f=fixture();const deny={getUser:async()=>({uid,disabled:true})};
 const db={doc:p=>({path:p}),runTransaction:async()=>{throw Error("unexpected transaction")}};
 await hold(()=>createRoomReadonlyGuard({db,auth:deny,clock:()=>NOW,enabled:true})(f.request),
   "AUTH_USER_MISSING_OR_DISABLED");
});
test("production reader rejects old mismatched grant path and timestamp schema",async()=>{
 const f=fixture();
 const current="deda_unified_room_read_grants/"+uid+"/domains/profile";
 const old="deda_unified_room_owner_authorizations/"+uid+"/domains/profile";
 const grant=f.docs.get(current);
 f.docs.delete(current);f.docs.set(old,grant);
 await hold(()=>f.guard(true)(f.request),"SERVER_OWNER_SCOPE_VIEW_MISSING");
 const g=fixture();const row=g.docs.get(current);
 row.issuedAtMs=NOW-2000;row.expiresAtMs=NOW+10000;
 delete row.issuedAt;delete row.expiresAt;
 await hold(()=>g.guard(true)(g.request),"SPECIFIC_DOMAIN_PROOF_NOT_VERIFIED");
});
test("production reader requires stable canonical session and scoped read-only grants",async()=>{
 const f=fixture();f.docs.get("deda_unified_room_sessions/"+uid).sessionNonce="";
 await hold(()=>f.guard(true)(f.request),"ROOM_SESSION_HISTORY_NOT_AUTHORIZED");
 const g=fixture();const path="deda_unified_room_read_grants/"+uid+"/domains/profile";
 delete g.docs.get(path).canWrite;
 await hold(()=>g.guard(true)(g.request),"SPECIFIC_DOMAIN_PROOF_NOT_VERIFIED");
 const h=fixture();h.docs.get(path).scopeVersion=2;
 await hold(()=>h.guard(true)(h.request),"SPECIFIC_DOMAIN_PROOF_NOT_VERIFIED");
});
test("service has no issuer and never calls Firebase admin .set or creates UID",()=>{
 const fs=require("node:fs");
 const body=fs.readFileSync(require.resolve("../deda_unified_room_readonly_guard_v1.js"),"utf8");
 for(const forbidden of ["createUser(", "createCustomToken(", "signInAnonymously(", "tx.set(", "tx.update(", "tx.delete(", "tx.create("])
   assert.equal(body.includes(forbidden),false,forbidden);
});


test("a valid historical A UID cannot be used as the B league or C friend source",async()=>{
 for(const domain of ["friends","league"]){
  const f=fixture(domain);
  f.docs.get("deda_unified_room_read_grants/"+uid+"/domains/"+domain)
   .sourceUid=a;
  f.docs.get("deda_unified_room_private_views/"+uid+"/domains/"+domain)
   .sourceUid=a;
  await hold(()=>f.guard(true)(f.request),"SPECIFIC_DOMAIN_PROOF_NOT_VERIFIED");
  assert.equal(f.stats().writes,0);
 }
});
test("one old room grant is invalid on a new same-UID session epoch",async()=>{
 const f=fixture("friends");
 f.docs.get("deda_unified_room_sessions/"+uid).sessionNonce="QA_SECOND_CANONICAL_SESSION_NONCE";
 await hold(()=>f.guard(true)(f.request),"SPECIFIC_DOMAIN_PROOF_NOT_VERIFIED");
 const g=fixture("league");
 g.docs.get("deda_unified_room_sessions/"+uid).revision=2;
 await hold(()=>g.guard(true)(g.request),"SPECIFIC_DOMAIN_PROOF_NOT_VERIFIED");
 const h=fixture("original_id");
 h.docs.get("deda_unified_room_private_views/"+uid+"/domains/original_id")
  .sessionRevision=2;
 await hold(()=>h.guard(true)(h.request),"SANITIZED_SERVER_VIEW_NOT_TRUSTED");
});
