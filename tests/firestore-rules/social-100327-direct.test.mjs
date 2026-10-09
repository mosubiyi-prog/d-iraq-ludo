import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {before, after, test} from 'node:test';
import {initializeTestEnvironment, assertSucceeds, assertFails}
  from '@firebase/rules-unit-testing';
import {doc, getDoc, setDoc, updateDoc, writeBatch,
  serverTimestamp, Timestamp} from 'firebase/firestore';

const PROJECT='demo-deda-100327-firestore-no-functions';
let env, owner, deputy, user, guest;

function iraqDay(offset=0) {
  const shifted=new Date(Date.now()+3*60*60*1000);
  shifted.setUTCDate(shifted.getUTCDate()+offset);
  const day=shifted.toISOString().slice(0,10);
  const [year,month,date]=day.split('-').map(Number);
  return {
    day,year,month,date,
    at:Timestamp.fromDate(new Date(
      Date.UTC(year,month-1,date,0,0,0)-3*60*60*1000)),
  };
}
const title='تابع قناة DEDA الرسمية على تليجرام';
const link='https://t.me/DEDA_Iraq';
function draftData(uid='gm') {
  return {
    platform:'telegram',action:'follow',title,url:link,
    rewardUnit:'diamonds',rewardAmount:10,
    doubleWithRewardedAd:false,otherPlatform:'',otherAction:'',
    rewardsEnabled:false,status:'draft',revision:1,
    scheduledDay:'',activateAt:null,
    createdByUid:uid,updatedByUid:uid,
    createdAt:serverTimestamp(),updatedAt:serverTimestamp(),
  };
}
function dayData(when, uid='gm') {
  return {
    dayId:when.day,year:when.year,month:when.month,day:when.date,
    activateAt:when.at,status:'scheduled',revision:1,
    platform:'telegram',action:'follow',title,url:link,
    rewardUnit:'diamonds',rewardAmount:10,
    doubleWithRewardedAd:false,rewardsEnabled:false,
    rewardClaimMode:'blocked-until-trusted-proof-and-ssv-ledger',
    createdByUid:uid,updatedByUid:uid,
    createdAt:serverTimestamp(),updatedAt:serverTimestamp(),
  };
}
const draft=(c)=>doc(c,'deda_social_direct_drafts','featured');
const day=(c,id)=>doc(c,'deda_social_direct_days',id);

before(async()=>{
  assert.equal(process.env.GCLOUD_PROJECT,PROJECT);
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST,'no real firebase tests');
  env=await initializeTestEnvironment({
    projectId:PROJECT,
    firestore:{rules:readFileSync('firestore.rules','utf8')},
  });
  await env.withSecurityRulesDisabled(async (ctx)=>{
    const db=ctx.firestore();
    for(const [id,role,active] of [
      ['gm','general_manager',true],
      ['deputy','deputy_manager',true],
      ['legacy',null,true],
      ['paused','general_manager',false],
    ]) {
      const data={active,status:active?'active':'disabled'};
      if(role)data.role=role;
      await setDoc(doc(db,'admins',id),data);
    }
  });
  owner=env.authenticatedContext('gm').firestore();
  deputy=env.authenticatedContext('deputy').firestore();
  user=env.authenticatedContext('member').firestore();
  guest=env.unauthenticatedContext().firestore();
});
after(async()=>{if(env)await env.cleanup();});

test('strict manager can save draft, no others may read or write it',async()=>{
  await assertSucceeds(setDoc(draft(owner),draftData()));
  for(const c of [user,deputy,guest,
    env.authenticatedContext('legacy').firestore(),
    env.authenticatedContext('paused').firestore()]){
    await assertFails(getDoc(draft(c)));
    await assertFails(setDoc(draft(c),draftData('gm')));
  }
  assert.equal((await assertSucceeds(getDoc(draft(owner)))).data().rewardAmount,10);
});

test('forge payout / other platform / insecure URLs are rejected',async()=>{
  for(const payload of [
    {...draftData(),rewardsEnabled:true},
    {...draftData(),url:'https://t.me.evil.org/DEDA_Iraq'},
    {...draftData(),url:'https://t.me/DEDA_Iraq?start=evil'},
    {...draftData(),platform:'other'},
    {...draftData(),rewardAmount:5000000},
  ]){
    await assertFails(setDoc(draft(owner),payload));
  }
});

test('GM can atomically schedule tomorrow, but cannot expose it early',async()=>{
  const tomorrow=iraqDay(1);
  const batch=writeBatch(owner);
  batch.set(day(owner,tomorrow.day),dayData(tomorrow));
  batch.update(draft(owner),{
    status:'scheduled',revision:2,scheduledDay:tomorrow.day,
    activateAt:tomorrow.at,updatedByUid:'gm',
    updatedAt:serverTimestamp(),
  });
  await assertSucceeds(batch.commit());
  await assertFails(getDoc(day(user,tomorrow.day)));
  await assertFails(getDoc(day(guest,tomorrow.day)));
  const record=await assertSucceeds(getDoc(day(owner,tomorrow.day)));
  assert.equal(record.data().rewardsEnabled,false);
  assert.equal(record.data().title,title);
});

test('tampering with a scheduled reward or cancelling without revision fails',async()=>{
  const tomorrow=iraqDay(1);
  await assertFails(updateDoc(day(owner,tomorrow.day),
    {rewardAmount:1000}));
  await assertFails(updateDoc(day(user,tomorrow.day),
    {status:'cancelled',revision:2,updatedAt:serverTimestamp()}));
});

test('GM can cancel before Baghdad midnight, and user can never see cancellation',async()=>{
  const tomorrow=iraqDay(1);
  const batch=writeBatch(owner);
  batch.update(day(owner,tomorrow.day),{
    status:'cancelled',revision:2,updatedByUid:'gm',
    updatedAt:serverTimestamp(),
  });
  batch.update(draft(owner),{
    status:'cancelled',revision:3,updatedByUid:'gm',
    updatedAt:serverTimestamp(),
  });
  await assertSucceeds(batch.commit());
  await assertFails(getDoc(day(user,tomorrow.day)));
});

test('a task that is due TODAY may be seen only online by signed-in user',async()=>{
  const today=iraqDay(0);
  await env.withSecurityRulesDisabled(async ctx=>{
    await setDoc(day(ctx.firestore(),today.day),{
      ...dayData(today),createdAt:Timestamp.now(),updatedAt:Timestamp.now(),
    });
  });
  const got=await assertSucceeds(getDoc(day(user,today.day)));
  assert.equal(got.data().url,link);
  assert.equal(got.data().rewardsEnabled,false);
  await assertFails(getDoc(day(guest,today.day)));
  await assertFails(updateDoc(day(owner,today.day),{
    rewardAmount:20,updatedAt:serverTimestamp(),
  }));
});

test('past date not visible and future date cannot be forged by manager',async()=>{
  const future=iraqDay(2);
  const old=iraqDay(-1);
  await env.withSecurityRulesDisabled(async ctx=>{
    await setDoc(day(ctx.firestore(),old.day),{
      ...dayData(old),createdAt:Timestamp.now(),updatedAt:Timestamp.now(),
    });
  });
  await assertFails(getDoc(day(user,old.day)));
  const invalid=dayData(future);
  invalid.activateAt=Timestamp.fromDate(new Date(Date.now()+60000));
  await assertFails(setDoc(day(owner,future.day),invalid));
});
