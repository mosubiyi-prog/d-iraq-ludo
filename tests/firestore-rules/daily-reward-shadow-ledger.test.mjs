import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {before, beforeEach, after, test} from 'node:test';
import {
  initializeTestEnvironment, assertFails, assertSucceeds,
} from '@firebase/rules-unit-testing';
import {doc, getDoc, setDoc} from 'firebase/firestore';

const nodeRequire = createRequire(import.meta.url);
const fnRequire = createRequire(
    new URL('../../functions/package.json', import.meta.url));
const {initializeApp, deleteApp} = fnRequire('firebase-admin/app');
const {getFirestore, Timestamp} = fnRequire('firebase-admin/firestore');
const {
  PROJECT, SHADOW_COLLECTIONS, eventId, ledgerId,
  simulateVerifiedDailyReward,
} = nodeRequire('../../functions/deda_daily_reward_shadow_ledger.js');

const DAY = '2026-10-10';
const MIDNIGHT = new Date('2026-10-09T21:00:00Z');
const PUBLISHED = new Date('2026-10-09T21:01:00Z');
const VERIFIED = new Date('2026-10-09T21:02:00Z');
const NOW = new Date('2026-10-10T14:00:00Z');
const UID = 'normal-user-1';
const SLOT = 'open_map';

let env, adminApp, db, user, guest;

function published(slot = SLOT, overrides = {}) {
  return {
    slotId: slot, action: slot,
    effectiveDay: DAY,
    publicationId: '20261010__' + slot,
    effectiveAt: Timestamp.fromDate(MIDNIGHT),
    publishedAt: Timestamp.fromDate(PUBLISHED),
    sourcePreviewRevision: 2,
    targetCount: 1,
    rewardUnit: 'points',
    rewardAmount: 5,
    // THIS IS A STAGE-3 INACTIVE CONFIG. NO LIVE PAYOUT.
    rewardsEnabled: false,
    rewardClaimMode: 'disabled_until_verified_server_ledger',
    ...overrides,
  };
}

function verifiedEvent(slot = SLOT, uid = UID, overrides = {}) {
  return {
    uid, slotId: slot, dayId: DAY, action: slot,
    publicationId: '20261010__' + slot,
    sourcePreviewRevision: 2,
    serverVerified: true,
    fixtureSource: 'stage9_emulator_server_fixture',
    eventState: 'verified',
    verifiedAt: Timestamp.fromDate(VERIFIED),
    ...overrides,
  };
}

async function seed(slot = SLOT, uid = UID, configOverrides = {},
    eventOverrides = {}) {
  await db.collection('deda_daily_published_task_slots')
      .doc(slot).set(published(slot, configOverrides));
  if (eventOverrides !== null) {
    await db.collection(SHADOW_COLLECTIONS.events)
        .doc(eventId(uid, DAY, slot))
        .set(verifiedEvent(slot, uid, eventOverrides));
  }
}

function simulate(slot = SLOT, uid = UID, time = NOW) {
  return simulateVerifiedDailyReward(db, {
    uid, slotId: slot, trustedNow: time,
  });
}

async function balances(uid = UID) {
  const record = await db.collection(SHADOW_COLLECTIONS.balances).doc(uid).get();
  return record.exists ? record.data() : null;
}

async function entries() {
  return db.collection(SHADOW_COLLECTIONS.ledger).get();
}

before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST,
      'EMULATOR_ONLY: refusing any production connection');
  assert.equal(process.env.GCLOUD_PROJECT, PROJECT,
      'Only the designated demo project is allowed');
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: {rules: readFileSync('firestore.rules', 'utf8')},
  });
  adminApp = initializeApp({projectId: PROJECT}, 'deda-stage9-ledger');
  db = getFirestore(adminApp);
  user = env.authenticatedContext(UID).firestore();
  guest = env.unauthenticatedContext().firestore();
});

beforeEach(async () => {
  await env.clearFirestore();
});

after(async () => {
  if (env) await env.cleanup();
  if (adminApp) await deleteApp(adminApp);
});

test('A verified fixture simulates one five-point transaction atomically', async () => {
  await seed();
  const outcome = await simulate();
  assert.deepEqual(outcome, {
    outcome: 'shadow-recorded', unit: 'points', amount: 5, dayId: DAY,
  });
  const b = await balances();
  assert.equal(b.points, 5);
  assert.equal(b.diamonds, 0);
  assert.equal(b.shadowOnly, true);
  const ledger = await entries();
  assert.equal(ledger.size, 1);
  assert.equal(ledger.docs[0].id, ledgerId(UID, DAY, SLOT, 2));
  assert.equal(ledger.docs[0].data().shadowOnly, true);
});

test('Replays and concurrent requests cannot double-credit a shadow balance', async () => {
  await seed();
  const results = await Promise.all([simulate(), simulate(), simulate()]);
  assert.deepEqual(results.map(r => r.outcome).sort(), [
    'already-recorded', 'already-recorded', 'shadow-recorded',
  ]);
  assert.equal((await simulate()).outcome, 'already-recorded');
  assert.equal((await balances()).points, 5);
  assert.equal((await entries()).size, 1);
});

test('Diamond preview does not turn into points, coins, or an admin debit', async () => {
  await seed(SLOT, UID, {rewardUnit: 'diamonds', rewardAmount: 30});
  assert.equal((await simulate()).outcome, 'shadow-recorded');
  const b = await balances();
  assert.equal(b.points, 0);
  assert.equal(b.diamonds, 30);
  const ledger = await entries();
  assert.equal(ledger.docs[0].data().unit, 'diamonds');
  assert.equal(ledger.docs[0].data().amount, 30);
});

test('No server-verified event means no simulated award', async () => {
  await seed(SLOT, UID, {}, null);
  assert.equal((await simulate()).outcome, 'unverified-event');
  assert.equal(await balances(), null);
  assert.equal((await entries()).size, 0);
});

test('Forged, stale, future, and wrong-revision event fixtures are rejected', async () => {
  const forgeries = [
    {serverVerified: false},
    {fixtureSource: 'client-upload'},
    {eventState: 'pending'},
    {uid: 'other'},
    {action: 'visit_telegram'},
    {publicationId: '20261009__open_map'},
    {sourcePreviewRevision: 1},
    {verifiedAt: Timestamp.fromDate(new Date('2026-10-09T20:59:59Z'))},
    {verifiedAt: Timestamp.fromDate(new Date('2026-10-10T16:00:00Z'))},
  ];
  for (const change of forgeries) {
    await env.clearFirestore();
    await seed(SLOT, UID, {}, change);
    assert.equal((await simulate()).outcome, 'unverified-event',
        'Forged completion was rejected: ' + JSON.stringify(change));
    assert.equal((await entries()).size, 0);
  }
});

test('Client cannot enable rewards, change sources or supply inflated amounts', async () => {
  const broken = [
    {rewardsEnabled: true},
    {rewardClaimMode: 'pay-now'},
    {rewardUnit: 'coins'},
    {rewardUnit: 'unknown'},
    {rewardAmount: 5001},
    {rewardAmount: 0},
    {rewardAmount: -10},
    {targetCount: 2},
    {action: 'visit_telegram'},
    {effectiveDay: '2026-10-11'},
    {publicationId: '20261009__open_map'},
    {sourcePreviewRevision: 0},
    {publishedAt: Timestamp.fromDate(new Date('2026-10-09T21:20:00Z'))},
  ];
  for (const change of broken) {
    await env.clearFirestore();
    await seed(SLOT, UID, change);
    assert.equal((await simulate()).outcome, 'invalid-or-inactive-config',
        'Bad published configuration rejected: ' + JSON.stringify(change));
    assert.equal((await entries()).size, 0);
  }
});

test('Baghdad midnight blocks early, past-day and next-day replay', async () => {
  await seed();
  assert.equal((await simulate(SLOT, UID,
      new Date('2026-10-09T20:59:59Z'))).outcome, 'invalid-or-inactive-config');
  assert.equal((await simulate(SLOT, UID,
      new Date('2026-10-10T21:00:00Z'))).outcome, 'invalid-or-inactive-config');
  assert.equal((await simulate()).outcome, 'shadow-recorded');
  assert.equal((await entries()).size, 1);
});

test('Missing published task and unsupported login replacement never pay', async () => {
  assert.equal((await simulate()).outcome, 'unpublished');
  assert.equal((await simulate('daily_login')).outcome, 'invalid-identity-or-slot');
  assert.equal((await simulate('invented')).outcome, 'invalid-identity-or-slot');
  assert.equal((await simulate(SLOT, 'bad/uid')).outcome,
      'invalid-identity-or-slot');
  assert.equal((await entries()).size, 0);
});

test('Daily shadow spending cap is atomic across multiple independent slots', async () => {
  for (const slot of ['open_map', 'long_trip', 'traffic_skills']) {
    await seed(slot, UID, {rewardAmount: 5000});
  }
  const results = await Promise.all([
    simulate('open_map'), simulate('long_trip'), simulate('traffic_skills'),
  ]);
  assert.deepEqual(results.map(x => x.outcome).sort(), [
    'shadow-limit-reached', 'shadow-recorded', 'shadow-recorded',
  ]);
  assert.equal((await balances()).points, 10000);
  assert.equal((await entries()).size, 2);
});

test('Malformed shadow balances and numeric overflow prevent any record', async () => {
  await seed();
  await db.collection(SHADOW_COLLECTIONS.balances).doc(UID)
      .set({points: Number.MAX_SAFE_INTEGER - 1, diamonds: 0});
  assert.equal((await simulate()).outcome, 'shadow-limit-reached');
  assert.equal((await entries()).size, 0);
  await db.collection(SHADOW_COLLECTIONS.balances).doc(UID)
      .set({points: '5', diamonds: 0});
  assert.equal((await simulate()).outcome, 'invalid-shadow-balance');
  assert.equal((await entries()).size, 0);
});

test('User, anonymous and administrative accounts cannot read or forge ledger', async () => {
  await seed();
  await simulate();
  for (const client of [user, guest]) {
    await assertFails(getDoc(doc(client, SHADOW_COLLECTIONS.ledger,
        ledgerId(UID, DAY, SLOT, 2))));
    await assertFails(getDoc(doc(client, SHADOW_COLLECTIONS.balances, UID)));
    await assertFails(getDoc(doc(client, SHADOW_COLLECTIONS.events,
        eventId(UID, DAY, SLOT))));
    await assertFails(setDoc(doc(client, SHADOW_COLLECTIONS.balances, UID),
        {points: 999999, diamonds: 999999}));
    await assertFails(setDoc(doc(client, SHADOW_COLLECTIONS.ledger, 'fake'),
        {amount: 9000}));
  }
  // Existing public published configs remain readable by signed-in users.
  const visible = await assertSucceeds(getDoc(doc(user,
      'deda_daily_published_task_slots', SLOT)));
  assert.equal(visible.data().rewardAmount, 5);
});

test('Real manager, gifts and user wallet documents are never touched', async () => {
  await db.collection('admins').doc('manager').set({
    role: 'general_manager', active: true,
  });
  await db.collection('admin_wallets').doc('manager').set({
    diamonds: 1000000, coins: 500000,
  });
  await db.collection('admin_gift_wallets').doc('manager').set({
    diamonds: 900000, coins: 900000,
  });
  await db.collection('users').doc(UID).set({
    diamonds: 17, coins: 11, points: 30,
  });
  const snapshots = await Promise.all([
    db.collection('admin_wallets').doc('manager').get(),
    db.collection('admin_gift_wallets').doc('manager').get(),
    db.collection('users').doc(UID).get(),
  ]);
  await seed();
  assert.equal((await simulate()).outcome, 'shadow-recorded');
  const refs = [
    db.collection('admin_wallets').doc('manager'),
    db.collection('admin_gift_wallets').doc('manager'),
    db.collection('users').doc(UID),
  ];
  for (let i = 0; i < refs.length; i++) {
    assert.deepEqual((await refs[i].get()).data(), snapshots[i].data());
  }
});

test('An emulator-only safety guard rejects missing or incorrect environment', async () => {
  const originalHost = process.env.FIRESTORE_EMULATOR_HOST;
  const originalProject = process.env.GCLOUD_PROJECT;
  try {
    delete process.env.FIRESTORE_EMULATOR_HOST;
    await assert.rejects(simulate(), /STAGE9_EMULATOR_ONLY_DO_NOT_PAY/);
    process.env.FIRESTORE_EMULATOR_HOST = originalHost;
    process.env.GCLOUD_PROJECT = 'real-production-project';
    await assert.rejects(simulate(), /STAGE9_EMULATOR_ONLY_DO_NOT_PAY/);
  } finally {
    process.env.FIRESTORE_EMULATOR_HOST = originalHost;
    process.env.GCLOUD_PROJECT = originalProject;
  }
});
