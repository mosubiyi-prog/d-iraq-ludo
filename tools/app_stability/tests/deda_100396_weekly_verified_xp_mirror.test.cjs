"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {createHash}=require("node:crypto");
const progress=require("../../../tools/app_stability/progress_archive/reconcile-core.cjs");
const {
 mirrorVerifiedTaskXp,seal,TaskXpHold,
}=require("../../../functions/deda_weekly_verified_xp_mirror_NOT_EXPORTED.js");
const FIRST=Date.UTC(2026,9,19,3); // Baghdad: Mon 06:00
const ACCOUNT="07701234567";
const OTHER="07707654321";
const KEY=Buffer.alloc(32,57);
const MID=FIRST+2*86400000;
function baghdad(t){
 const parts=Object.fromEntries(new Intl.DateTimeFormat("en-CA",{
  timeZone:"Asia/Baghdad",year:"numeric",month:"2-digit",day:"2-digit",
 }).formatToParts(new Date(t)).map(p=>[p.type,p.value]));
 return parts.year+"-"+parts.month+"-"+parts.day;
}
class Db {
 constructor(){this.docs=new Map();this.writePaths=[];}
 doc(path){return {path};}
 seed(path,value){this.docs.set(path,value);}
 get(path){return this.docs.get(path);}
 async runTransaction(fn){
  const ops=[];
  const tx={
   get:async ref=>({
    exists:this.docs.has(ref.path),
    data:()=>this.docs.get(ref.path),
   }),
   create:(ref,v)=>ops.push({type:"create",path:ref.path,v}),
   set:(ref,v)=>ops.push({type:"set",path:ref.path,v}),
  };
  const result=await fn(tx);
  for(const op of ops){
   if(op.type==="create"&&this.docs.has(op.path))throw Error("conflict");
  }
  for(const op of ops){
   this.docs.set(op.path,op.v);
   this.writePaths.push(op.path);
  }
  return result;
 }
}
function fixture(){
 const db=new Db();
 db.seed("deda_account_directory/"+ACCOUNT,{accountKey:ACCOUNT,
  active:true,createdUid:"originalUid123"});
 db.seed("deda_account_directory/"+OTHER,{accountKey:OTHER,
  active:true,createdUid:"originalUid456"});
 return db;
}
function record(db,{account=ACCOUNT,taskId="open_map",time=MID,
 forgedProof=false,levelXp=20}={}){
 const day=baghdad(time);
 const receipt={
  format:1,accountKey:account,source:"task-claim-v1",
  sourceId:"daily-task|"+day+"|"+taskId,kind:"award",
  delta:{points:5,coins:10,xp:levelXp,earnedDiamonds:0},
 };
 const eventKey=progress.eventKey(receipt);
 const event={
  format:1,accountKey:account,eventKey,appliedVersion:2,
  receipt,createdAt:{toMillis:()=>time},
  afterBalances:{xp:20,points:5,coins:10,earnedDiamonds:0},
 };
 const signed={
  accountKey:account,dayId:day,taskId,eventKey,
  appliedVersion:2,awardedAtMs:time,actionId:"serverActionVerified12345",
 };
 const proof={schema:1,issuer:"deda_server_verified_original_action_v1",
  productionApproved:true,...signed,
  signature:seal(KEY,signed)};
 if(forgedProof)proof.signature="f".repeat(64);
 db.seed("deda_verified_progress/"+account+"/events/"+eventKey,event);
 db.seed("deda_weekly_server_action_proofs/"+eventKey,proof);
 return eventKey;
}
const call=(db,eventKey,{accountKey=ACCOUNT,time=MID+3000}={})=>
 mirrorVerifiedTaskXp({db,accountKey,eventKey,secret:KEY,firstOpenMs:FIRST,nowMs:time});
const denied=(promise,re)=>assert.rejects(promise,e=>e instanceof TaskXpHold&&re.test(e.message));
test("01 verified applied level XP enters weekly tally, never changes original XP or wallet",async()=>{
 const db=fixture(),eventKey=record(db);
 db.seed("deda_verified_progress/"+ACCOUNT,{xp:20,points:5});
 db.seed("users/originalUid123/wallet/original",{diamonds:999});
 const r=await call(db,eventKey);
 assert.equal(r.status,"COUNTED");
 assert.equal(r.weeklyPoints,20);
 assert.equal(r.pointsAdded,20);
 assert.deepEqual(db.get("deda_verified_progress/"+ACCOUNT),{xp:20,points:5});
 assert.deepEqual(db.get("users/originalUid123/wallet/original"),{diamonds:999});
 assert.equal(db.writePaths.length,3);
 assert.ok(db.writePaths.every(p=>p.startsWith("deda_weekly_verified_xp_mirror_private/")));
});
test("02 second phone/repeat event never adds XP or points a second time",async()=>{
 const db=fixture(),eventKey=record(db);
 const first=await call(db,eventKey);
 const duplicate=await call(db,eventKey);
 assert.equal(first.weeklyPoints,20);
 assert.equal(duplicate.status,"ALREADY_COUNTED");
 assert.equal(duplicate.weeklyPoints,20);
 assert.equal(duplicate.pointsAdded,0);
 assert.equal(db.writePaths.length,3);
});
test("03 two distinct original completed tasks accumulate 40, no manager bonus",async()=>{
 const db=fixture();
 const a=record(db,{taskId:"open_map"});
 const b=record(db,{taskId:"open_saved_place",time:MID+30000});
 await call(db,a,{time:MID+33000});
 const out=await call(db,b,{time:MID+34000});
 assert.equal(out.weeklyPoints,40);
 assert.equal(out.pointsAdded,20);
 assert.equal(db.writePaths.length,6);
});
test("04 copied local score or forged server action proof fails closed",async()=>{
 const db=fixture(),eventKey=record(db,{forgedProof:true});
 await denied(call(db,eventKey),/BAD_ACTION_SIGNATURE/);
 assert.equal(db.writePaths.length,0);
 const proof=db.get("deda_weekly_server_action_proofs/"+eventKey);
 proof.productionApproved=false;
 await denied(call(db,eventKey),/UNVERIFIED_ACTION/);
 assert.equal(db.writePaths.length,0);
});
test("05 unknown task or fake original level XP amount never counts",async()=>{
 const db=fixture(),bad=record(db,{taskId:"fake_task"});
 await denied(call(db,bad),/UNKNOWN_TASK/);
 const db2=fixture(),fake=record(db2,{levelXp:500});
 await denied(call(db2,fake),/INVALID_TASK_LEVEL_XP/);
 assert.equal(db.writePaths.length+db2.writePaths.length,0);
});
test("06 different DEDA accounts cannot borrow each other's original receipts",async()=>{
 const db=fixture(),eventKey=record(db);
 await denied(call(db,eventKey,{accountKey:OTHER}),/NOT_APPLIED/);
 assert.equal(db.writePaths.length,0);
});
test("07 freeze at midnight does not add points, never reverses original XP",async()=>{
 const db=fixture(),close=FIRST+7*86400000-6*3600000;
 const key=record(db,{time:close+1000});
 const res=await call(db,key,{time:close+3000});
 assert.equal(res.status,"WEEK_FROZEN");
 assert.equal(res.counted,false);
 assert.equal(db.writePaths.length,0);
});
test("08 claimed event before freeze cannot be credited by late replay",async()=>{
 const db=fixture(),key=record(db);
 const close=FIRST+7*86400000-6*3600000;
 const out=await call(db,key,{time:close+1000});
 assert.equal(out.status,"WEEK_FROZEN");
 assert.equal(db.writePaths.length,0);
});
test("09 missing independent source proof blocks copied local task tick",async()=>{
 const db=fixture(),key=record(db);
 db.docs.delete("deda_weekly_server_action_proofs/"+key);
 await denied(call(db,key),/UNVERIFIED_ACTION/);
 assert.equal(db.writePaths.length,0);
});
test("10 no client amount, UID, install ID, or Google sign-in shortcut can alter mirror",async()=>{
 const db=fixture(),key=record(db);
 await assert.rejects(mirrorVerifiedTaskXp({
  db,accountKey:ACCOUNT,eventKey:key,firstOpenMs:FIRST,
  nowMs:MID+1000,secret:Buffer.from("tiny"),
 }),/SERVER_HMAC_SECRET_REQUIRED/);
 assert.equal(db.writePaths.length,0);
});
test("11 later week cannot reuse a prior week's original event",async()=>{
 const db=fixture(),key=record(db);
 await denied(call(db,key,{time:FIRST+7*86400000+2000}),/WRONG_COMPETITION_WEEK/);
 assert.equal(db.writePaths.length,0);
});
test("12 duplicate user data from old phone cannot overwrite points from canonical account",async()=>{
 const db=fixture(),a=record(db,{account:ACCOUNT});
 const b=record(db,{account:OTHER});
 const s1=await call(db,a);
 const s2=await call(db,b,{accountKey:OTHER});
 assert.equal(s1.weeklyPoints,20);
 assert.equal(s2.weeklyPoints,20);
 const scores=[...db.docs.entries()].filter(([k])=>k.includes("/scores/"));
 assert.equal(scores.length,2);
 assert.notEqual(scores[0][0],scores[1][0]);
 assert.equal(scores[0][0].includes(ACCOUNT),false);
 assert.equal(scores[1][0].includes(OTHER),false);
});
