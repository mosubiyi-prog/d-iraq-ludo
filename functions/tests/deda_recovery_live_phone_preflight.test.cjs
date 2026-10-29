"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {verifiedIraqiPhone,createRecoveryPhonePreflight:create}=
 require("../deda_recovery_live_phone_preflight.js");
const PHONE="+9647701234567",UID="firebase_phone_verified_uid_001";
class HttpsError extends Error{constructor(code,message){super(message);this.code=code;}}
function fixture({directories={"07701234567":true},phone=PHONE,disabled=false}={}){
 const reads=[],writes=[];
 const auth={
   async verifyIdToken(token,checkRevoked){
     assert.equal(checkRevoked,true);assert.equal(token,"synthetic_long_phone_auth_token_123");
     return {uid:UID,phone_number:phone};
   },
   async getUser(uid){
     assert.equal(uid,UID);
     return {uid,phoneNumber:phone,disabled};
   },
 };
 const db={doc(path){
   reads.push(path);
   return {get:async()=>({
     exists:directories[path.replace("deda_account_directory/","")]===true,
     data:()=>({
       active:true,accountKey:path.replace("deda_account_directory/",""),
     }),
   }),set:()=>writes.push(path),update:()=>writes.push(path),delete:()=>writes.push(path)};
 }};
 let options;
 const call=create({onCall:(o,handler)=>{options=o;return handler;},
   HttpsError,auth,db});
 const request={auth:{uid:UID},app:{appId:"verified-app-check"},
   data:{},rawRequest:{headers:{authorization:"Bearer synthetic_long_phone_auth_token_123"}}};
 return {call,request,reads,writes,options,auth,db};
}
test("Iraqi E.164 independently yields only two possible original account keys",()=>{
 assert.deepEqual(verifiedIraqiPhone(PHONE),{
   local:"07701234567",international:"9647701234567"});
 for(const bad of ["07701234567","+123456789123","+9646601234567",
    "+964770123456","+96477012345678",null,{},[]])
   assert.equal(verifiedIraqiPhone(bad),null);
});
test("verified phone and enforced AppCheck lookup existing account without grant",async()=>{
 const f=fixture();
 assert.equal(f.options.enforceAppCheck,true);
 const result=await f.call(f.request);
 assert.deepEqual(result,{
   format:1,verifiedPhone:true,appCheckVerified:true,
   accountState:"candidate-found",
   canTransferAccount:false,canWriteWallet:false,
   canGrantAssets:false,canChangePin:false,canIssueLeagueRewards:false});
 assert.deepEqual(f.reads,[
   "deda_account_directory/07701234567",
   "deda_account_directory/9647701234567",
 ]);
 assert.deepEqual(f.writes,[]);
 assert.equal(JSON.stringify(result).includes(PHONE),false);
 assert.equal(JSON.stringify(result).includes(UID),false);
});
test("no original account is hold-only, not a new account creation",async()=>{
 const f=fixture({directories:{}});
 const r=await f.call(f.request);
 assert.equal(r.accountState,"no-active-directory");
 assert.equal(r.canTransferAccount,false);
 assert.deepEqual(f.writes,[]);
});
test("two registered directory formats require manual review, never guess",async()=>{
 const f=fixture({directories:{"07701234567":true,"9647701234567":true}});
 const r=await f.call(f.request);
 assert.equal(r.accountState,"requires-owner-review");
 assert.deepEqual(f.writes,[]);
});
test("unsigned, no AppCheck, disabled account, forged identity and payload are rejected",async()=>{
 const f=fixture();
 const bad=[
   {...f.request,app:null},
   {...f.request,auth:{uid:"different_user"}},
   {...f.request,data:{accountKey:"07701234567"}},
   {...f.request,rawRequest:{headers:{authorization:"Basic bad"}}},
   {...f.request,data:{diamonds:1000000}},
 ];
 for(const q of bad)await assert.rejects(f.call(q),
   e=>e.code==="permission-denied");
 const g=fixture({disabled:true});
 await assert.rejects(g.call(g.request),e=>e.code==="permission-denied");
 assert.deepEqual(f.writes,[]);
});
test("non-phone Firebase Auth user fails closed",async()=>{
 const f=fixture({phone:null});
 await assert.rejects(f.call(f.request),e=>e.code==="permission-denied");
 assert.deepEqual(f.writes,[]);
});
