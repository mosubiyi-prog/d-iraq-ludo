'use strict';

const {plan,weekStart,WEEK_MS}=require('./deda_weekly_direct_prize_plan.js');

/**
 * Real eventual server-side settlement. Uses EXISTING هداياي pending gifts.
 * It never writes the player's balance: the unchanged owner-only claim
 * transaction already credits deda_diamond_gift_balances exactly once.
 *
 * Only run with a tightly scoped backend service identity, after owner
 * approves deployment. It does not use paid Cloud Functions or billing.
 * No player device or manager wallet may create a weekly prize.
 */
async function settleWeek(db,weekId,nowMs,{dryRun=true,clockTimestamp}={}) {
  if(!Number.isSafeInteger(nowMs) || nowMs < weekStart(weekId)+WEEK_MS) {
    throw Error('NOT_YET_SATURDAY_06_BAGHDAD');
  }
  const scoresColl=db.collection('deda_weekly_direct_weeks')
    .doc(weekId).collection('scores');
  const reviewsColl=db.collection('deda_weekly_direct_reviews')
    .doc(weekId).collection('users');
  const results=await scoresColl.limit(100).get();
  // Never silently truncate; the app's original rules cap each week to 56
  // tasks/person but no artificial 20-user score list is assumed.
  if(results.size===100) throw Error('TOO_MANY_SCORE_ROWS_MANUAL_REVIEW');
  const records=results.docs.map(d=>({id:d.id,data:d.data()}));
  const reviews=await reviewsColl.limit(100).get();
  if(reviews.size===100) throw Error('TOO_MANY_REVIEW_ROWS_MANUAL_REVIEW');
  const frozen=new Map();
  for(const d of reviews.docs) {
    if(d.data().frozen===true) frozen.set(d.id,true);
  }
  const expected=plan({weekId,atMs:nowMs,records,freezes:frozen});
  if(dryRun) return Object.freeze({
    dryRun:true,weekId,eligible:expected.winners.length,
    diamonds:expected.totalDiamonds,
    receipts:expected.winners.map(w=>w.giftId),
  });
  if(typeof clockTimestamp!=='function') {
    throw Error('SERVER_TIMESTAMP_REQUIRED');
  }

  const report={weekId,created:0,existing:0,held:0,invalid:0};
  for(const winner of expected.winners) {
    const gift=db.collection('deda_diamond_gifts').doc(winner.giftId);
    const source=scoresColl.doc(winner.publicId);
    const review=reviewsColl.doc(winner.publicId);
    const owner=db.collection('deda_share_ids').doc(winner.publicId);
    const outcome=await db.runTransaction(async tx=>{
      // All transaction reads before writes. Retry safely on Firestore conflicts.
      const [prior,score,reviewNow,personal]=await Promise.all([
        tx.get(gift),tx.get(source),tx.get(review),tx.get(owner),
      ]);
      if(prior.exists) {
        const old=prior.data();
        if(old?.targetPublicId!==winner.publicId ||
           old.amount!==winner.amount ||
           old.giftId!==winner.giftId ||
           old.sourceType!=='weekly_league') {
          throw Error('GIFT_ID_CONFLICT_STOP');
        }
        return 'existing';
      }
      if(reviewNow.exists && reviewNow.data().frozen===true) {
        return 'held';
      }
      if(!score.exists ||
          score.data().publicId!==winner.publicId ||
          score.data().weeklyXp!==
            (records.find(x=>x.id===winner.publicId)?.data.weeklyXp)) {
        return 'invalid';
      }
      if(!personal.exists || personal.data().kind!=='personal' ||
          personal.data().active!==true) {
        // Never pay a non-personal or retired identifier. No wallet credit.
        return 'invalid';
      }
      const reason='جائزة دوري DEDA — الأسبوع '+weekId+
        ' — المركز '+winner.place;
      tx.create(gift,{
        giftId:winner.giftId,
        sourceType:'weekly_league',
        adminUid:'deda-weekly-league-system',
        adminName:'دوري DEDA',
        senderLabel:'إدارة DEDA',
        targetPublicId:winner.publicId,
        targetName:winner.name,
        amount:winner.amount,
        reason,
        status:'pending',
        createdAt:clockTimestamp(),
      });
      return 'created';
    });
    report[outcome]++;
  }
  return Object.freeze(report);
}

async function main() {
  if(!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    throw Error('NO_SERVICE_ACCOUNT_CREDENTIALS');
  }
  const weekId=process.env.DEDA_LEAGUE_WEEK;
  if(!weekId) throw Error('DEDA_LEAGUE_WEEK_REQUIRED');
  // Firebase Admin SDK bypasses client rules; ONLY the protected
  // scheduled backend workflow is authorized to call this function.
  const {initializeApp,applicationDefault}=require('firebase-admin/app');
  const {getFirestore,FieldValue}=require('firebase-admin/firestore');
  initializeApp({credential:applicationDefault(),projectId:'deda-25b88'});
  const result=await settleWeek(getFirestore(),weekId,Date.now(),{
    dryRun:process.env.DEDA_LEAGUE_ACTUALLY_PAY!=='APPROVED_BY_OWNER',
    clockTimestamp:()=>FieldValue.serverTimestamp(),
  });
  console.log(JSON.stringify(result));
  if(result.dryRun) console.log('DRY_RUN_NO_PRODUCTION_WRITES');
}
if(require.main===module) {
  main().catch(error=>{
    console.error('WEEKLY_PRIZE_SETTLEMENT_FAILED:',error.message);
    process.exitCode=1;
  });
}
module.exports={settleWeek};
