const {test} = require('node:test');
const assert = require('node:assert/strict');
const {plan,weekStart,PRIZES,WEEK_MS} = require('../deda_weekly_direct_prize_plan.js');

const weekId='2026-10-31';
const ref=weekStart(weekId);
const record=(n,points,stamp=n)=>({
  id:'@DEDA-'+String(n).padStart(6,'0'),
  data:{
    publicId:'@DEDA-'+String(n).padStart(6,'0'),
    weekId,displayName:'DEDA user '+n,
    weeklyXp:points,completedTasks:points/20,updatedAt:ref + stamp,
  }
});
test('at 05:59 Baghdad next Saturday not a single diamond gift',()=>{
  assert.throws(()=>plan({weekId,atMs:ref+WEEK_MS-1,
    records:[record(1,20)]}),/AWARDS_BEFORE/);
  assert.equal(PRIZES.reduce((s,x)=>s+x,0),370);
});
test('after Saturday 06 rank 1..10 exact diamonds, no double ID',()=>{
  const results=plan({
    weekId,atMs:ref+WEEK_MS,
    records:Array.from({length:12},(_,i)=>record(i+1,240-i*20)),
  });
  assert.deepEqual(results.winners.map(x=>x.place),
    [1,2,3,4,5,6,7,8,9,10]);
  assert.deepEqual(results.winners.map(x=>x.amount),
    [150,100,50,10,10,10,10,10,10,10]);
  assert.equal(results.totalDiamonds,370);
  assert.equal(new Set(results.winners.map(x=>x.giftId)).size,10);
  const rerun=plan({
    weekId,atMs:ref+WEEK_MS+3600000,
    records:Array.from({length:12},(_,i)=>record(i+1,240-i*20)),
  });
  assert.deepEqual(results.winners,rerun.winners);
});
test('frozen rank held from gift, not stolen by rank 11',()=>{
  const rows=Array.from({length:12},(_,i)=>record(i+1,240-i*20));
  const freezes=new Map([['@DEDA-000001',true],['@DEDA-000004',true]]);
  const result=plan({weekId,atMs:ref+WEEK_MS,records:rows,freezes});
  assert.deepEqual(result.winners.map(x=>x.place),[2,3,5,6,7,8,9,10]);
  assert.equal(result.totalDiamonds,370-150-10);
  assert.equal(result.winners.some(x=>x.publicId==='@DEDA-000011'),false);
});
test('fake 20000, duplicate, invalid week or backdate strictly rejected',()=>{
  assert.throws(()=>plan({weekId,atMs:ref+WEEK_MS,
    records:[record(1,20000)]}),/UNTRUSTED_SCORE_ROW/);
  assert.throws(()=>plan({weekId,atMs:ref+WEEK_MS,
    records:[record(1,20),record(1,20)]}),/UNTRUSTED_SCORE_ROW/);
  assert.throws(()=>weekStart('2026-11-01'),/NOT_A_DEDA_WEEK/);
  assert.throws(()=>weekStart('2026-02-30'),/NOT_A_DEDA_WEEK/);
  assert.throws(()=>plan({weekId:'2026-11-07',
    atMs:ref+WEEK_MS,records:[]}),/AWARDS_BEFORE/);
});
test('ties deterministic by earlier XP receipt then public ID',()=>{
  const results=plan({weekId,atMs:ref+WEEK_MS,records:[
    record(3,40,2),record(1,40,1),record(2,40,2),
  ]});
  assert.deepEqual(results.winners.map(x=>x.publicId),[
    '@DEDA-000001','@DEDA-000002','@DEDA-000003',
  ]);
});
