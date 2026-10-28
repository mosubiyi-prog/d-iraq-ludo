"use strict";
/*
 * DEDA Stage60 — OWNER PRE-APK inventory validation and hard safety HOLD.
 * Reads GitHub SOURCE snapshot and owner inventory. NEVER starts a build,
 * reads cloud accounts, approves a migration, changes wallets or publishes.
 *
 * Green CI means the inventory is consistent and honest, NOT release-ready.
 */
const fs=require("node:fs"),path=require("node:path");
const root=path.resolve(__dirname,"../../..");
const manifestPath=path.join(__dirname,"owner_preapk_review_manifest.json");
const {reviewLeagueSource,readOriginalSources}=
  require("../stage59/live_league_integration_audit.cjs");
const statuses=new Set([
 "IMPLEMENTED_IN_SOURCE_ONLY","QA_MODEL_ONLY","PARTIAL_PHONE_EVIDENCE",
 "NOT_YET_VERIFIED_LIVE","SAFETY_HOLD"
]);
const fail=reason=>{throw Error("DEDA_STAGE60_OWNER_PREAPK_HOLD_"+reason);};
const ids=[
 "L01","L02","L03","L04","L05","L06","L07","L08","L09","L10","L11",
 "T01","T02","T03","T04","T05","F01","F02","I01","I02","I03",
 "I04","I05","I06","P01","A01","A02","A03","A04","G01",
 "V01","R01","R02"
];
const blocked=[
 "L01","L03","L06","L08","L11","T02","T03","T04","T05",
 "F02","I02","I03","I04","I06","A01","A02","A03","A04","G01","R01"
];
function src(p,base=root){
 const file=path.join(base,p);
 if(!fs.existsSync(file))fail("MISSING_SOURCE_"+p);
 const stat=fs.statSync(file);
 return stat.isDirectory()?"PRESENT_ASSET_DIRECTORY":fs.readFileSync(file,"utf8");
}
function verify(raw,{base=root}={}){
 const m=structuredClone(raw);
 if(!m||m.schema!==1||m.sourceCommit!==
  "926eb6cf11e7a42648913bd5b791814cd9c90d7c")
  fail("WRONG_GITHUB_SOURCE_BASELINE");
 for(const k of [
   "ownerReviewRequired"
 ])if(m[k]!==true)fail("MISSING_OWNER_APPROVAL_GATE_"+k);
 for(const k of [
   "apkBuildAuthorized","playPublishAuthorized","productionFirebaseDeployAuthorized",
   "realWalletWritesAuthorized","installedApkCompared","deviceQAAccepted",
   "weeklyProductionPayoutReady","crossDeviceTransferReady"
 ])if(m[k]!==false)fail("UNAUTHORIZED_RELEASE_OR_CREDIT_"+k);
 if(m.referenceBuildProtected!==100342)fail("BROKEN_PHONE_REFERENCE");
 if(!Array.isArray(m.items)||m.items.length!==ids.length)fail("INCOMPLETE_OWNER_SCOPE");
 const found=m.items.map(i=>i.id);
 if(new Set(found).size!==ids.length||
   ids.some(id=>!found.includes(id)))fail("DUPLICATE_OR_MISSING_OWNER_REQUIREMENT");
 const summary={};
 for(const it of m.items){
  if(typeof it.id!=="string"||!statuses.has(it.status)||
     typeof it.requirement!=="string"||it.requirement.length<20||
     typeof it.limitation!=="string"||it.limitation.length<15||
     typeof it.evidence!=="string"||it.evidence.includes("..")||
     path.isAbsolute(it.evidence))
     fail("BAD_OR_INCOMPLETE_REQUIREMENT_"+it.id);
  // Every item must name a REAL original source file or asset directory,
  // rather than substituting an invented "done" artifact.
  const c=src(it.evidence,base);
  if(c.length<20)fail("EMPTY_EVIDENCE_"+it.id);
  summary[it.status]=(summary[it.status]||0)+1;
 }
 for(const id of blocked)
   if(m.items.find(it=>it.id===id)?.status===
      "IMPLEMENTED_IN_SOURCE_ONLY")fail("BLOCKER_INCORRECTLY_DECLARED_COMPLETE_"+id);
 const read=p=>src(p,base);
 const main=read("lib/main.dart");
 const score=read("lib/deda_weekly_leaderboard_policy.dart");
 const leaguePage=read("lib/deda_weekly_leaderboard_page.dart");
 const admin=read("lib/deda_admin_league_page.dart");
 const functions=read("functions/index.js");
 const quiz=read("lib/traffic_quiz_page.dart");
 const stages=read("functions/deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
 const active=read("lib/deda_migrated_progress_firebase.dart");
 const backend=read("functions/deda_weekly_stage45_private_gifts_inbox_atomic_NOT_EXPORTED.js");
 if(main.includes("DedaWeeklyLeaderboardSafeScreen(")||
    main.includes("DedaLeaderboardHomeCard("))
   fail("USER_HOME_CHANGED_AFTER_SOURCE_AUDIT");
 if(!leaguePage.includes("class DedaLeaderboardHomeCard")||
    !score.includes("totalWeeklyDiamonds = 370"))
   fail("WEEKLY_UI_AND_REWARD_POLICY_EVIDENCE_CHANGED");
 if(!admin.includes("onPressed: null")||
    !admin.includes("are not connected yet"))
   fail("ADMIN_LEAGUE_PLACEHOLDER_EVIDENCE_CHANGED");
 if(/\bexports\.(?:dedaWeekly|dedaLeague|dedaLeaderboard|dedaTopTen|dedaIssueWeeklyGift)\w*\s*=/.test(functions))
   fail("PRODUCTION_LEAGUE_ENDPOINT_CHANGED_REQUIRE_REVIEW");
 if(!quiz.includes("_dailyQuestionCount = 5")||
    !quiz.includes("_trafficVariantsPerBase = 5")||
    !quiz.includes("20 core x 5 variants = 100")||
    !quiz.includes("base.answersAr.length != 4")||
    !quiz.includes("exactly four answers"))
   fail("TRAFFIC_QUIZ_STATUS_MUST_BE_REAUDITED");
 if(!active.includes("defaultValue: false")||
    !stages.includes("FREEZE_MS=6*3600000")||
    !backend.includes("shadowWallet"))
   fail("PRIVATE_SOURCE_CUTOVER_STATUS_CHANGED");
 const stage59=reviewLeagueSource(readOriginalSources(base));
 for(const id of ["user_home_league_route","verified_standings_reader",
       "original_live_weekly_server_callable"])
   if(stage59.findings.find(f=>f.id===id)?.status!=="NOT_WIRED")
     fail("STAGE59_ORIGINAL_INTEGRATION_VERDICT_DRIFT_"+id);
 const total=m.items.length;
 if(Object.values(summary).reduce((a,b)=>a+b,0)!==total)
   fail("COUNT_DRIFT");
 return Object.freeze({
  stage:60,sourceOnly:true,manifestValidated:true,
  referenceBuild:100342,
  ownerReviewRequired:true,ownerApproved:false,apkBuildAuthorized:false,
  productionDeploymentAuthorized:false,releaseReady:false,
  phonesTabletsNotRetested:true,
  historicalWalletNotMigrated:true,
  quizRequiresDistinct100ThreeAnswers:true,
  weeklyGiftsNotSpendable:true,
  featuresReviewed:total,sourceEvidenceCategories:summary,
  stage59OriginalFilesChecked:stage59.summary.reviewedPaths,
  stage59FeatureGapsReviewed:stage59.summary.featuresReviewed,
  blockingIds:[...blocked],
 });
}
function run(){
 const manifest=JSON.parse(fs.readFileSync(manifestPath,"utf8"));
 const result=verify(manifest);
 console.log("DEDA STAGE60 VERIFIED COMPLETE OWNER INVENTORY — HARD HOLD; NO APK");
 console.log(JSON.stringify(result,null,2));
}
if(require.main===module)run();
module.exports={verify,src,ids,blocked,statuses};
