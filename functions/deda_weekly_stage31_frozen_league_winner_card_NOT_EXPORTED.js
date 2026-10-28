"use strict";
/**
 * DEDA stage31: a PURE calendar, frozen-result and winner-card contract, plus
 * an optional emulator-only acknowledgement transaction. NOT EXPORTED in
 * functions/index.js. NOT a real snapshot signer, player identifier verifier,
 * Cloud Function, prize grant, Firebase deployment, or playable Flutter UI.
 * All leaderboard/gift documents below are explicitly synthetic fixtures.
 */
const WEEK_MS=7*86400000;
const FREEZE_MS=6*3600000;
const PROJECT="demo-deda-weekly-xp-stage9";
const SOURCE="stage31_emulator_fixture_only";
const PRIZES=Object.freeze([150,100,50,10,10,10,10,10,10,10]);
const RANKS=Object.freeze(["الأول","الثاني","الثالث","الرابع",
  "الخامس","السادس","السابع","الثامن","التاسع","العاشر"]);
const MEDALS=Object.freeze([" 🥇"," 🥈"," 🥉"]);
const PARTICIPANT=/^qa-player-[A-Za-z0-9_-]{25}$/;
function block(reason){throw Error("DEDA_STAGE31_PRIVATE_BLOCK_"+reason);}
function validMs(n){return Number.isSafeInteger(n)&&n>=0;}
function localDateParts(ms){
  if(!validMs(ms))block("invalid_time");
  const formatter=new Intl.DateTimeFormat("en-GB",{
    timeZone:"Asia/Baghdad",calendar:"gregory",numberingSystem:"latn",
    year:"numeric",month:"2-digit",day:"2-digit",hour:"2-digit",
    minute:"2-digit",second:"2-digit",hourCycle:"h23"
  });
  const fields=Object.fromEntries(formatter.formatToParts(new Date(ms))
    .map(x=>[x.type,x.value]));
  return fields;
}
function requireAnchor(firstOpenMs){
  const p=localDateParts(firstOpenMs);
  if(p.hour!=="06"||p.minute!=="00"||p.second!=="00"||
     firstOpenMs%1000!==0)block("first_open_must_be_0600_baghdad");
  return firstOpenMs;
}
function windowFor(firstOpenMs,index){
  requireAnchor(firstOpenMs);
  if(!Number.isSafeInteger(index)||index<0||index>5000)
    block("week_index");
  const openedAtMs=firstOpenMs+index*WEEK_MS;
  const nextOpenMs=openedAtMs+WEEK_MS;
  if(!validMs(nextOpenMs))block("week_overflow");
  const closeAtMs=nextOpenMs-FREEZE_MS;
  const p=localDateParts(openedAtMs);
  const weekId="deda-"+p.year+p.month+p.day+"-w"+String(index+1).padStart(5,"0");
  return Object.freeze({weekIndex:index,weekId,openedAtMs,closeAtMs,
    nextOpenMs,prizeReleaseAtMs:nextOpenMs});
}
function clockState({firstOpenMs,serverNowMs}){
  requireAnchor(firstOpenMs);
  if(!validMs(serverNowMs))block("invalid_server_clock");
  if(serverNowMs<firstOpenMs)
    return Object.freeze({phase:"not_started",leagueScoringAllowed:false,
      nextOpenMs:firstOpenMs,current:null,previous:null});
  const index=Math.floor((serverNowMs-firstOpenMs)/WEEK_MS);
  const current=windowFor(firstOpenMs,index);
  const previous=index===0?null:windowFor(firstOpenMs,index-1);
  const frozen=serverNowMs>=current.closeAtMs;
  return Object.freeze({phase:frozen?"frozen":"active",
    leagueScoringAllowed:!frozen,current,previous,
    displayedResultWeekId:frozen?current.weekId:previous?.weekId||null,
    nextOpenMs:current.nextOpenMs});
}
/**
 * Frozen table is based on a PRIVATE Admin SDK fixture only. Hashes, flag
 * strings and validation do not authenticate or certify production winners.
 * No user identifiers are sent into the winner card output.
 */
function previewFrozenResult({firstOpenMs,weekIndex,serverNowMs,snapshot}){
  const week=windowFor(firstOpenMs,weekIndex);
  if(!validMs(serverNowMs)||serverNowMs<week.closeAtMs)
    block("cannot_view_before_close");
  if(!snapshot||snapshot.source!==SOURCE||snapshot.emulatorOnly!==true||
     snapshot.weekId!==week.weekId||
     !validMs(snapshot.sealedAtMs)||
     snapshot.sealedAtMs<week.closeAtMs||
     snapshot.sealedAtMs>serverNowMs||
     !Array.isArray(snapshot.rows)||snapshot.rows.length>10)
    block("not_an_immutable_private_final_result");
  const seen=new Set();
  const rows=snapshot.rows.map((x,i)=>{
    if(!x||Object.keys(x).some(k=>!["place","participantId","weeklyXp",
      "verifiedTaskCount","reachedAtMs"].includes(k))||
       x.place!==i+1||!PARTICIPANT.test(x.participantId||"")||
       seen.has(x.participantId)||
       !Number.isSafeInteger(x.weeklyXp)||x.weeklyXp<0||
       !Number.isSafeInteger(x.verifiedTaskCount)||x.verifiedTaskCount<0||
       !validMs(x.reachedAtMs)||x.reachedAtMs<week.openedAtMs||
       x.reachedAtMs>=week.closeAtMs)
      block("untrusted_rank_row");
    seen.add(x.participantId);
    if(i>0){
      const prior=snapshot.rows[i-1];
      if(x.weeklyXp>prior.weeklyXp||
         (x.weeklyXp===prior.weeklyXp&&
          x.verifiedTaskCount>prior.verifiedTaskCount)||
         (x.weeklyXp===prior.weeklyXp&&
          x.verifiedTaskCount===prior.verifiedTaskCount&&
          x.reachedAtMs<prior.reachedAtMs))
        block("incorrect_frozen_order");
    }
    return Object.freeze({place:x.place,participantId:x.participantId,
      weeklyXp:x.weeklyXp,verifiedTaskCount:x.verifiedTaskCount,
      plannedDiamonds:PRIZES[i]});
  });
  return Object.freeze({weekId:week.weekId,closeAtMs:week.closeAtMs,
    releaseAtMs:week.nextOpenMs,previewOnly:true,payoutEnabled:false,
    sealedAtMs:snapshot.sealedAtMs,rows:Object.freeze(rows)});
}
function previewWinnerCard({firstOpenMs,weekIndex,serverNowMs,
  snapshot,viewerParticipantId,giftReceipt,acknowledged=false}){
  const result=previewFrozenResult({firstOpenMs,weekIndex,
    serverNowMs,snapshot});
  if(serverNowMs<result.releaseAtMs||acknowledged===true)return null;
  if(!PARTICIPANT.test(viewerParticipantId||""))
    block("unverified_fixture_participant");
  const winner=result.rows.find(x=>x.participantId===viewerParticipantId);
  if(!winner)return null;
  // Must have an existing, verified-shaped PENDING or RECEIVED fixture
  // before congratulating somebody about a gift; never mint a new receipt.
  if(!giftReceipt||giftReceipt.source!==SOURCE||
     giftReceipt.emulatorOnly!==true||
     giftReceipt.weekId!==result.weekId||
     giftReceipt.participantId!==viewerParticipantId||
     giftReceipt.place!==winner.place||
     giftReceipt.diamonds!==winner.plannedDiamonds||
     !["pending","received"].includes(giftReceipt.status))
     return null;
  const i=winner.place-1;
  return Object.freeze({
    demoOnly:true,creditsMade:0,canClaimAutomatically:false,
    background:"#101C35",innerBackground:"#233651",gold:"#F7CB65",
    icon:"trophy",title:"تهانينا يا بطل DEDA!",
    intro:"لقد حققت إنجازاً رائعاً في دوري المتصدرين الأسبوعي",
    rankLabel:"مركزك النهائي",
    rankText:"المركز "+RANKS[i]+(MEDALS[i]||""),
    prizeText:String(winner.plannedDiamonds)+" 💎",
    prizeLabel:"جائزتك الأسبوعية",
    footer:"شكراً لمشاركتك وتميّزك! استمر بالتحدي، فالدوري الجديد بدأ الآن.",
    primary:"🎁 الذهاب إلى هداياي",
    secondary:"مشاهدة نتائج الأسبوع",close:"إغلاق"
  });
}
function requireEmulator(db){
  if(process.env.GCLOUD_PROJECT!==PROJECT||
     !process.env.FIRESTORE_EMULATOR_HOST||
     !db||typeof db.runTransaction!=="function"||
     typeof db.doc!=="function")
    block("emulator_only_no_live_ack");
}
/** Invoke ONLY when the user dismisses the card in PRIVATE emulator QA.
 * Real production needs server-authenticated canonical owner and a crash-
 * safe display reservation/ack policy. This proves no duplicates in fixtures.
 */
async function acknowledgeFixtureWinnerCard({db,firstOpenMs,weekIndex,
  serverNowMs,snapshot,viewerParticipantId,giftReceipt}){
  requireEmulator(db);
  const card=previewWinnerCard({firstOpenMs,weekIndex,serverNowMs,
    snapshot,viewerParticipantId,giftReceipt});
  if(!card)block("no_eligible_mock_card");
  const week=windowFor(firstOpenMs,weekIndex);
  const ref=db.doc("deda_weekly_stage31_fixture_card_seen/"+
    week.weekId+"_"+viewerParticipantId);
  return db.runTransaction(async tx=>{
    const old=await tx.get(ref);
    if(old.exists)return Object.freeze({acknowledged:false,
      alreadyAcknowledged:true,emulatorOnly:true});
    tx.create(ref,{weekId:week.weekId,participantId:viewerParticipantId,
      acknowledgedAtMs:serverNowMs,emulatorOnly:true});
    return Object.freeze({acknowledged:true,
      alreadyAcknowledged:false,emulatorOnly:true});
  });
}
module.exports=Object.freeze({WEEK_MS,FREEZE_MS,PROJECT,SOURCE,PRIZES,
  windowFor,clockState,previewFrozenResult,previewWinnerCard,
  acknowledgeFixtureWinnerCard});
