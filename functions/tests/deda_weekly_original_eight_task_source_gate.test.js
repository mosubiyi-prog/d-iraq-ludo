'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const gate=require('../deda_weekly_original_eight_task_source_gate_NOT_EXPORTED.js');
const core=require('../../tools/app_stability/progress_archive/reconcile-core.cjs');
const {receiptFor}=require('../deda_weekly_stage42_server_share_action_producer_NOT_EXPORTED.js');

const accountKey='07701234567',dayId='2026-10-28';
const expected=[
  'share_personal_location','open_map','share_registered_place',
  'open_saved_place','open_received_place','review_added_place',
  'traffic_skills','long_trip',
];
test('eight original task keys EXACTLY match the original DEDA source',()=>{
 const original=fs.readFileSync('lib/main.dart','utf8');
 const body=original.split('static const List<String> weekly = <String>[')[1].split('];')[0];
 for(const id of expected) {
  assert.match(body,new RegExp('\\b'+id.replaceAll('_','\\_')+'\\b'));
  assert.match(original,new RegExp("'"+id+"'"));
 }
 assert.deepEqual(gate.TASK_IDS,expected);
 assert.equal(gate.PRIVATE_COVERAGE_COUNT,undefined);
});
test('original task points and xp are distinct, no synthetic extras',()=>{
 assert.equal(gate.ORIGINAL_TASK_POINTS,5);
 assert.equal(gate.ORIGINAL_LEVEL_XP_PER_TASK,20);
 const s=fs.readFileSync('lib/main.dart','utf8');
 assert.match(s,/static const int pointsPerTask = 5;/);
 assert.match(s,/static const int generalManagerBonusPoints = 1000000;/);
});
test('all 8 official tasks resolve to the identical original canonical receipt vector',()=>{
 for(const taskId of expected){
  const receipt=gate.originalTaskReceiptShape({accountKey,dayId,taskId});
  const parsed=core.parseReceipt(receipt,accountKey);
  assert.deepEqual(parsed.delta,{points:5,coins:10,xp:20,earnedDiamonds:0});
  assert.equal(parsed.sourceId,'daily-task|'+dayId+'|'+taskId);
  assert.match(core.eventKey(parsed),/^[0-9a-f]{64}$/);
 }
});
test('existing original share task receipt remains bit-identical',()=>{
 const canonical=gate.originalTaskReceiptShape({
  accountKey,dayId,taskId:'share_personal_location',
 });
 const share=receiptFor(accountKey,dayId);
 assert.ok(core.sameEvent(core.parseReceipt(canonical,accountKey),share.receipt));
 assert.equal(core.eventKey(canonical),share.eventKey);
});
test('only location share has an independent PRIVATE emulator producer: seven missing',()=>{
 const summary=gate.privateCoverageSummary();
 assert.equal(summary.expectedOriginalTaskIds,8);
 assert.equal(summary.privateSignedProducerCount,1);
 assert.equal(summary.productionVerifiedProducerCount,0);
 assert.equal(summary.readyForActualWeeklyStandings,false);
 assert.equal(summary.readyForRealPrizes,false);
 assert.equal(summary.rows[0].proofAvailableInPrivateEmulator,true);
 assert.equal(summary.rows.slice(1).filter(r=>r.proofAvailableInPrivateEmulator).length,0);
 for(const row of summary.rows) {
  assert.equal(row.realProductionIssuerAvailable,false);
  assert.equal(row.canAwardUserXp,false);
  assert.equal(row.canAddDiamonds,false);
  assert.equal(row.canRankProductionUsers,false);
 }
});
test('unknown task/reward client override, bogus dates and accounts always fail closed',()=>{
 for(const args of [
  {accountKey,dayId,taskId:'daily_login'},
  {accountKey,dayId,taskId:'admin_bonus'},
  {accountKey,dayId,taskId:'traffic_answer'},
  {accountKey,dayId,taskId:'share_personal_location',coins:0},
  {accountKey,dayId,taskId:'share_personal_location',coins:20},
  {accountKey:'@DEDA-AAAA',dayId,taskId:'share_personal_location'},
  {accountKey,dayId:'2026-13-25',taskId:'share_personal_location'},
  {accountKey,dayId,taskId:'share_personal_location',coins:1000000},
 ])assert.throws(()=>gate.originalTaskReceiptShape(args),/HOLD/);
 for(const fake of ['daily_login','admin_bonus','1000000','',null])
  assert.throws(()=>gate.serverSourceStatus(fake),/HOLD/);
});
test('all exported records immutable and no wallet/auth/producer methods',()=>{
 const p=gate.originalTaskReceiptShape({accountKey,dayId,taskId:'open_map'});
 assert.ok(Object.isFrozen(p));assert.ok(Object.isFrozen(p.delta));
 assert.ok(Object.isFrozen(gate.TASK_IDS));
 assert.ok(Object.isFrozen(gate.privateCoverageSummary().rows));
 assert.equal('grantPrize' in gate,false);
 assert.equal('creditXp' in gate,false);
 assert.equal('fromClient' in gate,false);
 assert.equal('writeWallet' in gate,false);
});
test('original production function is not using PRIVATE gate as an award issuer',()=>{
 const index=fs.readFileSync('functions/index.js','utf8');
 assert.ok(!index.includes('deda_weekly_original_eight_task_source_gate_NOT_EXPORTED'));
 const code=fs.readFileSync('functions/deda_weekly_original_eight_task_source_gate_NOT_EXPORTED.js','utf8');
 for(const marker of ['NOT_EXPORTED','realProductionIssuerAvailable:false','readyForRealPrizes:false'])
  assert.ok(code.includes(marker),marker);
});
