"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {autoRecoverForgottenPin} =
  require("../../functions/deda_pin_auto_recovery_worker.js");

const NOW = Date.parse("2026-10-10T10:00:00Z");
const ACCOUNT = "07712345678";
const REQUEST_ID = "test-recovery-request-1";
const UID = "publicDedaUid76b3";
const INSTALL = "abcdef0123456789".repeat(3);
const OLD_PIN = "123456";
const ms = (v) => ({toMillis:()=>v});

function mockDb(overrides = {}) {
  const defaultDocs = {
    [`recovery_requests/${REQUEST_ID}`]: {
      status:"new",requesterUid:UID,accountKey:ACCOUNT,
      requesterInstallId: INSTALL,fullName:"  حسن   علي  ",
      createdAt:ms(NOW-15000),
    },
    ["deda_automation_settings/pin_auto_recovery"]: {
      enabled:true,enabledAt:ms(NOW-60_000),changedByUid:"gm",
    },
    [`deda_account_directory/${ACCOUNT}`]: {
      active:true,accountKey:ACCOUNT,
    },
    [`deda_account_profiles/${ACCOUNT}`]: {
      name:"حسن علي",trustedInstallIds:[INSTALL],
    },
    [`deda_credentials/${ACCOUNT}`]: {
      active:true,accountKey:ACCOUNT,pin:OLD_PIN,
    },
  };
  const docs = new Map(Object.entries(defaultDocs));
  for (const [key,value] of Object.entries(overrides)) {
    if(value===null) docs.delete(key);
    else docs.set(key, {...docs.get(key), ...value});
  }
  const writes=[];
  return {
    docs,writes,
    collection(name) {return {doc(id) {return {key:`${name}/${id}`};}};},
    async runTransaction(fn) {
      const mutations=[];
      const tx={
        async get(ref) {
          return {exists:docs.has(ref.key),data:()=>docs.get(ref.key)};
        },
        update(ref, values) {
          mutations.push({action:"update",key:ref.key,values});
        },
        set(ref, values) {
          mutations.push({action:"set",key:ref.key,values});
        },
      };
      const res=await fn(tx);
      for(const mutation of mutations) {
        const {action,key,values}=mutation;
        if(action==="update" && !docs.has(key)) throw Error("missing-doc");
        docs.set(key,{...(docs.get(key)||{}),...values});
        writes.push(mutation);
      }
      return res;
    },
  };
}
const recovery=(db,nowMs=NOW)=>
  autoRecoverForgottenPin(db,{requestId:REQUEST_ID,nowMs});

test("real backend writes PIN, ready request, throttle and audit together after 10 seconds",async()=>{
  const db=mockDb();
  const result=await recovery(db);
  assert.equal(result.outcome,"issued");
  assert.equal(db.writes.length,4);
  const pin=db.docs.get(`deda_credentials/${ACCOUNT}`).pin;
  assert.match(pin,/^\d{6}$/);
  assert.notEqual(pin,OLD_PIN);
  const request=db.docs.get(`recovery_requests/${REQUEST_ID}`);
  assert.equal(request.status,"ready");
  assert.equal(request.autoIssued,true);
  assert.equal(request.recoveryPin,pin);
  assert.equal(request.recoveryPinExpiresAt.toMillis(),NOW+30*60*1000);
  const audit=db.docs.get(`admin_automation_audit/pin_${REQUEST_ID}`);
  assert.equal(audit.action,"trusted_device_pin_auto_reissue");
  assert.equal(JSON.stringify(audit).includes(pin),false,
    "audit must not expose the credential PIN");
  assert.equal(db.docs.get(`deda_recovery_auto_limit/${ACCOUNT}`).requestId,
    REQUEST_ID);
  const again=await recovery(db);
  assert.equal(again.outcome,"manual-review");
  assert.equal(db.writes.length,4,"duplicate issuance must be impossible");
});

test("10-second delay mandatory: 9999ms blocked, >=10000ms accepted",async()=>{
  const db=mockDb({[`recovery_requests/${REQUEST_ID}`]:{
    createdAt:ms(NOW-9999),
  }});
  assert.equal((await recovery(db)).outcome,"manual-review");
  assert.equal(db.writes.length,0);
  db.docs.get(`recovery_requests/${REQUEST_ID}`).createdAt=ms(NOW-10000);
  assert.equal((await recovery(db)).outcome,"issued");
});

test("OFF or requests created before switch preserve manual support flow",async()=>{
  for(const config of [
    {enabled:false},{enabledAt:ms(NOW-10000)},
  ]){
    const db=mockDb({"deda_automation_settings/pin_auto_recovery":config});
    assert.notEqual((await recovery(db)).outcome,"issued");
    assert.equal(db.writes.length,0);
  }
});

test("wrong trusted install ID, wrong name and inactive account cannot reset PIN",async()=>{
  const scenarios=[
    {[`recovery_requests/${REQUEST_ID}`]: {requesterInstallId:"e".repeat(48)}},
    {[`recovery_requests/${REQUEST_ID}`]: {fullName:"شخص آخر"}},
    {[`deda_account_profiles/${ACCOUNT}`]: {trustedInstallIds:[]}},
    {[`deda_account_directory/${ACCOUNT}`]: {active:false}},
    {[`deda_credentials/${ACCOUNT}`]: {active:false}},
    {[`deda_credentials/${ACCOUNT}`]: {accountKey:"07222222222"}},
  ];
  for(const change of scenarios){
    const db=mockDb(change);
    const res=await recovery(db);
    assert.notEqual(res.outcome,"issued");
    assert.equal(db.writes.length,0);
    assert.equal(db.docs.get(`deda_credentials/${ACCOUNT}`).pin,OLD_PIN);
  }
});

test("only one reset per real DEDA account per hour regardless of request ID",async()=>{
  const db=mockDb({
    [`deda_recovery_auto_limit/${ACCOUNT}`]: {
      issuedAt:ms(NOW-20*60*1000),requestId:"another-recovery",
    },
  });
  const result=await recovery(db);
  assert.equal(result.outcome,"manual-review");
  assert.equal(result.reason,"replay-or-rate-limit");
  assert.equal(db.writes.length,0);
});

test("disabled or malformed recovery request cannot touch admin credentials",async()=>{
  const db=mockDb({[`recovery_requests/${REQUEST_ID}`]:{
    purpose:"admin_password_reset",status:"review",
  }});
  const result=await recovery(db);
  assert.equal(result.outcome,"manual-review");
  assert.equal(db.writes.length,0);
  assert.equal(db.docs.get(`deda_credentials/${ACCOUNT}`).pin,OLD_PIN);
});
