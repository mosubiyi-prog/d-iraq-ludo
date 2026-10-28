"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const path=require("node:path");
const {required,states,readOriginalSources,reviewLeagueSource}=require(
 "../../tools/app_stability/stage59/live_league_integration_audit.cjs");
const root=path.resolve(__dirname,"../..");
const source=readOriginalSources(root);
const review=reviewLeagueSource(source);
const get=(r,id)=>r.findings.find(f=>f.id===id);
function result(id,status){assert.equal(get(review,id).status,status,id);}
function mutate(k,replace){
 return reviewLeagueSource({...source,[k]:replace});
}
test("01: original source inventory is anchored to actual DEDA main, backend, Rules and admin",()=>{
 assert.equal(Object.keys(required).length,18);
 for(const [k,p]of Object.entries(required)){
  assert.equal(typeof source[k],"string",p);
  assert.ok(source[k].length>50,p);
 }
 assert.equal(review.summary.reviewedPaths,18);
});
test("02: this is GitHub source audit, not installed APK comparison or Play release",()=>{
 assert.equal(review.summary.sourceScope,"STAGE58_GITHUB_BRANCH_SOURCE_NOT_INSTALLED_APK");
 assert.equal(review.summary.releaseReady,false);
 assert.equal(review.summary.phoneAndTabletTested,false);
 assert.equal(review.summary.productionFirebaseDeployedByThisAudit,false);
});
test("03: main.dart has no actual weekly home tile AND safe screen route",()=>{
 result("user_home_league_route","NOT_WIRED");
 assert.equal(source.main.includes("DedaLeaderboardHomeCard("),false);
 assert.equal(source.main.includes("DedaWeeklyLeaderboardSafeScreen("),false);
});
test("04: original Restaurants text remains as category source, not proof of replaced home card",()=>{
 result("original_restaurant_category","PRESENT_UI_ONLY");
 assert.ok(source.main.includes("'مطاعم'"));
});
test("05: weekly top10 podium/table UI source exists, but static code is not real device QA",()=>{
 result("leaderboard_top10_non_scroll_design","PRESENT_UI_ONLY");
 assert.ok(source.leaderboardPage.includes("podiumRow("));
 assert.ok(source.leaderboardPage.includes("rankingTable("));
});
test("06: center second place tap only works with verified identity and actual callbacks",()=>{
 result("rank_second_profile_friend_actions","NOT_WIRED");
 assert.ok(source.tapSurface.includes("onTap:canOpen?()=>_open(context):null"));
 assert.equal(source.main.includes("onSendExistingFriendRequest:"),false);
});
test("07: original equipped frame rendering is optional; main does not supply league frame hook",()=>{
 result("equipped_frames_live_players","NOT_WIRED");
 assert.ok(source.leaderboardPage.includes("drawOriginalEquippedAvatar"));
 assert.equal(source.main.includes("drawOriginalEquippedAvatar:"),false);
});
test("08: safe screen has nullable verified reader, no active production source supplied by home",()=>{
 result("verified_standings_reader","NOT_WIRED");
 assert.ok(source.safeScreen.includes("this.loadVerifiedStandings"));
 assert.equal(source.main.includes("loadVerifiedStandings:"),false);
});
test("09: original exported Functions do not contain approved deployed league score/gift endpoints",()=>{
 result("original_live_weekly_server_callable","NOT_WIRED");
 assert.ok(source.serverTopTen.includes("NOT EXPORTED"));
});
test("10: phone-local trial XP is not server-verified score authority",()=>{
 result("weekly_task_xp_source","LOCAL_QA_ONLY");
 assert.ok(source.localTrial.includes("SharedPreferences"));
});
test("11: 00:00–06:00 Baghdad freeze is defined in private NOT EXPORTED policy",()=>{
 result("00_to_06_baghdad_freeze","PRESENT_PRIVATE_ONLY");
 assert.ok(source.serverCalendar.includes("FREEZE_MS=6*3600000"));
});
test("12: morning winner greeting exists in private preview, not integrated notification",()=>{
 result("06_winner_congratulation_card","PRESENT_PRIVATE_ONLY");
 assert.ok(source.serverCalendar.includes("previewFrozenResult"));
});
test("13: owner 150/100/50/10 diamond prize schedule exists only as display",()=>{
 result("weekly_prize_values_display","PRESENT_UI_ONLY");
 assert.ok(source.scorePolicy.includes("totalWeeklyDiamonds = 370"));
 assert.equal(review.summary.canCreditWeeklyDiamonds,false);
});
test("14: Stage45 earned diamond gifts use private shadow—not actual spendable هداياي",()=>{
 result("earned_diamonds_weekly_gifts","PRESENT_PRIVATE_ONLY");
 assert.ok(source.serverGifts.includes("shadowWallet"));
});
test("15: monthly manager archive remains documented as unwired placeholder",()=>{
 result("monthly_manager_archive","ADMIN_PLACEHOLDER_ONLY");
 assert.ok(source.adminLeague.includes("are not connected yet"));
});
test("16: league admin tile is reachable for authorized GM, but it's a placeholder",()=>{
 result("manager_league_navigation","ADMIN_PLACEHOLDER_ONLY");
 assert.ok(source.adminDashboard.includes("DedaAdminLeaguePage(isArabic: ar)"));
});
test("17: admin start and stop are disabled by design, never credit diamonds",()=>{
 result("manager_start_stop_awards","ADMIN_PLACEHOLDER_ONLY");
 assert.equal((source.adminLeague.match(/onPressed:\s*null/g)||[]).length>=2,true);
});
test("18: published daily task display is not real verified server reward engine",()=>{
 result("task_publisher_to_real_xp","GATED_OFF");
 assert.ok(source.originalTask.includes("NOT connected"));
});
test("19: verified current+previous snapshot decoder is strict read-only contract, not network",()=>{
 result("verified_week_snapshot_contract","PRESENT_READONLY_CONTRACT");
 assert.ok(source.snapshotDecode.includes("future_server_issued_only"));
});
test("20: original cross-phone migrated progress path defaults to disabled",()=>{
 result("android_cross_phone_progress","GATED_OFF");
 assert.ok(source.accountRecovery.includes("defaultValue: false"));
 assert.equal(review.summary.crossPhoneMigrationActive,false);
});
test("21: original weekly server App Check plus verified snapshot still not connected",()=>{
 result("real_weekly_appcheck_ownership","NOT_WIRED");
 assert.ok(source.functions.includes("initializeApp();"));
});
test("22: every finding explicitly fails closed and reports source path + reason",()=>{
 assert.equal(review.findings.length,19);
 const ids=new Set();
 for(const f of review.findings){
  assert.ok(!ids.has(f.id),f.id);ids.add(f.id);
  assert.ok(states.has(f.status),f.status);
  assert.equal(f.liveProductionReady,false);
  assert.ok(Object.values(required).includes(f.path));
  assert.ok(f.reason.length>25,f.id);
 }
});
test("23: no audit result claims credit, migration, phone/tablet QA or production deploy",()=>{
 for(const f of review.findings)assert.equal(f.liveProductionReady,false);
 for(const k of ["noNewUserDataWrites","ownerPreApkReviewRequired"])
  assert.equal(review.summary[k],true);
 for(const k of ["releaseReady","canCreditWeeklyDiamonds",
   "crossPhoneMigrationActive","phoneAndTabletTested",
   "productionFirebaseDeployedByThisAudit"])
  assert.equal(review.summary[k],false);
});
test("24: missing original main or backend must REFUSE rather than invent evidence",()=>{
 for(const k of ["main","functions","adminLeague","scorePolicy"]){
  assert.throws(()=>reviewLeagueSource({...source,[k]:""}),/STAGE59_ORIGINAL_SOURCE_MISSING/);
 }
});
test("25: removing constructed UI can never accidentally flip NOT_WIRED to live",()=>{
 const hacked=mutate("main",source.main.replace("import 'admin_pages.dart';",""));
 assert.equal(get(hacked,"user_home_league_route").status,"NOT_WIRED");
 assert.equal(hacked.summary.releaseReady,false);
});
test("26: adding home constructor alone is NOT enough to label live",()=>{
 const stub=source.main+"\nDedaLeaderboardHomeCard(onTap: () {});\n";
 const hacked=mutate("main",stub);
 assert.equal(get(hacked,"user_home_league_route").status,"NOT_WIRED");
 assert.equal(get(hacked,"verified_standings_reader").status,"NOT_WIRED");
});
test("27: fake reader injection is NOT sufficient without production server callable",()=>{
 const demo=source.main+
   "\nimport 'deda_weekly_leaderboard_safe_screen.dart';"+
   "\nDedaLeaderboardHomeCard(onTap: () {});"+
   "\nDedaWeeklyLeaderboardSafeScreen(loadVerifiedStandings: fakeReader);";
 const hacked=mutate("main",demo);
 assert.equal(get(hacked,"original_live_weekly_server_callable").status,"NOT_WIRED");
 assert.equal(get(hacked,"verified_standings_reader").status,"NOT_WIRED");
 assert.equal(hacked.summary.canCreditWeeklyDiamonds,false);
});
test("28: changing UI award display cannot authorize actual credited gems",()=>{
 const hacked=mutate("scorePolicy",source.scorePolicy.replace("totalWeeklyDiamonds = 370","totalWeeklyDiamonds = 371"));
 assert.equal(get(hacked,"weekly_prize_values_display").status,"NOT_ESTABLISHED");
 assert.equal(hacked.summary.canCreditWeeklyDiamonds,false);
});
test("29: optional tap surface without actual social callbacks cannot become active",()=>{
 const stub=source.tapSurface.replace("onTap:canOpen?()=>_open(context):null","onTap:null");
 const hacked=mutate("tapSurface",stub);
 assert.equal(get(hacked,"rank_second_profile_friend_actions").status,"NOT_WIRED");
});
test("30: adding an untrusted local league export name is NOT production AppCheck attestation",()=>{
 const hacked=mutate("functions",source.functions+
  "\nexports.dedaWeeklyDummy = {}; // fake unit test, never deployed\n");
 assert.equal(get(hacked,"real_weekly_appcheck_ownership").status,"NOT_WIRED");
 assert.equal(hacked.summary.releaseReady,false);
});
