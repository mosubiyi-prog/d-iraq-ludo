"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const account = "07712345678";
const id = "recovery-test-100436";
const install = "a".repeat(48);
const oldPin = "123456";
const Timestamp = {fromMillis:ms=>({toMillis:()=>ms})};
const FieldValue = {serverTimestamp:()=>({server:true})};

function loadWorker() {
  const module = {exports:{}};
  const code = fs.readFileSync(
    path.join(__dirname,"../deda_pin_auto_recovery_worker.js"), "utf8");
  const requireStub = name=>{
    if(name==="node:crypto") return require("node:crypto");
    if(name==="firebase-admin/firestore") return {Timestamp,FieldValue};
    if(name==="./deda_pin_auto_recovery_policy.js") return {
      decide:()=>({eligible:true}),
    };
    throw Error("unexpected-Module:"+name);
  };
  vm.runInNewContext(code,{
    module,exports:module.exports,require:requireStub,console,Date,Promise,
  },{filename:"deda_pin_auto_recovery_worker.js"});
  return module.exports.autoRecoverForgottenPin;
}

class Db {
  constructor(linked) {
    this.docs=new Map();
    this.writes=[];
    this.put(`recovery_requests/${id}`,{
      status:"new",accountKey:account,requesterUid:"requester-uid",
      requesterInstallId:install,fullName:"Tester",phone:account,
    });
    this.put("deda_automation_settings/pin_auto_recovery",{enabled:true});
    this.put(`deda_account_directory/${account}`,{
      active:true,accountKey:account,
      ...(linked?{authEmail:`${account}@deda-login.invalid`}:{}),
    });
    this.put(`deda_account_profiles/${account}`,{
      trustedInstallIds:[install],name:"Tester",
    });
    this.put(`deda_credentials/${account}`,{
      active:true,accountKey:account,pin:oldPin,
    });
  }
  put(k,v){this.docs.set(k,{...v});}
  collection(name){return {doc:id=>{
    const path=`${name}/${id}`;
    return {path};
  }};}
  async runTransaction(fn){
    const changes=[];
    const tx={
      get:async ref=>{
        const value=this.docs.get(ref.path);
        return {exists:!!value,data:()=>value?{...value}:undefined};
      },
      update:(ref,value)=>changes.push({kind:"update",path:ref.path,value}),
      set:(ref,value)=>changes.push({kind:"set",path:ref.path,value}),
    };
    const result=await fn(tx);
    for(const change of changes){
      const old=this.docs.get(change.path)||{};
      this.put(change.path,{...old,...change.value});
      this.writes.push(change.path);
    }
    return result;
  }
}

test("private pilot ON blocks automatic PIN-only rotation for linked Firebase UID",async()=>{
  const db=new Db(true),worker=loadWorker();
  const result=await worker(db,{requestId:id,linkedPinCompatEnabled:true,
    nowMs:1780000000000});
  assert.equal(result.outcome,"manual-review");
  assert.equal(result.reason,"linked-pin-dual-sync-required");
  assert.equal(db.docs.get(`deda_credentials/${account}`).pin,oldPin);
  assert.equal(db.writes.length,0);
});

test("unlinked legacy account retains auto PIN recovery under new pilot",async()=>{
  const db=new Db(false),worker=loadWorker();
  const result=await worker(db,{requestId:id,linkedPinCompatEnabled:true,
    nowMs:1780000000000});
  assert.equal(result.outcome,"issued");
  assert.notEqual(db.docs.get(`deda_credentials/${account}`).pin,oldPin);
  assert.equal(db.docs.get(`recovery_requests/${id}`).status,"ready");
});

test("pilot OFF preserves prior linked-account auto-worker behavior",async()=>{
  const db=new Db(true),worker=loadWorker();
  const result=await worker(db,{requestId:id,nowMs:1780000000000});
  assert.equal(result.outcome,"issued");
  assert.notEqual(db.docs.get(`deda_credentials/${account}`).pin,oldPin);
});

test("Functions index keeps compatibility OFF and PIN proof strictly emulator-only",()=>{
  const src=fs.readFileSync(path.join(__dirname,"../index.js"),"utf8");
  assert.match(src,/const dedaPinCompatPilotEnabled = false;/);
  assert.match(src,/process\.env\.FUNCTIONS_EMULATOR === "true"/);
  assert.match(src,/process\.env\.DEDA_OWNER_PIN_PROOF_EMULATOR === "1"/);
  assert.match(src,/enabled: dedaOwnerPinProofEmulatorEnabled/);
  assert.doesNotMatch(src,/enabled: true/);
  assert.match(src,/completeApprovedManualPinRecovery/);
});
