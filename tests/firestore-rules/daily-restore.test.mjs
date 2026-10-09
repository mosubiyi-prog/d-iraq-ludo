import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {before, after, beforeEach, test} from 'node:test';
import {
  initializeTestEnvironment, assertFails, assertSucceeds,
} from '@firebase/rules-unit-testing';
import {doc, getDoc, setDoc} from 'firebase/firestore';

const require = createRequire(import.meta.url);
const fnRequire = createRequire(new URL('../../functions/package.json', import.meta.url));
const {initializeApp, deleteApp} = fnRequire('firebase-admin/app');
const {getFirestore, Timestamp} = fnRequire('firebase-admin/firestore');
const {
  nextIraqMidnightUtc, restoreDecision, schedulePreviousDailyTask,
} = require('../../functions/deda_daily_task_restore.js');
const {publishDueDailySlots} = require(
    '../../functions/deda_daily_task_publisher.js');

const PROJECT = 'demo-deda-daily-task-restore';
const SLOT = 'open_map';
const HISTORY_ID = '20261010__open_map';
const INITIAL = new Date('2026-10-09T21:00:00.000Z');
const NOW = new Date('2026-10-10T14:00:00.000Z');
const NEXT = new Date('2026-10-10T21:00:00.000Z');

let env, app, db, ordinary;

function defaultPrior() {
  return {
    action: SLOT,
    titleAr: 'افتح الخريطة',
    targetCount: 1, rewardUnit: 'points', rewardAmount: 5, url: '',
  };
}

async function seed({
  adminRole = 'general_manager', adminActive = true,
  currentId = HISTORY_ID, previous = defaultPrior(),
  previewEffective = INITIAL, previewStatus = 'pending',
} = {}) {
  await db.collection('admins').doc('gm').set({
    role: adminRole, active: adminActive,
    status: adminActive ? 'active' : 'stopped',
    displayName: 'مدير تجريبي',
  });
  await db.collection('admins').doc('employee').set({
    role: 'employee', active: true, status: 'active',
  });
  await db.collection('deda_daily_published_task_slots').doc(SLOT).set({
    slotId: SLOT, action: 'visit_telegram',
    titleAr: 'زيارة تليجرام التجريبية',
    titleEn: 'زيارة تليجرام التجريبية',
    targetCount: 1, rewardUnit: 'diamonds', rewardAmount: 12,
    url: 'https://t.me/DEDA_Iraq',
    effectiveDay: '2026-10-10',
    effectiveAt: Timestamp.fromDate(INITIAL),
    publicationId: currentId,
    rewardsEnabled: false,
    rewardClaimMode: 'disabled_until_verified_server_ledger',
    publishedAt: Timestamp.fromDate(new Date('2026-10-09T21:01:00.000Z')),
  });
  await db.collection('deda_daily_task_publication_history')
      .doc(HISTORY_ID).set({
        publicationId: HISTORY_ID, slotId: SLOT, effectiveDay: '2026-10-10',
        priorConfig: previous,
        newConfig: {
          action: 'visit_telegram', titleAr: 'زيارة تليجرام التجريبية',
          targetCount: 1, rewardUnit: 'diamonds', rewardAmount: 12,
          url: 'https://t.me/DEDA_Iraq',
        },
      });
  await db.collection('admin_daily_schedule_previews')
      .doc('preview_' + SLOT).set({
        slotId: SLOT,
        action: 'visit_telegram',
        titleAr: 'زيارة تليجرام التجريبية',
        titleEn: 'زيارة تليجرام التجريبية',
        targetCount: 1, rewardUnit: 'diamonds', rewardAmount: 12,
        url: 'https://t.me/DEDA_Iraq',
        status: previewStatus, revision: 4,
        effectiveAt: Timestamp.fromDate(previewEffective),
        createdByUid: 'gm', updatedByUid: 'gm',
        createdAt: Timestamp.fromDate(new Date('2026-10-09T14:00:00Z')),
        updatedAt: Timestamp.fromDate(new Date('2026-10-09T14:00:00Z')),
      });
}

async function restore(uid = 'gm', slot = SLOT, id = HISTORY_ID,
    instant = NOW) {
  return schedulePreviousDailyTask(db, {
    slotId: slot, publicationId: id, requesterUid: uid, trustedNow: instant,
  });
}

before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw Error('EMULATOR_ONLY: refusing without local Firestore emulator');
  }
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: {rules: readFileSync('firestore.rules', 'utf8')},
  });
  app = initializeApp({projectId: PROJECT}, 'deda-restore-prototype');
  db = getFirestore(app);
  ordinary = env.authenticatedContext('ordinary').firestore();
});

beforeEach(async () => {
  await env.clearFirestore();
  await seed();
});

after(async () => {
  if (env) await env.cleanup();
  if (app) await deleteApp(app);
});

test('Next Baghdad midnight is exact across regular and year-end dates', () => {
  assert.equal(nextIraqMidnightUtc(NOW).toISOString(), NEXT.toISOString());
  assert.equal(
      nextIraqMidnightUtc(new Date('2026-12-31T22:00:00Z')).toISOString(),
      '2027-01-01T21:00:00.000Z');
});

test('Manager restoration stages prior task for tomorrow, without immediate publish', async () => {
  const outcome = await restore();
  assert.equal(outcome.outcome, 'scheduled');
  assert.equal(outcome.effectiveAt, NEXT.toISOString());
  const preview = (await db.collection('admin_daily_schedule_previews')
      .doc('preview_open_map').get()).data();
  assert.equal(preview.action, SLOT);
  assert.equal(preview.titleAr, 'افتح الخريطة');
  assert.equal(preview.rewardAmount, 5);
  assert.equal(preview.rewardUnit, 'points');
  assert.equal(preview.revision, 5);
  assert.equal(preview.status, 'pending');
  assert.equal(preview.effectiveAt.toDate().toISOString(), NEXT.toISOString());
  assert.equal((await db.collection('admin_audit').get()).size, 1);
  const current = (await db.collection('deda_daily_published_task_slots')
      .doc(SLOT).get()).data();
  assert.equal(current.action, 'visit_telegram');
  assert.equal(current.rewardAmount, 12);
});

test('Next midnight publisher activates restoration with history, without payouts', async () => {
  assert.equal((await restore()).outcome, 'scheduled');
  const results = await publishDueDailySlots(db, new Date('2026-10-10T21:01:00Z'));
  assert.equal(results.find(x => x.slotId === SLOT).outcome, 'published-config-only');
  const publicData = (await db.collection('deda_daily_published_task_slots')
      .doc(SLOT).get()).data();
  assert.equal(publicData.titleAr, 'افتح الخريطة');
  assert.equal(publicData.action, SLOT);
  assert.equal(publicData.rewardAmount, 5);
  assert.equal(publicData.rewardsEnabled, false);
  assert.equal(publicData.publicationId, '20261011__open_map');
  const history = (await db.collection('deda_daily_task_publication_history')
      .doc('20261011__open_map').get()).data();
  assert.equal(history.priorConfig.action, 'visit_telegram');
  assert.equal(history.newConfig.action, SLOT);
});

test('Duplicate or concurrent restore requests do not add extra revisions or audit', async () => {
  const outcomes = await Promise.all([restore(), restore()]);
  assert.deepEqual(outcomes.map(x => x.outcome).sort(),
      ['already-scheduled', 'scheduled']);
  assert.equal((await restore()).outcome, 'already-scheduled');
  const preview = (await db.collection('admin_daily_schedule_previews')
      .doc('preview_open_map').get()).data();
  assert.equal(preview.revision, 5);
  assert.equal((await db.collection('admin_audit').get()).size, 1);
});

test('Employee, stopped manager and ordinary requester are denied', async () => {
  assert.equal((await restore('employee')).outcome, 'general-manager-required');
  assert.equal((await restore('nobody')).outcome, 'general-manager-required');
  await db.collection('admins').doc('gm').update({active: false, status: 'stopped'});
  assert.equal((await restore()).outcome, 'general-manager-required');
  assert.equal((await db.collection('admin_audit').get()).size, 0);
});

test('Old history cannot override a newer published config', async () => {
  await db.collection('deda_daily_published_task_slots').doc(SLOT)
      .update({publicationId: '20261011__open_map'});
  assert.equal((await restore()).outcome, 'stale-or-missing-publication');
  assert.equal((await db.collection('admin_audit').get()).size, 0);
});

test('An unrelated future scheduled change is never overwritten', async () => {
  await db.collection('admin_daily_schedule_previews').doc('preview_open_map')
      .update({status: 'pending', effectiveAt: Timestamp.fromDate(NEXT)});
  assert.equal((await restore()).outcome, 'conflict-pending-schedule');
  assert.equal((await db.collection('admin_audit').get()).size, 0);
});

test('Invalid previous config and attempts to restore daily login are blocked', async () => {
  await db.collection('deda_daily_task_publication_history').doc(HISTORY_ID)
      .update({'priorConfig.action': 'visit_telegram',
        'priorConfig.url': 'https://t.me.evil.com/fake'});
  assert.equal((await restore()).outcome, 'invalid-previous-configuration');
  assert.equal((await restore('gm', 'daily_login', '20261010__daily_login'))
      .outcome, 'invalid-request');
  assert.equal((await db.collection('admin_audit').get()).size, 0);
});

test('Late-night restoration cannot retroactively cross the boundary', async () => {
  assert.equal((await restore('gm', SLOT, HISTORY_ID,
      new Date('2026-10-10T20:59:30Z'))).outcome, 'too-close-to-midnight');
});

test('An ordinary client cannot read history or private previews, or write public config', async () => {
  await assertFails(getDoc(doc(ordinary,
      'deda_daily_task_publication_history', HISTORY_ID)));
  await assertFails(getDoc(doc(ordinary,
      'admin_daily_schedule_previews', 'preview_open_map')));
  await assertFails(setDoc(doc(ordinary,
      'deda_daily_published_task_slots', SLOT), {rewardAmount: 99999}));
  const read = await assertSucceeds(getDoc(doc(ordinary,
      'deda_daily_published_task_slots', SLOT)));
  assert.equal(read.exists(), true);
});

test('Neither system nor manager/user balances are touched by restoration', async () => {
  await db.collection('admin_wallets').doc('gm').set({diamonds: 1000000});
  await db.collection('users').doc('ordinary').set({coins: 77, diamonds: 11});
  assert.equal((await restore()).outcome, 'scheduled');
  assert.equal((await db.collection('admin_wallets').doc('gm').get())
      .data().diamonds, 1000000);
  assert.equal((await db.collection('users').doc('ordinary').get())
      .data().coins, 77);
  assert.equal((await db.collection('users').doc('ordinary').get())
      .data().diamonds, 11);
});
