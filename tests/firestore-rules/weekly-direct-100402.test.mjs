import {readFileSync} from 'node:fs';
import {before, after, test} from 'node:test';
import {initializeTestEnvironment, assertSucceeds, assertFails}
  from '@firebase/rules-unit-testing';
import {doc, collection, getDoc, getDocs, setDoc, updateDoc,
  serverTimestamp, Timestamp} from 'firebase/firestore';

const source=readFileSync(process.env.DEDA_DIRECT_RULES_PATH || 'firestore.rules','utf8');
const PROJECT='demo-deda-weekly-100402-direct';
const week='2026-10-31';
const start=Timestamp.fromDate(new Date(Date.now()-60000)); // emulator test clock only
const account1='07701234567',account2='07707654321';
const id1='@DEDA-AB1234',id2='@DEDA-CD5678';
let env,a,b,other,anonymous;
const path=(id)=>doc(a,'deda_weekly_direct_weeks',week,'scores',id);
const ownerPath=(id)=>doc(a,'deda_weekly_direct_accounts',id);
const payload=(id,task='2026-10-31|open_map')=>({
  weekId:week,weekStart:start,publicId:id,displayName:'مستخدم ديدا',
  claimedKeys:[task],lastClaimKey:task,completedTasks:1,weeklyXp:20,
  updatedAt:serverTimestamp(),
});

before(async()=>{
  env=await initializeTestEnvironment({projectId:PROJECT,
    firestore:{rules:source}});
  a=env.authenticatedContext('firebase-user-A').firestore();
  b=env.authenticatedContext('firebase-user-B').firestore();
  other=env.authenticatedContext('firebase-user-C').firestore();
  anonymous=env.unauthenticatedContext().firestore();
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    for(const [uid,account,id] of [
      ['firebase-user-A',account1,id1],
      ['firebase-user-B',account2,id2],
    ]){
      await setDoc(doc(db,'deda_sessions',uid),{
        uid,accountKey:account,installId:'testdevice',signedInAt:start,
      });
      await setDoc(doc(db,'users',uid),{
        accountKey:account,sharePersonalId:id,name:'مستخدم ديدا',
      });
    }
  });
});
after(async()=>{if(env)await env.cleanup();});

test('original account alone binds private ID; competitors cannot read accountKey',async()=>{
  await assertSucceeds(setDoc(ownerPath(id1),{
    accountKey:account1,publicId:id1,createdByUid:'firebase-user-A',
    createdAt:serverTimestamp(),
  }));
  await assertFails(getDoc(doc(b,'deda_weekly_direct_accounts',id1)));
  await assertFails(setDoc(doc(b,'deda_weekly_direct_accounts',id2),{
    accountKey:account1,publicId:id2,createdByUid:'firebase-user-B',
    createdAt:serverTimestamp(),
  }));
  await assertSucceeds(setDoc(doc(b,'deda_weekly_direct_accounts',id2),{
    accountKey:account2,publicId:id2,createdByUid:'firebase-user-B',
    createdAt:serverTimestamp(),
  }));
});
test('two different real-auth fixtures earn one original +20 each, share reads',async()=>{
  await assertSucceeds(setDoc(path(id1),payload(id1)));
  await assertSucceeds(setDoc(doc(b,'deda_weekly_direct_weeks',week,
    'scores',id2),payload(id2)));
  const rows=await assertSucceeds(getDocs(
    collection(b,'deda_weekly_direct_weeks',week,'scores')));
  if(rows.size!==2)throw Error('Two users must see the same two rows');
  const aRow=await assertSucceeds(getDoc(doc(b,
    'deda_weekly_direct_weeks',week,'scores',id1)));
  if(aRow.data().weeklyXp!==20)throw Error('Other user must see +20');
});
test('one more distinct task adds exactly 20; duplicate or 20k is rejected',async()=>{
  await assertSucceeds(updateDoc(path(id1),{
    claimedKeys:['2026-10-31|open_map','2026-10-31|traffic_skills'],
    lastClaimKey:'2026-10-31|traffic_skills',
    completedTasks:2,weeklyXp:40,updatedAt:serverTimestamp(),
  }));
  await assertFails(updateDoc(path(id1),{
    claimedKeys:['2026-10-31|open_map','2026-10-31|traffic_skills'],
    lastClaimKey:'2026-10-31|traffic_skills',
    completedTasks:2,weeklyXp:40,updatedAt:serverTimestamp(),
  }));
  await assertFails(updateDoc(path(id1),{
    claimedKeys:['2026-10-31|open_map','2026-10-31|traffic_skills',
      '2026-10-31|long_trip'],
    lastClaimKey:'2026-10-31|long_trip',
    completedTasks:3,weeklyXp:20000,updatedAt:serverTimestamp(),
  }));
});
test('other users cannot write score or change XP/ID',async()=>{
  await assertFails(updateDoc(doc(b,'deda_weekly_direct_weeks',week,
    'scores',id1),{weeklyXp:9999,updatedAt:serverTimestamp()}));
  await assertFails(updateDoc(doc(other,'deda_weekly_direct_weeks',week,
    'scores',id1),{weeklyXp:9999}));
  await assertFails(setDoc(doc(anonymous,'deda_weekly_direct_weeks',week,
    'scores',id1),payload(id1)));
});
