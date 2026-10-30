"use strict";
/**
 * Private server-only read of the 100396 verified +20-XP mirrors.
 * Provides ordered points for the EXISTING leaderboard, not a replacement UI.
 * Public identity must be independently resolved before showing user names.
 * This does NOT release weekly prizes or register the endpoint in index.js.
 */
const {windowFor}=require("./deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
const HASH=/^[a-f0-9]{64}$/;
const safe=n=>Number.isSafeInteger(n)&&n>=0;
function blocked(why){throw Error("DEDA_WEEKLY_TOP10_HOLD_"+why);}
async function readVerifiedLeagueTopTen({db,firstOpenMs,nowMs=Date.now()}){
 if(!db||typeof db.collection!=="function"||!safe(nowMs))
   blocked("INVALID_BACKEND");
 const index=Math.floor((nowMs-firstOpenMs)/(7*86400000));
 if(!Number.isSafeInteger(index)||index<0)blocked("NOT_STARTED");
 const window=windowFor(firstOpenMs,index);
 if(nowMs<window.openedAtMs||nowMs>=window.nextOpenMs)
   blocked("INVALID_WEEK_WINDOW");
 const path="deda_weekly_verified_xp_mirror_private/"+
   window.weekId+"/scores";
 const data=await db.collection(path).get();
 if(!safe(data.size)||data.size>10000)
   blocked("UNBOUNDED_COMPETITORS");
 const scores=[];
 for(const item of data.docs){
  const s=item.data();
  if(!HASH.test(item.id)||s?.accountDigest!==item.id||
     s.weekId!==window.weekId||
     !safe(s.weeklyPoints)||s.weeklyPoints%20!==0||
     !safe(s.verifiedTaskCompletions)||
     s.weeklyPoints!==s.verifiedTaskCompletions*20||
     !safe(s.lastEarnedAtMs)||
     s.lastEarnedAtMs<window.openedAtMs||
     s.lastEarnedAtMs>=window.closeAtMs||
     s.rewardsCredited!==false||s.levelXpChanged!==false)
     blocked("MALFORMED_VERIFIED_SCORE");
  scores.push(s);
 }
 scores.sort((a,b)=>b.weeklyPoints-a.weeklyPoints||
   b.verifiedTaskCompletions-a.verifiedTaskCompletions||
   a.lastEarnedAtMs-b.lastEarnedAtMs||
   a.accountDigest.localeCompare(b.accountDigest));
 return Object.freeze({
  weekId:window.weekId,
  status:nowMs>=window.closeAtMs?"frozen":"active",
  openedAtMs:window.openedAtMs,
  closeAtMs:window.closeAtMs,
  nextOpenMs:window.nextOpenMs,
  source:"applied_server_level_xp_only",
  verifiedAccountProjection:true,
  productionReady:false,
  rewardsCredited:false,
  originalLevelXpUnchanged:true,
  // Account digest is private: caller must resolve an active verified ID
  // server-side; never expose digest directly to the untrusted app.
  privateRows:scores.slice(0,10).map((s,i)=>({
    place:i+1,accountDigest:s.accountDigest,
    weeklyPoints:s.weeklyPoints,
    verifiedTaskCompletions:s.verifiedTaskCompletions,
    lastEarnedAtMs:s.lastEarnedAtMs,
  })),
 });
}
module.exports={readVerifiedLeagueTopTen};
