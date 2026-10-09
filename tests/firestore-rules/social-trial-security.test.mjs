import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {before, after, test} from 'node:test';
import {initializeTestEnvironment, assertFails, assertSucceeds}
  from '@firebase/rules-unit-testing';
import {doc, getDoc, setDoc, updateDoc} from 'firebase/firestore';

const PROJECT = 'demo-deda-social-trial-live-rules';
let env, admin, user, deputy, guest;

before(async () => {
  assert.equal(process.env.GCLOUD_PROJECT, PROJECT);
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'Firestore emulator only');
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: {rules: readFileSync('firestore.rules', 'utf8')},
  });
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await setDoc(doc(db,'admins','owner'), {
      active:true,status:'active',role:'general_manager',
    });
    await setDoc(doc(db,'admins','deputy'), {
      active:true,status:'active',role:'deputy_manager',
    });
    await setDoc(doc(db,'deda_social_task_public','featured'), {
      taskId:'featured',platform:'telegram',action:'follow',
      title:'تابع قناة DEDA',url:'https://t.me/DEDA_Iraq',
      rewardUnit:'diamonds',rewardAmount:10,
      rewardsEnabled:false,
      rewardClaimMode:'blocked-until-trusted-proof-and-ssv-ledger',
    });
    await setDoc(doc(db,'deda_social_admin_state','featured'), {
      revision:2,status:'scheduled',
    });
    await setDoc(doc(db,'deda_social_task_audit','publish_2026-10-10'), {
      taskId:'featured',op:'publish-config-only',
    });
  });
  admin=env.authenticatedContext('owner').firestore();
  user=env.authenticatedContext('user').firestore();
  deputy=env.authenticatedContext('deputy').firestore();
  guest=env.unauthenticatedContext().firestore();
});
after(async () => {if(env)await env.cleanup();});

test('signed-in users can read verified public task config', async()=>{
  for(const client of [user,admin,deputy]) {
    const got=await assertSucceeds(getDoc(
      doc(client,'deda_social_task_public','featured')));
    assert.equal(got.data().rewardsEnabled,false);
    assert.equal(got.data().rewardAmount,10);
  }
  await assertFails(getDoc(doc(guest,'deda_social_task_public','featured')));
});

test('all client SDK writes to public publication denied including manager', async()=>{
  for(const client of [admin,user,deputy,guest]) {
    await assertFails(updateDoc(doc(client,'deda_social_task_public','featured'),
      {rewardsEnabled:true, rewardAmount:1000000}));
    await assertFails(setDoc(doc(client,'deda_social_task_public','fake'),{
      platform:'telegram',rewardsEnabled:true,
    }));
  }
});

test('even manager cannot bypass authenticated Callable private records', async()=>{
  for(const client of [admin,user,deputy,guest]) {
    await assertFails(getDoc(doc(client,'deda_social_admin_state','featured')));
    await assertFails(setDoc(doc(client,'deda_social_admin_state','featured'),
      {status:'scheduled'}));
  }
});

test('audit readable to manager only and never writable by users', async()=>{
  await assertSucceeds(getDoc(doc(admin,'deda_social_task_audit',
    'publish_2026-10-10')));
  for(const client of [user,deputy,guest]) {
    await assertFails(getDoc(doc(client,'deda_social_task_audit',
      'publish_2026-10-10')));
  }
  for(const client of [admin,user,deputy,guest]) {
    await assertFails(setDoc(doc(client,'deda_social_task_audit','fake'),
      {op:'publish',actorUid:'owner'}));
  }
});
