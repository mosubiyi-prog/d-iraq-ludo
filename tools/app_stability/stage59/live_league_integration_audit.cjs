"use strict";
/**
 * DEDA Stage59 — SOURCE-GROUNDED LIVE INTEGRATION AUDIT (NO DEPLOY).
 * Static read-only review against this branch's actual original DEDA files.
 * Describes what is visibly wired vs only staged — NEVER approves release.
 *
 * It cannot prove what code is inside a previously installed APK, backend
 * deployment state, real account ownership, device QA or Firestore production
 * data. Every "live" flag below defaults to false until independently proven.
 */
const fs=require("node:fs"),path=require("node:path");
const required=Object.freeze({
  main:"lib/main.dart",
  adminDashboard:"lib/admin_pages.dart",
  adminLeague:"lib/deda_admin_league_page.dart",
  leaderboardPage:"lib/deda_weekly_leaderboard_page.dart",
  safeScreen:"lib/deda_weekly_leaderboard_safe_screen.dart",
  tapSurface:"lib/deda_weekly_leaderboard_tap_surface.dart",
  snapshotDecode:"lib/deda_weekly_snapshot_decode.dart",
  scorePolicy:"lib/deda_weekly_leaderboard_policy.dart",
  localTrial:"lib/deda_weekly_private_trial_local_xp.dart",
  functions:"functions/index.js",
  serverCalendar:"functions/deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js",
  serverTopTen:"functions/deda_weekly_stage44_verified_ledger_top10_archive_NOT_EXPORTED.js",
  serverGifts:"functions/deda_weekly_stage45_private_gifts_inbox_atomic_NOT_EXPORTED.js",
  monthlyShadow:"functions/deda_weekly_monthly_top10_archive_NOT_EXPORTED.js",
  rules:"firestore.rules",
  accountRecovery:"lib/deda_migrated_progress_firebase.dart",
  leagueFriendCard:"lib/deda_weekly_competitor_public_card.dart",
  originalTask:"lib/deda_daily_published_tasks.dart",
});
const states=new Set(["PRESENT_UI_ONLY","PRESENT_PRIVATE_ONLY",
  "ADMIN_PLACEHOLDER_ONLY","NOT_WIRED","LOCAL_QA_ONLY","GATED_OFF",
  "PRESENT_READONLY_CONTRACT","NOT_ESTABLISHED"]);
const findings=(id,status,path,reason)=>Object.freeze({
  id,status,path,reason,liveProductionReady:false,
});
function reviewLeagueSource(s){
  for(const [k,p] of Object.entries(required)){
    if(typeof s?.[k]!=="string"||s[k].length===0)
      throw Error("STAGE59_ORIGINAL_SOURCE_MISSING_"+p);
  }
  const m=s.main,a=s.adminDashboard,admin=s.adminLeague;
  const page=s.leaderboardPage,safe=s.safeScreen,tap=s.tapSurface;
  const fn=s.functions,calendar=s.serverCalendar,gifts=s.serverGifts;
  const includes=(src,term)=>src.includes(term);
  const homeWired=includes(m,"DedaLeaderboardHomeCard(")&&
    includes(m,"DedaWeeklyLeaderboardSafeScreen(")&&
    includes(m,"deda_weekly_leaderboard_safe_screen.dart");
  const readerInjected=/DedaWeeklyLeaderboardSafeScreen\s*\([\s\S]*?loadVerifiedStandings\s*:/.test(m);
  const prodLeagueEndpoint=/\bexports\.(?:dedaWeekly|dedaLeague|dedaLeaderboard|dedaTopTen|dedaIssueWeeklyGift|dedaWeeklyGift)\w*\s*=/.test(fn);
  const top10UI=includes(page,"class DedaWeeklyLeaderboardPage")&&
    includes(page,"rankingTable(")&&includes(page,"podiumRow(");
  const adminRouted=includes(a,"import 'deda_admin_league_page.dart'")&&
    includes(a,"DedaAdminLeaguePage(isArabic: ar)");
  const adminControlsDisabled=includes(admin,"deda_league_admin_start_disabled")&&
    includes(admin,"deda_league_admin_stop_disabled")&&
    (admin.match(/onPressed:\s*null/g)||[]).length>=2;
  const ranksHaveTapWidget=includes(page,"DedaWeeklyLeaderboardTapSurface(")&&
    includes(tap,"onTap:canOpen?()=>_open(context):null");
  const rankTwoLive=homeWired&&readerInjected&&
    /onOpenExistingPublicProfile\s*:/.test(m)&&
    /onSendExistingFriendRequest\s*:/.test(m);
  const avatarLive=homeWired&&/drawOriginalEquippedAvatar\s*:/.test(m);
  const appCheckLive=homeWired&&readerInjected&&prodLeagueEndpoint&&
    /enforceAppCheck:\s*true/.test(fn);
  const prizeDisplay=includes(s.scorePolicy,"return 150;")&&
    includes(s.scorePolicy,"return 100;")&&
    includes(s.scorePolicy,"return 50;")&&
    includes(s.scorePolicy,"return 10;")&&
    includes(s.scorePolicy,"totalWeeklyDiamonds = 370");
  const frozenPolicy=includes(calendar,"FREEZE_MS=6*3600000")&&
    includes(calendar,"not_released_0600_baghdad")===false&&
    includes(calendar,"frozen");
  const out=[
    findings("user_home_league_route",
      homeWired?"PRESENT_READONLY_CONTRACT":"NOT_WIRED",
      required.main,
      homeWired?"Home constructor found; independent signed backend still required":
      "Current main.dart does not construct weekly home card + safe page"),
    findings("original_restaurant_category",
      /['"]مطاعم['"]/.test(m)?"PRESENT_UI_ONLY":"NOT_ESTABLISHED",
      required.main,
      "Original source still includes Restaurants; not proof of retired home tile replacement"),
    findings("leaderboard_top10_non_scroll_design",
      top10UI?"PRESENT_UI_ONLY":"NOT_ESTABLISHED",
      required.leaderboardPage,
      "Fixed Flutter top-three podium + ranking table source, not device QA"),
    findings("rank_second_profile_friend_actions",
      rankTwoLive?"PRESENT_READONLY_CONTRACT":"NOT_WIRED",
      required.tapSurface,
      ranksHaveTapWidget?
        "Optional click widget exists; no original main route and authenticated social callbacks established":
        "No verified participant click surface"),
    findings("equipped_frames_live_players",
      avatarLive?"PRESENT_READONLY_CONTRACT":"NOT_WIRED",
      required.leaderboardPage,
      "Frame renderer is optional; no production current-user avatar/equipped frame callback in main"),
    findings("verified_standings_reader",
      readerInjected&&prodLeagueEndpoint?"PRESENT_READONLY_CONTRACT":"NOT_WIRED",
      required.safeScreen,
      includes(safe,"this.loadVerifiedStandings")?
        "Safe screen's backend reader parameter defaults null; main does not supply a verified callable":
        "No verified server reader source"),
    findings("original_live_weekly_server_callable",
      prodLeagueEndpoint?"PRESENT_READONLY_CONTRACT":"NOT_WIRED",
      required.functions,
      "Production functions/index.js does not export the separately staged weekly rank/settle handlers"),
    findings("weekly_task_xp_source",
      includes(s.localTrial,"SharedPreferences")?"LOCAL_QA_ONLY":"NOT_ESTABLISHED",
      required.localTrial,
      "Local QA reads phone task points; independent server-signed task issuer not live-wired"),
    findings("00_to_06_baghdad_freeze",
      frozenPolicy?"PRESENT_PRIVATE_ONLY":"NOT_ESTABLISHED",
      required.serverCalendar,
      "Six-hour Baghdad frozen-scoring policy is in NOT_EXPORTED module; not live calendar"),
    findings("06_winner_congratulation_card",
      includes(calendar,"previewFrozenResult")?"PRESENT_PRIVATE_ONLY":"NOT_ESTABLISHED",
      required.serverCalendar,
      "Private preview contract, not approved deployed winner card/view receipt"),
    findings("weekly_prize_values_display",
      prizeDisplay?"PRESENT_UI_ONLY":"NOT_ESTABLISHED",
      required.scorePolicy,
      "Positions 1/2/3/4–10 display 150/100/50/10; no actual credit proof"),
    findings("earned_diamonds_weekly_gifts",
      includes(gifts,"shadowWallet")?"PRESENT_PRIVATE_ONLY":"NOT_ESTABLISHED",
      required.serverGifts,
      "Stage45 uses synthetic gift inbox/private shadow diamonds, NOT a real هداياي settlement"),
    findings("monthly_manager_archive",
      includes(s.monthlyShadow,"NOT_EXPORTED")&&
        includes(admin,"not connected yet")?
        "ADMIN_PLACEHOLDER_ONLY":"NOT_ESTABLISHED",
      required.adminLeague,
      "General manager monthly weekly top-ten archive says not connected; source model is private only"),
    findings("manager_league_navigation",
      adminRouted?"ADMIN_PLACEHOLDER_ONLY":"NOT_ESTABLISHED",
      required.adminDashboard,
      "Owner/general-manager dashboard can navigate to isolated league overview"),
    findings("manager_start_stop_awards",
      adminControlsDisabled?"ADMIN_PLACEHOLDER_ONLY":"NOT_ESTABLISHED",
      required.adminLeague,
      "League start/stop controls disabled by null onPressed; no live award authority"),
    findings("task_publisher_to_real_xp",
      includes(s.originalTask,"NOT connected")?"GATED_OFF":"NOT_ESTABLISHED",
      required.originalTask,
      "Published task UI read model not wired to original reward engine/server XP source"),
    findings("verified_week_snapshot_contract",
      includes(s.snapshotDecode,"future_server_issued_only")?
        "PRESENT_READONLY_CONTRACT":"NOT_ESTABLISHED",
      required.snapshotDecode,
      "Strict decoder is only data contract; server must issue independent verified snapshots"),
    findings("android_cross_phone_progress",
      includes(s.accountRecovery,"defaultValue: false")?
        "GATED_OFF":"NOT_ESTABLISHED",
      required.accountRecovery,
      "Original migrated progress feature remains compile-time OFF; Stage54–58 private QA only"),
    findings("real_weekly_appcheck_ownership",
      appCheckLive?"PRESENT_READONLY_CONTRACT":"NOT_WIRED",
      required.functions,
      "No original home reader plus server weekly callable with independent production AppCheck issuer"),
  ];
  for(const f of out)if(!states.has(f.status))throw Error("STAGE59_BAD_REVIEW_STATE");
  const summary={
    sourceScope:"STAGE58_GITHUB_BRANCH_SOURCE_NOT_INSTALLED_APK",
    reviewedPaths:Object.values(required).length,
    featuresReviewed:out.length,
    observedStates:Object.fromEntries([...states].map(x=>[x,out.filter(f=>f.status===x).length])),
    noNewUserDataWrites:true,
    releaseReady:false,
    canCreditWeeklyDiamonds:false,
    crossPhoneMigrationActive:false,
    phoneAndTabletTested:false,
    productionFirebaseDeployedByThisAudit:false,
    ownerPreApkReviewRequired:true,
  };
  return Object.freeze({summary,findings:out});
}
function readOriginalSources(root){
  const out={};
  for(const [key,p]of Object.entries(required)){
    const full=path.join(root,p);
    if(!fs.existsSync(full)||!fs.statSync(full).isFile())
      throw Error("STAGE59_MISSING_SOURCE_"+p);
    out[key]=fs.readFileSync(full,"utf8");
  }
  return out;
}
function main(){
  const root=path.resolve(__dirname,"../../..");
  const review=reviewLeagueSource(readOriginalSources(root));
  if(!review.findings.some(f=>f.id==="verified_standings_reader"&&f.status==="NOT_WIRED")||
     !review.findings.some(f=>f.id==="original_live_weekly_server_callable"&&f.status==="NOT_WIRED")||
     !review.findings.some(f=>f.id==="manager_start_stop_awards"&&f.status==="ADMIN_PLACEHOLDER_ONLY"))
    throw Error("STAGE59_PINNED_GAP_EXPECTATION_CHANGED_REQUIRE_FRESH_OWNER_REVIEW");
  console.log("DEDA Stage59 evidence: SOURCE REVIEW ONLY, NEVER LIVE RELEASE APPROVAL");
  console.log(JSON.stringify(review,null,2));
}
if(require.main===module)main();
module.exports={required,states,readOriginalSources,reviewLeagueSource};
