"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  readVerifiedPublicAlias, resolveVerifiedGiftRecipientOriginal,
} = require("../functions/deda_qa32_public_alias_resolver_NOT_EXPORTED.js");

const O = "@DEDA-AQPYXJ", A = "@DEDA-IRAQI", X = "@DEDA-OTHER";
function database(options={}) {
  const docs=new Map();
  let reads=0,writes=0;
  const put=(k,v)=>docs.set(k,structuredClone(v));
  const db={
    doc:(key)=>({get:async()=>{
      reads++;
      const value=docs.get(key);
      return {exists:value!==undefined,data:()=>structuredClone(value)};
    }}),
    get reads(){return reads;},
    get writes(){return writes;},
    put,
  };
  put("deda_share_ids/"+O,{
    publicId:O,kind:"personal",active:true,ownerUid:"verifiedUser"
  });
  if(!options.noPremium){
    put("deda_stage71_active_identifier/"+O,{
      originalId:O,activeId:A
    });
    put("deda_stage71_granted_registry/"+A,{
      identifier:A,recipientOriginalId:O,kind:"gifted",
      group:"001",baseColor:"gold"
    });
    put("deda_stage74_id_gift_receipts/"+A,{
      identifier:A,originalId:O,group:"001",
      receivedAt:"2026-10-21T09:00:00Z"
    });
  }
  return db;
}
test("approved active alias is visible to recipient and resolves same original for GM diamond gifts",async()=>{
  const db=database();
  assert.deepEqual(await readVerifiedPublicAlias(db,O,"authorizedViewer"),{
    requestedId:O,displayId:A,permanentColor:"gold",serverConfirmed:true});
  assert.deepEqual(await resolveVerifiedGiftRecipientOriginal(db,A,"gmUid"),{
    requestedId:A,originalId:O,serverConfirmed:true});
  assert.deepEqual(await resolveVerifiedGiftRecipientOriginal(db,O,"gmUid"),{
    requestedId:O,originalId:O,serverConfirmed:true});
  assert.equal(db.writes,0);
});
test("original recipient lookup works without premium ID and does not fabricate alias",async()=>{
  const db=database({noPremium:true});
  assert.deepEqual(await resolveVerifiedGiftRecipientOriginal(db,O,"gmUid"),{
    requestedId:O,originalId:O,serverConfirmed:true});
  assert.equal(await resolveVerifiedGiftRecipientOriginal(db,A,"gmUid"),null);
  assert.equal((await readVerifiedPublicAlias(db,O,"viewer")).serverConfirmed,false);
});
test("recipient alias lookup refuses missing auth or bad IDs",async()=>{
  const db=database();
  for(const id of [A,O]){
    await assert.rejects(resolveVerifiedGiftRecipientOriginal(db,id,""),
      /AUTH_REQUIRED/);
  }
  for(const id of ["DEDA-IRAQI","@DEDA-iraqi","@DEDA-AB","@DEDA-AAAA AAAA"]){
    await assert.rejects(resolveVerifiedGiftRecipientOriginal(db,id,"gm"),
      /ID_INVALID/);
  }
});
test("another gift ledger owner, color, group or missing receipt fail closed",async()=>{
  const mutations=[
    db=>db.put("deda_stage71_granted_registry/"+A,
      {identifier:A,recipientOriginalId:"@DEDA-BB3344",kind:"gifted",group:"001",baseColor:"gold"}),
    db=>db.put("deda_stage71_granted_registry/"+A,
      {identifier:A,recipientOriginalId:O,kind:"gifted",group:"001",baseColor:"purple"}),
    db=>db.put("deda_stage71_granted_registry/"+A,
      {identifier:A,recipientOriginalId:O,kind:"gifted",group:"003",baseColor:"gold"}),
    db=>db.put("deda_stage74_id_gift_receipts/"+A,
      {identifier:A,originalId:"@DEDA-BB3344",group:"001",receivedAt:"today"}),
    db=>db.put("deda_stage74_id_gift_receipts/"+A,
      {identifier:A,originalId:O,group:"001",receivedAt:null}),
    db=>db.put("deda_stage71_active_identifier/"+O,
      {originalId:O,activeId:X}),
  ];
  for(let i=0;i<mutations.length;i++){
    const db=database();mutations[i](db);
    const result=await resolveVerifiedGiftRecipientOriginal(db,A,"gm")
      .then(v=>v,e=>e);
    assert.ok(result===null||result instanceof Error,
      "forged recipient was accepted "+i);
    assert.equal(db.writes,0);
  }
});
test("self-used GM identifier needs proof of owner grant, not receipt",async()=>{
  const db=database();
  db.put("deda_stage71_granted_registry/"+A,{
    identifier:A,recipientOriginalId:O,kind:"self_used",
    group:"002",baseColor:"royal"});
  db.put("deda_stage74_id_gift_receipts/"+A,{}); // not needed for self-used
  assert.deepEqual(await resolveVerifiedGiftRecipientOriginal(db,A,"gm"),{
    requestedId:A,originalId:O,serverConfirmed:true});
  assert.equal((await readVerifiedPublicAlias(db,O,"viewer")).permanentColor,"royal");
});
test("unknown premium cannot be used to transfer to arbitrary destination",async()=>{
  const db=database();
  assert.equal(await resolveVerifiedGiftRecipientOriginal(db,X,"gm"),null);
  assert.equal(db.writes,0);
});
