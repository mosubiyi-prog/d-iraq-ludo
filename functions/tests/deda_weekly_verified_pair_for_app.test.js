"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const {projectVerifiedWeekPairForApp} =
  require("../deda_weekly_verified_pair_for_app_NOT_EXPORTED.js");
const {opaqueReceiptId} =
  require("../deda_weekly_owner_receipt_gate_NOT_EXPORTED.js");

const NOW = Date.UTC(2026,9,27,11);
const START = Date.UTC(2026,9,26,21);
const CURRENT = {weekId:"owner-approved-test-current",startMs:START,
  endMs:START + 7*86400000};
const PREVIOUS = {weekId:"owner-approved-test-previous",
  startMs:START - 7*86400000,endMs:START};
const A = "07712345678", B = "07701234567";
const UID1 = "anonymous_owner_phone_1", UID2 = "anonymous_owner_phone_2";
const KEY = Buffer.alloc(32,37);
const CALENDAR = {
  issuer:"privileged_server_only_week_calendar_v1",
  activeWeekId:CURRENT.weekId,activeStartMs:CURRENT.startMs,
  activeEndMs:CURRENT.endMs,
  previousWeekId:PREVIOUS.weekId,previousStartMs:PREVIOUS.startMs,
  previousEndMs:PREVIOUS.endMs,
};
const REQUEST1={auth:{uid:UID1},app:{appId:"test_app_check"},
  data:{}};
const REQUEST2={auth:{uid:UID2},app:{appId:"test_app_check"},
  data:{}};

function record(account, task, week=CURRENT,at=NOW-5000,day="2026-10-27") {
  const id=opaqueReceiptId({accountKey:account,dayId:day,taskId:task});
  return {id,data:{
    issuer:"privileged_server_only_task_xp_issuer_v1",
    status:"final_award_committed",
    accountKey:account,taskId:task,dayId:day,weekId:week.weekId,
    receiptId:id,taskPointsAwarded:true,levelXpApplied:true,
    levelXpAmount:20,verifiedAtMs:at,
  }};
}
function makeFixtures() {
  const docs=new Map([
    ["deda_weekly_competition_config/current",structuredClone(CALENDAR)],
    ["deda_account_profiles/"+A,{accountKey:A,
      trustedInstallIds:["phone-install-1","phone-install-2"]}],
  ]);
  for(const [uid,install] of [[UID1,"phone-install-1"],
      [UID2,"phone-install-2"]]){
    docs.set("users/"+uid,{uid,accountKey:A});
    docs.set("deda_sessions/"+uid,{uid,accountKey:A,installId:install});
    docs.set("deda_weekly_identity_attestations/"+uid,{
      issuer:"privileged_identity_verifier_v1",state:"verified",
      uid,accountKey:A,installId:install,
      issuedAtMs:NOW-1000,expiresAtMs:NOW+60000,
    });
  }
  for(const [account,activePublicId,displayName] of [
    [A,"@DEDA-A12345","لاعب بغداد"],
    [B,"@DEDA-B12345","لاعب كركوك"],
  ]) {
    const hash=crypto.createHash("sha256").update(account).digest("hex");
    docs.set("deda_weekly_public_profiles/"+hash,{
      issuer:"privileged_server_only_public_profile_v1",
      state:"verified",accountKey:account,activePublicId,displayName,
    });
  }
  const events=new Map([
    [CURRENT.weekId,[
      record(A,"open_map",CURRENT,NOW-6000),
      record(A,"traffic_skills",CURRENT,NOW-5000),
      record(B,"open_map",CURRENT,NOW-4000),
    ]],
    [PREVIOUS.weekId,[
      record(A,"share_location",PREVIOUS,Date.UTC(2026,9,25,11),
        "2026-10-25"),
      record(B,"open_map",PREVIOUS,Date.UTC(2026,9,25,12),
        "2026-10-25"),
      record(B,"traffic_skills",PREVIOUS,Date.UTC(2026,9,25,13),
        "2026-10-25"),
    ]],
  ]);
  return {docs,events};
}
function fakeAdminDb(fixture) {
  let readCount=0,writeCount=0;
  return {
    get readCount(){return readCount},
    get writeCount(){return writeCount},
    doc(path){
      return {async get(){
        readCount++;
        const data=fixture.docs.get(path);
        return data ? {exists:true,data:()=>structuredClone(data)}
          : {exists:false};
      }};
    },
    collection(name){
      assert.equal(name,"deda_weekly_xp_receipts");
      return {doc(weekId){
        return {collection(path){
          assert.equal(path,"events");
          return {async get(){
            readCount++;
            const events=fixture.events.get(weekId);
            if(!events)throw Error("missing server receipt list");
            return {docs:events.map(x=>({
              id:x.id,data:()=>structuredClone(x.data),
            }))};
          }};
        }};
      }};
    },
    async runTransaction(){writeCount++;throw Error("write forbidden")},
    async set(){writeCount++;throw Error("write forbidden")},
    async update(){writeCount++;throw Error("write forbidden")},
  };
}
function call(db,request=REQUEST1){
  return projectVerifiedWeekPairForApp({
    db,request,serverNowMs:NOW,rankerKey:KEY,
  });
}

test("original app DTO: both weeks, actual-formatted winner order and earned LEVEL XP",async()=>{
  const db=fakeAdminDb(makeFixtures());
  const response=await call(db);
  assert.equal(response.source,"future_server_issued_only");
  assert.equal(response.readOnly,true);
  assert.equal(response.current.status,"live");
  assert.equal(response.previous.status,"closed");
  assert.deepEqual(response.current.rows.map(x=>x.weeklyPoints),[40,20]);
  assert.deepEqual(response.previous.rows.map(x=>x.weeklyPoints),[40,20]);
  assert.equal(response.current.rows[0].displayName,"لاعب بغداد");
  assert.equal(response.previous.rows[0].displayName,"لاعب كركوك");
  assert.equal(response.current.viewerPlace,1);
  assert.equal(response.previous.viewerPlace,2);
  assert.equal(response.current.rows[0].diamondsIfFinalWinner,150);
  assert.equal(response.current.rows[1].diamondsIfFinalWinner,100);
  assert.equal(response.current.rewardsCredited,false);
  assert.equal(response.previous.rewardsCredited,false);
  assert.equal(db.writeCount,0);
  assert.ok(db.readCount>=11);
  const packet=JSON.stringify(response);
  for(const privateValue of [A,B,UID1,UID2,"accountKey","installId",
      "trustedInstallIds","managerBalance","giftedBalance"]){
    assert.ok(!packet.includes(privateValue),
      "leaked private field "+privateValue);
  }
});
test("same original DEDA account on two phones is one competitor, not two",async()=>{
  const fixture=makeFixtures(),db=fakeAdminDb(fixture);
  const first=await call(db,REQUEST1);
  const second=await call(db,REQUEST2);
  assert.deepEqual(first.current.rows,second.current.rows);
  assert.equal(first.current.viewerParticipantId,
    second.current.viewerParticipantId);
  assert.equal(second.current.weeklyPoints,undefined);
  assert.equal(db.writeCount,0);
});
test("missing owner attestation fails closed without any fake ranking",async()=>{
  const f=makeFixtures();
  f.docs.delete("deda_weekly_identity_attestations/"+UID1);
  await assert.rejects(call(fakeAdminDb(f)),
    /verified_document_missing/);
});
test("server calendar must be explicitly issued, contiguous and current",async()=>{
  for(const mutation of [
    {issuer:"device_selected_week"},
    {previousEndMs:PREVIOUS.endMs-1},
    {activeStartMs:CURRENT.startMs-86400000},
  ]) {
    const f=makeFixtures();
    f.docs.set("deda_weekly_competition_config/current",
      {...CALENDAR,...mutation});
    await assert.rejects(call(fakeAdminDb(f)),
      /week_duration|week_boundary|unapproved_calendar/);
  }
});
test("unverified quiz, fake XP or missing previous week never shows live ranking",async()=>{
  for(const mutation of [
    {levelXpAmount:5},{levelXpApplied:false},
    {status:"client_claimed"},{issuer:"emulator_fixture_only_verified_task_v1"},
  ]) {
    const f=makeFixtures();
    f.events.get(PREVIOUS.weekId)[0].data={
      ...f.events.get(PREVIOUS.weekId)[0].data,...mutation,
    };
    await assert.rejects(call(fakeAdminDb(f)),
      /DEDA_STAGE10_WEEKLY_RANK_BLOCK_/);
  }
  const f=makeFixtures();
  f.events.delete(PREVIOUS.weekId);
  await assert.rejects(call(fakeAdminDb(f)),/missing server receipt list/);
});
test("client-submitted phone, diamonds, rank and points are prohibited",async()=>{
  for(const data of [
    {accountKey:A},{xp:1000000},{diamonds:370},
    {weekId:CURRENT.weekId},{viewerRank:1},
  ]){
    const db=fakeAdminDb(makeFixtures());
    await assert.rejects(call(db,{...REQUEST1,data}),
      /client_input_forbidden/);
    assert.equal(db.writeCount,0);
  }
});
test("backend HMAC secret cannot be absent, short or handset-supplied",async()=>{
  for(const rankerKey of [null,Buffer.alloc(2),"from_user_phone"]){
    const db=fakeAdminDb(makeFixtures());
    await assert.rejects(projectVerifiedWeekPairForApp({
      db,request:REQUEST1,serverNowMs:NOW,rankerKey,
    }),/private_ranker_secret_missing/);
    assert.equal(db.writeCount,0);
  }
});
