import {readFileSync} from 'node:fs';
import {before, after, test} from 'node:test';
import {initializeTestEnvironment, assertSucceeds, assertFails}
  from '@firebase/rules-unit-testing';
import {doc, setDoc, updateDoc, getDoc, serverTimestamp}
  from 'firebase/firestore';

const project='demo-deda-100408-prizes';
const week='2026-10-31', manager='deda-gm-100408';
const amounts=[150,100,50,10,10,10,10,10,10,10];
let env, gm, staff, user, anonymous;
const plan=(db)=>doc(db,'deda_weekly_direct_prize_plans',week);
const control=(db)=>doc(db,'deda_weekly_direct_control','active');
const value=(a,by)=>({weekId:week,amounts:a,reason:'زيادة جوائز المتصدرين أثناء الصيانة',
  updatedAt:serverTimestamp(),updatedBy:by});

before(async()=>{
  env=await initializeTestEnvironment({
    projectId:project,
    firestore:{rules:readFileSync(process.env.DEDA_DIRECT_RULES_PATH || 'firestore.rules','utf8')},
  });
  gm=env.authenticatedContext(manager).firestore();
  staff=env.authenticatedContext('league-staff').firestore();
  user=env.authenticatedContext('league-user').firestore();
  anonymous=env.unauthenticatedContext().firestore();
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    await setDoc(doc(db,'admins',manager),{
      role:'general_manager',active:true,status:'active',
    });
    await setDoc(doc(db,'admins','league-staff'),{
      role:'deputy_manager',active:true,status:'active',
    });
    await setDoc(control(db),{
      weekId:week,paused:true,reason:'صيانة أسبوعية للتحقق',
      updatedAt:serverTimestamp(),updatedBy:manager,
    });
  });
});
after(async()=>{if(env) await env.cleanup()});

test('only active GM may create paused 10-slot plan; authenticated users can read it',async()=>{
  await assertFails(setDoc(plan(user),value(amounts,'league-user')));
  await assertFails(setDoc(plan(staff),value(amounts,'league-staff')));
  await assertFails(setDoc(plan(anonymous),value(amounts,'anonymous')));
  await assertSucceeds(setDoc(plan(gm),value(amounts,manager)));
  const data=(await assertSucceeds(getDoc(plan(user)))).data();
  if(data.amounts.length!==10 || data.amounts[0]!==150)throw Error('invalid plan');
  await assertFails(getDoc(plan(anonymous)));
});

test('even GM cannot reduce any place or remove slots or exceed maximum',async()=>{
  const higher=[170,110,55,12,11,10,10,10,10,10];
  await assertSucceeds(updateDoc(plan(gm),{
    amounts:higher,reason:'زيادة جائزة مراكز الدوري',
    updatedAt:serverTimestamp(),updatedBy:manager,
  }));
  for(const bad of [
    [169,110,55,12,11,10,10,10,10,10],
    [170,110,55,12,11,10,10,10,10],
    [170,110,55,12,11,10,10,10,10,1000001],
  ]){
    await assertFails(updateDoc(plan(gm),{
      amounts:bad,reason:'مراجعة مبالغ الجوائز',
      updatedAt:serverTimestamp(),updatedBy:manager,
    }));
  }
});

test('manager prize changes require active paused week, and audit is immutable',async()=>{
  const event=doc(gm,'deda_weekly_direct_admin_events','prizes-100408');
  await assertSucceeds(setDoc(event,{
    action:'prizes_increase',weekId:week,publicId:'',
    reason:'زيادة رسمية للجوائز الأسبوعية',
    createdAt:serverTimestamp(),createdBy:manager,
  }));
  await assertFails(updateDoc(event,{reason:'تبديل سبب التدقيق'}));
  await assertSucceeds(setDoc(control(gm),{
    weekId:week,paused:false,reason:'انتهاء الصيانة والعودة للدوري',
    updatedAt:serverTimestamp(),updatedBy:manager,
  }));
  await assertFails(updateDoc(plan(gm),{
    amounts:[180,110,55,12,11,10,10,10,10,10],
    reason:'زيادة بعد الاستئناف مرفوضة',
    updatedAt:serverTimestamp(),updatedBy:manager,
  }));
});
