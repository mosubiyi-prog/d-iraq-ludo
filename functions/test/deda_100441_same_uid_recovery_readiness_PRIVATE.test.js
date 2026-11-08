"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  assessSameUidRecovery,
} = require("../deda_100441_same_uid_recovery_readiness_PRIVATE_NOT_EXPORTED.js");

const ACCOUNT="07111111111", ORIGINAL="@DEDA-ABC123";
const A="firebase-original-owner-qa-A";
const B="firebase-new-anonymous-B";
const C="firebase-social-owner-C";
const TOKEN="offline-test-verified-firebase-id-token-123456";
const GOOGLE_SUB="prelinked-google-subject-123456";
const NOW=Date.UTC(2026,10,8,12);
const PIN="481259"; // never returned

function baseRows(){
  return new Map(Object.entries({
    ["deda_account_directory/"+ACCOUNT]:{
      accountKey:ACCOUNT,createdUid:A,active:true},
    ["deda_credentials/"+ACCOUNT]:{
      accountKey:ACCOUNT,createdUid:A,active:true,pin:PIN},
    ["deda_share_ids/"+ORIGINAL]:{
      publicId:ORIGINAL,kind:"personal",active:true,ownerUid:A},
    ["users/"+A]:{accountKey:ACCOUNT,sharePersonalId:ORIGINAL},
    ["deda_social_profiles/"+ORIGINAL]:{
      publicId:ORIGINAL,ownerUid:A},
    ["deda_sessions/"+A]:{uid:A,accountKey:ACCOUNT},
    ["deda_owner_provider_enrollments/"+A]:{
      source:"trusted_server_pre_enrollment_v1",
      status:"active",revision:1,ownerUid:A,
      accountKey:ACCOUNT,originalId:ORIGINAL,providerId:"google.com",
      providerSubject:GOOGLE_SUB,enrolledAtMs:NOW-86400000,
    },
  }));
}
function setup({
  rows=baseRows(),uid=A,provider="google.com",subject=GOOGLE_SUB,
  decodedUid=uid,enabled=true,recordDisabled=false,
  invalidToken=false,recordError=false,dbError=false,
  now=()=>NOW,claims={},
}={}){
  const calls={verified:[],authReads:[],fireReads:[],writes:[]};
  const auth={
    async verifyIdToken(token,revoked){
      calls.verified.push({matchesToken:token===TOKEN,revoked});
      if(invalidToken)throw Error("expired-token");
      return {uid:decodedUid,
        firebase:{sign_in_provider:provider}};
    },
    async getUser(asked){
      calls.authReads.push(asked);
      if(recordError)throw Error("user-not-found");
      return {uid:asked,disabled:recordDisabled,customClaims:claims,
        providerData:[{providerId:"google.com",uid:subject},
          {providerId:"password",uid:"synthetic-password"}]};
    },
  };
  const db={doc(path){
    calls.fireReads.push(path);
    return {get:async()=>{
      if(dbError)throw Error("server-read-failed");
      const value=rows.get(path);
      return value===undefined?{exists:false}:{
        exists:true,data:()=>structuredClone(value)};
    }};
  }};
  return {
    input:{idToken:TOKEN,accountKey:ACCOUNT,originalId:ORIGINAL},
    deps:{auth,db,now},
    calls,rows,
  };
}
async function check(t){
  const out=await assessSameUidRecovery(t.input,t.deps);
  assert.equal(out.decision,"HOLD_INDEPENDENT_OWNER_PROOF_AND_SERVER_REVIEW");
  assert.equal(Object.isFrozen(out),true);
  for(const p of ["canSignIn","canCreateUid","canMintToken",
    "canBootstrapSession","canWriteFirestore","canTransferOwnership",
    "canModifyAdmin","canModifyWallet","canModifyGifts",
    "canModifyLeague"])assert.equal(out[p],false,p);
  const redacted=JSON.stringify(out);
  for(const x of [ACCOUNT,ORIGINAL,A,B,C,PIN,TOKEN,GOOGLE_SUB]){
    assert(!redacted.includes(x));
  }
  assert.equal(t.calls.writes.length,0);
  return out.classification;
}

test("prelinked Google on exact original Firebase UID is still REVIEW ONLY",async()=>{
  const t=setup();
  assert.equal(await check(t),"SAME_UID_EXISTING_SESSION_REVIEW_ONLY");
  assert.deepEqual(t.calls.verified,[{matchesToken:true,revoked:true}]);
  assert.deepEqual(t.calls.authReads,[A]);
  assert.equal(t.calls.fireReads.length,8);
  assert(t.calls.fireReads.includes("admins/"+A));
});

test("replacement phone with same provider UID and missing local session never creates another UID",async()=>{
  const rows=baseRows();
  rows.delete("deda_sessions/"+A);
  const t=setup({rows});
  assert.equal(await check(t),"SAME_UID_SEPARATE_SESSION_BOOTSTRAP_REQUIRED");
  assert(!t.calls.fireReads.includes("deda_sessions/"+B));
  assert.equal(t.calls.fireReads.length,8);
});

test("A/B/C three-way split halts without choosing A or B or C",async()=>{
  const rows=baseRows();
  rows.get("deda_account_directory/"+ACCOUNT).createdUid=B;
  rows.get("deda_credentials/"+ACCOUNT).createdUid=B;
  rows.get("deda_social_profiles/"+ORIGINAL).ownerUid=C;
  const t=setup({rows});
  assert.equal(await check(t),"SPLIT_UID_NO_IMPLICIT_RECOVERY");
});

test("new Firebase UID B from anonymous flow is not owner, even if original phone known",async()=>{
  const t=setup({uid:B,provider:"anonymous"});
  assert.equal(await check(t),"NO_PRELINKED_INDEPENDENT_PROVIDER");
  assert.equal(t.calls.fireReads.length,0);
});

test("old 6-digit PIN or password provider is NOT independent recovery proof",async()=>{
  const t=setup({provider:"password"});
  t.input.pin=PIN;
  assert.equal(await check(t),"NO_PRELINKED_INDEPENDENT_PROVIDER");
  assert.equal(t.calls.fireReads.length,0);
});

test("Google UID alone without prior immutable enrollment cannot restore account",async()=>{
  const rows=baseRows();rows.delete("deda_owner_provider_enrollments/"+A);
  const t=setup({rows});
  assert.equal(await check(t),"NO_TRUSTED_PREVIOUS_PROVIDER_ENROLLMENT");
});

test("provider subject mismatch prevents Google identity swap",async()=>{
  const t=setup({subject:"different-google-subject"});
  assert.equal(await check(t),"NO_TRUSTED_PREVIOUS_PROVIDER_ENROLLMENT");
});

test("server enrollment must be prior, valid, active, and not client-created",async()=>{
  for(const patch of [
    {status:"revoked"},{source:"client_shared_preferences"},
    {enrolledAtMs:NOW+100000},{revision:0},{ownerUid:B},
    {accountKey:"07222222222"},{originalId:"@DEDA-ZZZ999"},
  ]){
    const rows=baseRows();
    Object.assign(rows.get("deda_owner_provider_enrollments/"+A),patch);
    const t=setup({rows});
    assert.equal(await check(t),"NO_TRUSTED_PREVIOUS_PROVIDER_ENROLLMENT");
  }
});

test("missing route/social/credential/user does not fabricate owner registration",async()=>{
  for(const p of [
    "deda_share_ids/"+ORIGINAL,
    "deda_social_profiles/"+ORIGINAL,
    "deda_credentials/"+ACCOUNT,
    "users/"+A,
  ]){
    const rows=baseRows();rows.delete(p);
    const t=setup({rows});
    assert.equal(await check(t),"INCOMPLETE_LEGACY_OWNER_DOCUMENTS");
  }
});

test("mismatch of original route owner or social owner fails closed",async()=>{
  for(const p of [
    "deda_share_ids/"+ORIGINAL,
    "deda_social_profiles/"+ORIGINAL,
  ]){
    const rows=baseRows();rows.get(p).ownerUid=B;
    const t=setup({rows});
    assert.equal(await check(t),"SPLIT_UID_NO_IMPLICIT_RECOVERY");
  }
});

test("admin principal is always separate from ordinary account restoration",async()=>{
  const rows=baseRows();rows.set("admins/"+A,{active:true,role:"general_manager"});
  assert.equal(await check(setup({rows})),"ADMIN_REQUIRES_SEPARATE_REVIEW");
  assert.equal(await check(setup({claims:{admin:true}})),
    "ADMIN_REQUIRES_SEPARATE_REVIEW");
});

test("expired or revoked token never reads Firestore",async()=>{
  const t=setup({invalidToken:true});
  assert.equal(await check(t),"UNVERIFIED_AUTH_SESSION");
  assert.equal(t.calls.fireReads.length,0);
  assert.equal(t.calls.authReads.length,0);
});

test("disabled Auth user, unknown Auth record and Firestore failure fail closed",async()=>{
  const a=setup({recordDisabled:true});
  assert.equal(await check(a),"NO_PRELINKED_INDEPENDENT_PROVIDER");
  const b=setup({recordError:true});
  assert.equal(await check(b),"UNVERIFIED_AUTH_SESSION");
  const c=setup({dbError:true});
  assert.equal(await check(c),"SERVER_EVIDENCE_UNAVAILABLE");
});

test("malformed phone, premium alias, absent token or hostile id cannot scan records",async()=>{
  for(const patch of [
    {idToken:""},
    {originalId:"@DEDA-AB"},
    {originalId:"../admins/owner"},
    {accountKey:"../secrets"},
    {accountKey:"07111111111/../../users"},
  ]){
    const t=setup();
    Object.assign(t.input,patch);
    assert.equal(await check(t),"INVALID_OR_UNVERIFIED_REQUEST");
    assert.equal(t.calls.fireReads.length,0);
    assert.equal(t.calls.verified.length,0);
  }
});

test("credentials match is still not permission to change wallet gifts league or account",async()=>{
  const t=setup();
  t.input.pin=PIN;
  t.input.claimedOwnerUid=C;
  t.input.admin=true;
  assert.equal(await check(t),"SAME_UID_EXISTING_SESSION_REVIEW_ONLY");
  assert.equal(t.calls.writes.length,0);
});
