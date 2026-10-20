"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const fs=require("node:fs");
const {rejectIfUnprovenManagerPersonalSpending:check}=
  require("../tools/deda_owner19_stage55_gm_wallet_source_lock_2026_10_20.js");
const originalProject=process.env.GCLOUD_PROJECT;
const originalEmulator=process.env.FIRESTORE_EMULATOR_HOST;
function withEnv(project,host,fn){
  if(project===null)delete process.env.GCLOUD_PROJECT;
  else process.env.GCLOUD_PROJECT=project;
  if(host===null)delete process.env.FIRESTORE_EMULATOR_HOST;
  else process.env.FIRESTORE_EMULATOR_HOST=host;
  try{return fn();}finally{
    if(originalProject===undefined)delete process.env.GCLOUD_PROJECT;
    else process.env.GCLOUD_PROJECT=originalProject;
    if(originalEmulator===undefined)delete process.env.FIRESTORE_EMULATOR_HOST;
    else process.env.FIRESTORE_EMULATOR_HOST=originalEmulator;
  }
}
test("zero manager personal spend never requires a provenance exception",()=>{
  for(const project of [null,"real-deda-25b88","demo-deda-owner19-stage55"]){
    withEnv(project,null,()=>assert.equal(check(0),undefined));
  }
});
test("any positive GM test wallet spending is denied outside LOCAL DEMO emulator",()=>{
  const cases=[
    [null,null],["real-deda-25b88",null],
    ["real-deda-25b88","127.0.0.1:8080"],
    ["demo-deda-owner19-stage55",null],
    ["demo-deda-owner19-stage55","8.8.8.8:8080"],
    ["demo-deda-owner19-stage55","remotehost:8080"],
  ];
  for(const [project,host] of cases){
    withEnv(project,host,()=>{
      for(const amount of [1,4999,5000,10000,1000000]){
        assert.throws(()=>check(amount),e=>e.code==="failed-precondition");
      }
    });
  }
});
test("synthetic QA local demo emulator still exercises 5k/10k race logic",()=>{
  withEnv("demo-deda-owner19-stage55","127.0.0.1:8080",()=>{
    assert.equal(check(5000),undefined);
    assert.equal(check(10000),undefined);
  });
  withEnv("demo-deda-stage18-purchase-real-races","localhost:8080",()=>{
    assert.equal(check(7000),undefined);
  });
});
test("negative, fractions, too-large, string or NaN cannot bypass lock",()=>{
  for(const amount of [-1,0.5,NaN,Infinity,"5000",1073741825]){
    withEnv("demo-deda-owner19-stage55","localhost:8080",
      ()=>assert.throws(()=>check(amount),e=>e.code==="failed-precondition"));
  }
});
test("both staged backend purchase entry points invoke lock before ANY write",()=>{
  for(const filename of [
    "tools/deda_intakadha_point13_atomic_id_card_checkout_2026_10_19.js",
    "tools/deda_stage18_private_atomic_identifier_checkout_2026_10_19.js",
  ]){
    const src=fs.readFileSync(filename,"utf8");
    assert.equal((src.match(/rejectIfUnprovenManagerPersonalSpending\(/g)||[]).length,1);
    assert.match(src,/deda_owner19_stage55_gm_wallet_source_lock_2026_10_20/);
    const check=src.indexOf("    rejectIfUnprovenManagerPersonalSpending(");
    const firstWrite=Math.min(...["tx.update(","tx.create(","tx.set("].
      map(s=>{const x=src.indexOf(s);return x===-1?Infinity:x;}));
    assert.ok(check>=0&&check<firstWrite,filename+" must reject before debit");
  }
});
test("no deployed production callable imports test manager debit exemption",()=>{
  const prod=fs.readFileSync("functions/index.js","utf8");
  assert.doesNotMatch(prod,/stage55_gm_wallet_source_lock/);
  assert.doesNotMatch(prod,/checkoutVerifiedIdentifier/);
  assert.doesNotMatch(prod,/checkoutIdCard/);
});
