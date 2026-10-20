"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const fs=require("node:fs");
const {createHash}=require("node:crypto");
const {ROUTES,createStage57VerifiedReadOnlyRoutes:bundle}=
  require("../tools/deda_owner19_stage57_joined_verified_read_routes_PRIVATE_NO_DEPLOY_2026_10_20.js");
const orig="@DEDA-A1B2C3",premium="@DEDA-SALEM",uid="stage57_signed_user",
  key="stage57_stable_account",requester="stage57_another_authenticated";
const sha=s=>createHash("sha256").update(s).digest("hex");
const initialEnv={project:process.env.GCLOUD_PROJECT,
  host:process.env.FIRESTORE_EMULATOR_HOST};
function env(project,host){
  if(project===null)delete process.env.GCLOUD_PROJECT;
  else process.env.GCLOUD_PROJECT=project;
  if(host===null)delete process.env.FIRESTORE_EMULATOR_HOST;
  else process.env.FIRESTORE_EMULATOR_HOST=host;
}
test.after(()=>{
  if(initialEnv.project===undefined)delete process.env.GCLOUD_PROJECT;
  else process.env.GCLOUD_PROJECT=initialEnv.project;
  if(initialEnv.host===undefined)delete process.env.FIRESTORE_EMULATOR_HOST;
  else process.env.FIRESTORE_EMULATOR_HOST=initialEnv.host;
});
class Ref {
  constructor(db,path){this.db=db;this.path=path;}
  doc(name){return new Ref(this.db,this.path+"/"+name);}
}
class Db {
  constructor(){this.docs=new Map();this.writes=0;}
  collection(name){return new Ref(this,name);}
  put(path,data){this.docs.set(path,structuredClone(data));}
  change(path,patch){Object.assign(this.docs.get(path),patch);}
  async runTransaction(fn){
    return fn({get:async ref=>{
      const value=this.docs.get(ref.path);
      return {exists:value!==undefined,data:()=>structuredClone(value)};
    },set:()=>{this.writes++;throw Error("write forbidden");},
      update:()=>{this.writes++;throw Error("write forbidden");}});
  }
}
class HttpsError extends Error{
  constructor(code,msg){super(msg);this.code=code;}
}
function dbFixture(){
  const db=new Db();
  db.put("users/"+uid,{
    accountKey:key,sharePersonalId:orig,phone:"07700000000",
    personalWallet:999999,location:"private",
  });
  db.put("deda_sessions/"+uid,{uid,accountKey:key});
  db.put("deda_share_ids/"+orig,{
    kind:"personal",active:true,publicId:orig,ownerUid:uid,
  });
  db.put("deda_owned_identifier_accounts/"+sha(key),{
    accountKey:key,originalId:orig,
    ownedIds:[orig,premium],activeId:premium,
  });
  db.put("deda_owned_identifier_registry/"+premium,{
    identifier:premium,accountKey:key,originalId:orig,
    acquisition:"general_manager_gift",status:"owned",
    assignedColor:"diamond",
  });
  db.put("deda_owned_identifier_aliases/"+premium,{
    identifier:premium,accountKey:key,originalId:orig,
    kind:"permanent_alias",
  });
  db.put("deda_admin_identifier_grants/"+sha(key+":"+premium),{
    identifier:premium,accountKey:key,originalId:orig,color:"diamond",
  });
  return db;
}
const request=(data={},signedUid=uid)=>({
  auth:{uid:signedUid},app:{appId:"appcheck-verified-demo"},data,
});
function create(db,flags={}){
  const configs=[];
  const routes=bundle({db,HttpsError,flags,
    onCall:(config,handler)=>{configs.push(config);return handler;}});
  return {routes,configs};
}
test("exact three Flutter Stage48,50,51 callable names and AppCheck declarations",()=>{
  const db=dbFixture();env(null,null);
  const {routes,configs}=create(db);
  assert.deepEqual(Object.keys(routes),[
    "dedaPremiumReadActiveIdentifierInk",
    "dedaPremiumReadPublicIdentifierStyle",
    "dedaPremiumResolveFriendOriginal",
  ]);
  assert.deepEqual(Object.values(ROUTES),Object.keys(routes));
  assert.equal(configs.length,3);
  assert.ok(configs.every(c=>c.enforceAppCheck===true));
  for(const file of [
    ["lib/deda_stage48_verified_active_profile_ink.dart",ROUTES.activeInk],
    ["lib/deda_stage50_verified_friend_ink_badge.dart",ROUTES.publicInk],
    ["lib/deda_stage51_verified_friend_alias_search.dart",ROUTES.friendAlias],
  ]){
    assert.ok(fs.readFileSync(file[0],"utf8").includes("'"+file[1]+"'"));
  }
});
test("all server callable feature flags default OFF even with valid signed account",async()=>{
  env(null,null);const db=dbFixture(),{routes}=create(db);
  for(const [name,method] of Object.entries(routes)){
    const data=name===ROUTES.activeInk?{}:{identifier:orig};
    await assert.rejects(method(request(data)),e=>e.code==="unavailable");
  }
  assert.equal(db.writes,0);
});
test("attempted live enable without BOTH demo+local emulator fails before callables exist",()=>{
  const scenarios=[
    [null,null],["real-firebase-prod",null],
    ["real-firebase-prod","127.0.0.1:8080"],
    ["demo-deda-private",null],
    ["demo-deda-private","firebase-cloud:8080"],
  ];
  for(const [project,host] of scenarios){
    env(project,host);
    assert.throws(()=>create(dbFixture(),{activeInk:true}),
      e=>e.code==="failed-precondition");
  }
});
test("in real local DEMO integration, server proofs agree on one owner and colors",async()=>{
  env("demo-deda-owner19-stage57","127.0.0.1:8080");
  const db=dbFixture();
  const {routes}=create(db,{
    activeInk:true,publicInk:true,friendAlias:true,
  });
  const mine=await routes[ROUTES.activeInk](request({}));
  assert.deepEqual(mine,{
    serverConfirmed:true,accountUid:uid,
    originalId:orig,activeId:premium,permanentColor:"diamond",
  });
  const publicName=await routes[ROUTES.publicInk](
    request({identifier:orig},requester));
  assert.deepEqual(publicName,{
    serverConfirmed:true,requestedId:orig,
    displayId:premium,permanentColor:"diamond",
  });
  const alias=await routes[ROUTES.friendAlias](
    request({identifier:premium},requester));
  assert.deepEqual(alias,{
    serverConfirmed:true,requestedId:premium,originalId:orig,
  });
  const legacy=await routes[ROUTES.friendAlias](
    request({identifier:orig},requester));
  assert.equal(legacy.originalId,orig);
  assert.equal(db.writes,0);
  for(const response of [mine,publicName,alias,legacy]){
    const text=JSON.stringify(response);
    for(const privateField of [key,"phone","07700000000",
      "location","personalWallet","ownerUid","accountKey"]){
      assert.equal(text.includes(privateField),false);
    }
  }
});
test("cross-account current ink forbidden; public lookup never grants social relations",async()=>{
  env("demo-deda-owner19-stage57","localhost:8080");
  const db=dbFixture();
  const {routes}=create(db,{
    activeInk:true,publicInk:true,friendAlias:true,
  });
  await assert.rejects(
    routes[ROUTES.activeInk](request({},requester)),
    e=>["failed-precondition","internal"].includes(e.code));
  assert.equal((await routes[ROUTES.publicInk](
    request({identifier:orig},requester))).displayId,premium);
  assert.equal(db.writes,0);
});
test("missing AppCheck, missing Auth, client forged role/color/uid fail closed",async()=>{
  env("demo-deda-owner19-stage57","127.0.0.1:8080");
  const db=dbFixture(),{routes}=create(db,{
    activeInk:true,publicInk:true,friendAlias:true,
  });
  for(const fn of Object.values(routes)){
    const data=fn===routes[ROUTES.activeInk]?{}:{identifier:orig};
    await assert.rejects(fn({...request(data),app:null}),
      e=>e.code==="permission-denied");
    await assert.rejects(fn({...request(data),auth:null}),
      e=>e.code==="unauthenticated");
    await assert.rejects(fn(request({...data,role:"general_manager",
      color:"pink",ownerUid:uid})),
      e=>e.code==="invalid-argument");
  }
  assert.equal(db.writes,0);
});
test("mutated GM color receipt fails closed across private and public ink",async()=>{
  env("demo-deda-owner19-stage57","localhost:8080");
  const db=dbFixture();
  db.change("deda_admin_identifier_grants/"+sha(key+":"+premium),
    {color:"pink"});
  const {routes}=create(db,{
    activeInk:true,publicInk:true,friendAlias:true,
  });
  for(const [fn,data] of [
    [routes[ROUTES.activeInk],{}],
    [routes[ROUTES.publicInk],{identifier:orig}],
  ]){
    await assert.rejects(fn(request(data)),
      e=>["failed-precondition","internal"].includes(e.code));
  }
  assert.equal(db.writes,0);
});
