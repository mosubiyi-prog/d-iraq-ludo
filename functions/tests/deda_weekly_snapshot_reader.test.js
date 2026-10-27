"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {readFutureWeeklyStandings,verifyAndRedactSnapshot,validateServerCalendar}=
  require("../deda_weekly_snapshot_reader_NOT_EXPORTED.js");

const START=Date.UTC(2026,9,27,0);
const WEEK=7*86400000;
const NOW=START+2*86400000;
const CURRENT={weekId:"server-week-c",startMs:START,endMs:START+WEEK};
const PREVIOUS={weekId:"server-week-p",startMs:START-WEEK,endMs:START};
const UID="anonymous_test_uid",ACCOUNT="07700000012";
const CONFIG={
  issuer:"privileged_server_only_week_calendar_v1",
  activeWeekId:CURRENT.weekId,activeStartMs:CURRENT.startMs,
  activeEndMs:CURRENT.endMs,previousWeekId:PREVIOUS.weekId,
  previousStartMs:PREVIOUS.startMs,previousEndMs:PREVIOUS.endMs,
};
function rows(kind="current",num=12) {
  return Array.from({length:num},(_,i)=>({
    place:i+1,
    accountKey:"077"+String(i+1).padStart(8,"0"),
    publicCompetitorId:"leader-participant-"+String(i+1).padStart(5,"0"),
    displayName:"مستخدم "+String(i+1),
    activePublicId:"@DEDA-AA"+String(i+1).padStart(4,"0"),
    earnedLevelXp:(num-i)*20,taskClaims:num-i,
    lastEarnedAtMs:(kind==="previous"?PREVIOUS.startMs:CURRENT.startMs)+1000+i*100,
    potentialDiamonds:i===0?150:i===1?100:i===2?50:i<10?10:0,
  }));
}
function snapshot(kind="current",num=12) {
  return {issuer:"privileged_server_only_weekly_ranker_v1",
    weekId:kind==="current"?CURRENT.weekId:PREVIOUS.weekId,
    state:kind==="current"?"live":"closed",
    generatedAtMs:kind==="current"?NOW-1000:PREVIOUS.endMs-1,
    rows:rows(kind,num),
  };
}
function docs({noAttestation=false}={}) {
  const items=new Map([
    ["users/"+UID,{accountKey:ACCOUNT,uid:UID}],
    ["deda_sessions/"+UID,{accountKey:ACCOUNT,uid:UID,installId:"test_install_1"}],
    ["deda_account_profiles/"+ACCOUNT,{accountKey:ACCOUNT,trustedInstallIds:["test_install_1"]}],
    ["deda_weekly_competition_config/current",CONFIG],
    ["deda_weekly_standings/"+CURRENT.weekId,snapshot()],
    ["deda_weekly_standings/"+PREVIOUS.weekId,snapshot("previous")],
  ]);
  if(!noAttestation)items.set("deda_weekly_identity_attestations/"+UID,{
    issuer:"privileged_identity_verifier_v1",
    uid:UID,accountKey:ACCOUNT,installId:"test_install_1",
    state:"verified",issuedAtMs:NOW-1000,expiresAtMs:NOW+1000,
  });
  return items;
}
function store(map) {
  let reads=0;
  return {get reads(){return reads},doc(key) {
    return {async get(){
      reads++;
      const d=map.get(key);
      return d?{exists:true,data:()=>structuredClone(d)}:{exists:false};
    }};
  }};
}
const REQUEST={auth:{uid:UID},app:{appId:"valid_attested_app_id"},data:{}};

test("future issued snapshots show top ten plus viewer place 12, no private account keys",async()=>{
  const response=await readFutureWeeklyStandings({
    db:store(docs()),request:REQUEST,serverNowMs:NOW,
  });
  assert.equal(response.readOnly,true);
  assert.equal(response.current.rows.length,11);
  assert.equal(response.current.viewerPlace,12);
  assert.equal(response.current.rows[10].place,12);
  assert.equal(response.current.rows[10].weeklyPoints,20);
  assert.equal(response.current.rows[10].diamondsIfFinalWinner,0);
  assert.equal(response.current.rows[0].diamondsIfFinalWinner,150);
  assert.equal(response.current.rows[9].diamondsIfFinalWinner,10);
  assert.equal(response.current.remainingMs,CURRENT.endMs-NOW);
  assert.equal(response.previous.remainingMs,0);
  const safe=JSON.stringify(response);
  assert.ok(!safe.includes(ACCOUNT));
  assert.ok(!safe.includes(UID));
  assert.ok(!safe.includes("install"));
  assert.equal(response.current.viewerParticipantId,
    "leader-participant-00012");
});
test("no authorized attestation means no user-specific results",async()=>{
  await assert.rejects(readFutureWeeklyStandings({
    db:store(docs({noAttestation:true})),
    request:REQUEST,serverNowMs:NOW,
  }),/verified_document_missing/);
});
test("cannot submit client claimed week, phone or XP",async()=>{
  for(const name of ["accountKey","uid","weeklyPoints","weekId","diamonds"]){
    await assert.rejects(readFutureWeeklyStandings({
      db:store(docs()),request:{...REQUEST,data:{[name]:123}},
      serverNowMs:NOW,
    }),/client_input_forbidden/);
  }
});
test("previous week must be contiguous and active week contains server clock",()=>{
  assert.deepEqual(validateServerCalendar(CONFIG,NOW),
    {current:CURRENT,previous:PREVIOUS});
  assert.throws(()=>validateServerCalendar({
    ...CONFIG,previousEndMs:START-1,
  },NOW),/week_duration|week_boundary/);
  assert.throws(()=>validateServerCalendar({
    ...CONFIG,issuer:"device",
  },NOW),/unapproved_calendar/);
  assert.throws(()=>validateServerCalendar(CONFIG,START+WEEK),
    /week_boundary/);
});
test("duplicate account across devices is blocked instead of receiving two ranking rows",()=>{
  const s=snapshot();
  s.rows[1].accountKey=s.rows[0].accountKey;
  assert.throws(()=>verifyAndRedactSnapshot(s,CURRENT,ACCOUNT,NOW,"current"),
    /rank_invalid/);
});
test("duplicate public competitor aliases cannot bypass duplicate rank checks",()=>{
  const s=snapshot();
  s.rows[1].publicCompetitorId=s.rows[0].publicCompetitorId;
  assert.throws(()=>verifyAndRedactSnapshot(s,CURRENT,ACCOUNT,NOW,"current"),
    /rank_invalid/);
});
test("malicious phone number, email and control-character names are rejected",()=>{
  for(const name of ["07712345678","john@example.test","x\nleak"]){
    const s=snapshot();s.rows[0].displayName=name;
    assert.throws(()=>verifyAndRedactSnapshot(s,CURRENT,ACCOUNT,NOW,"current"),
      /private_or_invalid_name|name/);
  }
});
test("rank sorting and server-supplied prize amount must agree with audited policy",()=>{
  const a=snapshot();
  a.rows[1].earnedLevelXp=a.rows[0].earnedLevelXp+20;
  a.rows[1].taskClaims=a.rows[0].taskClaims+1;
  assert.throws(()=>verifyAndRedactSnapshot(a,CURRENT,ACCOUNT,NOW,"current"),
    /ordering_mismatch/);
  const b=snapshot(); b.rows[2].potentialDiamonds=5000;
  assert.throws(()=>verifyAndRedactSnapshot(b,CURRENT,ACCOUNT,NOW,"current"),
    /prize_mismatch/);
  const c=snapshot();c.rows[0].earnedLevelXp=250;
  assert.throws(()=>verifyAndRedactSnapshot(c,CURRENT,ACCOUNT,NOW,"current"),
    /rank_invalid/);
});
test("unknown/untrusted rank issuer and stale current snapshots fail CLOSED",()=>{
  const untrusted=snapshot();untrusted.issuer="client_code";
  assert.throws(()=>verifyAndRedactSnapshot(untrusted,CURRENT,ACCOUNT,NOW,"current"),
    /snapshot_provenance/);
  const stale=snapshot();stale.generatedAtMs=NOW-10*60000;
  assert.throws(()=>verifyAndRedactSnapshot(stale,CURRENT,ACCOUNT,NOW,"current"),
    /snapshot_provenance/);
});
test("inconsistent rank number is rejected, no invented positions",()=>{
  const wrong=snapshot();wrong.rows[3].place=5;
  assert.throws(()=>verifyAndRedactSnapshot(wrong,CURRENT,ACCOUNT,NOW,"current"),
    /rank_invalid/);
});
test("viewer without earned XP is omitted, but server-issued top ten remain visible",()=>{
  const s=snapshot("current",10);
  const result=verifyAndRedactSnapshot(s,CURRENT,ACCOUNT,NOW,"current");
  assert.equal(result.viewerPlace,null);
  assert.equal(result.viewerParticipantId,null);
  assert.equal(result.rows.length,10);
});
test("past week cannot be rebranded live and current week cannot be tagged closed",()=>{
  const a=snapshot("previous");
  a.state="live";
  assert.throws(()=>verifyAndRedactSnapshot(a,PREVIOUS,ACCOUNT,NOW,"previous"),
    /snapshot_provenance/);
  const b=snapshot();
  b.state="closed";
  assert.throws(()=>verifyAndRedactSnapshot(b,CURRENT,ACCOUNT,NOW,"current"),
    /snapshot_provenance/);
});
test("read-only model contains no diamond balance payment or XP mutation",async()=>{
  const db=store(docs());
  const response=await readFutureWeeklyStandings({
    db,request:REQUEST,serverNowMs:NOW,
  });
  assert.ok(db.reads>=7);
  assert.equal(typeof db.runTransaction,"undefined");
  assert.equal(response.current.rewardsCredited,false);
  assert.equal(response.previous.rewardsCredited,false);
});

test("verified premium four-letter ID survives stage7 redaction",()=>{
  const sample=snapshot("current",1);
  sample.rows[0].activePublicId="@DEDA-ABAB";
  const safe=verifyAndRedactSnapshot(sample,CURRENT,ACCOUNT,NOW,"current");
  assert.equal(safe.rows[0].activePublicId,"@DEDA-ABAB");
});
