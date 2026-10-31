import {readFileSync} from 'node:fs';
import {before,after,test} from 'node:test';
import {initializeTestEnvironment,assertSucceeds,assertFails}
  from '@firebase/rules-unit-testing';
import {doc,getDoc,setDoc,updateDoc,serverTimestamp,Timestamp,writeBatch}
  from 'firebase/firestore';

const rules=readFileSync('firestore.rules','utf8');
const project='demo-deda-100405-admin-review';
const week='2026-10-31';
const id='@DEDA-AB1234';
const account='07701234567';
const uid='firebase-user-A';
const managerId='deda-general-manager';
const started=Timestamp.fromDate(new Date(Date.now()-60000));
let env,gm,user,other,agent,anonymous;

const score=(db)=>doc(db,'deda_weekly_direct_weeks',week,'scores',id);
const control=(db)=>doc(db,'deda_weekly_direct_control','active');
const review=(db)=>doc(db,'deda_weekly_direct_reviews',week,'users',id);
const notice=(db)=>doc(db,'deda_weekly_direct_notices',week,'users',id);
const scoreInitial={
  weekId:week,weekStart:started,publicId:id,displayName:'مستخدم ديدا',
  claimedKeys:['2026-10-31|open_map'],
  lastClaimKey:'2026-10-31|open_map',
  completedTasks:1,weeklyXp:20,updatedAt:serverTimestamp(),
};
const audit=(action,by)=>{
  const a={action,weekId:week,publicId:id,
    reason:'Suspicious weekly XP needs review',
    createdAt:serverTimestamp(),createdBy:by};
  return a;
};
const moderation=(frozen)=>({
  weekId:week,publicId:id,frozen,
  notice:'نقاط الدوري قيد المراجعة وسوف تستمر نقاط المستوى',
  reason:'Unexpected weekly score requires owner review',
  updatedAt:serverTimestamp(),updatedBy:managerId,
});

before(async()=>{
  env=await initializeTestEnvironment({
    projectId:project,firestore:{rules},
  });
  gm=env.authenticatedContext(managerId).firestore();
  user=env.authenticatedContext(uid).firestore();
  other=env.authenticatedContext('firebase-user-B').firestore();
  agent=env.authenticatedContext('staff-agent').firestore();
  anonymous=env.unauthenticatedContext().firestore();
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    await setDoc(doc(db,'admins',managerId),{
      role:'general_manager',active:true,status:'active',
    });
    await setDoc(doc(db,'admins','staff-agent'),{
      role:'deputy_manager',active:true,status:'active',
    });
    await setDoc(doc(db,'deda_sessions',uid),{accountKey:account});
    await setDoc(doc(db,'users',uid),{accountKey:account,sharePersonalId:id});
    await setDoc(doc(db,'deda_weekly_direct_accounts',id),{
      accountKey:account,publicId:id,createdByUid:uid,createdAt:started,
    });
    await setDoc(doc(db,'deda_share_ids',id),{
      ownerUid:uid,accountKey:account,kind:'personal',active:true,
    });
  });
});
after(async()=>{if(env) await env.cleanup();});

test('ONLY verified original general manager may pause or resume league',async()=>{
  const paused={weekId:week,paused:true,reason:'Review weekly results pending',
    updatedBy:managerId,updatedAt:serverTimestamp()};
  await assertFails(setDoc(control(user),paused));
  await assertFails(setDoc(control(agent),paused));
  await assertFails(setDoc(control(anonymous),paused));
  await assertSucceeds(setDoc(control(gm),paused));
  await assertFails(setDoc(score(user),scoreInitial));
  await assertSucceeds(getDoc(control(user)));
  const resumed={...paused,paused:false,updatedAt:serverTimestamp()};
  await assertSucceeds(setDoc(control(gm),resumed));
  await assertSucceeds(setDoc(score(user),scoreInitial));
});

test('score owner gets own freeze notice; other users do not read reason',async()=>{
  await assertFails(setDoc(review(user),moderation(true)));
  await assertFails(setDoc(review(agent),moderation(true)));
  const first=writeBatch(gm);
  first.set(review(gm),moderation(true));
  first.set(notice(gm),{
    weekId:week,publicId:id,frozen:true,
    notice:'نقاط الدوري قيد المراجعة وسوف تستمر نقاط المستوى',
    updatedAt:serverTimestamp(),updatedBy:managerId,
  });
  await assertSucceeds(first.commit());
  await assertFails(getDoc(review(user))); // Confidential manager reason.
  const myNote=await assertSucceeds(getDoc(notice(user)));
  if(myNote.data()?.frozen!==true || 'reason' in myNote.data()) {
    throw Error('owner freeze notification leaked manager reason');
  }
  await assertFails(getDoc(review(other)));
  await assertFails(getDoc(notice(other)));
  await assertFails(updateDoc(score(user),{
    claimedKeys:['2026-10-31|open_map','2026-10-31|long_trip'],
    lastClaimKey:'2026-10-31|long_trip',completedTasks:2,
    weeklyXp:40,updatedAt:serverTimestamp(),
  }));
  const cleared=writeBatch(gm);
  cleared.set(review(gm),moderation(false));
  cleared.set(notice(gm),{
    weekId:week,publicId:id,frozen:false,
    notice:'اكتملت مراجعة نقاط الدوري ورفعت الإدارة التجميد',
    updatedAt:serverTimestamp(),updatedBy:managerId,
  });
  await assertSucceeds(cleared.commit());
  await assertSucceeds(updateDoc(score(user),{
    claimedKeys:['2026-10-31|open_map','2026-10-31|long_trip'],
    lastClaimKey:'2026-10-31|long_trip',completedTasks:2,
    weeklyXp:40,updatedAt:serverTimestamp(),
  }));
});

test('immutable audit events are general-manager-only, not editable',async()=>{
  const ref=doc(gm,'deda_weekly_direct_admin_events','event-1');
  await assertFails(setDoc(doc(user,
    'deda_weekly_direct_admin_events','event-2'),audit('freeze',uid)));
  await assertSucceeds(setDoc(ref,audit('freeze',managerId)));
  await assertFails(updateDoc(ref,{reason:'Changed audit data'}));
  await assertFails(getDoc(doc(user,'deda_weekly_direct_admin_events','event-1')));
});

test('original Hadaya owner can claim backend-created weekly prize ONCE; no invented gems',async()=>{
  const gid='deda-weekly-'+week+'-'+id.slice(1);
  const gift=(database)=>doc(database,'deda_diamond_gifts',gid);
  const balance=(database)=>doc(database,'deda_diamond_gift_balances',id);
  await env.withSecurityRulesDisabled(async ctx=>{
    await setDoc(gift(ctx.firestore()),{
      giftId:gid,sourceType:'weekly_league',
      adminUid:'deda-weekly-league-system',
      adminName:'دوري DEDA',senderLabel:'إدارة DEDA',
      targetPublicId:id,targetName:'مستخدم ديدا',amount:150,
      reason:'جائزة دوري DEDA — الأسبوع '+week+' — المركز 1',
      status:'pending',createdAt:Timestamp.now(),
    });
  });
  const claim=writeBatch(user);
  claim.set(balance(user),{
    publicId:id,balance:150,lastClaimGiftId:gid,
    createdAt:serverTimestamp(),updatedAt:serverTimestamp(),
  });
  claim.update(gift(user),{
    status:'received',claimedAt:serverTimestamp(),
  });
  await assertSucceeds(claim.commit());
  const claimed=(await getDoc(balance(user))).data();
  if(claimed.balance!==150)throw Error('receipt was not credited');
  const second=writeBatch(user);
  second.update(balance(user),{
    balance:300,lastClaimGiftId:gid,updatedAt:serverTimestamp(),
  });
  second.update(gift(user),{
    status:'received',claimedAt:serverTimestamp(),
  });
  await assertFails(second.commit());
  const final=(await getDoc(balance(user))).data();
  if(final.balance!==150)throw Error('duplicate credit');
});
