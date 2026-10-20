"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const fs=require("node:fs");
const {ALL_NAMES,OWNER19,STAGE16,ROUTES,
  createOwner19Stage59PrivateRoutes:create}=require(
    "../tools/deda_owner19_stage59_all_server_routes_PRIVATE_NOT_EXPORTED_2026_10_20.js");
const savedProject=process.env.GCLOUD_PROJECT,savedHost=process.env.FIRESTORE_EMULATOR_HOST;
test.after(()=>{
  if(savedProject===undefined)delete process.env.GCLOUD_PROJECT;
  else process.env.GCLOUD_PROJECT=savedProject;
  if(savedHost===undefined)delete process.env.FIRESTORE_EMULATOR_HOST;
  else process.env.FIRESTORE_EMULATOR_HOST=savedHost;
});
function env(project,host){
  if(project===null)delete process.env.GCLOUD_PROJECT;
  else process.env.GCLOUD_PROJECT=project;
  if(host===null)delete process.env.FIRESTORE_EMULATOR_HOST;
  else process.env.FIRESTORE_EMULATOR_HOST=host;
}
class HttpsError extends Error{
  constructor(code,msg){super(msg);this.code=code;}
}
function setup(flags){
  let secrets=0,decrypts=0,dbAccess=0;
  const registrations=[];
  const db={
    runTransaction:async()=>{dbAccess++;throw Error("never-query-backend");},
    collection:()=>{dbAccess++;throw Error("never-access-users");},
  };
  const args={
    db,flags,HttpsError,
    secret:{value:()=>{secrets++;throw Error("never-read-reserved-100-key");}},
    decryptPrivate100:()=>{decrypts++;throw Error("never-decrypt-100");},
    readEncryptedManifest:()=>{decrypts++;throw Error("never-read-100-blob");},
    approvedGroup002:()=>{dbAccess++;throw Error("never-reveal-sale-approvals");},
    onCall:(config,callback)=>{
      registrations.push(config);
      return callback;
    },
  };
  const routes=create(args);
  return {routes,registrations,
    touches:()=>({secrets,decrypts,dbAccess})};
}
const authenticated=(data={})=>({
  auth:{uid:"verified_57_user"},app:{appId:"verified_appcheck"},data,
});
test("exact 15 unique callables cover owner shop, manager actions, verified IDs and public routes",()=>{
  env(null,null);
  const {routes,registrations,touches}=setup();
  assert.equal(ALL_NAMES.length,15);
  assert.equal(new Set(ALL_NAMES).size,15);
  assert.deepEqual(new Set(Object.keys(routes)),new Set(ALL_NAMES));
  assert.equal(Object.values(OWNER19).length,5);
  assert.equal(Object.values(STAGE16).length,7);
  assert.equal(Object.values(ROUTES).length,3);
  assert.equal(registrations.length,15);
  assert.ok(registrations.every(x=>x.enforceAppCheck===true));
  assert.equal(registrations.filter(x=>x.secrets?.length).length,6);
  assert.deepEqual(touches(),{secrets:0,decrypts:0,dbAccess:0});
});
test("EVERY purchase / admin / read endpoint defaults unavailable, not successful demo purchase",async()=>{
  env(null,null);
  const {routes,touches}=setup({});
  for(const name of ALL_NAMES){
    const input= name.includes("Read")||name.includes("List")?
      {}:{identifier:"@DEDA-SALEM"};
    await assert.rejects(routes[name](authenticated(input)),
      e=>e.code==="unavailable");
  }
  assert.deepEqual(touches(),{secrets:0,decrypts:0,dbAccess:0});
});
test("real project cannot enable ANY wallet, catalog, owner or friend operation",()=>{
  for(const [project,host] of [
    [null,null],["deda-iraq-production",null],
    ["deda-iraq-production","127.0.0.1:8080"],
    ["demo-deda-owner19",null],
    ["demo-deda-owner19","firebase-cloud:8080"],
  ]){
    env(project,host);
    for(const flags of [
      {purchase:{point16:{cardPurchase:true}}},
      {purchase:{point16:{cardUse:true}}},
      {purchase:{buyIdentifier:true}},
      {purchase:{readExclusive:true}},
      {purchase:{gmGift:true}},
      {read:{activeInk:true}},
      {read:{publicInk:true}},
      {read:{friendAlias:true}},
    ]){
      assert.throws(()=>setup(flags),
        e=>e.code==="failed-precondition");
    }
  }
});
test("disposable emulator can REGISTER routes only; real keys and balances never touched",()=>{
  env("demo-deda-stage59-private","localhost:8080");
  const {routes,registrations,touches}=setup({
    purchase:{point16:{read:true,cardPurchase:true,cardUse:true,
      identifierUse:true},buyIdentifier:true,readExclusive:true,
      gmGift:true,listSale:true},
    read:{activeInk:true,publicInk:true,friendAlias:true},
  });
  assert.equal(Object.keys(routes).length,15);
  assert.equal(registrations.length,15);
  assert.deepEqual(touches(),{secrets:0,decrypts:0,dbAccess:0});
});
test("reject misspelled flags and non-boolean enable, no silent auto-release",()=>{
  env("demo-deda-stage59-private","localhost:8080");
  for(const flags of [
    {purchase:{all:true}},
    {purchase:{buyIdentifier:"true"}},
    {purchase:{point16:{cardPurchase:1}}},
    {purchase:{point16:{diamondCredit:true}}},
    {read:{wallet:true}},
    {read:{activeInk:"true"}},
    {cashflow:{all:true}},
    {read:null},
  ]){
    assert.throws(()=>setup(flags),
      e=>e.code==="failed-precondition");
  }
});
test("actual 100360 Flutter clients reference names that are in the unified contract",()=>{
  const clients=[
    ["lib/deda_exclusive_ids_admin_page.dart",
      [OWNER19.adminRead,OWNER19.adminSelfUse,OWNER19.adminGrant]],
    ["lib/deda_stage42_verified_sale_panel.dart",
      [OWNER19.listSale,OWNER19.idPurchase,STAGE16.readIdentifiers]],
    ["lib/deda_stage48_verified_active_profile_ink.dart",[ROUTES.activeInk]],
    ["lib/deda_stage50_verified_friend_ink_badge.dart",[ROUTES.publicInk]],
    ["lib/deda_stage51_verified_friend_alias_search.dart",[ROUTES.friendAlias]],
  ];
  for(const [path,names] of clients){
    const code=fs.readFileSync(path,"utf8");
    for(const name of names){
      assert.ok(code.includes("'"+name+"'"),
        "missing Flutter callable name "+name+" in "+path);
    }
  }
});
test("release still lacks production exports and wallet source attestation",()=>{
  const production=fs.readFileSync("functions/index.js","utf8");
  for(const name of [...ALL_NAMES,
    "deda_owner19_stage59_all_server_routes_PRIVATE_NOT_EXPORTED_2026_10_20"]){
    assert.equal(production.includes(name),false,
      "SAFE_STOP: staged premium route unexpectedly in live production: "+name);
  }
  const shop=fs.readFileSync(
    "lib/deda_stage42_verified_sale_panel.dart","utf8");
  assert.match(shop,/DEDA_PREMIUM_IDS_SERVER_LIVE/);
  assert.match(shop,/defaultValue:\s*false/);
});
