'use strict';
const {test,before,after}=require('node:test');
const assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore,Timestamp}=require('firebase-admin/firestore');
const {settleWeek}=require('../deda_weekly_direct_prize_worker.cjs');
const {weekStart,WEEK_MS}=require('../deda_weekly_direct_prize_plan.js');

let app,db;
const week='2026-10-31';
const first='@DEDA-PLAYER1',second='@DEDA-PLAYER2';
const started=weekStart(week);
const payday=started+WEEK_MS;
const points=(id,count,stamp=1)=>({
  weekId:week,publicId:id,displayName:'Winner '+id,
  weeklyXp:count*20,completedTasks:count,
  updatedAt:Timestamp.fromMillis(started+stamp),
});
const stamp=()=>Timestamp.now();
function scores(){return db.collection('deda_weekly_direct_weeks').doc(week).collection('scores');}
function reviews(){return db.collection('deda_weekly_direct_reviews').doc(week).collection('users');}
function gifts(){return db.collection('deda_diamond_gifts');}
before(async()=>{
  if(!process.env.FIRESTORE_EMULATOR_HOST) throw Error('NO_EMULATOR');
  app=initializeApp({projectId:'demo-deda-100405-worker'});
  db=getFirestore(app);
  for(const id of [first,second]){
    await db.collection('deda_share_ids').doc(id).set({kind:'personal',active:true});
  }
  await scores().doc(first).set(points(first,3,1));
  await scores().doc(second).set(points(second,2,2));
});
after(async()=>{if(app) await deleteApp(app);});
test('no early payout and dry-run never touches hadaya wallet',async()=>{
  await assert.rejects(()=>settleWeek(db,week,payday-1,{dryRun:true}),/NOT_YET/);
  const dry=await settleWeek(db,week,payday,{dryRun:true});
  assert.equal(dry.dryRun,true);
  assert.equal(dry.eligible,2);
  assert.equal(dry.diamonds,250);
  assert.equal((await gifts().get()).size,0);
});
test('freeze leader prevents his gift; second gets 100, no rank reassignment',async()=>{
  await reviews().doc(first).set({frozen:true});
  const r=await settleWeek(db,week,payday,{
    dryRun:false,clockTimestamp:stamp,
  });
  assert.equal(r.created,1);
  assert.equal((await gifts().get()).size,1);
  const one=(await gifts().get()).docs[0].data();
  assert.equal(one.targetPublicId,second);
  assert.equal(one.amount,100);
  assert.equal(one.sourceType,'weekly_league');
  assert.equal(one.status,'pending');
  assert.match(one.reason,/المركز 2/);
  assert.equal((await db.collection('deda_diamond_gift_balances').get()).size,0);
});
test('repeat job is idempotent and unfreeze restores held ORIGINAL prize',async()=>{
  const repeat=await settleWeek(db,week,payday+60000,{
    dryRun:false,clockTimestamp:stamp,
  });
  assert.equal(repeat.created,0);
  assert.equal(repeat.existing,1);
  await reviews().doc(first).set({frozen:false});
  const after=await settleWeek(db,week,payday+120000,{
    dryRun:false,clockTimestamp:stamp,
  });
  assert.equal(after.created,1);
  assert.equal(after.existing,1);
  const docs=(await gifts().get()).docs.map(x=>x.data());
  assert.equal(docs.length,2);
  assert.equal(docs.find(x=>x.targetPublicId===first).amount,150);
  assert.equal(docs.find(x=>x.targetPublicId===second).amount,100);
  const last=await settleWeek(db,week,payday+180000,{
    dryRun:false,clockTimestamp:stamp,
  });
  assert.equal(last.created,0);
  assert.equal(last.existing,2);
  assert.equal((await db.collection('deda_diamond_gift_balances').get()).size,0);
});
test('abnormal 20000 score fails closed; no third gift',async()=>{
  await scores().doc('@DEDA-FRAUD1').set({
    ...points('@DEDA-FRAUD1',2),
    weeklyXp:20000,
  });
  await assert.rejects(()=>settleWeek(db,week,payday+180000,{
    dryRun:false,clockTimestamp:stamp,
  }),/UNTRUSTED_SCORE_ROW/);
  assert.equal((await gifts().get()).size,2);
});
