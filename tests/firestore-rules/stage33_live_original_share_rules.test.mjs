import {readFileSync} from 'node:fs';
import {before,after,test} from 'node:test';
import {assertFails,assertSucceeds,initializeTestEnvironment}
  from '@firebase/rules-unit-testing';
import {doc,getDoc,setDoc,updateDoc,deleteDoc,
  serverTimestamp,Timestamp} from 'firebase/firestore';

const PROJECT='demo-deda-stage33-real-share-rules-audit';
const FILE=process.env.DEDA_STAGE24_LIVE_RULES_TMPFILE;
if(!FILE||!FILE.endsWith('.rules')) {
  throw Error('STAGE33_NEEDS_EPHEMERAL_CURRENT_DEPLOYED_RULES');
}
const LIVE_RULES=readFileSync(FILE,'utf8');
const EXPECT_UNPATCHED_SELF_SHARE_GAP=process.env.DEDA_STAGE33_EXPECT_CURRENT_SELF_SHARE_GAP==='1';
if(!LIVE_RULES.includes('rules_version')||
   !LIVE_RULES.includes('match /deda_location_shares/{shareId}'))
  throw Error('STAGE33_CANNOT_ESTABLISH_CURRENT_ORIGINAL_SHARE_RULES');
let env,sender,recipient,outsider,manager,anon;
const FROM='@DEDA-A12345',TO='@DEDA-B12345';
const U='stage33_sender',R='stage33_receiver',O='stage33_other',M='stage33_manager';
function source(overrides={}){
  const now=Date.now();
  return {
    senderUid:U,senderPublicId:FROM,senderName:'Stage33 Sender',
    recipientPublicId:TO,shareType:'current',
    placeName:'',placeId:'',latitude:35.4,longitude:44.1,
    durationMinutes:15,status:'pending',
    createdAt:serverTimestamp(),updatedAt:serverTimestamp(),
    expiresAt:Timestamp.fromMillis(now+15*60*1000),
    ...overrides,
  };
}
before(async()=>{
  env=await initializeTestEnvironment({
    projectId:PROJECT,firestore:{rules:LIVE_RULES}
  });
  sender=env.authenticatedContext(U).firestore();
  recipient=env.authenticatedContext(R).firestore();
  outsider=env.authenticatedContext(O).firestore();
  manager=env.authenticatedContext(M,{role:'general_manager'}).firestore();
  anon=env.unauthenticatedContext().firestore();
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    await setDoc(doc(db,'users',U),{
      uid:U,accountKey:'07701234567',sharePersonalId:FROM,
      name:'Stage33 Sender'
    });
    await setDoc(doc(db,'users',R),{
      uid:R,accountKey:'07707654321',sharePersonalId:TO,
      name:'Stage33 Receiver'
    });
    await setDoc(doc(db,'users',O),{
      uid:O,accountKey:'07701110000',sharePersonalId:'@DEDA-C12345',
      name:'Stage33 Outsider'
    });
    await setDoc(doc(db,'deda_share_ids',FROM),{
      active:true,kind:'personal',ownerUid:U,publicId:FROM
    });
    await setDoc(doc(db,'deda_share_ids',TO),{
      active:true,kind:'personal',ownerUid:R,publicId:TO
    });
    await setDoc(doc(db,'admins',M),{
      active:true,status:'active',role:'general_manager'
    });
  });
});
after(async()=>{if(env)await env.cleanup();});
test('ACTUAL deployed rules: canonical signed sender can create original valid share',async()=>{
  await assertSucceeds(setDoc(doc(sender,'deda_location_shares','stage33_legit'),
    source()));
});
test('owner and recipient can read original valid share; outsider/anon cannot',async()=>{
  for(const db of [sender,recipient]){
    await assertSucceeds(getDoc(doc(db,'deda_location_shares','stage33_legit')));
  }
  for(const db of [outsider,anon]){
    await assertFails(getDoc(doc(db,'deda_location_shares','stage33_legit')));
  }
});
test('sender or general manager cannot delete a persisted share',async()=>{
  for(const db of [sender,manager]){
    await assertFails(deleteDoc(doc(db,'deda_location_shares','stage33_legit')));
  }
});
test('sender cannot change previously created location or status',async()=>{
  await assertFails(updateDoc(doc(sender,'deda_location_shares','stage33_legit'),
    {latitude:99}));
  await assertFails(updateDoc(doc(sender,'deda_location_shares','stage33_legit'),
    {status:'accepted'}));
});
const disallowed=[
  ['unauthenticated',()=>anon,{}],
  ['different auth user',()=>outsider,{}],
  ['manager forgery',()=>manager,{}],
  ['caller UID is forged',()=>sender,{senderUid:O}],
  ['premium alias not linked to original owner',()=>sender,
    {senderPublicId:'@DEDA-PREMI'}],
  ['unknown recipient',()=>sender,{recipientPublicId:'@DEDA-Z99999'}],
  ...(!EXPECT_UNPATCHED_SELF_SHARE_GAP ?
    [['self-share sender equals recipient',()=>sender,{recipientPublicId:FROM}]] : []),
  ['fabricated place share',()=>sender,{shareType:'place',placeId:'fake_place'}],
  ['latitude outside earth',()=>sender,{latitude:999}],
  ['invalid duration',()=>sender,{durationMinutes:5}],
  ['prewritten timestamp not request.time',()=>sender,
    {createdAt:Timestamp.fromMillis(10000),updatedAt:Timestamp.fromMillis(10000)}],
  ['extra weekly XP field',()=>sender,{levelXpApplied:true}],
  ['extra winner rank',()=>sender,{weeklyRank:1}],
  ['wrong sender display name',()=>sender,{senderName:'Imposter'}],
  ['wrong status',()=>sender,{status:'accepted'}],
  ['non empty place name for personal share',()=>sender,{placeName:'FAKE'}],
];
for(const [label,who,changes] of disallowed){
  test('ACTUAL deployed rules reject '+label,async()=>{
    const id='attack_'+label.replace(/[^a-z]/gi,'_');
    await assertFails(setDoc(doc(who(),'deda_location_shares',id),
      source(changes)));
  });
}
if(EXPECT_UNPATCHED_SELF_SHARE_GAP){
  test('CONFIRMED current live rules gap: self-share is allowed, NOT XP authority',async()=>{
    await assertSucceeds(setDoc(doc(sender,'deda_location_shares','stage33_known_self_gap'),
      source({recipientPublicId:FROM})));
  });
}
test('raw persisted location share cannot write future private stage32 XP candidate',async()=>{
  await assertFails(setDoc(doc(sender,
    'deda_weekly_stage32_share_candidates_fixture_only/attacker'),{
      originalLevelXpApplied:true,weeklyXpGranted:true,
      diamonds:99999
    }));
});
