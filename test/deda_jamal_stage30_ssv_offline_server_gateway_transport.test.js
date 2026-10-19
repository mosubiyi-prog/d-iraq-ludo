"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const http=require("node:http");
const {generateKeyPairSync,sign}=require("node:crypto");
const {readFileSync}=require("node:fs");
const {resolve}=require("node:path");
const {
  createOfflineSsvHttpReceiver,buildStagedSsvFirebaseDefinitions,
  rawCallbackQuery,
}=require("../tools/deda_jamal_stage30_ssv_offline_server_gateway_not_exported_2026_10_19.js");
const {CONSOLE_SNAPSHOT}=require(
  "../tools/deda_jamal_stage29_console_reward_contract_vs_diamond_gate_2026_10_19.js");
const pair=generateKeyPairSync("ec",{namedCurve:"prime256v1"});
const alien=generateKeyPairSync("ec",{namedCurve:"prime256v1"});
const keys={"812":pair.publicKey.export({type:"spki",format:"pem"}).toString()};
const PATH="/deda-stage30-ssv-offline";
const oldHost=process.env.FIRESTORE_EMULATOR_HOST;
const oldProject=process.env.GCLOUD_PROJECT;
test.before(()=>{
  process.env.FIRESTORE_EMULATOR_HOST="127.0.0.1:8080";
  process.env.GCLOUD_PROJECT="demo-deda-stage22-ssv-fakeprovider";
});
test.after(()=>{
  if(oldHost===undefined)delete process.env.FIRESTORE_EMULATOR_HOST;
  else process.env.FIRESTORE_EMULATOR_HOST=oldHost;
  if(oldProject===undefined)delete process.env.GCLOUD_PROJECT;
  else process.env.GCLOUD_PROJECT=oldProject;
});
function q({rewardItem="diamonds",rewardAmount=1,
  adUnit=CONSOLE_SNAPSHOT.adUnitId,signingKey=pair.privateKey}={}){
  const m=["ad_unit="+encodeURIComponent(adUnit),
    "custom_data="+"Z".repeat(32),"reward_amount="+rewardAmount,
    "reward_item="+encodeURIComponent(rewardItem),
    "timestamp=1792416900000","transaction_id=stage30_fake_tx_000001"].join("&");
  return m+"&signature="+sign("sha256",Buffer.from(m),signingKey)
    .toString("base64url")+"&key_id=812";
}
function fakeResponse(){
  const res={statusCode:200,body:"",headers:{},ended:false};
  res.setHeader=(k,v)=>{res.headers[k.toLowerCase()]=v;};
  res.end=(v="")=>{res.ended=true;res.body=v;};
  return res;
}
function call({url=PATH+"?"+q(),method="GET",keyMap=keys}={}){
  const res=fakeResponse();
  createOfflineSsvHttpReceiver({testPinnedPublicKeys:keyMap})({
    method,originalUrl:url,query:{signature:"spoofed-decoded"},
  },res);
  assert.equal(res.ended,true);
  const response=JSON.parse(res.body);
  assert.equal(response.ok,false);
  assert.equal(response.creditedDiamonds,0);
  assert.equal(response.creditedPoints,0);
  assert.equal(response.productionVerification,false);
  assert.equal(res.headers["cache-control"],"no-store, no-cache, max-age=0");
  return {status:res.statusCode,response,body:res.body};
}
test("01 fake P256 provider still cannot earn 3 diamonds or 200 OK",()=>{
  const r=call();
  assert.equal(r.status,409);
  assert.equal(r.response.code,"OFFLINE_SIGNATURE_IS_NOT_GOOGLE_SSV");
});
test("02 owner screenshot 5 DEDA Points callback cannot become 3 diamonds",()=>{
  const r=call({url:PATH+"?"+q({
    rewardItem:"DEDA Points",rewardAmount:5,
  })});
  assert.equal(r.status,422);
});
test("03 real Firebase project blocks callback before crypto",()=>{
  const old=process.env.GCLOUD_PROJECT;
  process.env.GCLOUD_PROJECT="actual-firebase-is-blocked";
  try{assert.equal(call().status,503);}
  finally{process.env.GCLOUD_PROJECT=old;}
});
test("04 no emulator host blocks callback",()=>{
  const old=process.env.FIRESTORE_EMULATOR_HOST;
  delete process.env.FIRESTORE_EMULATOR_HOST;
  try{assert.equal(call().status,503);}
  finally{process.env.FIRESTORE_EMULATOR_HOST=old;}
});
test("05 forged EC private key denied",()=>{
  assert.equal(call({url:PATH+"?"+q({
    signingKey:alien.privateKey,
  })}).status,422);
});
test("06 wrong ad unit signed cannot make payout",()=>{
  assert.equal(call({url:PATH+"?"+q({
    adUnit:"ca-app-pub-2512641627784244/0000000000",
  })}).status,409);
});
test("07 POST rejected",()=>{assert.equal(call({method:"POST"}).status,405);});
test("08 PUT rejected",()=>{assert.equal(call({method:"PUT"}).status,405);});
test("09 missing query refused",()=>{assert.equal(call({url:PATH+"?"}).status,400);});
test("10 alternate callback path refused",()=>{
  assert.equal(call({url:"/my-real-production-endpoint?"+q()}).status,400);
});
test("11 CRLF, fragment, backslash refused",()=>{
  for(const extra of ["\n","\r","#fragment","\\spoof"])
    assert.equal(call({url:PATH+"?"+q()+extra}).status,400);
});
test("12 altered signature amount rejected",()=>{
  assert.equal(call({url:PATH+"?"+q().replace(
    "reward_amount=1","reward_amount=100")}).status,422);
});
test("13 duplicate reward field refused",()=>{
  assert.equal(call({url:PATH+"?"+q().replace(
    "reward_amount=1","reward_amount=1&reward_amount=200")}).status,422);
});
test("14 overly long URL rejected before signature",()=>{
  assert.equal(call({url:PATH+"?"+("A".repeat(6000))}).status,413);
});
test("15 empty trusted pinned keys refuse request",()=>{
  assert.equal(call({keyMap:{}}).status,503);
});
test("16 signed raw URL is required, decoded req.query ignored",()=>{
  assert.equal(rawCallbackQuery({
    originalUrl:PATH+"?reward_item=DEDA%20Points&signature=AA&key_id=1",
  }).raw,"reward_item=DEDA%20Points&signature=AA&key_id=1");
  assert.equal(rawCallbackQuery({query:{reward_amount:100}}).raw,undefined);
});
test("17 no nonce/signature/accountKey/UID echoed in response",()=>{
  const r=call({url:PATH+"?"+q({signingKey:alien.privateKey})});
  for(const s of ["Z".repeat(32),"signature=","transaction_id=",
    "accountKey","ownerUid","ca-app-pub-2512641627784244"])
    assert.equal(r.body.includes(s),false);
});
test("18 factory enforces AppCheck and keeps challenge unavailable",async()=>{
  let optsCall,optsRequest;
  class FakeHttpsError extends Error{
    constructor(code,message){super(message);this.code=code;}
  }
  const factory=buildStagedSsvFirebaseDefinitions({
    onCall:(opts,handle)=>{optsCall=opts;return handle;},
    onRequest:(opts,handle)=>{optsRequest=opts;return handle;},
    HttpsError:FakeHttpsError,testPinnedPublicKeys:keys,
  });
  assert.equal(optsCall.enforceAppCheck,true);
  assert.equal(optsRequest.cors,false);
  assert.equal(factory.deployable,false);
  assert.equal(factory.exportedToProduction,false);
  await assert.rejects(factory.issueDemoChallenge({
    auth:{uid:"test"},app:{appId:"x"},
  }),e=>e.code==="unavailable");
});
test("19 exact standalone Stage30 module is never exported in Firebase",()=>{
  const src=readFileSync(resolve(__dirname,"../functions/index.js"),"utf8");
  assert.equal(src.includes("deda_jamal_stage30_ssv_offline_server_gateway"),
    false);
});
test("20 module never imports wallet or Firebase admin and never modifies users",()=>{
  const src=readFileSync(resolve(__dirname,
    "../tools/deda_jamal_stage30_ssv_offline_server_gateway_not_exported_2026_10_19.js"),"utf8");
  for(const expression of ["db.runTransaction(",'require("firebase-admin',
    'require("firebase-functions','collection("deda_diamond_gift_balances")',
    "DedaDiamondsWallet.claimReward()"])
    assert.equal(src.includes(expression),false);
});
test("21 real LOCAL HTTP server denies a fake Google 5-points callback",async()=>{
  const handle=createOfflineSsvHttpReceiver({testPinnedPublicKeys:keys});
  const server=http.createServer((req,res)=>{
    req.originalUrl=req.url;
    handle(req,res);
  });
  await new Promise((resolveListen,rejectListen)=>{
    server.once("error",rejectListen);
    server.listen(0,"127.0.0.1",resolveListen);
  });
  try {
    const addr=server.address();
    const url="http://127.0.0.1:"+addr.port+PATH+"?"+
      q({rewardItem:"DEDA Points",rewardAmount:5});
    const result=await new Promise((resolveResult,rejectResult)=>{
      http.get(url,{timeout:5000},response=>{
        let body="";
        response.on("data",x=>body+=x);
        response.on("end",()=>resolveResult({
          code:response.statusCode,body,
        }));
      }).on("error",rejectResult);
    });
    assert.equal(result.code,422);
    assert.equal(JSON.parse(result.body).creditedDiamonds,0);
    assert.equal(JSON.parse(result.body).creditedPoints,0);
  } finally {
    await new Promise(resolveClose=>server.close(resolveClose));
  }
});
