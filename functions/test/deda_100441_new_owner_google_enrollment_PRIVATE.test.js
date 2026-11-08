"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {createHmac} = require("node:crypto");
const {enrollNewGoogleOwner} = require(
  "../deda_100441_new_owner_google_enrollment_PRIVATE_NOT_EXPORTED.js"
);
const ACCOUNT="07111111111", ORIGINAL="@DEDA-ABC123";
const UID="new-google-original-test-uid", B="other-anonymous-test-uid";
const SUBJECT="google-subject-emulator-abc123";
const TOKEN="synthetic-only-google-auth-token-000000000000";
const PIN="123456"; // fake: never used by this enrollment flow
const KEY=Buffer.alloc(40,13); // fake test issuer secret; never production
const NOW=Date.UTC(2026,10,8,14);
const NONCE="f".repeat(64);

const sign = i => createHmac("sha256",KEY).update([
  "DEDA_STAGE6_PHONE_VERIFIED_INTENT_V1",i.accountKey,i.ownerUid,
  i.originalId,i.providerId,i.providerSubject,i.nonce,
  String(i.issuedAtMs),String(i.expiresAtMs),i.proofKind,
].join("\n"),"utf8").digest("hex");

function readyRows() {
  const intent={
    accountKey:ACCOUNT,ownerUid:UID,originalId:ORIGINAL,
    providerId:"google.com",providerSubject:SUBJECT,
    nonce:NONCE,issuedAtMs:NOW-1000,expiresAtMs:NOW+180000,
    proofKind:"independently_verified_phone_challenge_v1",
    status:"verified",
  };
  intent.mac=sign(intent);
  return new Map(Object.entries({
    ["deda_account_directory/"+ACCOUNT]:{
      accountKey:ACCOUNT,createdUid:UID,active:true,
      registrationVersion:2,authMethod:"google_uid_first_v1",
    },
    ["deda_credentials/"+ACCOUNT]:{
      accountKey:ACCOUNT,createdUid:UID,active:true,
      registrationVersion:2,authMethod:"google_uid_first_v1",pin:PIN,
    },
    ["deda_share_ids/"+ORIGINAL]:{
      publicId:ORIGINAL,kind:"personal",active:true,ownerUid:UID,
    },
    ["users/"+UID]:{
      accountKey:ACCOUNT,sharePersonalId:ORIGINAL,
      registrationVersion:2,
    },
    ["deda_social_profiles/"+ORIGINAL]:{
      publicId:ORIGINAL,ownerUid:UID,
    },
    ["deda_sessions/"+UID]:{accountKey:ACCOUNT,uid:UID},
    ["deda_owner_registration_verified_intents/"+ACCOUNT]:intent,
  }));
}

function harness({
  rows=readyRows(),enabled=true,uid=UID,provider="google.com",
  subject=SUBJECT,disabled=false,claims={},
  key=KEY,now=()=>NOW,verifyThrows=false,getUserThrows=false,dbThrows=false,
}={}) {
  const calls={verify:[],auth:[],reads:[],writes:[]};
  const auth={
    async verifyIdToken(token,checkRevoked){
      calls.verify.push({tokenCorrect:token===TOKEN,checkRevoked});
      if(verifyThrows)throw Error("revoked-or-invalid-auth");
      return {uid,firebase:{sign_in_provider:provider}};
    },
    async getUser(u){
      calls.auth.push(u);
      if(getUserThrows)throw Error("auth-record-missing");
      return {uid:u,disabled,customClaims:claims,
        providerData:[{providerId:"google.com",uid:subject}]};
    },
  };
  const db={
    doc(path){return {path};},
    async runTransaction(callback){
      if(dbThrows)throw Error("firestore-unavailable");
      let writing=false;
      const pending=[];
      const tx={
        async get(ref){
          if(writing)throw Error("firestore-read-after-write");
          calls.reads.push(ref.path);
          const data=rows.get(ref.path);
          return data===undefined?{exists:false}:{
            exists:true,data:()=>structuredClone(data),
          };
        },
        create(ref,data){
          writing=true;
          if(rows.has(ref.path))throw Error("already-exists");
          pending.push({kind:"create",path:ref.path,data:structuredClone(data)});
        },
        update(ref,data){
          writing=true;
          if(!rows.has(ref.path))throw Error("not-found");
          pending.push({kind:"update",path:ref.path,data:structuredClone(data)});
        },
      };
      const result=await callback(tx);
      for(const p of pending){
        rows.set(p.path,p.kind==="update" ?
          {...rows.get(p.path),...p.data}:p.data);
        calls.writes.push(p);
      }
      return result;
    },
  };
  return {rows,calls,input:{accountKey:ACCOUNT,originalId:ORIGINAL,
    idToken:TOKEN},deps:{auth,db,now,intentMacKey:key,enabled}};
}
async function inspect(t) {
  const outcome=await enrollNewGoogleOwner(t.input,t.deps);
  assert.equal(outcome.authorizedToSignIn,false);
  assert.equal(outcome.mayCreateUid,false);
  assert.equal(outcome.mayTransferOwnership,false);
  assert.equal(outcome.mayModifyAdmin,false);
  assert.equal(outcome.mayModifyFinances,false);
  assert.equal(outcome.legacyAccountUntouched,true);
  assert.equal(Object.isFrozen(outcome),true);
  const redacted=JSON.stringify(outcome);
  for(const secret of [ACCOUNT,UID,B,ORIGINAL,SUBJECT,PIN,TOKEN,NONCE]){
    assert(!redacted.includes(secret));
  }
  for(const p of t.calls.writes) assert(
    /^(deda_owner_provider_enrollments|deda_owner_registration_verified_intents)\//
      .test(p.path),"unexpected write "+p.path);
  return outcome.status;
}
test("off by default prevents even token verification and phone scans",async()=>{
  const t=harness({enabled:false});
  assert.equal(await inspect(t),"NOT_ENABLED_OR_INVALID_REQUEST");
  assert.equal(t.calls.verify.length,0);
  assert.equal(t.calls.reads.length,0);
});
test("new Google-first UID with prior independent server-signed phone intent can enroll once",async()=>{
  const t=harness();
  assert.equal(await inspect(t),"ENROLLED_FOR_FUTURE_INDEPENDENT_REVIEW");
  assert.deepEqual(t.calls.verify,[{tokenCorrect:true,checkRevoked:true}]);
  assert.deepEqual(t.calls.auth,[UID]);
  assert.equal(t.calls.reads.length,9);
  assert.equal(t.calls.writes.length,2);
  assert.equal(t.rows.get("deda_owner_provider_enrollments/"+UID).ownerUid,UID);
  assert.equal(t.rows.get("deda_owner_provider_enrollments/"+UID).source,
    "trusted_server_pre_enrollment_v1");
  assert.equal(t.rows.get(
    "deda_owner_registration_verified_intents/"+ACCOUNT).status,"consumed");
});
test("idempotent retry on exactly same UID creates no extra enrollment",async()=>{
  const t=harness();
  assert.equal(await inspect(t),"ENROLLED_FOR_FUTURE_INDEPENDENT_REVIEW");
  assert.equal(await inspect(t),"ALREADY_ENROLLED_SAME_UID");
  assert.equal(t.calls.writes.length,2);
});
test("legacy 100340 anonymous registration never becomes trusted v2 enrollment",async()=>{
  const t=harness();
  t.rows.get("deda_account_directory/"+ACCOUNT).registrationVersion=1;
  t.rows.get("deda_account_directory/"+ACCOUNT).authMethod="deda_pin_firestore_v1";
  assert.equal(await inspect(t),"NOT_A_VERIFIED_NEW_CANONICAL_ACCOUNT");
  assert.equal(t.calls.writes.length,0);
});
test("A/B/C split blocks any enrollment or owner migration",async()=>{
  const t=harness();
  t.rows.get("deda_account_directory/"+ACCOUNT).createdUid=B;
  t.rows.get("deda_social_profiles/"+ORIGINAL).ownerUid="uid-three-C";
  assert.equal(await inspect(t),"NOT_A_VERIFIED_NEW_CANONICAL_ACCOUNT");
  assert.equal(t.calls.writes.length,0);
});
test("new google UID cannot hijack existing accountKey even with matching phone text",async()=>{
  const t=harness({uid:B});
  assert.equal(await inspect(t),"NOT_A_VERIFIED_NEW_CANONICAL_ACCOUNT");
  assert.equal(t.calls.writes.length,0);
});
test("no independent phone proof halts, even when Google is authenticated",async()=>{
  const t=harness();
  t.rows.delete("deda_owner_registration_verified_intents/"+ACCOUNT);
  assert.equal(await inspect(t),"NO_INDEPENDENT_PHONE_VERIFICATION");
  assert.equal(t.calls.writes.length,0);
});
test("client-generated or tampered claim HMAC cannot enroll",async()=>{
  for(const patch of [
    {mac:"0".repeat(64)},{source:"phone-local-only",nonce:"xyz"},
    {ownerUid:B},{providerSubject:"other-subject"},
    {status:"client-verified"},{expiresAtMs:NOW-1},
    {issuedAtMs:NOW+1},
  ]){
    const t=harness();
    Object.assign(t.rows.get(
      "deda_owner_registration_verified_intents/"+ACCOUNT),patch);
    assert.equal(await inspect(t),"NO_INDEPENDENT_PHONE_VERIFICATION");
    assert.equal(t.calls.writes.length,0);
  }
});
test("expired token, wrong provider or disabled Auth user cannot reach Firestore",async()=>{
  for(const o of [
    {verifyThrows:true},{getUserThrows:true},{provider:"anonymous"},
    {provider:"password"},{disabled:true},{claims:{admin:true}},
  ]){
    const t=harness(o);
    const status=await inspect(t);
    assert(["UNVERIFIED_AUTH_TOKEN","NO_VERIFIED_GOOGLE_FIRST_IDENTITY"]
      .includes(status));
    assert.equal(t.calls.reads.length,0);
    assert.equal(t.calls.writes.length,0);
  }
});
test("mismatched Google provider subject is blocked by server intent",async()=>{
  const t=harness({subject:"other-google-subject"});
  assert.equal(await inspect(t),"NO_INDEPENDENT_PHONE_VERIFICATION");
  assert.equal(t.calls.writes.length,0);
});
test("admin uid is excluded from ordinary enrollment",async()=>{
  const t=harness();
  t.rows.set("admins/"+UID,{active:true,role:"general_manager"});
  assert.equal(await inspect(t),"NOT_A_VERIFIED_NEW_CANONICAL_ACCOUNT");
  assert.equal(t.calls.writes.length,0);
});
test("conflicting old enrollment is never overwritten",async()=>{
  const t=harness();
  t.rows.set("deda_owner_provider_enrollments/"+UID,{
    source:"trusted_server_pre_enrollment_v1",status:"active",
    ownerUid:B,accountKey:ACCOUNT,originalId:ORIGINAL,
    providerId:"google.com",providerSubject:SUBJECT,revision:1,
  });
  assert.equal(await inspect(t),"EXISTING_ENROLLMENT_CONFLICT");
  assert.equal(t.calls.writes.length,0);
});
test("server unknown or malformed registration rows do not create account",async()=>{
  for(const p of [
    "deda_credentials/"+ACCOUNT,
    "deda_share_ids/"+ORIGINAL,
    "users/"+UID,
    "deda_social_profiles/"+ORIGINAL,
    "deda_sessions/"+UID,
  ]) {
    const t=harness();t.rows.delete(p);
    assert.equal(await inspect(t),"NOT_A_VERIFIED_NEW_CANONICAL_ACCOUNT");
    assert.equal(t.calls.writes.length,0);
  }
});
test("Firestore transaction unavailable fails closed with no hidden partial grants",async()=>{
  const t=harness({dbThrows:true});
  assert.equal(await inspect(t),"TRANSACTION_UNAVAILABLE_OR_CONFLICT");
  assert.equal(t.calls.writes.length,0);
});
test("secret absent, malformed account or premium alias fail before all account reads",async()=>{
  const cases=[
    ()=>harness({key:Buffer.alloc(8)}),
    ()=>{const t=harness();t.input.accountKey="wrong/path";return t;},
    ()=>{const t=harness();t.input.originalId="@DEDA-123";return t;},
    ()=>{const t=harness();t.input.idToken="";return t;},
  ];
  for(const make of cases){
    const t=make();
    assert.equal(await inspect(t),"NOT_ENABLED_OR_INVALID_REQUEST");
    assert.equal(t.calls.reads.length,0);
    assert.equal(t.calls.verify.length,0);
  }
});
