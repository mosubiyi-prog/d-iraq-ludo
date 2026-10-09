import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {before, beforeEach, after, test} from 'node:test';
import {
  initializeTestEnvironment, assertFails, assertSucceeds,
} from '@firebase/rules-unit-testing';
import {doc, getDoc, setDoc, updateDoc} from 'firebase/firestore';

const requireFromHere = createRequire(import.meta.url);
const adminRequire = createRequire(
    new URL('../../functions/package.json', import.meta.url));
const {initializeApp, deleteApp} = adminRequire('firebase-admin/app');
const {getFirestore} = adminRequire('firebase-admin/firestore');

const PROJECT = 'demo-deda-stage13-security-readiness';
const SHADOW = [
  'deda_stage9_shadow_balances',
  'deda_stage9_shadow_ledger',
  'deda_stage9_shadow_verified_events',
  'deda_stage9_shadow_daily_totals',
  'deda_stage11_shadow_login_control',
  'deda_stage11_shadow_login_audit',
];

let env, app, db;
let manager, deputy, employee, paused, legacy, normal, stranger, guest;

before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST,
      'EMULATOR_ONLY: refusing production Firestore');
  assert.equal(process.env.GCLOUD_PROJECT, PROJECT);
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: {rules: readFileSync('firestore.rules', 'utf8')},
  });
  app = initializeApp({projectId: PROJECT}, 'stage13-rules-readiness');
  db = getFirestore(app);
  manager = env.authenticatedContext('gm').firestore();
  deputy = env.authenticatedContext('deputy').firestore();
  employee = env.authenticatedContext('employee').firestore();
  paused = env.authenticatedContext('paused').firestore();
  legacy = env.authenticatedContext('legacy-roleless').firestore();
  normal = env.authenticatedContext('member').firestore();
  stranger = env.authenticatedContext('stranger').firestore();
  guest = env.unauthenticatedContext().firestore();
});

beforeEach(async () => {
  await env.clearFirestore();
  for (const [id, role, active, status] of [
    ['gm', 'general_manager', true, 'active'],
    ['deputy', 'deputy_manager', true, 'active'],
    ['employee', 'employee', true, 'active'],
    ['paused', 'general_manager', false, 'temporarily_stopped'],
  ]) {
    await db.collection('admins').doc(id).set({
      role, active, status,
      permissions: {viewAudit: role === 'general_manager'},
    });
  }
  // Existing rules have a legacy compatibility path for admins missing role.
  await db.collection('admins').doc('legacy-roleless').set({
    active: true, status: 'active',
  });
  await db.collection('admin_task_drafts')
      .doc('daily_slot_open_map').set({
        cycle: 'daily', action: 'open_map',
        titleAr: 'افتح الخريطة',
        titleEn: 'افتح الخريطة',
        targetCount: 1, rewardUnit: 'points', rewardAmount: 5,
        url: '', status: 'draft', revision: 1,
        createdByUid: 'gm', updatedByUid: 'gm',
      });
  await db.collection('admin_daily_schedule_previews')
      .doc('preview_open_map').set({
        slotId: 'open_map', action: 'open_map',
        titleAr: 'افتح الخريطة',
        status: 'pending',
        rewardUnit: 'points', rewardAmount: 5,
      });
  await db.collection('deda_daily_published_task_slots')
      .doc('open_map').set({
        slotId: 'open_map', action: 'open_map',
        titleAr: 'افتح الخريطة', rewardAmount: 5,
        rewardsEnabled: false,
        rewardClaimMode: 'disabled_until_verified_server_ledger',
      });
  await db.collection('deda_daily_task_publication_history')
      .doc('20261010__open_map').set({
        slotId: 'open_map', priorConfig: {titleAr: 'قديم'},
      });
  await db.collection('users').doc('member').set({
    accountKey: '9647000001111', points: 47,
    coins: 13, diamonds: 7,
  });
  await db.collection('admin_wallets').doc('gm').set({
    diamonds: 1000000, coins: 1000000,
  });
  await db.collection('admin_gift_wallets').doc('gm').set({
    diamonds: 800000, coins: 800000,
  });
  for (const collection of SHADOW) {
    await db.collection(collection).doc('test').set({
      uid: 'member', amount: 5000, shadowOnly: true,
    });
  }
});

after(async () => {
  if (env) await env.cleanup();
  if (app) await deleteApp(app);
});

test('Signed-in users may read a published CONFIG but anonymous clients cannot', async () => {
  for (const client of [normal, employee, deputy, manager]) {
    const got = await assertSucceeds(getDoc(doc(client,
        'deda_daily_published_task_slots', 'open_map')));
    assert.equal(got.data().rewardsEnabled, false);
  }
  await assertFails(getDoc(doc(guest,
      'deda_daily_published_task_slots', 'open_map')));
});

test('Not even a general manager may write a published task config via SDK', async () => {
  for (const client of [manager, normal, employee, deputy, guest]) {
    await assertFails(setDoc(doc(client,
        'deda_daily_published_task_slots', 'open_map'), {
      rewardsEnabled: true, rewardAmount: 5000,
    }));
  }
  assert.equal((await db.collection('deda_daily_published_task_slots')
      .doc('open_map').get()).data().rewardsEnabled, false);
});

test('Private admin daily task drafts allow only authorized managers', async () => {
  await assertSucceeds(getDoc(doc(manager,
      'admin_task_drafts', 'daily_slot_open_map')));
  for (const client of [normal, deputy, employee, paused, guest]) {
    await assertFails(getDoc(doc(client,
        'admin_task_drafts', 'daily_slot_open_map')));
  }
});

test('The private schedule requires strict general-manager role and active status', async () => {
  await assertSucceeds(getDoc(doc(manager,
      'admin_daily_schedule_previews', 'preview_open_map')));
  for (const client of [normal, deputy, employee, paused, legacy, guest]) {
    await assertFails(getDoc(doc(client,
        'admin_daily_schedule_previews', 'preview_open_map')));
  }
});

test('No client can write future schedule pretending to be a server', async () => {
  for (const client of [normal, employee, deputy, paused, guest]) {
    await assertFails(setDoc(doc(client,
        'admin_daily_schedule_previews', 'preview_open_map'), {
      slotId: 'open_map',
      action: 'visit_telegram',
      rewardAmount: 5000,
      rewardsEnabled: true,
    }));
  }
});

test('Publication history is private even from a signed-in general manager', async () => {
  for (const client of [manager, deputy, employee, normal, guest]) {
    await assertFails(getDoc(doc(client,
        'deda_daily_task_publication_history',
        '20261010__open_map')));
  }
});

test('All experimental reward and login policy collections are private', async () => {
  for (const coll of SHADOW) {
    for (const client of [manager, normal, employee, guest]) {
      await assertFails(getDoc(doc(client, coll, 'test')));
      await assertFails(setDoc(doc(client, coll, 'test'), {
        amount: 99999999,
      }));
    }
  }
});

test('An owner cannot inject coins, diamonds or points into their users document', async () => {
  const member = doc(normal, 'users', 'member');
  for (const mutation of [{coins: 999999}, {diamonds: 999999},
    {points: 999999}]) {
    await assertFails(updateDoc(member, mutation));
  }
  const original = (await db.collection('users').doc('member').get()).data();
  assert.deepEqual([original.coins, original.diamonds, original.points],
      [13, 7, 47]);
});

test('Ordinary users cannot edit manager or gift wallets to mint rewards', async () => {
  for (const coll of ['admin_wallets', 'admin_gift_wallets']) {
    await assertFails(setDoc(doc(normal, coll, 'gm'),
        {diamonds: 9000000, coins: 9000000}));
  }
  const wallet = (await db.collection('admin_wallets').doc('gm').get()).data();
  assert.equal(wallet.diamonds, 1000000);
});

test('Legacy roleless admin fallback is exposed as an explicit unresolved risk', async () => {
  // Existing rules deliberately support old roleless administrators in drafts
  // but STRICTLY require role=general_manager for new scheduling. Stage 13
  // audits this inconsistency, does not silently change old production rules.
  const draft = await assertSucceeds(getDoc(doc(legacy,
      'admin_task_drafts', 'daily_slot_open_map')));
  assert.equal(draft.exists(), true);
  await assertFails(getDoc(doc(legacy,
      'admin_daily_schedule_previews', 'preview_open_map')));
});

test('No user can modify old published evidence or task history retroactively', async () => {
  for (const client of [normal, manager, guest]) {
    await assertFails(setDoc(doc(client,
        'deda_daily_task_publication_history',
        '20261010__open_map'), {
      priorConfig: {rewardAmount: 1000000},
    }));
  }
});

test('Suspended general-manager session cannot view drafts or private previews', async () => {
  for (const coll of ['admin_task_drafts',
    'admin_daily_schedule_previews']) {
    const id = coll === 'admin_task_drafts'
      ? 'daily_slot_open_map' : 'preview_open_map';
    await assertFails(getDoc(doc(paused, coll, id)));
  }
});
