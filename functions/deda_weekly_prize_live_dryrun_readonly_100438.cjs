'use strict';
/**
 * DEDA weekly prize read-only preflight. No write calls.
 * This script is safe before the actual Saturday 06:00 Baghdad settlement.
 * Never report individual IDs, names, gift IDs or balance values to CI.
 */
const assert=require('node:assert/strict');
const {initializeApp,cert,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {settleWeek}=require('./deda_weekly_direct_prize_worker.cjs');
const {weekStart,WEEK_MS}=require('./deda_weekly_direct_prize_plan.js');
async function main() {
  const info=JSON.parse(process.env.DEDA_FIREBASE_SERVICE_KEY||'null');
  assert.equal(info?.type,'service_account','APPROVED_CREDENTIAL_REQUIRED');
  assert.equal(info.project_id,'deda-25b88','WRONG_PROJECT_ABORT');
  assert.equal(info.client_email,'firebase-adminsdk-fbsvc@deda-25b88.iam.gserviceaccount.com','WRONG_IDENTITY_ABORT');
  const week=process.env.DEDA_LEAGUE_WEEK;
  assert.match(week||'',/^20\d\d-\d\d-\d\d$/,'WEEK_REQUIRED');
  const app=initializeApp({credential:cert(info),projectId:'deda-25b88'});
  try{
    const db=getFirestore(app);
    const plan=await db.collection('deda_weekly_direct_prize_plans').doc(week).get();
    assert.equal(plan.exists,true,'MISSING_OWNER_APPROVED_PLAN_NO_LEGACY_FALLBACK');
    const amounts=plan.data()?.amounts;
    assert.equal(Array.isArray(amounts),true);
    assert.equal(amounts.length,10);
    const planned=await settleWeek(db,week,weekStart(week)+WEEK_MS,{dryRun:true});
    const scoreDocs=await db.collection('deda_weekly_direct_weeks').doc(week)
      .collection('scores').limit(100).get();
    assert.equal(scoreDocs.size<100,true,'TOO_MANY_SCORES');
    const recipientRefs=scoreDocs.docs.map(d=>db.collection('deda_share_ids').doc(d.id));
    const owners=await Promise.all(recipientRefs.map(ref=>ref.get()));
    if(owners.some(d=>!d.exists||d.data()?.kind!=='personal'||d.data()?.active!==true))
      throw Error('SOME_SCORE_IDS_NOT_ACTIVE_PERSONAL_REVIEW_REQUIRED');
    assert.equal(planned.eligible<=10,true);
    assert.equal(planned.eligible>0,true,'EMPTY_WEEK_NO_PAYOUT');
    const report={
      status:'PASS_LIVE_FIRESTORE_READ_ONLY_DRY_RUN_NOT_A_REAL_PAYOUT',
      weekId:week,
      scoreRows:scoreDocs.size,
      eligibleWinners:planned.eligible,
      prospectiveDiamonds:planned.diamonds,
      expectedIfTwo:planned.eligible===2?250+200:null,
      noProductionWrites:true,
      actualPayoutAuthorizedByThisCheck:false
    };
    console.log(JSON.stringify(report));
  }finally{await deleteApp(app);}
}
main().catch(e=>{
  // Avoid printing Google API error bodies and user IDs.
  console.error('BLOCK_WEEKLY_PRIZE_DRYRUN:'+String(e.message||e).split('\n')[0].slice(0,160));
  process.exitCode=1;
});
