"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {createHash}=require("node:crypto");
const {resolveStage51FriendOriginalId,buildStage51FriendAliasCallable}=
  require("../tools/deda_owner19_stage51_friend_original_alias_private_2026_10_20.js");
const original="@DEDA-A1B2C3",premium="@DEDA-SALEM",inactive="@DEDA-T202";
const uid="historicUid51",key="persistentAccount51";
const hash=x=>createHash("sha256").update(x,"utf8").digest("hex");
class Ref{
  constructor(db,path){this.db=db;this.path=path;}
  doc(id){return new Ref(this.db,this.path+"/"+id);}
}
class Db{
  constructor(){this.docs=new Map();this.writes=0;}
  collection(c){return new Ref(this,c);}
  set(path,data){this.docs.set(path,structuredClone(data));}
  patch(path,data){Object.assign(this.docs.get(path),data);}
  del(path){this.docs.delete(path);}
  async runTransaction(cb){
    return cb({get:async ref=>{
      const val=this.docs.get(ref.path);
      return {exists:val!==undefined,data:()=>structuredClone(val)};
    }});
  }
}
function setup({withLedger=true}={}){
  const db=new Db();
  db.set("deda_share_ids/"+original,{
    kind:"personal",active:true,publicId:original,ownerUid:uid});
  db.set("users/"+uid,{accountKey:key,sharePersonalId:original,
    phone:"07700000000",walletDiamonds:4000});
  if(withLedger){
    db.set("deda_owned_identifier_accounts/"+hash(key),{
      accountKey:key,originalId:original,
      ownedIds:[original,premium,inactive],activeId:premium});
  }
  for(const id of [premium,inactive]){
    db.set("deda_owned_identifier_registry/"+id,{
      identifier:id,originalId:original,accountKey:key,status:"owned"});
    db.set("deda_owned_identifier_aliases/"+id,{
      identifier:id,originalId:original,accountKey:key,
      kind:"permanent_alias"});
  }
  return db;
}
const query=(db,identifier)=>resolveStage51FriendOriginalId(db,{identifier});
test("premium and inactive-but-owned IDs resolve ONLY canonical public original",async()=>{
  const db=setup();
  for(const id of [premium,inactive,original]){
    assert.deepEqual(await query(db,id),{
      serverConfirmed:true,requestedId:id,originalId:original});
  }
  assert.equal(db.writes,0);
  const output=JSON.stringify(await query(db,premium));
  for(const secret of [uid,key,"phone","wallet","recipient","location"]){
    assert.equal(output.includes(secret),false);
  }
});
test("original DEDA friends stay discoverable without premium ledger",async()=>{
  const db=setup({withLedger:false});
  assert.deepEqual(await query(db,original),{
    serverConfirmed:true,requestedId:original,originalId:original});
  await assert.rejects(query(db,premium),e=>e.code==="failed-precondition");
});
test("old signed-in UID rotation does not break historical original directory",async()=>{
  const db=setup();
  db.patch("deda_share_ids/"+original,{ownerUid:"earlierAccountUid"});
  db.set("users/earlierAccountUid",{accountKey:key,sharePersonalId:original});
  assert.deepEqual(await query(db,premium),{
    serverConfirmed:true,requestedId:premium,originalId:original});
});
test("unknown ID cannot accidentally create a new friend/account",async()=>{
  const db=setup();
  assert.equal(await query(db,"@DEDA-UNLISTED"),null);
  for(const bad of ["@DEDA-A","@DEDA-abcd","DEDA-ABCD","@DEDA-A B C",
    "@DEDA-ABCDEFGHIJKLMNOP"]){
    await assert.rejects(query(db,bad),e=>e.code==="invalid-argument");
  }
});
test("forged alias, fake registry, revoked owner and missing ledger FAIL closed",async()=>{
  const corrupt=[
    db=>db.patch("deda_owned_identifier_aliases/"+premium,
      {originalId:"@DEDA-Z1Z2Z3"}),
    db=>db.patch("deda_owned_identifier_aliases/"+premium,
      {accountKey:"thief"}),
    db=>db.patch("deda_owned_identifier_registry/"+premium,
      {status:"available"}),
    db=>db.patch("deda_owned_identifier_accounts/"+hash(key),
      {ownedIds:[original,inactive]}),
    db=>db.patch("deda_owned_identifier_accounts/"+hash(key),
      {activeId:"@DEDA-FAKE"}),
    db=>db.patch("deda_share_ids/"+original,{active:false}),
    db=>db.patch("users/"+uid,{accountKey:"thief"}),
    db=>db.patch("users/"+uid,{sharePersonalId:"@DEDA-TAMPER"}),
    db=>db.del("deda_owned_identifier_accounts/"+hash(key)),
    db=>db.set("deda_share_ids/"+premium,{kind:"personal",
      publicId:premium,active:true,ownerUid:"thief"}),
    db=>db.patch("deda_owned_identifier_accounts/"+hash(key),
      {ownedIds:[original,premium,premium]}),
  ];
  for(let i=0;i<corrupt.length;i++){
    const db=setup();
    corrupt[i](db);
    const result=await query(db,premium).then(v=>v,e=>e);
    assert.ok(result===null||(result instanceof Error &&
      result.code==="failed-precondition"),"forgery was resolved "+i);
  }
});
test("AppCheck and Firebase Auth required; OFF by default; no client ownerUid",async()=>{
  const db=setup();
  class HttpsError extends Error{
    constructor(code,message){super(message);this.code=code;}
  }
  const onCall=(config,fn)=>{
    assert.equal(config.enforceAppCheck,true);
    return fn;
  };
  const settings={db,onCall,HttpsError};
  const request={auth:{uid:"searcher51"},app:{appId:"verified-app"},
    data:{identifier:premium}};
  const off=buildStage51FriendAliasCallable(settings);
  await assert.rejects(off(request),e=>e.code==="unavailable");
  const on=buildStage51FriendAliasCallable({...settings,enabled:true});
  await assert.rejects(on({...request,auth:null}),
    e=>e.code==="unauthenticated");
  await assert.rejects(on({...request,app:null}),
    e=>e.code==="permission-denied");
  await assert.rejects(on({...request,data:{identifier:premium,
    ownerUid:"admin",accountKey:"spoof"}}),
    e=>e.code==="invalid-argument");
  assert.deepEqual(await on(request),{
    serverConfirmed:true,requestedId:premium,originalId:original});
  assert.deepEqual(await on({...request,data:{identifier:"@DEDA-UNKNOWN"}}),{
    serverConfirmed:false,requestedId:"@DEDA-UNKNOWN",originalId:null});
  assert.equal(db.writes,0);
});
