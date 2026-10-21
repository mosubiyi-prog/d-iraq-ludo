"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {inspectContinuity}=require("../deda_qa32_account_continuity_policy_NOT_EXPORTED.js");
const proof=Object.freeze({
  authUid:"server-authenticated-uid",
  userUid:"server-authenticated-uid",
  sessionUid:"server-authenticated-uid",
  userAccountKey:"stable-account-key",
  sessionAccountKey:"stable-account-key",
  publishedOwnerAccountKey:"stable-account-key",
  originalId:"@DEDA-ABC123",
  sessionOriginalId:"@DEDA-ABC123",
  verifiedPhoneByAdmin:true,
});
const server=Object.freeze({
  accountKey:"stable-account-key",originalId:"@DEDA-ABC123",
  ledgerRevision:17,xp:240,taskPoints:975645,coins:200,diamonds:998960,
});
test("new phone with all local zero balances CANNOT reset saved server data",()=>{
 const result=inspectContinuity(proof,server,
   {xp:0,taskPoints:0,coins:0,diamonds:0});
 assert.equal(result.status,"display-verified-server");
 assert.equal(result.allowWrite,false);
 assert.equal(result.xp,240);
 assert.equal(result.diamonds,998960);
 assert.equal(result.taskPoints,975645);
});
test("local device with bigger stale balance cannot auto merge or double count",()=>{
 const result=inspectContinuity(proof,server,
   {xp:99999,taskPoints:999999,coins:50000,diamonds:1000000});
 assert.equal(result.xp,240);
 assert.equal(result.diamonds,998960);
 assert.equal(result.allowWrite,false);
});
test("changed unauthenticated UID or account key blocks all account display",()=>{
 const badUid={...proof,sessionUid:"new-device-anonymous-uid"};
 const badKey={...proof,sessionAccountKey:"different-account"};
 for(const p of [badUid,badKey]){
  assert.deepEqual(inspectContinuity(p,server,{}),
   {status:"blocked-identity",allowWrite:false});
 }
});
test("unverified phone does not establish rights to the former account",()=>{
 assert.equal(inspectContinuity({...proof,verifiedPhoneByAdmin:false},
   server,{}).status,"blocked-identity");
});
test("absent server snapshot must request recovery, not overwrite with defaults",()=>{
 assert.deepEqual(inspectContinuity(proof,null,{diamonds:0}),
  {status:"needs-verified-recovery",allowWrite:false});
});
test("corrupt/negative server amount blocks instead of displaying or spending",()=>{
 for(const item of [{...server,diamonds:-1},{...server,xp:NaN},
   {...server,ledgerRevision:-1},{...server,accountKey:"other"},
   {...server,originalId:"@DEDA-DEF456"}]){
  assert.deepEqual(inspectContinuity(proof,item,{}),
   {status:"blocked-server-record",allowWrite:false});
 }
});
test("restored data has no phone number, raw user UID or full account secret",()=>{
 const result=inspectContinuity(proof,server,{});
 assert.equal("authUid" in result,false);
 assert.equal("phoneNumber" in result,false);
 assert.equal("sessionAccountKey" in result,false);
 assert.equal(Object.isFrozen(result),true);
});

test("regular user without published place still keeps verified account data",()=>{
 const regular={...proof,publishedOwnerAccountKey:null,hasPublishedPlace:false};
 const restored=inspectContinuity(regular,server,{diamonds:0});
 assert.equal(restored.status,"display-verified-server");
 assert.equal(restored.diamonds,998960);
 assert.equal(restored.allowWrite,false);
});
test("published place owner cannot omit or forge their verified venue account key",()=>{
 for(const bad of [
   {...proof,hasPublishedPlace:true,publishedOwnerAccountKey:null},
   {...proof,hasPublishedPlace:true,publishedOwnerAccountKey:"other"},
 ]){
   assert.equal(inspectContinuity(bad,server,{}).status,"blocked-identity");
 }
});
