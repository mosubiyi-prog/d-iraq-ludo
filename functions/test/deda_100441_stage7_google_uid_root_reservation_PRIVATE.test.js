"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {reserveNewGoogleRoot} = require(
  "../deda_100441_stage7_google_uid_root_reservation_PRIVATE_NOT_EXPORTED.js");
const UID = "new-google-qa-original-uid";
const UID_B = "second-qa-other-uid";
const SUBJECT = "google-provider-subject-verified-xyz";
const TOKEN = "fake-test-token-not-production-000000000";
const HMAC_KEY=Buffer.alloc(40,0x3b);
const NOW=Date.UTC(2026,10,8,12);
function fixture({enabled=true,uid=UID,subject=SUBJECT,provider="google.com",
    recordDisabled=false,admin=false,tokenError=false,dbError=false,
    rows=new Map(),now=()=>NOW,key=HMAC_KEY}={}) {
  const calls={auth:[],reads:[],writes:[]};
  const auth={
    async verifyIdToken(t, revoked) {
      calls.auth.push({t:t===TOKEN,revoked});
      if(tokenError) throw Error("revoked");
      return {uid,firebase:{sign_in_provider:provider}};
    },
    async getUser(value) {
      return {uid:value,disabled:recordDisabled,
        customClaims:admin?{admin:true}:{},
        providerData:[{providerId:"google.com",uid:subject}]};
    },
  };
  const db={
    doc(path){return {path};},
    async runTransaction(work){
      if(dbError) throw Error("firestore");
      const pending=[], tx={
        async get(ref){
          if(pending.length)throw Error("firestore-read-after-write");
          calls.reads.push(ref.path);
          const v=rows.get(ref.path);
          return v ? {exists:true,data:()=>structuredClone(v)} : {exists:false};
        },
        create(ref,obj){
          if(rows.has(ref.path))throw Error("already-exists");
          pending.push({path:ref.path,v:structuredClone(obj)});
        },
      };
      const res=await work(tx);
      for(const x of pending){rows.set(x.path,x.v);calls.writes.push(x)}
      return res;
    },
  };
  return {rows,calls,input:{idToken:TOKEN},
    deps:{auth,db,enabled,subjectIndexKey:key,now}};
}
async function run(t){
  const response=await reserveNewGoogleRoot(t.input,t.deps);
  assert.equal(response.decision,
    "HOLD_GOOGLE_ROOT_PENDING_APPROVED_REGISTRATION");
  for(const key of ["ownerUidGranted","phoneOwnershipProved",
    "mayClaimPhoneNumber","mayCreateDedaProfile","maySignIn",
    "mayMintAuthToken","mayTransferExistingAccount","mayModifyAdmin",
    "mayModifyWallet","mayModifyGifts","mayModifyLeague"]) {
    assert.equal(response[key],false,key);
  }
  assert.equal(response.internalOnly,true);
  assert(Object.isFrozen(response));
  const printed=JSON.stringify(response);
  for(const s of [UID,UID_B,SUBJECT,TOKEN,"07111111111","@DEDA-ABC123"])
    assert(!printed.includes(s));
  for(const x of t.calls.writes) {
    assert(/^(deda_google_uid_reservations_private_v1|deda_google_subject_index_private_v1)\//
      .test(x.path));
    assert(!/phone|pin|accountKey|originalId|diamonds|gifts|admin|wallet/
      .test(JSON.stringify(x.v)));
  }
  return response.classification;
}
test("new Google-root pilot OFF denies all work by default",async()=>{
  const t=fixture({enabled:false});
  assert.equal(await run(t),"NOT_ENABLED_OR_INVALID_REQUEST");
  assert.equal(t.calls.auth.length,0);
  assert.equal(t.calls.reads.length,0);
});
test("valid Google ID token+provider can reserve UID but cannot claim a DEDA phone",async()=>{
  const t=fixture();
  assert.equal(await run(t),"GOOGLE_UID_RESERVED_PHONE_UNVERIFIED");
  assert.equal(t.calls.writes.length,2);
  assert.equal(t.calls.reads.length,6);
  assert.equal(t.calls.auth.length,1);
  assert.deepEqual(t.calls.auth[0],{t:true,revoked:true});
  assert(t.calls.writes.every(w=>!/phone|pin|wallet|gifts/.test(w.path)));
});
test("retry on same Google UID does not create another reservation",async()=>{
  const t=fixture();
  assert.equal(await run(t),"GOOGLE_UID_RESERVED_PHONE_UNVERIFIED");
  assert.equal(await run(t),"SAME_UID_PENDING_REVIEW_NO_DUPLICATE");
  assert.equal(t.calls.writes.length,2);
});
test("expired old reservation cannot be silently reset or claimed",async()=>{
  let clock=NOW;
  const t=fixture({now:()=>clock});
  assert.equal(await run(t),"GOOGLE_UID_RESERVED_PHONE_UNVERIFIED");
  clock+=16*60*1000;
  assert.equal(await run(t),"PRIOR_RESERVATION_CONFLICT_OR_EXPIRED");
  assert.equal(t.calls.writes.length,2);
});
test("existing legacy user document blocks first new-account reservation",async()=>{
  const t=fixture({rows:new Map([["users/"+UID,{accountKey:"07111111111"}]])});
  assert.equal(await run(t),"EXISTING_ACCOUNT_OR_ADMIN_REQUIRES_SEPARATE_REVIEW");
  assert.equal(t.calls.writes.length,0);
});
test("existing session, admin or enrollment blocks new-account route",async()=>{
  for(const key of [
    "deda_sessions/"+UID,"admins/"+UID,
    "deda_owner_provider_enrollments/"+UID,
  ]) {
    const t=fixture({rows:new Map([[key,{uid:UID,active:true}]])});
    assert.equal(await run(t),"EXISTING_ACCOUNT_OR_ADMIN_REQUIRES_SEPARATE_REVIEW");
    assert.equal(t.calls.writes.length,0);
  }
});
test("anonymous/password provider, disabled principal or admin claim cannot reserve",async()=>{
  for(const cfg of [
    {provider:"anonymous"},{provider:"password"},
    {recordDisabled:true},{admin:true},
  ]) {
    const t=fixture(cfg);
    assert.equal(await run(t),"UNVERIFIED_GOOGLE_PROVIDER");
    assert.equal(t.calls.reads.length,0);
  }
});
test("revoked or invalid ID token stops before read",async()=>{
  const t=fixture({tokenError:true});
  assert.equal(await run(t),"UNVERIFIED_AUTH_SESSION");
  assert.equal(t.calls.reads.length,0);
});
test("client cannot inject PIN/phone/UID fields as new-account proof",async()=>{
  const t=fixture();
  Object.assign(t.input,{accountKey:"07111111111",pin:"123456",uid:UID});
  assert.equal(await run(t),"NOT_ENABLED_OR_INVALID_REQUEST");
  assert.equal(t.calls.auth.length,0);
});
test("secret missing or firestore unavailable fails closed",async()=>{
  const t=fixture({key:Buffer.alloc(4)});
  assert.equal(await run(t),"NOT_ENABLED_OR_INVALID_REQUEST");
  const bad=fixture({dbError:true});
  assert.equal(await run(bad),"SERVER_TRANSACTION_UNAVAILABLE");
  assert.equal(bad.calls.writes.length,0);
});
test("provider subject collision from another UID fails without switching ownership",async()=>{
  const original=fixture();
  assert.equal(await run(original),"GOOGLE_UID_RESERVED_PHONE_UNVERIFIED");
  const other=fixture({uid:UID_B,rows:original.rows});
  assert.equal(await run(other),"PRIOR_RESERVATION_CONFLICT_OR_EXPIRED");
  assert.equal(other.calls.writes.length,0);
  assert.equal(original.rows.get(
    "deda_google_uid_reservations_private_v1/"+UID).uid,UID);
});
test("different Google subject can reserve separately without phone collision",async()=>{
  const original=fixture();
  assert.equal(await run(original),"GOOGLE_UID_RESERVED_PHONE_UNVERIFIED");
  const other=fixture({uid:UID_B,subject:"another-google-subject-verified",
    rows:original.rows});
  assert.equal(await run(other),"GOOGLE_UID_RESERVED_PHONE_UNVERIFIED");
  assert.equal(original.rows.size,4);
  assert.equal(other.calls.writes.length,2);
});
test("server clock backwards and malformed identity are blocked",async()=>{
  const invalid=fixture({now:()=>0});
  assert.equal(await run(invalid),"INVALID_SERVER_CLOCK");
  const fake=fixture({uid:"a"});
  assert.equal(await run(fake),"UNVERIFIED_AUTH_SESSION");
});
