"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {buildReadPublicAliasCallable,buildResolveGiftRecipientCallable,
  buildResolvePublicRecipientCallable}=
  require("../functions/deda_100374_qa32_verified_public_gift_callables_NOT_EXPORTED.js");

const original="@DEDA-AQPYXJ",alias="@DEDA-IRAQI";
class HttpsError extends Error{
  constructor(code,message){super(message);this.code=code;}
}
const onCall=(opts,fn)=>{assert.equal(opts.enforceAppCheck,true);return fn;};
function setup(){
  const docs=new Map();
  const set=(id,body)=>docs.set(id,structuredClone(body));
  set("admins/gm01",{active:true,role:"general_manager"});
  set("admins/normalUser",{active:true,role:"employee"});
  set("deda_share_ids/"+original,{publicId:original,kind:"personal",
    active:true,ownerUid:"recipient01"});
  set("deda_stage71_active_identifier/"+original,{originalId:original,
    activeId:alias});
  set("deda_stage71_granted_registry/"+alias,{identifier:alias,
    recipientOriginalId:original,kind:"gifted",group:"001",baseColor:"gold"});
  set("deda_stage74_id_gift_receipts/"+alias,{identifier:alias,
    originalId:original,group:"001",receivedAt:"2026-10-21"});
  const db={doc:k=>({get:async()=>{
    const v=docs.get(k);return{exists:v!==undefined,data:()=>structuredClone(v)};
  }})};
  return {db,set};
}
const req=(identifier,uid="gm01")=>({
  auth:{uid},app:{appId:"verifiedAndroid"},data:{identifier}});
test("public callable verifies same premium ID without disclosing UID, phone or wallet",async()=>{
  const {db}=setup();
  const read=buildReadPublicAliasCallable({onCall,HttpsError,db});
  assert.deepEqual(await read(req(original,"normalUser")),{requestedId:original,
    displayId:alias,permanentColor:"gold",serverConfirmed:true});
  assert.equal(JSON.stringify(await read(req(original))).includes("recipient01"),false);
});
test("GM lookup accepts original and activated alias with ONE canonical target",async()=>{
  const {db}=setup();
  const lookup=buildResolveGiftRecipientCallable({onCall,HttpsError,db});
  for(const id of [alias,original]){
    const x=await lookup(req(id));
    assert.equal(x.originalId,original);
    assert.equal(x.serverConfirmed,true);
  }
});
test("gift lookup forbids employees, absent auth or AppCheck, and extra client UID",async()=>{
  const {db}=setup();
  const lookup=buildResolveGiftRecipientCallable({onCall,HttpsError,db});
  await assert.rejects(lookup(req(alias,"normalUser")),e=>e.code==="permission-denied");
  await assert.rejects(lookup({...req(alias),auth:null}),e=>e.code==="unauthenticated");
  await assert.rejects(lookup({...req(alias),app:null}),e=>e.code==="permission-denied");
  await assert.rejects(lookup({...req(alias),data:{identifier:alias,uid:"thief"}}),
    e=>e.code==="invalid-argument");
});
test("only active explicit legacy GM aliases are authorized; never employees or disabled managers",async()=>{
  for(const role of ["general_manager","generalManager","manager","director","admin"]){
    const {db,set}=setup();
    set("admins/gm01",{active:true,status:"active",role});
    const handler=buildResolveGiftRecipientCallable({onCall,HttpsError,db});
    const result=await handler(req(alias));
    assert.equal(result.originalId,original);
    assert.equal(result.serverConfirmed,true);
  }
  for(const record of [
    {active:true,status:"temporarily_stopped",role:"manager"},
    {active:false,status:"disabled",role:"general_manager"},
    {active:true,status:"active",role:"employee"},
    {active:true,status:"active",role:"deputy_manager"},
    {active:true,status:"active"},
  ]){
    const {db,set}=setup();
    set("admins/gm01",record);
    const handler=buildResolveGiftRecipientCallable({onCall,HttpsError,db});
    await assert.rejects(handler(req(alias)),
      e=>e.code==="permission-denied");
  }
});
test("missing receipt, inactive alias and corrupted grant cannot authorize gem recipient",async()=>{
  const {db,set}=setup();
  const lookup=buildResolveGiftRecipientCallable({onCall,HttpsError,db});
  set("deda_stage74_id_gift_receipts/"+alias,{identifier:alias,
    originalId:"@DEDA-ZZ1122",group:"001",receivedAt:"2026"});
  await assert.rejects(lookup(req(alias)),e=>e.code==="failed-precondition");
  set("deda_stage74_id_gift_receipts/"+alias,{identifier:alias,
    originalId:original,group:"001",receivedAt:"2026"});
  set("deda_stage71_active_identifier/"+original,{originalId:original,
    activeId:original});
  const no=await lookup(req(alias));
  assert.equal(no.serverConfirmed,false);
  assert.equal(no.originalId,null);
});

test("read-only premium recipient resolver accepts friend/location lookup for any verified user", async()=>{
  const {db}=setup();
  const handler=buildResolvePublicRecipientCallable({onCall,HttpsError,db});
  for(const role of ["normalUser","gm01"]){
    const item=await handler(req(alias,role));
    assert.deepEqual(item,{requestedId:alias,originalId:original,serverConfirmed:true});
  }
  const originalResult=await handler(req(original,"normalUser"));
  assert.deepEqual(originalResult,{requestedId:original,originalId:original,serverConfirmed:true});
  const unknown=await handler(req("@DEDA-NEVER","normalUser"));
  assert.equal(unknown.serverConfirmed,false);
  assert.equal(unknown.originalId,null);
});
test("read-only friend/location recipient lookup cannot be spoofed by no auth/AppCheck or client UID",async()=>{
  const {db}=setup();
  const handler=buildResolvePublicRecipientCallable({onCall,HttpsError,db});
  await assert.rejects(handler({...req(alias),auth:null}),e=>e.code==="unauthenticated");
  await assert.rejects(handler({...req(alias),app:null}),e=>e.code==="permission-denied");
  await assert.rejects(handler({...req(alias),data:{identifier:alias,accountKey:"someone-else"}}),
    e=>e.code==="invalid-argument");
});
test("read-only friend/location recipient rejects inactive, claimed but unreceived or wrong-owner premium aliases",async()=>{
  const {db,set}=setup();
  const handler=buildResolvePublicRecipientCallable({onCall,HttpsError,db});
  set("deda_stage71_active_identifier/"+original,{originalId:original,activeId:original});
  assert.equal((await handler(req(alias))).serverConfirmed,false);
  set("deda_stage71_active_identifier/"+original,{originalId:original,activeId:alias});
  set("deda_stage74_id_gift_receipts/"+alias,{identifier:alias,originalId:"@DEDA-ZZ2222",group:"001",receivedAt:"2026"});
  await assert.rejects(handler(req(alias)),e=>e.code==="failed-precondition");
});
