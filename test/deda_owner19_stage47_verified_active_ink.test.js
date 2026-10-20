"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {createHash} = require("node:crypto");
const {readVerifiedActiveIdentifierInk,buildVerifiedInkReadCallable} =
  require("../tools/deda_owner19_stage47_verified_active_ink_private_2026_10_20.js");
const original="@DEDA-A1B2C3", bonus="@DEDA-SALEM";
const uid="manager42",otherUid="other42",key="account42";
const hash=x=>createHash("sha256").update(x).digest("hex");
class Ref {
  constructor(db,path){this.db=db;this.path=path;}
  doc(id){return new Ref(this.db,this.path+"/"+id);}
}
class Db {
  constructor(){this.docs=new Map();this.writes=0;}
  collection(name){return new Ref(this,name);}
  put(path,record){this.docs.set(path,structuredClone(record));}
  async runTransaction(fn){
    const tx={get:async(ref)=>{
      const value=this.docs.get(ref.path);
      return {exists:value!==undefined,data:()=>structuredClone(value)};
    }};
    return fn(tx);
  }
}
function setup({active=bonus,kind="general_manager_gift",
  color="diamond"}={}){
  const db=new Db();
  db.put("users/"+uid,{accountKey:key,sharePersonalId:original});
  db.put("deda_sessions/"+uid,{uid,accountKey:key});
  db.put("deda_share_ids/"+original,{
    kind:"personal",active:true,publicId:original,ownerUid:uid,
  });
  db.put("deda_owned_identifier_accounts/"+hash(key),{
    accountKey:key,originalId:original,
    ownedIds:[original,bonus],activeId:active,
  });
  db.put("deda_owned_identifier_registry/"+bonus,{
    identifier:bonus,accountKey:key,originalId:original,
    acquisition:kind,assignedColor:color,status:"owned",
  });
  db.put("deda_owned_identifier_aliases/"+bonus,{
    kind:"permanent_alias",identifier:bonus,accountKey:key,
    originalId:original,
  });
  db.put("deda_admin_identifier_grants/"+hash(key+":"+bonus),{
    accountKey:key,identifier:bonus,originalId:original,color,
  });
  return db;
}
const read=db=>readVerifiedActiveIdentifierInk(db,{uid});

test("server-confirmed GM gifted active ID returns permanently fixed ink",async()=>{
  const db=setup();
  assert.deepEqual(await read(db),{
    serverConfirmed:true,accountUid:uid,
    originalId:original,activeId:bonus,permanentColor:"diamond",
  });
  assert.equal(db.writes,0);
});
test("original active ID has no premium ink despite having gifted inventory",async()=>{
  const db=setup({active:original});
  const r=await read(db);
  assert.equal(r.activeId,original);
  assert.equal(r.permanentColor,null);
});
test("verified Group002 paid ID cannot impersonate exclusive lifetime color",async()=>{
  const db=setup({kind:"verified_purchase",color:null});
  const r=await read(db);
  assert.equal(r.permanentColor,null);
  db.docs.get("deda_owned_identifier_registry/"+bonus).assignedColor="pink";
  await assert.rejects(read(db),/unavailable/);
});
test("unregistered, cross-owner, or forged alias and receipt fail closed",async()=>{
  const edits=[
    db=>db.docs.get("deda_sessions/"+uid).accountKey="otherAccount",
    db=>db.docs.get("deda_owned_identifier_registry/"+bonus).accountKey="other",
    db=>db.docs.get("deda_owned_identifier_aliases/"+bonus).originalId="@DEDA-000000",
    db=>db.docs.get("deda_admin_identifier_grants/"+hash(key+":"+bonus)).color="pink",
    db=>db.docs.get("deda_owned_identifier_accounts/"+hash(key)).ownedIds.pop(),
    db=>db.docs.delete("deda_admin_identifier_grants/"+hash(key+":"+bonus)),
  ];
  for(const edit of edits){
    const db=setup();
    edit(db);
    await assert.rejects(read(db),/unavailable/);
  }
});
test("unknown UID and missing login cannot read another account color",async()=>{
  const db=setup();
  await assert.rejects(readVerifiedActiveIdentifierInk(db,{uid:otherUid}),
    /unavailable/);
  await assert.rejects(readVerifiedActiveIdentifierInk(db,{uid:"!"}),
    /unavailable/);
});
test("callable defaults disabled, requires verified Auth and AppCheck",async()=>{
  const db=setup();
  const HttpsError=class extends Error{constructor(code,message){
    super(message);this.code=code;}};
  const onCall=(config,handler)=>{assert.equal(config.enforceAppCheck,true);
    return handler;};
  const cfg={db,HttpsError,onCall};
  const disabled=buildVerifiedInkReadCallable(cfg);
  const req={auth:{uid},app:{appId:"verifiedApp"},data:{}};
  await assert.rejects(disabled(req),e=>e.code==="unavailable");
  const enabled=buildVerifiedInkReadCallable({...cfg,enabled:true});
  await assert.rejects(enabled({...req,auth:null}),
    e=>e.code==="unauthenticated");
  await assert.rejects(enabled({...req,app:null}),
    e=>e.code==="permission-denied");
  await assert.rejects(enabled({...req,data:{color:"pink"}}),
    e=>e.code==="invalid-argument");
  const data=await enabled(req);
  assert.equal(data.permanentColor,"diamond");
  assert.equal(Object.hasOwn(data,"accountKey"),false);
  assert.equal(Object.hasOwn(data,"ownedIds"),false);
  assert.equal(db.writes,0);
});
