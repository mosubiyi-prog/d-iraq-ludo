"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore}=require("firebase-admin/firestore");
const {
  PROJECT,ROOT,privateWalletId,simulateShadowWeekPrizes,
}=require("../deda_weekly_prize_shadow_settlement_NOT_EXPORTED.js");

if (!process.env.FIRESTORE_EMULATOR_HOST ||
    process.env.GCLOUD_PROJECT!==PROJECT) {
  throw Error("STAGE12_LOCAL_FIRESTORE_EMULATOR_REQUIRED_NEVER_REAL_DATABASE");
}
const APP=initializeApp({projectId:PROJECT},"deda_stage12_local_prize_qa");
const db=getFirestore(APP);
const SECRET=Buffer.alloc(32,63),WEEK_MS=7*86400000;
const NOW=Date.UTC(2026,10,3,10);
const BASE=Date.UTC(2026,9,26,21);
const WEEK_A={weekId:"approved-demo-week-a",
  startMs:BASE,endMs:BASE+WEEK_MS};
const WEEK_B={weekId:"approved-demo-week-b",
  startMs:BASE-WEEK_MS,endMs:BASE};
const REWARDS=[150,100,50,10,10,10,10,10,10,10];
const ACCOUNTS=Array.from({length:12},(_,i)=>"077"+String(i+1).padStart(8,"0"));
const UID1="original_user_phone_1",UID2="original_user_phone_2";
const originals={
  xp:1200,level:14,earnedDiamonds:987,managerBalance:1000000,
  giftedBalance:170,legacyTaskPoints:250,
};
const originalRef=db.doc("users/"+UID1);
const nextPhoneRef=db.doc("users/"+UID2);

function closed(week,count=12) {
  return {
    issuer:"privileged_server_only_weekly_ranker_v1",
    shadowFixtureOnly:true,state:"closed",weekId:week.weekId,
    generatedAtMs:week.endMs-1,
    rows:ACCOUNTS.slice(0,count).map((accountKey,i)=>({
      place:i+1,accountKey,
      publicCompetitorId:"leader-participant-"+String(i+1).padStart(5,"0"),
      displayName:"متسابق "+(i+1),
      activePublicId:"@DEDA-AA"+String(i+1).padStart(4,"0"),
      earnedLevelXp:(count-i)*20,taskClaims:count-i,
      lastEarnedAtMs:week.startMs+1000+i*1000,
      potentialDiamonds:REWARDS[i]||0,
    })),
  };
}
async function seedWeek(week,rows=12) {
  await db.doc(ROOT.snapshot+"/"+week.weekId).set(closed(week,rows));
}
function execute(week,serverNowMs=NOW,extras={}) {
  return simulateShadowWeekPrizes({
    db,serverNowMs,weekConfig:week,backendSecret:SECRET,...extras,
  });
}
async function wallet(account) {
  return db.doc(ROOT.wallet+"/"+privateWalletId(account,SECRET)).get();
}
test.after(async()=>{await deleteApp(APP);});

test("original DEDA wallet fixtures stay UNCHANGED during all payout tests",async()=>{
  await originalRef.set({accountKey:ACCOUNTS[0],...originals});
  await nextPhoneRef.set({accountKey:ACCOUNTS[0],...originals});
  await db.doc("deda_admin_diamond_wallets/admin_fixture").set({
    balance:1000000,initialBalance:1000000,
  });
});
test("exactly 370 shadow earned diamonds for ten ranks; eleventh/twelfth get none",async()=>{
  await seedWeek(WEEK_A);
  const pre=await originalRef.get();
  const result=await execute(WEEK_A);
  assert.deepEqual(result,{
    outcome:"shadow_settled",shadowDiamondsAdded:370,
    winnerCount:10,shadowOnly:true,
  });
  const ledger=await db.doc(ROOT.settlement+"/"+WEEK_A.weekId).get();
  assert.equal(ledger.get("totalDiamonds"),370);
  assert.equal(ledger.get("winnerCount"),10);
  const paid=await db.collection(ROOT.receipt).get();
  assert.equal(paid.size,10);
  for(let i=0;i<10;i++){
    const doc=await wallet(ACCOUNTS[i]);
    assert.equal(doc.get("shadowOnly"),true);
    assert.equal(doc.get("earnedPrizeDiamonds"),REWARDS[i]);
    assert.equal(doc.get("lastWeekId"),WEEK_A.weekId);
  }
  for(let i=10;i<12;i++){
    const doc=await wallet(ACCOUNTS[i]);
    assert.equal(doc.exists,false);
  }
  assert.deepEqual((await originalRef.get()).data(),pre.data());
  assert.deepEqual((await nextPhoneRef.get()).data(),pre.data());
  assert.equal((await db.doc("deda_admin_diamond_wallets/admin_fixture")
    .get()).get("balance"),1000000);
});
test("two competing retries settle the same week exactly once",async()=>{
  const outputs=await Promise.all([execute(WEEK_A),execute(WEEK_A)]);
  assert.deepEqual(outputs.map(x=>x.outcome),
    ["already_settled","already_settled"]);
  assert.equal(outputs.reduce((v,x)=>v+x.shadowDiamondsAdded,0),0);
  assert.equal((await db.collection(ROOT.receipt).get()).size,10);
  assert.equal((await wallet(ACCOUNTS[0])).get("earnedPrizeDiamonds"),150);
});
test("another CLOSED week can award, but never erase earlier earned mock prizes",async()=>{
  await seedWeek(WEEK_B);
  const result=await execute(WEEK_B);
  assert.equal(result.shadowDiamondsAdded,370);
  assert.equal(result.winnerCount,10);
  assert.equal((await db.collection(ROOT.receipt).get()).size,20);
  assert.equal((await wallet(ACCOUNTS[0])).get("earnedPrizeDiamonds"),300);
  assert.equal((await wallet(ACCOUNTS[1])).get("earnedPrizeDiamonds"),200);
  assert.equal((await originalRef.get()).get("earnedDiamonds"),987);
  assert.equal((await originalRef.get()).get("managerBalance"),1000000);
});
test("no payouts for open week, tampered rankings, replay changed snapshots",async()=>{
  const opened={weekId:"still-open-test-week",
    startMs:BASE+WEEK_MS,endMs:BASE+WEEK_MS*2};
  await seedWeek(opened);
  await assert.rejects(execute(opened,opened.startMs+2000),
    /week_not_closed/);

  const tampered={...closed(WEEK_A)};
  tampered.rows=[...tampered.rows];
  tampered.rows[0]={...tampered.rows[0],potentialDiamonds:5000};
  await db.doc(ROOT.snapshot+"/"+WEEK_A.weekId).set(tampered);
  await assert.rejects(execute(WEEK_A),
    /prize_mismatch|immutable_closed_fixture_required/);
  await db.doc(ROOT.snapshot+"/"+WEEK_A.weekId).set(closed(WEEK_A));
  const replay=await execute(WEEK_A);
  assert.equal(replay.outcome,"already_settled");
  const changed=closed(WEEK_A);
  changed.rows[0].displayName="اسم جديد";
  await db.doc(ROOT.snapshot+"/"+WEEK_A.weekId).set(changed);
  await assert.rejects(execute(WEEK_A),
    /already_settled_snapshot_changed/);
  await db.doc(ROOT.snapshot+"/"+WEEK_A.weekId).set(closed(WEEK_A));
  assert.equal((await db.collection(ROOT.receipt).get()).size,20);
});
test("no fake 5-point traffic answer, missing snapshot or client-selected wallet/amount",async()=>{
  const empty={weekId:"empty-demo-week",startMs:BASE-2*WEEK_MS,
    endMs:BASE-WEEK_MS};
  await assert.rejects(execute(empty),/snapshot_missing/);
  const invalid=closed(empty,1);
  invalid.rows[0].earnedLevelXp=5;
  invalid.rows[0].taskClaims=1;
  await db.doc(ROOT.snapshot+"/"+empty.weekId).set(invalid);
  await assert.rejects(execute(empty),/rank_invalid/);
  for(const bad of [
    {accountKey:ACCOUNTS[0]},{diamonds:999999},
    {wallet:"deda_admin_diamond_wallets"},{rank:1},
    {phone:"07712345678"},{clientXP:9000},
  ]) {
    await assert.rejects(execute(WEEK_A,NOW,bad),
      /client_or_unreviewed_input/);
  }
});
test("missing private backend HMAC secret and production environment ALWAYS blocked",async()=>{
  await assert.rejects(simulateShadowWeekPrizes({
    db,serverNowMs:NOW,weekConfig:WEEK_A,
    backendSecret:Buffer.alloc(4),
  }),/backend_only_secret/);
  await assert.rejects(simulateShadowWeekPrizes({
    db,serverNowMs:NOW,weekConfig:WEEK_A,
    backendSecret:"hardcoded user password",
  }),/backend_only_secret/);
  const previous=process.env.GCLOUD_PROJECT;
  process.env.GCLOUD_PROJECT="real-deda";
  try{
    await assert.rejects(execute(WEEK_A),
      /emulator_only_no_real_wallet/);
  } finally { process.env.GCLOUD_PROJECT=previous; }
});
