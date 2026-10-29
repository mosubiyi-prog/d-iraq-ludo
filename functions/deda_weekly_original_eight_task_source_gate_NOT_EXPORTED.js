'use strict';
// Private original-source coverage gate. It NEVER awards XP or diamonds.
// Existing source: lib/main.dart DedaTaskIds.weekly / DedaTaskEngine and
// the only independently signed task claim in Stage46 (location share).
// Merely having eight client task IDs does NOT make eight server proofs.
const TASK_IDS=Object.freeze([
  'share_personal_location','open_map','share_registered_place',
  'open_saved_place','open_received_place','review_added_place',
  'traffic_skills','long_trip',
]);
const ORIGINAL_TASK_POINTS=5,ORIGINAL_LEVEL_XP_PER_TASK=20;
const VERIFIED_PRIVATE_PRODUCER='share_personal_location';
const block=(why)=>{throw Error('DEDA_ORIGINAL_WEEKLY_SOURCE_HOLD_'+why);};
function allowlistedTaskId(id){
  return typeof id==='string'&&TASK_IDS.includes(id);
}
function serverSourceStatus(id){
  if(!allowlistedTaskId(id))block('UNKNOWN_OR_CLIENT_TASK_ID');
  return Object.freeze({
    taskId:id,
    proofAvailableInPrivateEmulator:id===VERIFIED_PRIVATE_PRODUCER,
    realProductionIssuerAvailable:false,
    canAwardUserXp:false,canAddDiamonds:false,
    canRankProductionUsers:false,
  });
}
/**
 * This is the exact expected ORIGINAL task-claim shape, *not an issuer*.
 * Cannot be satisfied by SharedPreferences, local+5, client completion flags,
 * manager's 1m points, on-device XP or a spoofed anonymous Auth UID.
 *
 * Only verified server-side applied XP receipts plus source Action proof can
 * be considered in a future production league. Stage46 supplies an emulator
 * proof path ONLY for the location share task, still not real users.
 */
function originalTaskReceiptShape({accountKey,dayId,taskId,coins=10}){
  if(!/^[0-9]{10,16}$/.test(accountKey||'')||
     !/^20\d{2}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])$/.test(dayId||'')||
     !allowlistedTaskId(taskId)||
     coins!==10)
    block('INVALID_ORIGINAL_RECEIPT_INPUT');
  return Object.freeze({
    format:1,accountKey,source:'task-claim-v1',
    sourceId:`daily-task|${dayId}|${taskId}`,
    kind:'award',
    delta:Object.freeze({
      points:ORIGINAL_TASK_POINTS,coins:10,
      xp:ORIGINAL_LEVEL_XP_PER_TASK,earnedDiamonds:0,
    }),
  });
}
function privateCoverageSummary(){
  const rows=TASK_IDS.map(serverSourceStatus);
  return Object.freeze({
    expectedOriginalTaskIds:rows.length,
    privateSignedProducerCount:rows.filter(r=>r.proofAvailableInPrivateEmulator).length,
    productionVerifiedProducerCount:0,
    readyForActualWeeklyStandings:false,
    readyForRealPrizes:false,
    rows:Object.freeze(rows),
  });
}
module.exports=Object.freeze({
  TASK_IDS,ORIGINAL_TASK_POINTS,ORIGINAL_LEVEL_XP_PER_TASK,
  allowlistedTaskId,serverSourceStatus,originalTaskReceiptShape,
  privateCoverageSummary,
});
