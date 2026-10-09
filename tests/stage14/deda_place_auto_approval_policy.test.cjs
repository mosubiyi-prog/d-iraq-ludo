const {test} = require("node:test");
const assert = require("node:assert/strict");
const {assess} = require("../../functions/deda_place_auto_approval_policy.js");
const now=Date.UTC(2026,9,10,1,0,0);
const ts=(x)=>({toMillis:()=>x});
const request={
  status:"pending",requestType:"create",createdAt:ts(now-40000),
  placeName:"صيدلية الرافدين",phone:"07701234567",governorate:"بغداد",
  address:"شارع ١٢",openingHours:"8-22",description:"صيدلية عمومية",
  category:"pharmacy",accountKey:"9647701234567",ownerUid:"owner-1",
  latitude:33.312,longitude:44.36,
};
const cfg={enabled:true,enabledAt:ts(now-120000)};
const input=(updates={})=>({
  request,settings:cfg,exactTrustedOwner:true,serverNowMs:now,...updates
});
test("new request from authenticated owner automatically eligible after 30 seconds",()=>{
  assert.deepEqual(assess(input()),{eligible:true,reason:"ready-for-auto-publication"});
});
test("no employee review or duplicate/moderation screening when toggle ON",()=>{
  assert.equal(assess(input({request:{
    ...request, reportedAsDuplicate:true, suspicious:true,
  }})).eligible,true);
});
test("old pending before toggle never auto-approves",()=>{
  assert.equal(assess(input({request:{...request,createdAt:ts(now-150000)}})).eligible,false);
  assert.equal(assess(input({request:{...request,createdAt:ts(now-120000)}})).eligible,false);
});
test("not until at least 30 seconds of server time",()=>{
  assert.equal(assess(input({request:{...request,createdAt:ts(now-29999)}})).eligible,false);
  assert.equal(assess(input({request:{...request,createdAt:ts(now-30000)}})).eligible,true);
});
test("OFF, unverified owner, edits and wrong status stay manual",()=>{
  for(const x of [
    {settings:{...cfg,enabled:false}}, {settings:null},
    {exactTrustedOwner:false},
    {request:{...request,requestType:"update"}},
    {request:{...request,status:"reviewing"}},
  ]) assert.equal(assess(input(x)).eligible,false);
});
test("fields and location integrity still mandatory",()=>{
  for(const change of [
    {description:" "},{phone:null},{otherCategoryText:null,category:"other"},
    {latitude:0},{longitude:180},
  ])assert.equal(assess(input({request:{...request,...change}})).eligible,false);
});
