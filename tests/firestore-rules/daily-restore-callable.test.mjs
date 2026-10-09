import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {before, beforeEach, after, test} from 'node:test';
import {
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';

const nodeRequire = createRequire(import.meta.url);
const functionsRequire = createRequire(
    new URL('../../functions/package.json', import.meta.url));
const {initializeApp, deleteApp} = functionsRequire('firebase-admin/app');
const {getFirestore, Timestamp} = functionsRequire('firebase-admin/firestore');
const {createRestoreRequestHandler} = nodeRequire(
    '../../functions/deda_daily_task_restore_callable.js');

const PROJECT_ID = 'demo-deda-stage8-manager-restore-callable';
const SLOT = 'open_map';
const SOURCE_ID = '20261010__open_map';
const TODAY_START = new Date('2026-10-09T21:00:00.000Z');
const REQUEST_TIME = new Date('2026-10-10T14:00:00.000Z');
const TOMORROW_START = new Date('2026-10-10T21:00:00.000Z');

let env, app, db, handler;

function trustedRequest(uid = 'gm', data = {
  slotId: SLOT, publicationId: SOURCE_ID, confirmRestore: true,
}) {
  return {
    auth: uid ? {uid, token: {firebase: {sign_in_provider: 'password'}}} : null,
    app: {appId: '1:123456789:android:trusted-test-app-id'},
    data,
  };
}

async function expectCode(request, code) {
  await assert.rejects(handler(request), (error) => {
    assert.ok(error && typeof error.code === 'string');
    assert.ok(error.code === code || error.code === 'functions/' + code,
        'Expected ' + code + ' got ' + error.code);
    return true;
  });
}

async function prepare() {
  await db.collection('admins').doc('gm').set({
    role: 'general_manager', active: true, status: 'active',
    displayName: 'المدير العام',
  });
  await db.collection('admins').doc('employee').set({
    role: 'employee', active: true, status: 'active',
  });
  await db.collection('admins').doc('deputy').set({
    role: 'deputy_manager', active: true, status: 'active',
  });
  await db.collection('deda_daily_published_task_slots')
      .doc(SLOT).set({
        slotId: SLOT,
        action: 'visit_telegram',
        titleAr: 'زيارة قناة DEDA التجريبية',
        titleEn: 'زيارة قناة DEDA التجريبية',
        targetCount: 1,
        rewardUnit: 'diamonds',
        rewardAmount: 10,
        url: 'https://t.me/DEDA_Iraq',
        publicationId: SOURCE_ID,
        effectiveDay: '2026-10-10',
        effectiveAt: Timestamp.fromDate(TODAY_START),
        rewardsEnabled: false,
        rewardClaimMode: 'disabled_until_verified_server_ledger',
      });
  await db.collection('deda_daily_task_publication_history')
      .doc(SOURCE_ID).set({
        slotId: SLOT,
        effectiveDay: '2026-10-10',
        publicationId: SOURCE_ID,
        newConfig: {
          action: 'visit_telegram',
          titleAr: 'زيارة قناة DEDA التجريبية',
          targetCount: 1,
          rewardUnit: 'diamonds',
          rewardAmount: 10,
          url: 'https://t.me/DEDA_Iraq',
        },
        priorConfig: {
          action: SLOT,
          titleAr: 'افتح الخريطة',
          targetCount: 1,
          rewardUnit: 'points',
          rewardAmount: 5,
          url: '',
        },
      });
  await db.collection('admin_daily_schedule_previews')
      .doc('preview_' + SLOT).set({
        slotId: SLOT,
        action: 'visit_telegram',
        titleAr: 'زيارة قناة DEDA التجريبية',
        titleEn: 'زيارة قناة DEDA التجريبية',
        targetCount: 1,
        rewardUnit: 'diamonds',
        rewardAmount: 10,
        url: 'https://t.me/DEDA_Iraq',
        status: 'pending',
        revision: 3,
        effectiveAt: Timestamp.fromDate(TODAY_START),
        createdByUid: 'gm',
        updatedByUid: 'gm',
        createdAt: Timestamp.fromDate(new Date('2026-10-09T12:00:00Z')),
        updatedAt: Timestamp.fromDate(new Date('2026-10-09T12:00:00Z')),
      });
}

before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw Error('EMULATOR_ONLY: production is strictly forbidden');
  }
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {rules: readFileSync('firestore.rules', 'utf8')},
  });
  app = initializeApp({projectId: PROJECT_ID}, 'deda-stage8-trusted-adapter');
  db = getFirestore(app);
  handler = createRestoreRequestHandler({
    db, serverNow: () => new Date(REQUEST_TIME.getTime()),
  });
});

beforeEach(async () => {
  await env.clearFirestore();
  await prepare();
});

after(async () => {
  if (env) await env.cleanup();
  if (app) await deleteApp(app);
});

test('Only a verified manager/AppCheck request can schedule tomorrow', async () => {
  const result = await handler(trustedRequest());
  assert.equal(result.status, 'scheduled');
  assert.equal(result.slotId, SLOT);
  assert.equal(result.effectiveAt, TOMORROW_START.toISOString());
  const preview = (await db.collection('admin_daily_schedule_previews')
      .doc('preview_open_map').get()).data();
  assert.equal(preview.revision, 4);
  assert.equal(preview.status, 'pending');
  assert.equal(preview.titleAr, 'افتح الخريطة');
  assert.equal(preview.effectiveAt.toDate().toISOString(),
      TOMORROW_START.toISOString());
  assert.equal((await db.collection('admin_audit').get()).size, 1);
});

test('Rejects unsigned, anonymous and missing app-check contexts', async () => {
  await expectCode(trustedRequest(null), 'unauthenticated');
  const anonymous = trustedRequest();
  anonymous.auth.token.firebase.sign_in_provider = 'anonymous';
  await expectCode(anonymous, 'unauthenticated');
  const missingAppCheck = trustedRequest();
  missingAppCheck.app = null;
  await expectCode(missingAppCheck, 'failed-precondition');
  assert.equal((await db.collection('admin_audit').get()).size, 0);
});

test('Rejects caller-supplied uid, role, timestamp, injected DB and unknown keys', async () => {
  for (const extra of [
    {requesterUid: 'gm'},
    {adminUid: 'gm'},
    {trustedNow: '2026-10-10T21:01:00Z'},
    {role: 'general_manager'},
    {db: {runTransaction: true}},
    {effectiveAt: TOMORROW_START.toISOString()},
    {rewardsEnabled: true},
  ]) {
    await expectCode(trustedRequest('employee', {
      slotId: SLOT, publicationId: SOURCE_ID, confirmRestore: true, ...extra,
    }), 'invalid-argument');
  }
  await expectCode(trustedRequest('gm', {
    slotId: SLOT, publicationId: SOURCE_ID,
  }), 'invalid-argument');
  await expectCode(trustedRequest('gm', {
    slotId: SLOT, publicationId: SOURCE_ID, confirmRestore: 'true',
  }), 'invalid-argument');
  assert.equal((await db.collection('admin_audit').get()).size, 0);
});

test('Employee, deputy and disabled manager cannot use forged task restore', async () => {
  await expectCode(trustedRequest('employee'), 'permission-denied');
  await expectCode(trustedRequest('deputy'), 'permission-denied');
  await db.collection('admins').doc('gm').update({
    active: false, status: 'stopped',
  });
  await expectCode(trustedRequest(), 'permission-denied');
  assert.equal((await db.collection('admin_audit').get()).size, 0);
});

test('Unknown task IDs, login reward and mismatched publication IDs blocked', async () => {
  for (const [slotId, publicationId] of [
    ['daily_login', '20261010__daily_login'],
    ['fake_slot', '20261010__fake_slot'],
    ['open_map', '20261011__open_map'],
    ['open_map', '20261010__traffic_skills'],
    ['open_map', '../../../admin_wallets'],
  ]) {
    const request = trustedRequest('gm', {
      slotId, publicationId, confirmRestore: true,
    });
    if (slotId === 'open_map' && publicationId === '20261011__open_map') {
      await expectCode(request, 'failed-precondition');
    } else {
      await expectCode(request, 'invalid-argument');
    }
  }
  assert.equal((await db.collection('admin_audit').get()).size, 0);
});

test('Restore replays are idempotent, no duplicate audit or writes', async () => {
  const results = await Promise.all([
    handler(trustedRequest()), handler(trustedRequest()),
  ]);
  assert.deepEqual(results.map(r => r.status).sort(),
      ['already-scheduled', 'scheduled']);
  assert.equal((await handler(trustedRequest())).status,
      'already-scheduled');
  assert.equal((await db.collection('admin_audit').get()).size, 1);
  const preview = (await db.collection('admin_daily_schedule_previews')
      .doc('preview_open_map').get()).data();
  assert.equal(preview.revision, 4);
});

test('A future competing task update must not be overwritten', async () => {
  await db.collection('admin_daily_schedule_previews')
      .doc('preview_open_map').update({
        status: 'pending',
        effectiveAt: Timestamp.fromDate(TOMORROW_START),
      });
  await expectCode(trustedRequest(), 'aborted');
  assert.equal((await db.collection('admin_audit').get()).size, 0);
});

test('Malformed prior config and previous overwritten publication both rejected', async () => {
  await db.collection('deda_daily_task_publication_history')
      .doc(SOURCE_ID).update({
        'priorConfig.action': 'visit_telegram',
        'priorConfig.url': 'https://t.me.evil.example/channel',
      });
  await expectCode(trustedRequest(), 'failed-precondition');
  await db.collection('deda_daily_published_task_slots').doc(SLOT).update({
    publicationId: '20261011__open_map',
  });
  await expectCode(trustedRequest(), 'failed-precondition');
  assert.equal((await db.collection('admin_audit').get()).size, 0);
});

test('Ignoring fake client timestamps never changes server-defined Iraqi day', async () => {
  const altered = trustedRequest('gm', {
    slotId: SLOT, publicationId: SOURCE_ID, confirmRestore: true,
    now: '2099-01-01',
  });
  await expectCode(altered, 'invalid-argument');
  const actual = await handler(trustedRequest());
  assert.equal(actual.effectiveAt, TOMORROW_START.toISOString());
});

test('No wallet or balances altered by a valid restored preview', async () => {
  await db.collection('admin_wallets').doc('gm').set({
    diamonds: 1000000, coins: 1000000,
  });
  await db.collection('users').doc('u1').set({
    points: 45, coins: 33, diamonds: 27,
  });
  const beforeManager = (await db.collection('admin_wallets').doc('gm').get()).data();
  const beforeUser = (await db.collection('users').doc('u1').get()).data();
  await handler(trustedRequest());
  const afterManager = (await db.collection('admin_wallets').doc('gm').get()).data();
  const afterUser = (await db.collection('users').doc('u1').get()).data();
  assert.deepEqual(afterManager, beforeManager);
  assert.deepEqual(afterUser, beforeUser);
  const live = (await db.collection('deda_daily_published_task_slots')
      .doc(SLOT).get()).data();
  assert.equal(live.action, 'visit_telegram');
  assert.equal(live.rewardAmount, 10);
  assert.equal(live.rewardsEnabled, false);
});
