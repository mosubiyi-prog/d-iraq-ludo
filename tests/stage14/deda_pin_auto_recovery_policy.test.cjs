const {test}=require("node:test");
const assert=require("node:assert/strict");
const {decide}=require("../../functions/deda_pin_auto_recovery_policy.js");
const ts=(v)=>({toMillis:()=>v});
const now=Date.UTC(2026,9,10,1,0,0);
const req={
  requestId:"request-1",status:"new",type:"forgot_pin",
  requesterUid:"owner-1",requesterInstallId:"installation-abc",
  accountKey:"9647700000000",riskLevel:"low",
  accountFound:true,sameDevice:true,nameMatches:true,
  createdAt:ts(now-10001),
};
const setting={enabled:true,enabledAt:ts(now-120000)};
const proof={valid:true,uid:req.requesterUid,accountKey:req.accountKey,
  revoked:false,kind:"verified-credential-proof"};
const input=(patch={})=>({
  request:req,setting,ready:true,serverNow:ts(now),
  serverProof:proof,attemptCountLastHour:1,
  latestRequestId:req.requestId,...patch,
});
test("strict new verified proof after ten seconds can be ELIGIBLE, never issues PIN",()=>{
  const result=decide(input());
  assert.equal(result.eligible,true);
  assert.equal(result.outcome,"eligible-for-server-only-issuance");
  assert.equal("pin" in result,false);
});
test("off/manual, old pre-toggle requests and first 10 seconds blocked",()=>{
  for (const part of [
    {ready:false},{setting:{enabled:false,enabledAt:ts(now-120000)}},
    {request:{...req,createdAt:ts(now-130000)}},
    {request:{...req,createdAt:ts(now-9999)}},
    {request:{...req,status:"review"}},
  ])assert.equal(decide(input(part)).eligible,false);
});
test("client name + phone + trusted install ID is NOT strong proof",()=>{
  for(const serverProof of [
    undefined, null, {valid:false,...proof},
    {...proof,uid:"attacker"}, {...proof,kind:"client-install-id"},
    {...proof,revoked:true},
  ])assert.equal(decide(input({serverProof})).eligible,false);
});
test("rate limit, replay and duplicate requests remain manual",()=>{
  for(const p of [
    {attemptCountLastHour:2}, {attemptCountLastHour:0},
    {latestRequestId:"older-request"}, {request:{...req,riskLevel:"review"}},
    {request:{...req,accountFound:false}}, {request:{...req,nameMatches:false}},
    {request:{...req,type:"admin",status:"new"}},
  ])assert.equal(decide(input(p)).eligible,false);
});
