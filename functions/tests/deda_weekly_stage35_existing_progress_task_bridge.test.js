"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const core=require("../../tools/app_stability/progress_archive/reconcile-core.cjs");
const {clockState}=require(
  "../deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
const {dayInIraq}=require(
  "../deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const {opaqueReceiptId}=require(
  "../deda_weekly_owner_receipt_gate_NOT_EXPORTED.js");
const {previewTaskClaimForExistingProgress:preview}=require(
  "../deda_weekly_stage35_existing_progress_task_bridge_NOT_EXPORTED.js");
const ACCOUNT="07701234567";
const START=Date.UTC(2026,9,27,3);
const NOW=START+8*3600000;
const FROZEN=START+7*86400000-6*3600000+60000;
const NEXT=START+8*86400000+2000;
function receipt(at=NOW,changes={}){
 const dayId=dayInIraq(at);
 const clock=clockState({firstOpenMs:START,serverNowMs:at});
 return {
  emulatorOnly:true,issuer:"stage34_atomic_level_fixture_v1",
  accountKey:ACCOUNT,taskId:"share_personal_location",dayId,
  receiptId:opaqueReceiptId({accountKey:ACCOUNT,dayId,taskId:"share_personal_location"}),
  amount:20,verifiedAtMs:at-1000,createdAtMs:at,
  weekId:clock.phase==="active"?clock.current.weekId:null,
  competitionStatus:clock.phase==="active"?"league":"frozen",
  ...changes,
 };
}
function cutover(changes={}){
 return {emulatorOnly:true,canAuthorizeLiveWrites:false,
   accountKey:ACCOUNT,cutoverPhase:"reviewed_fixture_only",
   originalLocalSourcePreserved:true,protectedWriterFenceModelled:true,
   ...changes};
}
function compose(at=NOW,changes={},approval=cutover()){
 return preview({shadowReceipt:receipt(at,changes),
   reviewedCutoverFixture:approval,requestedAccountKey:ACCOUNT,
   firstOpenMs:START});
}
function base(){
 const r=core.parseReceipt({
  format:1,accountKey:ACCOUNT,source:"legacy-baseline-v1",
  sourceId:"approved-fixture-existing-account",
  kind:"baseline",
  delta:{points:310,coins:90,xp:1250,earnedDiamonds:700}
 },ACCOUNT);
 return core.applyEvent(null,r);
}
test("reuse EXISTING progress ledger instead of creating a second XP wallet",()=>{
 const v=compose(),old=base();
 const next=core.applyEvent(old,v.progressReceipt);
 assert.equal(v.privateCompatibilityPreviewOnly,true);
 assert.equal(v.canWriteRealProgress,false);
 assert.equal(v.canGrantDiamonds,false);
 assert.equal(v.existingProgressPath,"deda_verified_progress");
 assert.equal(v.progressReceipt.source,"task-claim-v1");
 assert.deepEqual(next.balances,{
  points:315,coins:90,xp:1270,earnedDiamonds:700});
 assert.equal(next.initializedBy,old.initializedBy);
 assert.equal(next.version,2);
 assert.equal(v.eligibleLeagueXp,20);
});
test("missing reviewed original baseline cannot create an artificial zero account",()=>{
 const v=compose();
 assert.throws(()=>core.applyEvent(null,v.progressReceipt),
   e=>e.code==="progress-initialization-required");
 for(const c of [
   null,cutover({canAuthorizeLiveWrites:true}),
   cutover({protectedWriterFenceModelled:false}),
   cutover({accountKey:"07701234568"}),
   cutover({cutoverPhase:"pending"})
 ]){
  assert.throws(()=>compose(NOW,{},c),/historic_progress_review_not_proven/);
 }
});
test("replay on two device wrappers has the SAME immutable source event key",()=>{
 const first=compose(),second=compose();
 assert.equal(first.eventKey,second.eventKey);
 assert.equal(first.progressReceipt.sourceId,second.progressReceipt.sourceId);
 assert.equal(first.progressReceipt.delta.xp,20);
 assert.equal(first.progressReceipt.delta.earnedDiamonds,0);
});
test("week freeze: original level XP remains +20 but league XP stays ZERO",()=>{
 const v=compose(FROZEN);
 assert.equal(v.eligibleLeagueXp,0);
 assert.equal(v.leagueWeekId,null);
 const state=core.applyEvent(base(),v.progressReceipt);
 assert.equal(state.balances.xp,1270);
 assert.equal(state.balances.points,315);
 assert.equal(state.balances.earnedDiamonds,700);
});
test("next league round uses a separate week and keeps original XP baseline",()=>{
 const initial=compose(),other=compose(NEXT);
 assert.notEqual(initial.leagueWeekId,other.leagueWeekId);
 assert.notEqual(initial.eventKey,other.eventKey);
 const after=core.applyEvent(
   core.applyEvent(base(),initial.progressReceipt),other.progressReceipt);
 assert.equal(after.balances.xp,1290);
 assert.equal(after.version,3);
 assert.equal(other.eligibleLeagueXp,20);
});
test("disallow fake alias, copied UID, tampered amount, or changed phase",()=>{
 const invalid=[
  {premiumAlias:"@DEDA-GOLD"},{authUid:"other"},
  {amount:1000},{accountKey:"07709999999"},{issuer:"client_award"},
  {originalLevelXpApplied:true},{weekId:"other"},
  {competitionStatus:"frozen"},{verifiedAtMs:NOW+1000},
  {dayId:"2026-12-01"},{receiptId:"a".repeat(64)}
 ];
 for(const patch of invalid){
  assert.throws(()=>compose(NOW,patch),/original_shadow_receipt_not_verified|league_phase_or_week_mismatch/);
 }
});
test("new benefit uses no clock, UID, alias or prize fields from the app",()=>{
 const item=compose();
 assert.deepEqual(Object.keys(item.progressReceipt),
   ["format","accountKey","source","sourceId","kind","delta"]);
 assert.deepEqual(Object.keys(item.progressReceipt.delta),
   ["points","coins","xp","earnedDiamonds"]);
 assert.equal(item.canPublishLeague,false);
 assert.equal(item.progressReceipt.delta.coins,0);
});
