"use strict";
const {test,before,after}=require("node:test");
const assert=require("node:assert/strict");
const {createHash}=require("node:crypto");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore,Timestamp}=require("firebase-admin/firestore");
const core=require("../../tools/app_stability/progress_archive/reconcile-core.cjs");
const {TASK_IDS}=require("../../functions/deda_weekly_original_eight_task_source_gate_NOT_EXPORTED.js");
const {windowFor}=require("../../functions/deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
const {ROSTER,PROOFS,canonicalProofBody,seal,projectCanonicalEarnedXpTopTen:project}=
 require("../../functions/deda_weekly_canonical_daily_xp_top10_NOT_EXPORTED.js");
const PROJECT="demo-deda-restore-readiness";
const SECRET=Buffer.from("a".repeat(64),"hex");
const FIRST=Date.UTC(2026,9,19,3);
const WEEK=windowFor(FIRST,0);
const MID=FIRST+2*24*3600000+12*3600000;
const FROZEN=WEEK.closeAtMs+1000;
let app,db,seedCount=0;
const originalId=n=>"@DEDA-"+String(n).padStart(6,"0");
function account(n){return "0770"+String(n).padStart(7,"0");}
async function put(path,value){await db.doc(path).set(value);}
async function get(path){const s=await db.doc(path).get();return s.exists?s.data():null;}
function basicState(key,init){return{
 format:1,accountKey:key,version:2,
 balances:{points:5,coins:10,xp:20,earnedDiamonds:0},
 initializedBy:init,
};}
async function enroll(n,{tasks=["open_map"],when=MID,level=20}={}){
 const key=account(n),oid=originalId(n),uid="original_qa_user_"+n;
 const start=core.parseReceipt({format:1,accountKey:key,
  source:"account-bootstrap-v1",sourceId:"created",
  kind:"baseline",delta:{points:0,coins:0,xp:0,earnedDiamonds:0}},key);
 const ini=core.eventKey(start);
 await put("deda_account_directory/"+key,{accountKey:key,active:true,createdUid:uid});
 await put("deda_account_profiles/"+key,{accountKey:key,name:"لاعب "+n});
 await put("users/"+uid,{accountKey:key,sharePersonalId:oid,name:"لاعب "+n});
 await put("deda_share_ids/"+oid,{kind:"personal",publicId:oid,
  active:true,ownerUid:uid});
 const hash=createHash("sha256").update(key).digest("hex");
 await put("deda_owned_identifier_accounts/"+hash,{
  accountKey:key,originalId:oid,activeId:oid,ownedIds:[oid]});
 await put("deda_verified_progress/"+key,{
  ...basicState(key,ini),version:1+tasks.length,
  balances:{points:5*tasks.length,coins:10*tasks.length,
    xp:20*tasks.length,earnedDiamonds:0},
 });
 const entries=[];
 for(let i=0;i<tasks.length;i++){
  const taskId=tasks[i],at=when+i*60000;
  const date=new Intl.DateTimeFormat("en-CA",{
   timeZone:"Asia/Baghdad",year:"numeric",month:"2-digit",day:"2-digit",
  }).formatToParts(new Date(at));
  const datePart=Object.fromEntries(date.map(p=>[p.type,p.value]));
  const day=datePart.year+"-"+datePart.month+"-"+datePart.day;
  const receipt=core.parseReceipt({
   format:1,accountKey:key,source:"task-claim-v1",
   sourceId:"daily-task|"+day+"|"+taskId,kind:"award",
   delta:{points:5,coins:10,xp:20,earnedDiamonds:0},
  },key);
  const eventKey=core.eventKey(receipt),appliedVersion=i+2;
  const body=canonicalProofBody({
   accountKey:key,dayId:day,taskId,eventKey,appliedVersion,awardedAtMs:at,
  });
  await put("deda_verified_progress/"+key+"/events/"+eventKey,{
   format:1,accountKey:key,eventKey,receipt,receiptId:eventKey,
   appliedVersion,createdAt:Timestamp.fromMillis(at),
   afterBalances:{points:5*(i+1),coins:10*(i+1),
    xp:20*(i+1),earnedDiamonds:0},
  });
  await put(PROOFS+"/"+eventKey,{...body,seal:seal(SECRET,body)});
  entries.push({key,eventKey,taskId,day,at});
 }
 return {key,uid,oid,entries,hash};
}
async function roster(keys){await put(ROSTER,{
 accountKeys:keys,emulatorOnly:true,productionReady:false});}
function projection(now=FROZEN){
 return project({db,backendSecret:SECRET,firstOpenMs:FIRST,
   weekIndex:0,serverNowMs:now});
}
before(async()=>{
 assert.equal(process.env.GCLOUD_PROJECT,PROJECT);
 assert.equal(process.env.FIRESTORE_EMULATOR_HOST,"127.0.0.1:8080");
 assert.equal(process.env.DEDA_CANONICAL_LEAGUE_EMULATOR_ONLY,"true");
 app=initializeApp({projectId:PROJECT},"canonical-daily-xp-emulator");
 db=getFirestore(app);
});
after(async()=>{if(app)await deleteApp(app);});
test("01 same ORIGINAL daily-task XP receipts -> top10 ordered, not wallet points",async()=>{
 const a=await enroll(++seedCount,{tasks:["open_map","open_received_place"]});
 const b=await enroll(++seedCount,{tasks:["open_map"]});
 await roster([a.key,b.key]);
 const result=await projection(MID+2*60000);
 assert.equal(result.productionReady,false);
 assert.equal(result.creditsDiamonds,false);
 assert.equal(result.hasVerifiedServerAppliedXpOnly,true);
 assert.equal(result.rows.length,2);
 assert.deepEqual(result.rows.map(r=>r.weeklyPoints),[40,20]);
 assert.deepEqual(result.rows.map(r=>r.verifiedTaskCompletions),[2,1]);
 assert.deepEqual(result.rows.map(r=>r.diamondsIfFinalWinner),[150,100]);
 assert.deepEqual(new Set(result.rows.map(r=>r.participantId)).size,2);
 assert.ok(!JSON.stringify(result).includes(a.key));
 assert.ok(!JSON.stringify(result).includes(b.key));
 assert.equal((await get("deda_verified_progress/"+a.key)).balances.xp,40);
});
test("02 change phone UID but preserve account => same score, position and participant ID",async()=>{
 const a=await enroll(++seedCount,{tasks:["share_personal_location","open_map"]});
 await roster([a.key]);
 const beforeView=await projection();
 const newUid="second_qa_user_"+seedCount;
 await put("users/"+newUid,{accountKey:a.key,sharePersonalId:a.oid,
   name:"لاعب "+seedCount});
 await put("deda_share_ids/"+a.oid,{
   kind:"personal",publicId:a.oid,active:true,ownerUid:newUid});
 await put("deda_migration_account_authority/"+a.key,{
   accountKey:a.key,originalUid:a.uid,activeUid:newUid,
   status:"new-device-exclusive"});
 await put("deda_migration_spend_authority/"+a.oid,{
   publicId:a.oid,originalUid:a.uid,activeUid:newUid,
   status:"new-device-exclusive"});
 const afterView=await projection();
 assert.deepEqual(afterView.rows,beforeView.rows);
 assert.equal(afterView.rows[0].weeklyPoints,40);
 assert.equal((await get("deda_verified_progress/"+a.key)).balances.xp,40);
 const foreign="attacker_wrong_qa_user";
 await put("deda_share_ids/"+a.oid,{
   kind:"personal",publicId:a.oid,active:true,ownerUid:foreign});
 await assert.rejects(projection(),/UNAUTHORIZED_PHONE_HANDOVER/);
});
test("03 fake duplicated or modified applied task proof fails closed, never adds XP",async()=>{
 const a=await enroll(++seedCount,{tasks:["open_map"]});
 await roster([a.key]);
 const p=PROOFS+"/"+a.entries[0].eventKey;
 const original=await get(p);
 await put(p,{...original,seal:"f".repeat(64)});
 await assert.rejects(projection(),/MISSING_INDEPENDENT_SIGNED_ACTION_PROOF/);
 await put(p,original);
 const applied="deda_verified_progress/"+a.key+"/events/"+a.entries[0].eventKey;
 const previous=await get(applied);
 await put(applied,{...previous,receipt:{...previous.receipt,
  delta:{points:5,coins:10,xp:40,earnedDiamonds:0}}});
 await assert.rejects(projection(),/NOT_ORIGINAL_TASK_XP|NOT_APPLIED_CANONICAL_EVENT/);
 assert.equal((await get("deda_verified_progress/"+a.key)).balances.xp,20);
});
test("04 after midnight original level XP may remain, league gets no new XP",async()=>{
 const a=await enroll(++seedCount,{tasks:["open_map"],when:WEEK.closeAtMs+30000});
 await roster([a.key]);
 const out=await projection(FROZEN+60000);
 assert.equal(out.rows.length,0);
 assert.equal((await get("deda_verified_progress/"+a.key)).balances.xp,20);
});
test("05 all eight original task IDs admitted only with independent signed applied proof",async()=>{
 const a=await enroll(++seedCount,{tasks:TASK_IDS,when:MID});
 await roster([a.key]);
 const out=await projection(MID+8*60000);
 assert.equal(out.rows[0].weeklyPoints,160);
 assert.equal(out.rows[0].verifiedTaskCompletions,8);
 assert.equal(out.creditsDiamonds,false);
 assert.equal((await get("deda_verified_progress/"+a.key)).balances.xp,160);
});
test("06 cannot convert old local task booleans, manager bonus or raw XP into leaderboard",async()=>{
 const a=await enroll(++seedCount,{tasks:[]});
 await put("deda_verified_progress/"+a.key,{
  format:1,accountKey:a.key,version:1,initializedBy:"a".repeat(64),
  balances:{points:1000000,coins:0,xp:1000000,earnedDiamonds:0}});
 await roster([a.key]);
 const res=await projection();
 assert.equal(res.rows.length,0);
 await assert.rejects(project({db,backendSecret:SECRET,
  firstOpenMs:FIRST,weekIndex:0,serverNowMs:FROZEN,
  clientXp:1000000}),/CLIENT_SCORE_OR_PHONE_OVERRIDE/);
});
