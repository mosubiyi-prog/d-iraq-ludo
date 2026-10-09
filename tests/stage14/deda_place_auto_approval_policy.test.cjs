const {test} = require("node:test");
const assert = require("node:assert/strict");
const {assess} = require("../../functions/deda_place_auto_approval_policy.js");
const now=Date.UTC(2026,9,10,1,0,0);
const ts=(x)=>({toMillis:()=>x});
const request={
  status:"pending",requestType:"create",createdAt:ts(now-2500),
  placeName:"صيدلية الرافدين",phone:"07701234567",governorate:"بغداد",
  address:"شارع ١٢",openingHours:"8-22",description:"صيدلية عمومية",
  category:"pharmacy",accountKey:"9647701234567",ownerUid:"owner-1",
  latitude:33.312,longitude:44.36,
};
const cfg={enabled:true,enabledAt:ts(now-6000)};
const input=(updates={})=>({
  request,settings:cfg,publishedInProvince:[],
  provinceScanComplete:true,exactTrustedOwner:true,serverNowMs:now,...updates
});
test("new valid verified owner approved when mode on and bounded duplicate scan complete",()=>{
  assert.deepEqual(assess(input()),{eligible:true,reason:"passed-conservative-review"});
});
test("never approve requests present BEFORE toggle",()=>{
  assert.equal(assess(input({request:{...request,createdAt:ts(now-15000)}})).eligible,false);
  assert.equal(assess(input({request:{...request,createdAt:ts(now-6000)}})).eligible,false);
});
test("toggle off / absent, unverified owner, edits all manual",()=>{
  for(const p of [
    {settings:{...cfg,enabled:false}},
    {settings:null},
    {exactTrustedOwner:false},
    {request:{...request,requestType:"update"}},
    {request:{...request,status:"reviewing"}},
  ])assert.equal(assess(input(p)).eligible,false);
});
test("incomplete, forged, bad geographical location blocked",()=>{
  for(const change of [
    {description:" "},{phone:null},{otherCategoryText:null,category:"other"},
    {latitude:0},{longitude:180},{suspicious:true},{reportedAsDuplicate:true},
  ])assert.equal(assess(input({request:{...request,...change}})).eligible,false);
});
test("duplicate same name nearby and same owner are manual",()=>{
  for(const old of [
    {...request,published:true,latitude:33.313,longitude:44.36},
    {...request,published:true,accountKey:request.accountKey,latitude:33.8},
    {...request,published:true,latitude:null,longitude:null},
  ])assert.equal(assess(input({publishedInProvince:[old]})).eligible,false);
});
test("unreliable or truncated province scan never auto approves",()=>{
  assert.equal(assess(input({provinceScanComplete:false})).eligible,false);
  assert.equal(assess(input({publishedInProvince:null})).eligible,false);
});
