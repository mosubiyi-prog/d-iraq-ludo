"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const crypto=require("node:crypto");
const {
  projectFutureServerWeek,competitorId,
}=require("../deda_weekly_receipts_to_standings_NOT_EXPORTED.js");
const {opaqueReceiptId}=
  require("../deda_weekly_owner_receipt_gate_NOT_EXPORTED.js");
const {verifyAndRedactSnapshot}=
  require("../deda_weekly_snapshot_reader_NOT_EXPORTED.js");
const NOW=Date.UTC(2026,9,27,11);
const WEEK={weekId:"server-chosen-week-c",startMs:Date.UTC(2026,9,26,21),
  endMs:Date.UTC(2026,10,2,21)};
const OLD={weekId:"server-chosen-week-p",startMs:WEEK.startMs-7*86400000,
  endMs:WEEK.startMs};
const ACCOUNT_A="07712345678",ACCOUNT_B="07701234567";
const KEY=Buffer.alloc(32,42),OTHER=Buffer.alloc(32,43);
const source="privileged_server_only_task_xp_issuer_v1";
function receipt({account=ACCOUNT_A,task="open_map",week=WEEK,
  verifiedAtMs=NOW-5000,dayId="2026-10-27"}={}) {
  const id=opaqueReceiptId({accountKey:account,dayId,taskId:task});
  return {id,data:{
    issuer:source,status:"final_award_committed",accountKey:account,
    taskId:task,dayId,weekId:week.weekId,receiptId:id,
    taskPointsAwarded:true,levelXpApplied:true,levelXpAmount:20,
    verifiedAtMs,
  }};
}
function profile(account,id,name) {
  return {path:"deda_weekly_public_profiles/"+
    crypto.createHash("sha256").update(account).digest("hex"),
    data:{issuer:"privileged_server_only_public_profile_v1",
      state:"verified",accountKey:account,activePublicId:id,
      displayName:name},
  };
}
function store({events=[],profiles=[],week=WEEK}={}){
  const collectionPath="deda_weekly_xp_receipts/"+week.weekId+"/events";
  const publicDocs=new Map(profiles.map(x=>[x.path,x.data]));
  let reads=0;
  return {
    get reads(){return reads},
    doc(path){
      return {async get(){
        reads++;
        const data=publicDocs.get(path);
        return data?{exists:true,data:()=>structuredClone(data)}:{exists:false};
      }};
    },
    collection(name){
      assert.equal(name,"deda_weekly_xp_receipts");
      return {doc(id){
        assert.equal(id,week.weekId);
        return {collection(child){
          assert.equal(child,"events");
          return {async get(){
            reads++;
            return {docs:events.map(x=>({
              id:x.id,data:()=>structuredClone(x.data),
            }))};
          }};
        }};
      }};
    },
    async runTransaction(){throw Error("read-only ranker cannot write")},
  };
}
function args(db,week=WEEK,kind="current",now=NOW){
  return {db,weekConfig:week,serverNowMs:now,rankerKey:KEY,kind};
}
const profiles=[
  profile(ACCOUNT_A,"@DEDA-A12345","لاعب العراق"),
  profile(ACCOUNT_B,"@DEDA-B12345","لاعب آخر"),
];
test("2 tasks vs 1 task yield real-formatted current top1 + top2 + safe personal view",async()=>{
  const db=store({events:[
    receipt({account:ACCOUNT_B,task:"traffic_skills",verifiedAtMs:NOW-4000}),
    receipt({account:ACCOUNT_A,task:"traffic_skills",verifiedAtMs:NOW-3000}),
    receipt({account:ACCOUNT_A,task:"open_map",verifiedAtMs:NOW-2000}),
  ],profiles});
  const snapshot=await projectFutureServerWeek(args(db));
  assert.equal(snapshot.issuer,"privileged_server_only_weekly_ranker_v1");
  assert.equal(snapshot.rows[0].earnedLevelXp,40);
  assert.equal(snapshot.rows[0].taskClaims,2);
  assert.equal(snapshot.rows[0].potentialDiamonds,150);
  assert.equal(snapshot.rows[1].earnedLevelXp,20);
  assert.equal(snapshot.rows[1].potentialDiamonds,100);
  assert.equal(snapshot.rows[0].accountKey,ACCOUNT_A);
  const userView=verifyAndRedactSnapshot(snapshot,WEEK,ACCOUNT_B,NOW,"current");
  assert.equal(userView.viewerPlace,2);
  assert.equal(userView.rows.length,2);
  const safe=JSON.stringify(userView);
  for(const secret of [ACCOUNT_A,ACCOUNT_B,"uid","installId"])
    assert.ok(!safe.includes(secret),"private identifier leaked: "+secret);
  assert.equal(userView.rewardsCredited,false);
});
test("tampered claims, 5 quiz-answer points and wrong XP totals fail closed",async()=>{
  const legitimate=receipt();
  for(const mutation of [
    {issuer:"user_client"}, {status:"claimed_only"},
    {taskPointsAwarded:false},{levelXpApplied:false},
    {levelXpAmount:5},{levelXpAmount:500000},
    {weekId:"client_week"},{dayId:"2026-10-26"},
    {verifiedAtMs:NOW+1000},
  ]) {
    const wrong={...legitimate,data:{...legitimate.data,...mutation}};
    await assert.rejects(projectFutureServerWeek(args(store({
      events:[wrong],profiles,
    }))),/DEDA_STAGE10_WEEKLY_RANK_BLOCK_/);
  }
});
test("different UID or public alias cannot produce two rows for one canonical account",async()=>{
  const repeated=receipt();
  const duplicate={...repeated};
  await assert.rejects(projectFutureServerWeek(args(store({
    events:[repeated,duplicate],profiles,
  }))),/duplicated_or_wrong_receipt_document/);
  const a=await projectFutureServerWeek(args(store({
    events:[receipt()],profiles,
  })));
  assert.equal(a.rows[0].publicCompetitorId,
    competitorId(ACCOUNT_A,KEY));
  assert.notEqual(competitorId(ACCOUNT_A,KEY),competitorId(ACCOUNT_A,OTHER));
  assert.ok(!competitorId(ACCOUNT_A,KEY).includes(ACCOUNT_A));
});
test("privacy requires server-issued public identity and names without phones",async()=>{
  const record=receipt();
  for(const p of [
    profile(ACCOUNT_A,"@DEDA-A12345","07712345678"),
    profile(ACCOUNT_A,"@DEDA-A12345","hello@example.com"),
    profile(ACCOUNT_A,"@DEDA-X","لاعب"),
    {...profile(ACCOUNT_A,"@DEDA-A12345","لاعب"),
      data:{...profile(ACCOUNT_A,"@DEDA-A12345","لاعب").data,
        issuer:"phone_user"}},
  ]) {
    await assert.rejects(projectFutureServerWeek(args(store({
      events:[record],profiles:[p],
    }))),/unsafe_public_profile/);
  }
  await assert.rejects(projectFutureServerWeek(args(store({
    events:[record],profiles:[],
  }))),/missing_server_owned_public_profile/);
});
test("admin or phone cannot submit unsafe ranker credentials",async()=>{
  const db=store({events:[receipt()],profiles});
  for(const key of [null,"test",Buffer.alloc(6),Buffer.alloc(0)]) {
    await assert.rejects(projectFutureServerWeek({
      ...args(db),rankerKey:key,
    }),/private_ranker_secret_missing/);
  }
  assert.ok(!JSON.stringify(db).includes(ACCOUNT_A));
});
test("previous week only closes after 7-day cutoff and cannot include current points",async()=>{
  const at=OLD.endMs-1000;
  const date="2026-10-26";
  const previous=receipt({week:OLD,verifiedAtMs:at,dayId:date});
  const db=store({events:[previous],profiles,week:OLD});
  const closed=await projectFutureServerWeek(args(db,OLD,"previous",NOW));
  assert.equal(closed.state,"closed");
  assert.equal(closed.generatedAtMs,OLD.endMs-1);
  const view=verifyAndRedactSnapshot(closed,OLD,ACCOUNT_A,NOW,"previous");
  assert.equal(view.remainingMs,0);
  assert.equal(view.rows.length,1);
  await assert.rejects(projectFutureServerWeek(args(
    store({events:[],profiles,week:OLD}),OLD,"current",NOW,
  )),/active_week_closed/);
});
test("zero genuine committed XP is a zero-rank snapshot, not invented winners",async()=>{
  const db=store({events:[],profiles});
  const raw=await projectFutureServerWeek(args(db));
  assert.deepEqual(raw.rows,[]);
  const redacted=verifyAndRedactSnapshot(raw,WEEK,ACCOUNT_A,NOW,"current");
  assert.equal(redacted.viewerPlace,null);
  assert.equal(redacted.rows.length,0);
});
test("duplicate active DEDA IDs for different accounts fail closed",async()=>{
  const p2=profile(ACCOUNT_B,"@DEDA-A12345","خصم");
  await assert.rejects(projectFutureServerWeek(args(store({
    events:[receipt({account:ACCOUNT_A}),
      receipt({account:ACCOUNT_B,task:"traffic_skills"})],
    profiles:[profiles[0],p2],
  }))),/duplicate_public_id/);
});

test("legitimate four-letter premium ID is retained in verified weekly ranking",async()=>{
  const db=store({events:[receipt()],profiles:[
    profile(ACCOUNT_A,"@DEDA-AAAA","لاعب أربع"),
  ]});
  const result=await projectFutureServerWeek(args(db));
  assert.equal(result.rows[0].activePublicId,"@DEDA-AAAA");
  const exposed=verifyAndRedactSnapshot(result,WEEK,ACCOUNT_A,NOW,"current");
  assert.equal(exposed.rows[0].activePublicId,"@DEDA-AAAA");
});
