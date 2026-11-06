import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {before,after,test} from 'node:test';
import {
  initializeTestEnvironment,assertSucceeds,assertFails
} from '@firebase/rules-unit-testing';
import {
  doc,setDoc,getDoc,collection,query,getDocs,orderBy,documentId,startAt,endAt
} from 'firebase/firestore';

const PROJECT='demo-deda-admin-winners-100439';
const WEEK='2026-10-31';
const ID1='@DEDA-AAAA11',ID2='@DEDA-BBBB22';
let env,gm,staff,member,guest;
const ref=(db,col,id)=>doc(db,col,id);
const prizeId=(id)=>'deda-weekly-'+WEEK+'-'+id.slice(1);
const scores=(db)=>collection(db,'deda_weekly_direct_weeks',WEEK,'scores');
const reviews=(db)=>collection(db,'deda_weekly_direct_reviews',WEEK,'users');
const receipts=(db)=>{
  const prefix='deda-weekly-'+WEEK+'-';
  return query(collection(db,'deda_diamond_gifts'),orderBy(documentId()),
      startAt(prefix),endAt(prefix+'\uf8ff'));
};

before(async()=>{
  assert.equal(process.env.GCLOUD_PROJECT,PROJECT);
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST,'EMULATOR_ONLY');
  env=await initializeTestEnvironment({
    projectId:PROJECT,
    firestore:{rules:readFileSync(
      process.env.DEDA_LIVE_RULES_PATH||'firestore.rules','utf8')},
  });
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    await setDoc(ref(db,'admins','gm'),{
      role:'general_manager',active:true,status:'active',
    });
    await setDoc(ref(db,'admins','staff'),{
      role:'deputy_manager',active:true,status:'active',
    });
    for(const [id,name,score,rank,status,amount] of [
      [ID1,'هناء',540,1,'pending',250],
      [ID2,'سالم حسن',220,2,'received',200],
    ]){
      await setDoc(doc(db,'deda_weekly_direct_weeks',WEEK,'scores',id),{
        weekId:WEEK,publicId:id,displayName:name,
        weeklyXp:score,completedTasks:score/20,
        updatedAt:new Date('2026-11-02T12:00:00Z'),
      });
      await setDoc(ref(db,'deda_diamond_gifts',prizeId(id)),{
        giftId:prizeId(id),sourceType:'weekly_league',
        targetPublicId:id,targetName:name,
        amount,status,reason:'جائزة دوري DEDA — الأسبوع '+WEEK+' — المركز '+rank,
      });
    }
    await setDoc(ref(db,'deda_weekly_direct_prize_plans',WEEK),{
      weekId:WEEK,amounts:[250,200,150,100,100,100,100,100,100,100],
    });
    await setDoc(doc(db,'deda_weekly_direct_reviews',WEEK,'users',ID1),{
      weekId:WEEK,publicId:ID1,frozen:false,
    });
  });
  gm=env.authenticatedContext('gm').firestore();
  staff=env.authenticatedContext('staff').firestore();
  member=env.authenticatedContext('member').firestore();
  guest=env.unauthenticatedContext().firestore();
});
after(async()=>{if(env)await env.cleanup();});

test('active general manager can query only intended weekly gift IDs and exact actual statuses',async()=>{
  const rows=await assertSucceeds(getDocs(receipts(gm)));
  assert.equal(rows.docs.length,2);
  const map=new Map(rows.docs.map(d=>[d.id,d.data()]));
  assert.equal(map.get(prizeId(ID1)).amount,250);
  assert.equal(map.get(prizeId(ID1)).status,'pending');
  assert.equal(map.get(prizeId(ID2)).amount,200);
  assert.equal(map.get(prizeId(ID2)).status,'received');
});
test('manager reads verified points, freeze reviews and per-week approved prize amounts',async()=>{
  assert.equal((await assertSucceeds(getDocs(scores(gm)))).docs.length,2);
  assert.equal((await assertSucceeds(getDocs(reviews(gm)))).docs.length,1);
  const plan=await assertSucceeds(getDoc(ref(gm,'deda_weekly_direct_prize_plans',WEEK)));
  assert.deepEqual(plan.data().amounts,[250,200,150,100,100,100,100,100,100,100]);
});
test('staff and ordinary users cannot inspect other players Hadaya prizes',async()=>{
  await assertFails(getDocs(receipts(staff)));
  await assertFails(getDocs(receipts(member)));
  await assertFails(getDocs(receipts(guest)));
  await assertFails(getDocs(reviews(staff)));
});
