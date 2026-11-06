'use strict';
/** Owner-approved, Saturday-06 Baghdad weekly DEDA prize runner.
 * Release does NOT execute until every read-only guard passes, then
 * invokes idempotent gift worker. Only MAIN-branch scheduled Actions invoke.
 */
const assert=require('node:assert/strict');
const {plan,weekStart,WEEK_MS}=require('./deda_weekly_direct_prize_plan.js');
const {settleWeek,latestFinishedWeekIds}=require('./deda_weekly_direct_prize_worker.cjs');
const OWNER_DEFAULT=Object.freeze([250,200,150,100,100,100,100,100,100,100]);
const FREEZE_DURATION_MS=6*60*60*1000;
async function releaseOneClosedWeek(db,nowMs,{pay=false,clockTimestamp}={}){
  assert(Number.isSafeInteger(nowMs),'CURRENT_CLOCK_REQUIRED');
  const [weekId]=latestFinishedWeekIds(nowMs,1);
  assert(weekId,'NO_FINISHED_WEEK_NO_PAYMENT');
  const closedAt=weekStart(weekId)+WEEK_MS;
  assert(nowMs>=closedAt,'BEFORE_SATURDAY_06_BAGHDAD');
  assert(nowMs<closedAt+36*3600000,'ONLY_LATEST_CLOSED_WEEK_36_HOUR_WINDOW');
  const control=await db.collection('deda_weekly_direct_control').doc('active').get();
  assert(control.exists,'LEAGUE_CONTROL_RECORD_MISSING');
  assert(control.data()?.paused===false,'LEAGUE_PAUSED_OR_UNKNOWN');
  const prizePlanRef=db.collection('deda_weekly_direct_prize_plans').doc(weekId);
  const planDoc=await prizePlanRef.get();
  const amounts=planDoc.exists?planDoc.data()?.amounts:OWNER_DEFAULT;
  assert(Array.isArray(amounts)&&amounts.length===10,'INVALID_OWNER_PRIZE_PLAN');
  for(let i=0;i<10;i++) {
    assert(Number.isSafeInteger(amounts[i]),'PRIZE_AMOUNT_NOT_INTEGER');
    assert(amounts[i]>=OWNER_DEFAULT[i],'PRIZE_BELOW_OWNER_APPROVED_MINIMUM');
    assert(amounts[i]<=1000000,'PRIZE_OVER_SAFETY_LIMIT');
  }
  const scoreDocs=await db.collection('deda_weekly_direct_weeks')
    .doc(weekId).collection('scores').limit(100).get();
  assert(scoreDocs.size>0&&scoreDocs.size<100,'WEEKLY_SCORE_CENSUS_UNSAFE');
  const cutoff=closedAt-FREEZE_DURATION_MS;
  const records=scoreDocs.docs.map(d=>{
    const entry=d.data();
    const t=entry?.updatedAt?.toMillis?.();
    assert(Number.isSafeInteger(t)&&t<cutoff,'WEEKLY_SCORE_MODIFIED_DURING_FREEZE_ABORT');
    return {id:d.id,data:entry};
  });
  const reviewDocs=await db.collection('deda_weekly_direct_reviews')
    .doc(weekId).collection('users').limit(100).get();
  assert(reviewDocs.size<100,'WEEKLY_FREEZE_REVIEW_LIST_TRUNCATED');
  const frozen=new Map();
  for(const d of reviewDocs.docs)if(d.data()?.frozen===true)frozen.set(d.id,true);
  const expected=plan({weekId,atMs:nowMs,records,freezes:frozen,approvedAmounts:amounts});
  assert(expected.winners.length>0,'NO_ELIGIBLE_WEEKLY_WINNERS');
  assert(expected.winners.length<=10,'MORE_THAN_TEN_GIFTS');
  const recipients=await Promise.all(expected.winners.map(w=>
    db.collection('deda_share_ids').doc(w.publicId).get()));
  for(let i=0;i<expected.winners.length;i++){
    const owner=recipients[i].data();
    assert(recipients[i].exists&&owner.kind==='personal'&&owner.active===true,
      'WEEKLY_RECIPIENT_NO_LONGER_ACTIVE_PERSONAL');
  }
  const gifts=await Promise.all(expected.winners.map(w=>
    db.collection('deda_diamond_gifts').doc(w.giftId).get()));
  for(let i=0;i<gifts.length;i++){
    if(!gifts[i].exists)continue;
    const existing=gifts[i].data(),w=expected.winners[i];
    assert(existing?.sourceType==='weekly_league' &&
      existing.giftId===w.giftId &&
      existing.targetPublicId===w.publicId &&
      existing.amount===w.amount &&
      ['pending','received'].includes(existing.status),
      'EXISTING_WEEKLY_GIFT_CONFLICT_STOP');
  }
  const audit=Object.freeze({
    weekId,verifiedWinners:expected.winners.length,
    plannedDiamonds:expected.totalDiamonds,
    existingGifts:gifts.filter(g=>g.exists).length,
    noDisclosedRecipientIDs:true
  });
  if(!pay)return Object.freeze({...audit,dryRun:true,created:0});
  assert(typeof clockTimestamp==='function','SERVER_TIME_REQUIRED');
  const committed=await settleWeek(db,weekId,nowMs,{dryRun:false,clockTimestamp});
  return Object.freeze({...audit,dryRun:false,created:committed.created,
    alreadyPresent:committed.existing,held:committed.held,invalid:committed.invalid});
}
async function main(){
  assert.equal(process.env.GITHUB_REPOSITORY,'mosubiyi-prog/d-iraq-ludo',
    'ONLY_OWNER_GITHUB_REPOSITORY_CAN_PAY');
  assert.equal(process.env.GITHUB_REF,'refs/heads/main','ONLY_DEFAULT_BRANCH_CAN_PAY');
  assert.equal(process.env.GITHUB_EVENT_NAME,'schedule','ONLY_SCHEDULED_RUN_CAN_PAY');
  assert.equal(process.env.DEDA_OWNER_PAYOUT_APPROVAL,'APPROVED_2026_11_06',
    'OWNER_PAYOUT_APPROVAL_MISSING');
  const info=JSON.parse(process.env.DEDA_FIREBASE_SERVICE_KEY||'null');
  assert.equal(info?.type,'service_account','MISSING_SERVICE_ACCOUNT');
  assert.equal(info?.project_id,'deda-25b88','WRONG_FIREBASE_PROJECT');
  assert.equal(info.client_email,'firebase-adminsdk-fbsvc@deda-25b88.iam.gserviceaccount.com',
    'UNAPPROVED_SERVICE_ACCOUNT');
  const {initializeApp,cert,deleteApp}=require('firebase-admin/app');
  const {getFirestore,FieldValue}=require('firebase-admin/firestore');
  const app=initializeApp({credential:cert(info),projectId:'deda-25b88'});
  try{
    const db=getFirestore(app),now=Date.now();
    const preflight=await releaseOneClosedWeek(db,now,{pay:false});
    console.log('OWNER_APPROVED_WEEKLY_GIFT_READONLY_PREFLIGHT',JSON.stringify(preflight));
    const result=await releaseOneClosedWeek(db,Date.now(),{
      pay:true,clockTimestamp:()=>FieldValue.serverTimestamp(),
    });
    console.log('OWNER_APPROVED_WEEKLY_GIFT_COMMIT',JSON.stringify(result));
  }finally{await deleteApp(app);}
}
if(require.main===module){
  main().catch(e=>{
    const safe=String(e?.message||e).replace(/@DEDA-[A-Z0-9]+/g,'[redacted]');
    console.error('BLOCK_OR_FAIL_WEEKLY_GIFT_PAYOUT',safe.slice(0,200));
    process.exitCode=1;
  });
}
module.exports={releaseOneClosedWeek,OWNER_DEFAULT};
