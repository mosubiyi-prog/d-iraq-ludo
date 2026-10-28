"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {
  WEEK_MS,FREEZE_MS,PROJECT,SOURCE,PRIZES,
  clockState,windowFor,previewFrozenResult,previewWinnerCard,
  acknowledgeFixtureWinnerCard,
}=require("../deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");

const ANCHOR=Date.UTC(2026,9,27,3); // Tue 2026-10-27, 06:00 Baghdad; NOT a prescribed weekday
const W=windowFor(ANCHOR,0);
const AT_CLOSE=W.closeAtMs;
const AT_OPEN=W.nextOpenMs;
const A="qa-player-"+"A".repeat(25);
const B="qa-player-"+"B".repeat(25);
const C="qa-player-"+"C".repeat(25);
const ROWS=[
  {place:1,participantId:A,weeklyXp:100,verifiedTaskCount:5,
    reachedAtMs:W.openedAtMs+10*60000},
  {place:2,participantId:B,weeklyXp:80,verifiedTaskCount:4,
    reachedAtMs:W.openedAtMs+20*60000},
  {place:3,participantId:C,weeklyXp:60,verifiedTaskCount:3,
    reachedAtMs:W.openedAtMs+30*60000},
];
function snapshot(rows=ROWS,changes={}){
  return {source:SOURCE,emulatorOnly:true,weekId:W.weekId,
    sealedAtMs:AT_CLOSE,rows,...changes};
}
function gift(participantId,place,status="pending",changes={}){
  return {source:SOURCE,emulatorOnly:true,weekId:W.weekId,
    participantId,place,diamonds:PRIZES[place-1],status,...changes};
}
function card({viewerParticipantId=A,rows=ROWS,now=AT_OPEN,
  receipt=gift(A,1),acknowledged=false}={}){
  return previewWinnerCard({firstOpenMs:ANCHOR,weekIndex:0,
    serverNowMs:now,snapshot:snapshot(rows),viewerParticipantId,
    giftReceipt:receipt,acknowledged});
}
test("arbitrary first launch weekday, canonical Baghdad 06:00 and exact week",()=>{
  assert.equal(W.weekIndex,0);
  assert.equal(WEEK_MS,604800000);
  assert.equal(FREEZE_MS,21600000);
  assert.equal(W.closeAtMs,ANCHOR+WEEK_MS-FREEZE_MS);
  assert.equal(W.nextOpenMs,ANCHOR+WEEK_MS);
  assert.equal(windowFor(ANCHOR,1).openedAtMs,W.nextOpenMs);
  assert.notEqual(windowFor(ANCHOR,1).weekId,W.weekId);
  assert.throws(()=>windowFor(ANCHOR+1000,0),/first_open/);
  assert.throws(()=>windowFor(ANCHOR+3600000,0),/first_open/);
});
test("23:59:59 eligible; 00:00 freezes; 05:59:59 frozen; 06:00 next round",()=>{
  const before=clockState({firstOpenMs:ANCHOR,serverNowMs:AT_CLOSE-1});
  assert.equal(before.phase,"active");
  assert.equal(before.leagueScoringAllowed,true);
  for(const when of [AT_CLOSE,AT_OPEN-1]){
    const s=clockState({firstOpenMs:ANCHOR,serverNowMs:when});
    assert.equal(s.phase,"frozen");
    assert.equal(s.leagueScoringAllowed,false);
    assert.equal(s.displayedResultWeekId,W.weekId);
  }
  const after=clockState({firstOpenMs:ANCHOR,serverNowMs:AT_OPEN});
  assert.equal(after.phase,"active");
  assert.equal(after.leagueScoringAllowed,true);
  assert.equal(after.previous.weekId,W.weekId);
  assert.equal(after.current.weekIndex,1);
  assert.equal(after.displayedResultWeekId,W.weekId);
  assert.equal(clockState({firstOpenMs:ANCHOR,serverNowMs:ANCHOR-1})
    .phase,"not_started");
});
test("frozen immutable fixture ranks retain rank and 150/100/50 without paying",()=>{
  const first=previewFrozenResult({firstOpenMs:ANCHOR,weekIndex:0,
    serverNowMs:AT_CLOSE,snapshot:snapshot()});
  const later=previewFrozenResult({firstOpenMs:ANCHOR,weekIndex:0,
    serverNowMs:AT_OPEN,snapshot:snapshot()});
  assert.deepEqual(first,later);
  assert.deepEqual(first.rows.map(x=>x.plannedDiamonds),[150,100,50]);
  assert.equal(first.payoutEnabled,false);
  assert.equal(first.previewOnly,true);
  assert.ok(Object.isFrozen(first.rows));
});
test("reject premature, forged, reordered, duplicate and private identity fields",()=>{
  const common={firstOpenMs:ANCHOR,weekIndex:0,serverNowMs:AT_CLOSE};
  assert.throws(()=>previewFrozenResult({...common,
    serverNowMs:AT_CLOSE-1,snapshot:snapshot()}),/before_close/);
  assert.throws(()=>previewFrozenResult({...common,
    snapshot:snapshot(ROWS,{source:"real_live_winners"})}),/not_an_immutable/);
  assert.throws(()=>previewFrozenResult({...common,
    snapshot:snapshot(ROWS,{sealedAtMs:AT_CLOSE-1})}),/not_an_immutable/);
  assert.throws(()=>previewFrozenResult({...common,
    snapshot:snapshot([...ROWS].reverse())}),/untrusted_rank_row/);
  assert.throws(()=>previewFrozenResult({...common,
    snapshot:snapshot([ROWS[0],{...ROWS[1],participantId:A}])}),/untrusted_rank_row/);
  assert.throws(()=>previewFrozenResult({...common,
    snapshot:snapshot([{...ROWS[0],name:"secret"}])}),/untrusted_rank_row/);
  assert.throws(()=>previewFrozenResult({...common,
    snapshot:snapshot([ROWS[0],{...ROWS[1],weeklyXp:120}])}),/incorrect_frozen_order/);
  assert.throws(()=>previewFrozenResult({...common,
    snapshot:snapshot([{...ROWS[0],reachedAtMs:AT_CLOSE}])}),/untrusted_rank_row/);
});
test("winner card only post-six and only with exact matching gift fixture",()=>{
  assert.equal(card({now:AT_OPEN-1}),null);
  assert.equal(card({viewerParticipantId:C,receipt:gift(C,3)})
    ?.rankText,"المركز الثالث 🥉");
  assert.equal(card({viewerParticipantId:B,receipt:gift(B,2)})
    ?.prizeText,"100 💎");
  assert.equal(card({viewerParticipantId:C,receipt:gift(C,3)})
    ?.prizeText,"50 💎");
  assert.equal(card({viewerParticipantId:"qa-player-"+"Z".repeat(25)}),null);
  assert.equal(card({receipt:gift(A,1,"unverified")}),null);
  assert.equal(card({receipt:gift(A,1,"pending",{diamonds:999999})}),null);
  assert.equal(card({receipt:null}),null);
  assert.equal(card({acknowledged:true}),null);
  assert.equal(card({receipt:gift(A,1,"received")})?.rankText,
    "المركز الأول 🥇");
});
test("exact owner-approved visible text and palette, no username, ID or photo",()=>{
  const c=card();
  assert.ok(c);
  assert.equal(c.title,"تهانينا يا بطل DEDA!");
  assert.equal(c.intro,"لقد حققت إنجازاً رائعاً في دوري المتصدرين الأسبوعي");
  assert.equal(c.rankLabel,"مركزك النهائي");
  assert.equal(c.rankText,"المركز الأول 🥇");
  assert.equal(c.prizeText,"150 💎");
  assert.equal(c.prizeLabel,"جائزتك الأسبوعية");
  assert.equal(c.footer,"شكراً لمشاركتك وتميّزك! استمر بالتحدي، فالدوري الجديد بدأ الآن.");
  assert.equal(c.primary,"🎁 الذهاب إلى هداياي");
  assert.equal(c.secondary,"مشاهدة نتائج الأسبوع");
  assert.equal(c.close,"إغلاق");
  assert.equal(c.background,"#101C35");
  assert.equal(c.innerBackground,"#233651");
  assert.equal(c.gold,"#F7CB65");
  for(const field of ["name","displayName","id","publicId","avatar","photo",
    "profile","participantId","accountKey","weekId"]){
    assert.equal(Object.hasOwn(c,field),false,field+" leaked to card");
  }
  assert.equal(c.canClaimAutomatically,false);
  assert.equal(c.creditsMade,0);
});
test("places four and ten show exactly 10 diamonds, eleven has no card",()=>{
  const rows=Array.from({length:10},(_,i)=>({
    place:i+1,participantId:"qa-player-"+String(i).padStart(25,"X"),
    weeklyXp:200-i*20,verifiedTaskCount:10-i,
    reachedAtMs:ANCHOR+(i+1)*60000,
  }));
  const snap=snapshot(rows);
  for(const place of [4,10]){
    const participantId=rows[place-1].participantId;
    const c=previewWinnerCard({firstOpenMs:ANCHOR,weekIndex:0,
      serverNowMs:AT_OPEN,snapshot:snap,viewerParticipantId:participantId,
      giftReceipt:gift(participantId,place)});
    assert.equal(c.prizeText,"10 💎");
  }
  const loser="qa-player-"+"Z".repeat(25);
  assert.equal(previewWinnerCard({firstOpenMs:ANCHOR,weekIndex:0,
    serverNowMs:AT_OPEN,snapshot:snap,viewerParticipantId:loser,
    giftReceipt:gift(loser,10)}),null);
});
test("next week and year/month rollovers leave original week frozen and distinct",()=>{
  const next=windowFor(ANCHOR,1);
  const nextAfter=clockState({firstOpenMs:ANCHOR,serverNowMs:next.closeAtMs});
  assert.equal(nextAfter.displayedResultWeekId,next.weekId);
  assert.notEqual(nextAfter.displayedResultWeekId,W.weekId);
  const december=Date.UTC(2026,11,30,3);
  const year=windowFor(december,1);
  assert.equal(year.openedAtMs,Date.UTC(2027,0,6,3));
});
test("attempting acknowledgement outside dedicated emulator refuses",async()=>{
  const oldProject=process.env.GCLOUD_PROJECT;
  const oldEmulator=process.env.FIRESTORE_EMULATOR_HOST;
  process.env.GCLOUD_PROJECT="deda-25b88";
  delete process.env.FIRESTORE_EMULATOR_HOST;
  try{
    await assert.rejects(acknowledgeFixtureWinnerCard({
      db:{},firstOpenMs:ANCHOR,weekIndex:0,serverNowMs:AT_OPEN,
      snapshot:snapshot(),viewerParticipantId:A,giftReceipt:gift(A,1),
    }),/emulator_only/);
  } finally {
    if(oldProject===undefined)delete process.env.GCLOUD_PROJECT;
    else process.env.GCLOUD_PROJECT=oldProject;
    if(oldEmulator===undefined)delete process.env.FIRESTORE_EMULATOR_HOST;
    else process.env.FIRESTORE_EMULATOR_HOST=oldEmulator;
  }
});
test("real Firestore emulator: account/week-specific acknowledgement at most once",{
  skip:!(process.env.GCLOUD_PROJECT===PROJECT&&process.env.FIRESTORE_EMULATOR_HOST),
},async()=>{
  const {initializeApp,deleteApp}=require("firebase-admin/app");
  const {getFirestore}=require("firebase-admin/firestore");
  const app=initializeApp({projectId:PROJECT},"deda-stage31");
  try {
    const db=getFirestore(app);
    const args={db,firstOpenMs:ANCHOR,weekIndex:0,serverNowMs:AT_OPEN,
      snapshot:snapshot(),viewerParticipantId:A,giftReceipt:gift(A,1)};
    const [x,y]=await Promise.all([
      acknowledgeFixtureWinnerCard(args),acknowledgeFixtureWinnerCard(args)
    ]);
    assert.equal(Number(x.acknowledged)+Number(y.acknowledged),1);
    const z=await acknowledgeFixtureWinnerCard(args);
    assert.equal(z.alreadyAcknowledged,true);
    const original=await db.doc("deda_admin_diamond_wallets/manager").get();
    assert.equal(original.exists,false); // no manager or user wallet writes
  } finally {await deleteApp(app);}
});
