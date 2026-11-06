'use strict';
const {test,before,after}=require('node:test');
const assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore,Timestamp}=require('firebase-admin/firestore');
const {settleWeek}=require('../deda_weekly_direct_prize_worker.cjs');
const {weekStart,WEEK_MS}=require('../deda_weekly_direct_prize_plan.js');

const WEEK='2026-11-07';
const ONE='@DEDA-PAYOUT1',TWO='@DEDA-PAYOUT2';
const paidAt=weekStart(WEEK)+WEEK_MS;
const approved=[250,200,150,100,100,100,100,100,100,100];
let app,db;
const scores=()=>db.collection('deda_weekly_direct_weeks').doc(WEEK).collection('scores');
const gifts=()=>db.collection('deda_diamond_gifts');
const prizePlan=()=>db.collection('deda_weekly_direct_prize_plans').doc(WEEK);
const point=(id,count,stamp)=>({
  weekId:WEEK,publicId:id,displayName:'Demo payout recipient',
  weeklyXp:20*count,completedTasks:count,
  updatedAt:Timestamp.fromMillis(weekStart(WEEK)+stamp),
});
before(async()=>{
  if(!process.env.FIRESTORE_EMULATOR_HOST)throw Error('EMULATOR_REQUIRED_NO_PROD');
  app=initializeApp({projectId:'demo-deda-100405-worker'});
  db=getFirestore(app);
  await prizePlan().set({weekId:WEEK,amounts:approved,updatedAt:Timestamp.now()});
  await scores().doc(ONE).set(point(ONE,3,1));
  await scores().doc(TWO).set(point(TWO,2,2));
  for(const id of [ONE,TWO])
    await db.collection('deda_share_ids').doc(id).set({kind:'personal',active:true});
});
after(async()=>{if(app)await deleteApp(app);});

test('the only two real qualified participants receive 250+200; no empty rank is rewarded',async()=>{
  const dry=await settleWeek(db,WEEK,paidAt,{dryRun:true});
  assert.equal(dry.dryRun,true);
  assert.equal(dry.eligible,2);
  assert.equal(dry.diamonds,450);
  assert.equal((await gifts().get()).size,0);
  const write=await settleWeek(db,WEEK,paidAt,{
    dryRun:false,clockTimestamp:()=>Timestamp.now(),
  });
  assert.equal(write.created,2);
  const rows=(await gifts().get()).docs.map(d=>d.data()).filter(d=>d.sourceType==='weekly_league');
  assert.equal(rows.length,2);
  assert.equal(rows.find(x=>x.targetPublicId===ONE).amount,250);
  assert.equal(rows.find(x=>x.targetPublicId===TWO).amount,200);
  assert.equal(rows.every(x=>x.status==='pending'),true);
  assert.equal((await db.collection('deda_diamond_gift_balances').get()).size,0);
});

test('repeat is exactly-once; changing plan after payout refuses silent extra/incorrect gifts',async()=>{
  const again=await settleWeek(db,WEEK,paidAt+30000,{
    dryRun:false,clockTimestamp:()=>Timestamp.now(),
  });
  assert.equal(again.created,0);
  assert.equal(again.existing,2);
  await prizePlan().set({weekId:WEEK,amounts:[300,...approved.slice(1)]});
  await assert.rejects(
    ()=>settleWeek(db,WEEK,paidAt+60000,{
      dryRun:false,clockTimestamp:()=>Timestamp.now(),
    }),/GIFT_ID_CONFLICT_STOP/
  );
  assert.equal((await gifts().get()).size,2);
});

test('invalid custom plan fails closed instead of reverting silently to low old prizes',async()=>{
  const other='2026-11-14';
  const early=weekStart(other)+WEEK_MS;
  await db.collection('deda_weekly_direct_prize_plans').doc(other)
    .set({weekId:other,amounts:[1,2,3]});
  await assert.rejects(
    ()=>settleWeek(db,other,early,{dryRun:true}),/INVALID_WEEK_PRIZE_PLAN_STOP/
  );
});

test('subsequent week with no special GM plan inherits the approved 250/200/150/100, NOT 150/100/50/10',async()=>{
  const future='2026-11-21';
  const start=weekStart(future);
  const doc=db.collection('deda_weekly_direct_weeks').doc(future).collection('scores').doc(ONE);
  await doc.set({
    weekId:future,publicId:ONE,displayName:'Verified future winner',
    weeklyXp:60,completedTasks:3,updatedAt:Timestamp.fromMillis(start+1),
  });
  const result=await settleWeek(db,future,start+WEEK_MS,{dryRun:true});
  assert.equal(result.eligible,1);
  assert.equal(result.diamonds,250);
});
test('administrator pause blocks all weekly payouts, even pending eligible prizes',async()=>{
  const future='2026-11-21';
  const ctrl=db.collection('deda_weekly_direct_control').doc('active');
  await ctrl.set({paused:true,weekId:future});
  await assert.rejects(
    ()=>settleWeek(db,future,weekStart(future)+WEEK_MS,{dryRun:true}),
    /WEEKLY_LEAGUE_PAUSED_NO_PAYOUT/
  );
  await ctrl.set({paused:false,weekId:future});
});
