"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const {createHash}=require("node:crypto");
const {claim,standings,weekAt,iraqDay}=require("../deda_weekly_community_scores_core");
const START=Date.UTC(2026,9,31,3); // Saturday, Baghdad 06:00
const NOW=START+60000;
const key=i=>"0770"+String(i).padStart(7,"0");
const uid=i=>"anonymousLeagueUser"+String(i).padStart(3,"0");
const pub=i=>"@DEDA-"+String(i).padStart(6,"A");
const digest=s=>createHash("sha256").update(s).digest("hex");
class DB{
  constructor(){this.docs=new Map();this.writes=[];}
  seed(path,value){this.docs.set(path,structuredClone(value));}
  snap(path){return {exists:this.docs.has(path),
    data:()=>this.docs.get(path)};}
  doc(path){return {path,get:async()=>this.snap(path)};}
  collection(path){return {get:async()=>{
    const docs=[...this.docs.entries()].filter(([p])=>p.startsWith(path+"/")&&
      !p.slice(path.length+1).includes("/"))
      .map(([p,value])=>({id:p.slice(path.length+1),
        data:()=>structuredClone(value)}));
    return {docs,size:docs.length};
  }};}
  async runTransaction(fn){
    const pending=[];
    const tx={get:async ref=>this.snap(ref.path),
      create:(ref,value)=>pending.push({path:ref.path,value,create:true}),
      set:(ref,value)=>pending.push({path:ref.path,value,create:false})};
    const result=await fn(tx);
    for(const w of pending)if(w.create&&this.docs.has(w.path))
      throw Error("duplicate-firestore-create");
    for(const w of pending){this.docs.set(w.path,structuredClone(w.value));
      this.writes.push(w.path);}
    return result;
  }
}
function fixture(n=20){
  const db=new DB(),users=new Map();
  db.seed("deda_weekly_community_config/active",{
    communityEnabled:true,grantDiamonds:false,
    allowClientTaskReports:true,startAtMs:START});
  for(let i=1;i<=n;i++){
    const a=key(i),u=uid(i);
    users.set(u,{uid:u,disabled:false,email:null,providerData:[]});
    db.seed("deda_account_directory/"+a,{accountKey:a,active:true,createdUid:u});
    db.seed("deda_account_profiles/"+a,{accountKey:a,name:"مستخدم "+i});
    db.seed("users/"+u,{accountKey:a,sharePersonalId:pub(i)});
  }
  return {db,auth:{getUser:async u=>users.get(u)||null},users};
}
function req(i=1,taskId="open_map",u=uid(i),day=iraqDay(NOW)){
  return {auth:{uid:u,token:{firebase:{sign_in_provider:"anonymous"}}},
    app:{appId:"android-deda-approved-app-check"},
    data:{accountKey:key(i),taskId,claimDay:day}};
}
function readReq(i=1){
  const r=req(i);r.data={accountKey:key(i)};return r;
}
function award(f,i=1,taskId="open_map",nowMs=NOW){
  return claim({...f,request:req(i,taskId,uid(i),iraqDay(nowMs)),nowMs});
}
function read(f,i=1,nowMs=NOW){
  return standings({...f,request:readReq(i),nowMs});
}
test("20 actual account fixtures share an XP-ranked week, no made-up contestants",async()=>{
  const f=fixture();
  for(let i=1;i<=20;i++)await award(f,i);
  for(let i=1;i<=4;i++)await award(f,i,"traffic_skills");
  const r=await read(f,17);
  assert.equal(r.current.rows.length,11); // 10 winners + viewer outside top 10
  assert.equal(r.current.rows[0].weeklyPoints,40);
  assert.equal(r.current.rows[4].weeklyPoints,20);
  assert.ok(r.current.rows[10].place>10);
  assert.equal(r.current.viewerPlace,r.current.rows[10].place);
  assert.equal(r.current.rows[10].diamondsIfFinalWinner,0);
  assert.deepEqual(r.current.rows.slice(0,3).map(x=>x.diamondsIfFinalWinner),
    [150,100,50]);
  assert.equal(r.source,"future_server_issued_only");
  assert.equal(r.current.rewardsCredited,false);
  assert.equal(JSON.stringify(r).includes(key(17)),false);
  assert.equal(JSON.stringify(r).includes(uid(17)),false);
  assert.equal(f.db.writes.length,48);
});
test("the same day and task adds exactly one +20 level XP score",async()=>{
  const f=fixture(1);
  const first=await award(f);
  const repeated=await award(f);
  assert.equal(first.status,"COUNTED_COMMUNITY");
  assert.equal(first.weeklyXp,20);
  assert.equal(repeated.status,"ALREADY_RECORDED");
  assert.equal(repeated.weeklyXp,20);
  assert.equal(f.db.writes.length,2);
  assert.equal(f.db.docs.get("users/"+uid(1)).sharePersonalId,pub(1));
});
test("changed authenticated UID cannot borrow a different DEDA account",async()=>{
  const f=fixture(2);
  await assert.rejects(claim({...f,request:req(1,"open_map",uid(2)),nowMs:NOW}),
    /COMMUNITY_WEEKLY_ACCOUNT_UNVERIFIED/);
  assert.equal(f.db.writes.length,0);
});
test("explicit verified binding keeps original account and prevents repeat on second phone",async()=>{
  const f=fixture(1),other="anonymousNewDevice00001";
  f.users.set(other,{uid:other,disabled:false,email:null,providerData:[]});
  f.db.seed("deda_secure_account_bindings/"+other,{
    uid:other,accountKey:key(1),status:"PIN_VERIFIED_HOLD",
    canMigrate:false,canRestoreAssets:false});
  await award(f);
  const r=await claim({...f,request:req(1,"open_map",other),nowMs:NOW});
  assert.equal(r.status,"ALREADY_RECORDED");
  assert.equal(f.db.writes.length,2);
});
test("disabled config, missing App Check and anonymous auth reject writes",async()=>{
  const f=fixture(1);
  f.db.docs.delete("deda_weekly_community_config/active");
  await assert.rejects(award(f),/COMMUNITY_WEEKLY_LEAGUE_DISABLED/);
  f.db.seed("deda_weekly_community_config/active",{
    communityEnabled:true,grantDiamonds:false,
    allowClientTaskReports:true,startAtMs:START});
  let r=req();delete r.app;
  await assert.rejects(claim({...f,request:r,nowMs:NOW}),/AUTH_REQUIRED/);
  r=req();r.auth.token.firebase.sign_in_provider="google.com";
  await assert.rejects(claim({...f,request:r,nowMs:NOW}),/AUTH_REQUIRED/);
  assert.equal(f.db.writes.length,0);
});
test("extra client XP or diamonds and unknown task cannot create scores",async()=>{
  const f=fixture(1);
  let r=req();r.data.weeklyXp=900;
  await assert.rejects(claim({...f,request:r,nowMs:NOW}),/AUTH_REQUIRED/);
  await assert.rejects(award(f,1,"fake_admin_bonus"),/BAD_TASK/);
  assert.equal(f.db.writes.length,0);
});
test("Baghdad midnight-six freeze, seven-day restart and prior rankings",async()=>{
  const f=fixture(1);
  await award(f);
  const frozen=START+7*86400000-6*3600000+1000;
  const x=await award(f,1,"traffic_skills",frozen);
  assert.equal(x.status,"WEEK_FROZEN");
  const prior=await read(f,1,START+7*86400000+1000);
  assert.equal(prior.current.rows.length,0);
  assert.equal(prior.previous.rows.length,1);
  assert.equal(prior.previous.rows[0].weeklyPoints,20);
  assert.equal(f.db.writes.length,2);
});
test("Saturday 06:00 Baghdad is configured, and not a hard-coded Friday",()=>{
  assert.equal(new Date(START).toISOString(),"2026-10-31T03:00:00.000Z");
  assert.equal(weekAt(START,START).id,"community-00000");
  assert.equal(weekAt(START,START+7*86400000).id,"community-00001");
  assert.throws(()=>weekAt(START-3600000,START),/INVALID_START/);
  assert.throws(()=>weekAt(START,START-1),/NOT_STARTED/);
});
test("no payouts, local XP or diamond writes in community backend",async()=>{
  const f=fixture(1);
  f.db.seed("users/"+uid(1)+"/wallet/original",
    {diamonds:150,levelXp:500});
  await award(f);
  assert.deepEqual(f.db.docs.get("users/"+uid(1)+"/wallet/original"),
    {diamonds:150,levelXp:500});
  assert.equal(f.db.writes.every(p=>p.startsWith("deda_weekly_community/")),true);
});
test("server settings must forbid diamonds and client XP amounts",async()=>{
  const f=fixture(1);
  f.db.seed("deda_weekly_community_config/active",{
    communityEnabled:true,grantDiamonds:true,
    allowClientTaskReports:true,startAtMs:START});
  await assert.rejects(award(f),/LEAGUE_DISABLED/);
  assert.equal(f.db.writes.length,0);
});

test("a delayed claim may not be attributed to a different Baghdad day",async()=>{
  const f=fixture(1);
  const tomorrow=Date.UTC(2026,9,31,21,1); // Nov 1 00:01 Baghdad
  const oldRequest=req(1,"open_map",uid(1),iraqDay(NOW));
  await assert.rejects(claim({...f,request:oldRequest,nowMs:tomorrow}),
    /COMMUNITY_WEEKLY_DAY_MISMATCH/);
  assert.equal(f.db.writes.length,0);
});
test("a caller cannot submit a future-day or malformed task date",async()=>{
  const f=fixture(1);
  for(const claimDay of ["2026-11-01","2026-10-00","tomorrow",20261031]){
    const r=req();
    r.data.claimDay=claimDay;
    await assert.rejects(claim({...f,request:r,nowMs:NOW}),
      /COMMUNITY_WEEKLY_DAY_MISMATCH/);
  }
  assert.equal(f.db.writes.length,0);
});
