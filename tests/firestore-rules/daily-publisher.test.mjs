import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {before, after, beforeEach, test} from 'node:test';
import {
  initializeTestEnvironment, assertFails, assertSucceeds,
} from '@firebase/rules-unit-testing';
import {doc, getDoc, getDocs, setDoc, collection} from 'firebase/firestore';

const require = createRequire(import.meta.url);
const requireFunctions = createRequire(
    new URL('../../functions/package.json', import.meta.url));
const {initializeApp, deleteApp} = requireFunctions('firebase-admin/app');
const {getFirestore, Timestamp} = requireFunctions('firebase-admin/firestore');
const {
  SLOTS, iraqDayId, midnightUtcForIraqDay, publicationDecision,
  publishDueDailySlots,
} = require('../../functions/deda_daily_task_publisher.js');

const projectId = 'demo-deda-daily-task-publisher';
const MIDNIGHT = new Date('2026-10-09T21:00:00.000Z');
const NOW = new Date('2026-10-09T21:01:00.000Z');
const TODAY = '2026-10-10';

let environment, adminApp, db, member, anonymous;

function preview(slotId, changes = {}) {
  return {
    slotId,
    action: slotId,
    titleAr: 'مهمة تجريبية آمنة',
    titleEn: 'مهمة تجريبية آمنة',
    targetCount: 1,
    rewardUnit: 'points',
    rewardAmount: 5,
    url: '',
    status: 'pending',
    revision: 1,
    effectiveAt: Timestamp.fromDate(MIDNIGHT),
    createdByUid: 'manager',
    updatedByUid: 'manager',
    createdAt: Timestamp.fromDate(new Date('2026-10-09T10:00:00.000Z')),
    updatedAt: Timestamp.fromDate(new Date('2026-10-09T10:00:00.000Z')),
    ...changes,
  };
}

async function seed(slotId, changes = {}) {
  await db.collection('admin_daily_schedule_previews')
      .doc('preview_' + slotId).set(preview(slotId, changes));
}

before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw Error('EMULATOR_ONLY: refusing to run without local Firestore emulator');
  }
  environment = await initializeTestEnvironment({
    projectId,
    firestore: {rules: readFileSync('firestore.rules', 'utf8')},
  });
  adminApp = initializeApp({projectId}, 'deda-publisher-unit');
  db = getFirestore(adminApp);
  member = environment.authenticatedContext('normal-user').firestore();
  anonymous = environment.unauthenticatedContext().firestore();
});

beforeEach(async () => {
  await environment.clearFirestore();
});

after(async () => {
  if (environment) await environment.cleanup();
  if (adminApp) await deleteApp(adminApp);
});

test('The Iraqi midnight boundary is deterministic in UTC', () => {
  assert.equal(iraqDayId(NOW), TODAY);
  assert.equal(iraqDayId(new Date('2026-10-09T20:59:59Z')), '2026-10-09');
  assert.equal(midnightUtcForIraqDay(TODAY).toISOString(),
      MIDNIGHT.toISOString());
  assert.equal(SLOTS.length, 8);
  assert.ok(!SLOTS.includes('daily_login'));
});

test('Publish only one selected daily card; seven untouched', async () => {
  await seed('open_map');
  const results = await publishDueDailySlots(db, NOW);
  assert.equal(results.filter(x => x.outcome === 'published-config-only').length, 1);
  const current = await db.collection('deda_daily_published_task_slots')
      .doc('open_map').get();
  assert.equal(current.exists, true);
  assert.equal(current.data().effectiveDay, TODAY);
  assert.equal(current.data().rewardsEnabled, false);
  assert.equal(current.data().rewardClaimMode,
      'disabled_until_verified_server_ledger');
  const all = await db.collection('deda_daily_published_task_slots').get();
  assert.equal(all.size, 1);
  const history = await db.collection('deda_daily_task_publication_history')
      .doc('20261010__open_map').get();
  assert.equal(history.exists, true);
  assert.equal(history.data().priorConfig.action, 'open_map');
  assert.equal(history.data().priorConfig.titleAr, 'افتح الخريطة');
});

test('Replay or concurrent executions cannot publish twice', async () => {
  await seed('open_map');
  await Promise.all([
    publishDueDailySlots(db, NOW),
    publishDueDailySlots(db, NOW),
  ]);
  const history = await db.collection('deda_daily_task_publication_history').get();
  assert.equal(history.size, 1);
  const replay = await publishDueDailySlots(db, NOW);
  assert.equal(replay.find(x => x.slotId === 'open_map').outcome,
      'already-published');
});

test('An admin cancellation never becomes publicly visible', async () => {
  await seed('traffic_skills', {status: 'cancelled'});
  const outcome = await publishDueDailySlots(db, NOW);
  assert.equal(outcome.find(x => x.slotId === 'traffic_skills').outcome,
      'not-pending');
  const current = await db.collection('deda_daily_published_task_slots')
      .doc('traffic_skills').get();
  assert.equal(current.exists, false);
});

test('No mid-day, wrong-day, or late configuration publication', async () => {
  await seed('open_map');
  const early = await publishDueDailySlots(db,
      new Date('2026-10-09T20:59:59.000Z'));
  assert.equal(early.find(x => x.slotId === 'open_map').outcome,
      'not-today-midnight');
  const late = await publishDueDailySlots(db,
      new Date('2026-10-09T21:16:00.000Z'));
  assert.equal(late.find(x => x.slotId === 'open_map').outcome,
      'outside-midnight-window');
  const nextDay = await publishDueDailySlots(db,
      new Date('2026-10-10T21:01:00.000Z'));
  assert.equal(nextDay.find(x => x.slotId === 'open_map').outcome,
      'not-today-midnight');
  assert.equal(
      (await db.collection('deda_daily_published_task_slots').get()).size, 0);
});

test('Reject forged reward flags, unknown tasks or malformed external URLs', () => {
  for (const payload of [
    preview('open_map', {rewardAmount: 99999}),
    preview('open_map', {action: 'invented_task'}),
    preview('open_map', {titleEn: 'English only'}),
    preview('open_map', {action: 'visit_telegram',
      url: 'https://t.me.evil.com/channel'}),
    preview('open_map', {action: 'visit_telegram',
      url: 'https://t.me/channel?follow=true'}),
    preview('open_map', {effectiveAt: Timestamp.fromDate(
      new Date('2026-10-09T21:05:00.000Z'))}),
  ]) {
    assert.equal(publicationDecision(payload, 'open_map', NOW).eligible, false);
  }
});

test('A snapshot retains the immediately prior live config for restoration', async () => {
  await db.collection('deda_daily_published_task_slots').doc('open_map').set({
    action: 'open_map', titleAr: 'مهمة اليوم السابقة',
    targetCount: 2, rewardUnit: 'diamonds', rewardAmount: 10, url: '',
    effectiveDay: '2026-10-09',
  });
  await seed('open_map', {action: 'visit_telegram',
    titleAr: 'زيارة قناتنا في تليجرام', titleEn: 'زيارة قناتنا في تليجرام',
    url: 'https://t.me/DEDA_Iraq'});
  await publishDueDailySlots(db, NOW);
  const history = await db.collection('deda_daily_task_publication_history')
      .doc('20261010__open_map').get();
  assert.equal(history.data().priorConfig.titleAr, 'مهمة اليوم السابقة');
  assert.equal(history.data().priorConfig.rewardUnit, 'diamonds');
  assert.equal(history.data().priorConfig.rewardAmount, 10);
  assert.equal(history.data().newConfig.action, 'visit_telegram');
  assert.equal(
    (await db.collection('deda_daily_published_task_slots')
        .doc('open_map').get()).data().rewardsEnabled, false);
});

test('User may only read published task config, not write or read admin history', async () => {
  await seed('open_map');
  await publishDueDailySlots(db, NOW);
  const ref = doc(member, 'deda_daily_published_task_slots', 'open_map');
  const record = await assertSucceeds(getDoc(ref));
  assert.equal(record.data().slotId, 'open_map');
  await assertFails(setDoc(ref, {rewardAmount: 100000}, {merge: true}));
  await assertFails(getDoc(doc(anonymous,
      'deda_daily_published_task_slots', 'open_map')));
  await assertFails(getDocs(collection(member,
      'deda_daily_task_publication_history')));
  await assertFails(getDoc(doc(member,
      'admin_daily_schedule_previews', 'preview_open_map')));
});

test('Two edited slots publish independently without modifying other six', async () => {
  await seed('open_map');
  await seed('long_trip', {rewardUnit: 'diamonds', rewardAmount: 12});
  const statuses = await publishDueDailySlots(db, NOW);
  assert.equal(statuses.filter(x => x.outcome === 'published-config-only').length, 2);
  const configs = await db.collection('deda_daily_published_task_slots').get();
  assert.deepEqual(configs.docs.map(x => x.id).sort(),
      ['long_trip', 'open_map']);
  assert.equal(
      (await db.collection('deda_daily_task_publication_history').get()).size, 2);
});
