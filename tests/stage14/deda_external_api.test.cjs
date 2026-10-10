"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const http=require("node:http");
const {createDedaExternalApi,secretEqual}=
  require("../../functions/deda_external_api.js");
const KEY="A".repeat(48),TOKEN="B".repeat(64);
async function serve(overrides,run){
  const calls=[];
  const d={
    webhookSecret:KEY,
    verifyUser:async t=>{calls.push("verify");return t===TOKEN?"verifiedUid":"";},
    requireManager:async uid=>{calls.push("manager");return uid==="verifiedUid"
      ? {uid,role:"general_manager",active:true}:null;},
    begin:async uid=>{calls.push("begin");return {outcome:"started",uid};},
    claim:async uid=>{calls.push("claim");return {outcome:"not-eligible",uid};},
    botStart:async()=>{calls.push("botStart");return {outcome:"linked"};},
    onBotLinked:async()=>{calls.push("botReply");},
    telegramReady:async()=>{calls.push("botReady");return false;},
    manage:async(actor,op)=>{calls.push("manage");return {outcome:"deactivated",op};},
    ...overrides,
  };
  const server=http.createServer(createDedaExternalApi(d));
  await new Promise(r=>server.listen(0,"127.0.0.1",r));
  const url="http://127.0.0.1:"+server.address().port;
  const call=async(path,{auth=false,secret="",body={},method="POST"}={})=>{
    const r=await fetch(url+path,{
      method,headers:{"Content-Type":"application/json",
        ...(auth?{Authorization:"Bearer "+TOKEN}:{}),
        ...(secret?{"X-Telegram-Bot-Api-Secret-Token":secret}:{})},
      ...(method==="POST"?{body:JSON.stringify(body)}:{}),
    });
    return {status:r.status,data:await r.json()};
  };
  try{await run(call,calls);}finally{
    await new Promise(r=>server.close(r));
  }
}
test("health is public but privileged endpoint GET rejected",async()=>{
  await serve({},async call=>{
    assert.equal((await call("/health",{method:"GET"})).status,200);
    assert.equal((await call("/v1/telegram/claim",{method:"GET"})).status,405);
    assert.equal((await call("/unknown")).status,404);
  });
});
test("Firebase bearer required, request body cannot spoof UID",async()=>{
  await serve({},async(call,calls)=>{
    assert.equal((await call("/v1/telegram/claim",{body:{uid:"victim"}})).status,401);
    assert.deepEqual(calls,[]);
    const r=await call("/v1/telegram/start",{auth:true,body:{uid:"victim"}});
    assert.equal(r.status,200);
    assert.equal(r.data.result.uid,"verifiedUid");
    assert.deepEqual(calls,["verify","begin"]);
  });
});
test("webhook secret required BEFORE accepting messages",async()=>{
  await serve({},async(call,calls)=>{
    assert.equal((await call("/telegram/webhook")).status,403);
    assert.equal((await call("/telegram/webhook",{secret:"wrong"})).status,403);
    assert.deepEqual(calls,[]);
    const x=await call("/telegram/webhook",{secret:KEY,body:{message:{text:"/start"}}});
    assert.equal(x.status,200);
    assert.deepEqual(calls,["botStart","botReply"]);
  });
});
test("cannot switch ON without verified channel admin AND exact webhook",async()=>{
  await serve({},async(call,calls)=>{
    const blocked=await call("/v1/telegram/manage",{auth:true,body:{op:"enable"}});
    assert.equal(blocked.status,409);
    assert.equal(calls.includes("manage"),false);
    const off=await call("/v1/telegram/manage",{auth:true,body:{op:"disable"}});
    assert.equal(off.status,200);
    assert.equal(off.data.result.op,"disable");
    assert.equal((await call("/v1/telegram/manage",{auth:true,
      body:{op:"enable",uid:"forged"}})).status,400);
  });
});
test("backend MUST NOT advertise undeployed PIN/place automations",async()=>{
  await serve({},async call=>{
    assert.equal((await call("/v1/automation/readiness")).status,401);
    assert.equal((await call("/v1/automation/readiness",{auth:true})).data.result.ready,false);
  });
});
test("non-manager blocked from payout and automation operations",async()=>{
  await serve({requireManager:async()=>null},async call=>{
    assert.equal((await call("/v1/telegram/manage",{auth:true,body:{op:"enable"}})).status,403);
    assert.equal((await call("/v1/automation/readiness",{auth:true})).status,403);
  });
});
test("constant-time webhook equality defaults to deny",()=>{
  assert.equal(secretEqual(KEY,KEY),true);
  assert.equal(secretEqual("",""),false);
  assert.equal(secretEqual(KEY,"A".repeat(47)),false);
});
