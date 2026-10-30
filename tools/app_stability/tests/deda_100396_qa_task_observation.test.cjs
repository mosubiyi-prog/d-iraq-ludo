"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {createHash}=require("node:crypto");
const {
  recordMonitoredTask,readMonitoredXp,MonitorHold,
}=require("../../../functions/deda_weekly_100396_observation_core.js");
const ACCOUNT="07705558888",UID="originalTestUser123";
const START=Date.UTC(2026,9,26,3); // Baghdad: 06:00
const NOW=START+2*86400000;
class Db {
  constructor(){this.docs=new Map();this.writes=[];}
  doc(path){return {path,get:async()=>({
    exists:this.docs.has(path),data:()=>this.docs.get(path),
  })};}
  seed(path,data){this.docs.set(path,structuredClone(data));}
  async runTransaction(fn){
    const ops=[];
    const tx={
      get:async ref=>({exists:this.docs.has(ref.path),
        data:()=>this.docs.get(ref.path)}),
      create:(ref,v)=>ops.push({ref,value:v,create:true}),
      set:(ref,v)=>ops.push({ref,value:v,create:false}),
    };
    const result=await fn(tx);
    for(const op of ops)if(op.create&&this.docs.has(op.ref.path))
      throw Error("duplicate-create");
    for(const op of ops){
      this.docs.set(op.ref.path,structuredClone(op.value));
      this.writes.push(op.ref.path);
    }
    return result;
  }
}
function req({uid=UID,taskId="open_map",accountKey=ACCOUNT}={}){
  return {
    auth:{uid,token:{firebase:{sign_in_provider:"anonymous"}}},
    app:{appId:"emulator-only-test-app"},
    data:{accountKey,taskId},
  };
}
const readReq=uid=>({auth:req({uid}).auth,app:req().app,
  data:{accountKey:ACCOUNT}});
function fixture(){
 const db=new Db();
 const digest=createHash("sha256").update(ACCOUNT).digest("hex");
 const auth={getUser:async uid=>({
  uid,disabled:false,email:null,providerData:[],
 })};
 db.seed("deda_account_directory/"+ACCOUNT,{
  accountKey:ACCOUNT,active:true,createdUid:UID,
 });
 db.seed("deda_weekly_observation_config/active",{
  qaEnabled:true,payoutsDisabled:true,productionRankEnabled:false,
  allowlistedAccountHashes:[digest],firstOpenMs:START,
 });
 return {db,auth,digest};
}
const count=(f,request=req(),nowMs=NOW)=>
  recordMonitoredTask({...f,request,nowMs});
const read=(f,request=readReq(UID),nowMs=NOW)=>
  readMonitoredXp({...f,request,nowMs});
const deny=p=>assert.rejects(p,e=>e instanceof MonitorHold);
test("1: QA first task records 20 observed XP but NO level/diamonds",async()=>{
 const f=fixture();
 f.db.seed("users/"+UID+"/wallet/original",{diamonds:550});
 const r=await count(f);
 assert.equal(r.status,"OBSERVATION_RECORDED_QA");
 assert.equal(r.observedWeeklyXp,20);
 assert.equal(r.credited,false);
 assert.equal(r.unverified,true);
 assert.equal(f.db.writes.length,2);
 assert.ok(f.db.writes.every(p=>p.startsWith("deda_weekly_observation_only/")));
 assert.deepEqual(f.db.docs.get("users/"+UID+"/wallet/original"),{diamonds:550});
});
test("2: repeated click from same phone or retry never doubles task",async()=>{
 const f=fixture();
 await count(f);
 const retry=await count(f);
 assert.equal(retry.status,"OBSERVATION_ALREADY_RECORDED");
 assert.equal(f.db.writes.length,2);
});
test("3: two distinct original tasks become 40 provisional points",async()=>{
 const f=fixture();
 await count(f);
 const r=await count(f,req({taskId:"open_saved_place"}));
 assert.equal(r.observedWeeklyXp,40);
 const own=await read(f);
 assert.equal(own.observedXp,40);
 assert.equal(own.independentlyVerified,false);
 assert.equal(own.payoutEligible,false);
 assert.equal(own.publicRankingAllowed,false);
});
test("4: missing owner approval and account allowlist fails closed",async()=>{
 const f=fixture();
 f.db.seed("deda_weekly_observation_config/active",{
  qaEnabled:false,payoutsDisabled:true,productionRankEnabled:false,
  allowlistedAccountHashes:[f.digest],firstOpenMs:START,
 });
 await deny(count(f));
 const g=fixture();g.db.docs.delete("deda_weekly_observation_config/active");
 await deny(count(g));
 assert.equal(f.db.writes.length+g.db.writes.length,0);
});
test("5: unrelated Firebase UID cannot impersonate original account",async()=>{
 const f=fixture();
 await deny(count(f,req({uid:"differentUser123"})));
 await deny(read(f,readReq("differentUser123")));
 assert.equal(f.db.writes.length,0);
});
test("6: forged points/client extras and nonoriginal task rejected",async()=>{
 const f=fixture();
 const attack=req();attack.data.claimedXp=900000;
 await deny(count(f,attack));
 await deny(count(f,req({taskId:"manager_bonus"})));
 assert.equal(f.db.writes.length,0);
});
test("7: 00:00–06:00 Baghdad freeze has no provisional credit",async()=>{
 const f=fixture();
 const atClose=START+7*86400000-6*3600000;
 const r=await count(f,req(),atClose+1000);
 assert.equal(r.status,"FROZEN_NO_POINTS");
 assert.equal(f.db.writes.length,0);
});
test("8: self-monitor reads zero until real observed claim, never synthetic rankings",async()=>{
 const f=fixture();
 const before=await read(f);
 assert.equal(before.observedXp,0);
 assert.equal(before.publicRankingAllowed,false);
 assert.equal(before.status,"QA_OBSERVATION_ONLY_NOT_APPROVED");
 assert.equal(f.db.writes.length,0);
});
test("9: no App Check context must block observations",async()=>{
 const f=fixture(),request=req();
 delete request.app;
 await deny(count(f,request));
 assert.equal(f.db.writes.length,0);
});
