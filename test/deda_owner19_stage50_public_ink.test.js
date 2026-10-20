"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {createHash} = require("node:crypto");
const {readVerifiedPublicIdentifierInk, buildStage50PublicInkCallable} =
  require("../tools/deda_owner19_stage50_public_verified_ink_private_2026_10_20.js");

const original="@DEDA-A1B2C3", premium="@DEDA-SALEM",
  extra="@DEDA-T202", uid="accountUid001", key="stableAccount001";
const hash=x=>createHash("sha256").update(x,"utf8").digest("hex");

class Ref {
  constructor(db,p){this.db=db;this.path=p;}
  doc(id){return new Ref(this.db,this.path+"/"+id);}
}
class Db {
  constructor(){this.map=new Map();this.writes=0;}
  collection(p){return new Ref(this,p);}
  put(path,value){this.map.set(path,structuredClone(value));}
  del(path){this.map.delete(path);}
  patch(path,fields){Object.assign(this.map.get(path),fields);}
  async runTransaction(cb) {
    const tx={get:async ref=>{
      const value=this.map.get(ref.path);
      return {exists:value!==undefined, data:()=>structuredClone(value)};
    }};
    return cb(tx);
  }
}
function setup({active=premium,color="gold",kind="general_manager_gift",
  hasLedger=true}={}){
  const db=new Db();
  db.put("deda_share_ids/"+original,{
    active:true,kind:"personal",publicId:original,ownerUid:uid,
  });
  db.put("users/"+uid,{
    accountKey:key,sharePersonalId:original,
    phone:"07700000000",privateWallet:9999,
  });
  if(hasLedger)db.put("deda_owned_identifier_accounts/"+hash(key),{
    accountKey:key,originalId:original,
    ownedIds:[original,premium,extra],activeId:active,
  });
  for(const id of [premium,extra]){
    db.put("deda_owned_identifier_registry/"+id,{
      identifier:id,accountKey:key,originalId:original,
      status:"owned",acquisition:kind,
      ...(id===premium&&color!==null?{assignedColor:color}:{}),
    });
    db.put("deda_owned_identifier_aliases/"+id,{
      identifier:id,accountKey:key,originalId:original,
      kind:"permanent_alias",
    });
  }
  if(color!==null)db.put("deda_admin_identifier_grants/"+hash(key+":"+premium),{
    identifier:premium,accountKey:key,originalId:original,color,
  });
  return db;
}
const read=(db,id=original)=>
  readVerifiedPublicIdentifierInk(db,{identifier:id});
const result=(requestedId,displayId,permanentColor)=>({
  serverConfirmed:true,requestedId,displayId,permanentColor,
});

test("canonical original resolves to verified ACTIVE luxury ID ink",async()=>{
  const db=setup();
  assert.deepEqual(await read(db),result(original,premium,"gold"));
  assert.equal(db.writes,0);
  const leaked=JSON.stringify(await read(db));
  for(const value of ["phone","07700000000","ownerUid",uid,"accountKey",
    key,"wallet","location","privateCatalog","giftRecipient"]) {
    assert.equal(leaked.includes(value),false);
  }
});
test("existing premium alias also reaches active ID without client ownership",async()=>{
  const db=setup();
  assert.deepEqual(await read(db,premium),result(premium,premium,"gold"));
  assert.deepEqual(await read(db,extra),result(extra,premium,"gold"));
});
test("when active ID is original, no inactive premium decoration leaks",async()=>{
  const db=setup({active:original});
  assert.deepEqual(await read(db),result(original,original,null));
  assert.deepEqual(await read(db,premium),result(premium,original,null));
});
test("legacy account with no premium ledger stays discoverable",async()=>{
  const db=setup({hasLedger:false});
  assert.deepEqual(await read(db),result(original,original,null));
  assert.equal(await read(db,premium),null);
});
test("unknown IDs are not claimed and malformed identifiers are rejected",async()=>{
  const db=setup();
  assert.equal(await read(db,"@DEDA-UNKNOWN"),null);
  for(const id of ["@DEDA-AB","@DEDA-abc","@DEDA-SAL EM",
    "DEDA-SALEM","@DEDA-SALEM'"]) {
    await assert.rejects(read(db,id),e=>e.code==="invalid-argument");
  }
});
test("stolen registry, forged alias and receipt mismatches fail closed",async()=>{
  const corrupt=[
    db=>db.patch("deda_owned_identifier_registry/"+premium,
      {accountKey:"stolenAccount"}),
    db=>db.patch("deda_owned_identifier_aliases/"+premium,
      {originalId:"@DEDA-B1B2B3"}),
    db=>db.patch("deda_admin_identifier_grants/"+hash(key+":"+premium),
      {color:"pink"}),
    db=>db.del("deda_admin_identifier_grants/"+hash(key+":"+premium)),
    db=>db.patch("users/"+uid,{accountKey:"forgedAccount"}),
    db=>db.patch("users/"+uid,{sharePersonalId:"@DEDA-Z1Z2Z3"}),
    db=>db.patch("deda_share_ids/"+original,{active:false}),
    db=>db.put("deda_share_ids/"+premium,{
      kind:"personal",publicId:premium,active:true,ownerUid:"intruder",
    }),
    db=>db.patch("deda_owned_identifier_accounts/"+hash(key),
      {activeId:"@DEDA-STOLEN"}),
    db=>db.patch("deda_owned_identifier_accounts/"+hash(key),
      {ownedIds:[original,premium,premium]}),
  ];
  for(const sabotage of corrupt){
    const db=setup();
    sabotage(db);
    const outcome=await read(db);
    // Deactivated canonical original is not found; forged data fails closed.
    if(outcome===null)continue;
    assert.fail("forged ownership/display ID was accepted");
  }
});
test("Group002 purchased ID never inherits GM lifetime color",async()=>{
  const db=setup({kind:"verified_purchase",color:null});
  assert.deepEqual(await read(db),result(original,premium,null));
  db.patch("deda_owned_identifier_registry/"+premium,
    {assignedColor:"gold"});
  await assert.rejects(read(db),e=>e.code==="failed-precondition");
});
test("original alias outlives auth UID rotation when verified stable key remains",async()=>{
  const db=setup();
  const previous="historicUid", current="newUid";
  db.patch("deda_share_ids/"+original,{ownerUid:previous});
  db.put("users/"+previous,{accountKey:key,sharePersonalId:original});
  db.put("users/"+current,{accountKey:key,sharePersonalId:original});
  assert.deepEqual(await read(db),result(original,premium,"gold"));
});
test("Callable denies offline, missing auth/AppCheck and caller-supplied role",async()=>{
  const db=setup();
  class HttpsError extends Error{
    constructor(code,message){super(message);this.code=code;}
  }
  const onCall=(config,handler)=>{
    assert.equal(config.enforceAppCheck,true);return handler;
  };
  const settings={db,HttpsError,onCall};
  const request={auth:{uid:"signedInRequester001"},
    app:{appId:"verifiedAndroidApp"},data:{identifier:original}};
  const off=buildStage50PublicInkCallable(settings);
  await assert.rejects(off(request),e=>e.code==="unavailable");
  const callable=buildStage50PublicInkCallable({...settings,enabled:true});
  await assert.rejects(callable({...request,auth:null}),
    e=>e.code==="unauthenticated");
  await assert.rejects(callable({...request,app:null}),
    e=>e.code==="permission-denied");
  await assert.rejects(callable({...request,data:{
    identifier:original,role:"general_manager",
  }}),e=>e.code==="invalid-argument");
  const answer=await callable(request);
  assert.deepEqual(answer,result(original,premium,"gold"));
  assert.deepEqual(await callable({...request,data:{identifier:"@DEDA-UNKNOWN"}}),{
    serverConfirmed:false,requestedId:"@DEDA-UNKNOWN",
    displayId:null,permanentColor:null,
  });
  assert.equal(db.writes,0);
});
