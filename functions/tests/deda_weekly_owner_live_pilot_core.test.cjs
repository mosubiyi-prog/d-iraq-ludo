"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const {createHash}=require("node:crypto");
const {claim,standings,weekAt,baghdadDay}=
 require("../../functions/deda_weekly_owner_live_pilot_core");
const START=Date.UTC(2026,9,30,3),NOW=START+2*86400000;
const A="07701234567",B="07701234568",UID="anonymousUser111";
const SEED="Deda100396PrivateQATestReadKey-MustNotUseInProduction";
class Db {
 constructor(){this.docs=new Map();this.writes=[];}
 doc(path){return {path,get:async()=>({
  exists:this.docs.has(path),data:()=>this.docs.get(path)})};}
 collection(path){return {get:async()=>{const docs=[...this.docs]
  .filter(([p])=>p.startsWith(path+"/") &&
   !p.slice(path.length+1).includes("/"))
  .map(([p,v])=>({id:p.slice(path.length+1),data:()=>v}));
  return {size:docs.length,docs};}};}
 seed(p,d){this.docs.set(p,structuredClone(d));}
 async runTransaction(fn){
  const ops=[];const tx={
   get:async ref=>({exists:this.docs.has(ref.path),
    data:()=>this.docs.get(ref.path)}),
   create:(ref,value)=>ops.push({path:ref.path,value,create:true}),
   set:(ref,value)=>ops.push({path:ref.path,value,create:false}),
  };
  const result=await fn(tx);
  for(const op of ops)if(op.create&&this.docs.has(op.path))
   throw Error("conflict");
  for(const op of ops){this.docs.set(op.path,structuredClone(op.value));
   this.writes.push(op.path);}
  return result;
 }
}
function fixture(){
 const db=new Db(),auth={getUser:async uid=>({
  uid,disabled:false,email:null,providerData:[],
 })};
 for(const [key,uid,name,pub] of [[A,UID,"لاعب تجريبي","@DEDA-AB1234"],
   [B,"anonymousUser222","منافس تجريبي","@DEDA-AB1235"]]){
  db.seed("deda_account_directory/"+key,{
   accountKey:key,active:true,createdUid:uid});
  db.seed("deda_account_profiles/"+key,{accountKey:key,name});
  db.seed("users/"+uid,{accountKey:key,sharePersonalId:pub});
 }
 db.seed("deda_weekly_owner_pilot_config/active",{
  ownerQaEnabled:true,grantDiamonds:false,
  allowClientTaskReports:true,
  allowedAccounts:[A,B].map(v=>createHash("sha256").update(v).digest("hex")),
 });
 return {db,auth};
}
const req=(key=A,uid=UID,taskId="open_map")=>({
 auth:{uid,token:{firebase:{sign_in_provider:"anonymous"}}},
 app:{appId:"emulator-AppCheck-context-not-attested"},
 data:{accountKey:key,taskId},
});
const get=(key=A,uid=UID)=>({...req(key,uid),
 data:{accountKey:key}});
const take=(f,r=req(),nowMs=NOW)=>
 claim({...f,request:r,nowMs});
const read=(f,r=get(),nowMs=NOW)=>
 standings({...f,request:r,nowMs,secret:SEED});
test("1: 100396 original task adds 20 to real server shared week once",async()=>{
 const f=fixture();f.db.seed("users/"+UID+"/wallet/original",
  {diamonds:90,frames:["paid"]});
 const first=await take(f);assert.equal(first.status,"COUNTED_OWNER_QA");
 assert.equal(first.weeklyXp,20);assert.equal(first.counted,true);
 const repeat=await take(f);assert.equal(repeat.status,"ALREADY_RECORDED");
 assert.equal(repeat.weeklyXp,20);
 assert.equal(f.db.writes.length,2);
 assert.deepEqual(f.db.docs.get("users/"+UID+"/wallet/original"),
  {diamonds:90,frames:["paid"]});
});
test("2: two verified accounts show real server first and second ranks",async()=>{
 const f=fixture();
 await take(f);
 await take(f,req(A,UID,"open_saved_place"));
 await take(f,req(B,"anonymousUser222"));
 const x=await read(f);assert.deepEqual(
  x.current.rows.map(y=>y.weeklyPoints),[40,20]);
 assert.deepEqual(x.current.rows.map(y=>y.place),[1,2]);
 assert.equal(x.current.rows[0].displayName,"لاعب تجريبي");
 assert.equal(x.current.rows[1].displayName,"منافس تجريبي");
 assert.equal(x.current.viewerPlace,1);
 assert.equal(x.current.rewardsCredited,false);
 assert.equal(JSON.stringify(x).includes(A),false);
 assert.equal(JSON.stringify(x).includes(UID),false);
});
test("3: no owner allowlist means no writes or public scoring",async()=>{
 const f=fixture();f.db.docs.delete("deda_weekly_owner_pilot_config/active");
 await assert.rejects(take(f),/DEDA_WEEKLY_OWNER_QA_DISABLED/);
 await assert.rejects(read(f),/DEDA_WEEKLY_OWNER_QA_DISABLED/);
 assert.equal(f.db.writes.length,0);
});
test("4: no extra client-supplied score or diamonds accepted",async()=>{
 const f=fixture();const r=req();r.data.weeklyXp=999;
 await assert.rejects(take(f,r),/DEDA_WEEKLY_AUTH_REQUIRED/);
 assert.equal(f.db.writes.length,0);
});
test("5: different UID and account key cannot borrow another score",async()=>{
 const f=fixture();
 await assert.rejects(take(f,req(A,"anonymousUser222")),
  /DEDA_WEEKLY_ACCOUNT_UNVERIFIED/);
});
test("6: bad task name, absent AppCheck and authenticated user forbidden",async()=>{
 const f=fixture();
 await assert.rejects(take(f,req(A,UID,"admin_bonus")),
  /DEDA_WEEKLY_BAD_TASK/);
 const r=req();delete r.app;
 await assert.rejects(take(f,r),/DEDA_WEEKLY_AUTH_REQUIRED/);
});
test("7: competing account and same account different task counted only once",async()=>{
 const f=fixture();
 await take(f);await take(f,req(B,"anonymousUser222"));
 await take(f,req(A,UID,"long_trip"));
 const x=await read(f);
 assert.equal(x.current.rows[0].weeklyPoints,40);
 assert.equal(x.current.rows[1].weeklyPoints,20);
 assert.equal(f.db.writes.length,6);
});
test("8: cannot score during Baghdad weekly midnight-to-six freeze",async()=>{
 const f=fixture();const closing=START+7*86400000-6*3600000;
 const r=await take(f,req(),closing+1000);
 assert.equal(r.status,"WEEK_FROZEN");
 assert.equal(f.db.writes.length,0);
});
test("9: next week's leaderboard empty, user lifetime XP untouched",async()=>{
 const f=fixture();await take(f);
 const next=await read(f,get(),START+7*86400000+2000);
 assert.equal(next.current.rows.length,0);
 assert.equal(next.previous.rows[0].weeklyPoints,20);
 assert.equal(next.current.rewardsCredited,false);
});
test("10: test cannot claim before competition begins",async()=>{
 const f=fixture();
 await assert.rejects(take(f,req(),START-1000),/DEDA_WEEKLY_NOT_STARTED/);
});
test("11: Baghdad weekday and official period rules are stable",()=>{
 assert.equal(baghdadDay(START),"2026-10-30");
 assert.equal(weekAt(START).id,"weekly-00000");
 assert.equal(weekAt(START+7*86400000).id,"weekly-00001");
 assert.equal(weekAt(START+7*86400000-6*3600000).closeAtMs,
  START+7*86400000-6*3600000);
});
