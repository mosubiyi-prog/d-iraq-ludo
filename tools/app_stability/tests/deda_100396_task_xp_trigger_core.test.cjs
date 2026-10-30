"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const progress=require("../../../tools/app_stability/progress_archive/reconcile-core.cjs");
const {seal}=require("../../../functions/deda_weekly_verified_xp_mirror_NOT_EXPORTED.js");
const {processProof}=require("../../../functions/deda_weekly_100396_task_xp_trigger_core.js");
const ACCOUNT="07701234567",FIRST=Date.UTC(2026,9,19,3);
const TIME=FIRST+2*86400000,KEY=Buffer.alloc(32,57);
class MemoryDb {
 constructor(){this.docs=new Map();this.writes=[];}
 doc(path){return {path,get:async()=>({
  exists:this.docs.has(path),data:()=>this.docs.get(path)})};}
 seed(path,content){this.docs.set(path,content);}
 async runTransaction(fn){
  const ops=[];
  const tx={get:async ref=>({
   exists:this.docs.has(ref.path),data:()=>this.docs.get(ref.path)}),
   create:(ref,v)=>ops.push({path:ref.path,value:v,create:true}),
   set:(ref,v)=>ops.push({path:ref.path,value:v,create:false})};
  const result=await fn(tx);
  for(const op of ops)if(op.create&&this.docs.has(op.path))
    throw Error("document-already-exists");
  for(const op of ops){this.docs.set(op.path,op.value);this.writes.push(op.path);}
  return result;
 }
}
const baghdad=ms=>new Intl.DateTimeFormat("en-CA",{
 timeZone:"Asia/Baghdad",year:"numeric",month:"2-digit",day:"2-digit",
}).formatToParts(new Date(ms)).filter(p=>p.type!=="literal")
 .reduce((o,p)=>(o[p.type]=p.value,o),{});
function fixture(){
 const db=new MemoryDb();
 db.seed("deda_account_directory/"+ACCOUNT,{accountKey:ACCOUNT,active:true});
 const date=baghdad(TIME),dayId=date.year+"-"+date.month+"-"+date.day;
 const receipt={format:1,accountKey:ACCOUNT,source:"task-claim-v1",
  sourceId:"daily-task|"+dayId+"|open_map",kind:"award",
  delta:{points:5,coins:10,xp:20,earnedDiamonds:0}};
 const eventKey=progress.eventKey(receipt);
 const appliedVersion=2;
 const event={format:1,accountKey:ACCOUNT,eventKey,receipt,appliedVersion,
  createdAt:{toMillis:()=>TIME},
  afterBalances:{points:5,coins:10,xp:20,earnedDiamonds:0}};
 db.seed("deda_verified_progress/"+ACCOUNT+"/events/"+eventKey,event);
 const signed={accountKey:ACCOUNT,taskId:"open_map",dayId,eventKey,
  appliedVersion,awardedAtMs:TIME,actionId:"serverVerifiedActionOne"};
 const proof={...signed,schema:1,
  issuer:"deda_server_verified_original_action_v1",
  productionApproved:true,signature:seal(KEY,signed)};
 db.seed("deda_weekly_server_action_proofs/"+eventKey,proof);
 return {db,proof,eventKey};
}
const invoke=(f,extra={})=>processProof({db:f.db,proof:f.proof,
 eventKey:f.eventKey,secret:KEY,nowMs:TIME+2000,...extra});
test("01 default disabled calendar blocks all score mirror writes",async()=>{
 const f=fixture();
 const x=await invoke(f);
 assert.equal(x.status,"OWNER_CALENDAR_NOT_ENABLED");
 assert.equal(f.db.writes.length,0);
});
test("02 verified source with explicit owner calendar mirrors once",async()=>{
 const f=fixture();
 f.db.seed("deda_weekly_verified_calendar/active",{
  enabled:true,publisherApproved:true,
  allowLocalTaskBooleanProofs:false,allowClientMintedXp:false,
  firstOpenMs:FIRST});
 const first=await invoke(f),repeat=await invoke(f);
 assert.equal(first.status,"COUNTED");
 assert.equal(first.weeklyPoints,20);
 assert.equal(repeat.status,"ALREADY_COUNTED");
 assert.equal(repeat.weeklyPoints,20);
 assert.equal(f.db.writes.length,3);
 assert.ok(f.db.writes.every(path=>path.startsWith(
  "deda_weekly_verified_xp_mirror_private/")));
});
test("03 client-minted XP or unchecked calendar cannot open contest",async()=>{
 for(const forbidden of [
  {enabled:true,publisherApproved:false},
  {enabled:true,publisherApproved:true,allowLocalTaskBooleanProofs:true},
  {enabled:true,publisherApproved:true,allowClientMintedXp:true},
 ]){
  const f=fixture();
  f.db.seed("deda_weekly_verified_calendar/active",{
   allowLocalTaskBooleanProofs:false,allowClientMintedXp:false,
   firstOpenMs:FIRST,...forbidden});
  const r=await invoke(f);
  assert.equal(r.counted,false);
  assert.equal(f.db.writes.length,0);
 }
});
test("04 wrong source account/event cannot create a weekly score",async()=>{
 const f=fixture();
 f.db.seed("deda_weekly_verified_calendar/active",{
  enabled:true,publisherApproved:true,
  allowLocalTaskBooleanProofs:false,allowClientMintedXp:false,
  firstOpenMs:FIRST});
 await assert.rejects(invoke(f,{eventKey:"f".repeat(64)}),
  /DEDA_WEEKLY_XP_HOLD_INVALID_PROOF_DOCUMENT/);
 assert.equal(f.db.writes.length,0);
});
test("05 unapproved signer does nothing and never writes",async()=>{
 const f=fixture();f.proof={...f.proof,productionApproved:false};
 const x=await invoke(f);
 assert.equal(x.status,"UNAPPROVED_PROOF_IGNORED");
 assert.equal(f.db.writes.length,0);
});
