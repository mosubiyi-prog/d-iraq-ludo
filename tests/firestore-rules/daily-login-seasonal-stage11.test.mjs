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
const {getFirestore} = fnRequire('firebase-admin/firestore');
const {
  PROJECT, CONTROL, AUDIT, CONTROL_ID, BASE, nextIraqDay,
  selectLoginReward, simulateManagerLoginPolicyChange,
} = nodeRequire('../../functions/deda_daily_login_seasonal_shadow.js');

const NOW = new Date('2026-10-09T12:00:00.000Z');
const BEFORE_MIDNIGHT = new Date('2026-10-09T20:59:59.999Z');
const AFTER_MIDNIGHT = new Date('2026-10-09T21:00:00.000Z');
const EID_START = new Date('2026-10-10T21:00:00.000Z');
const EID_LAST_DAY = new Date('2026-10-12T20:59:59.999Z');
const AFTER_EID = new Date('2026-10-12T21:00:00.000Z');

let env, app, db, normalUser, anonymousUser;

async function policy() {
  const snap = await db.collection(CONTROL).doc(CONTROL_ID).get();
  return snap.exists ? snap.data() : null;
}

async function edit(command, uid = 'gm', now = NOW) {
  return simulateManagerLoginPolicyChange(db, {
    requesterUid: uid, command, trustedNow: now,
  });
}

function offer(id = 'eid_bonus_2026', startDay = '2026-10-11',
    endDay = '2026-10-12', amount = 50, unit = 'coins',
    expectedRevision = 0) {
  return {kind: 'offer', id, startDay, endDay, unit,
    amount, expectedRevision};
}

function regular(id = 'base_20', effectiveDay = '2026-10-10',
    amount = 20, unit = 'points', expectedRevision = 0) {
  return {kind: 'regular', id, effectiveDay, amount, unit,
    expectedRevision};
}

async function audits() {
  return (await db.collection(AUDIT).get()).docs;
}

before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST,
      'Cannot run tests without a local Firebase emulator');
  assert.equal(process.env.GCLOUD_PROJECT, PROJECT);
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: {rules: readFileSync('firestore.rules', 'utf8')},
  });
  app = initializeApp({projectId: PROJECT}, 'deda-stage11-login-shadow');
  db = getFirestore(app);
  normalUser = env.authenticatedContext('member').firestore();
  anonymousUser = env.unauthenticatedContext().firestore();
});

beforeEach(async () => {
  await env.clearFirestore();
  await db.collection('admins').doc('gm').set({
    role: 'general_manager', active: true, status: 'active',
    displayName: 'مدير تجريبي',
  });
  await db.collection('admins').doc('deputy').set({
    role: 'deputy_manager', active: true, status: 'active',
  });
  await db.collection('admins').doc('employee').set({
    role: 'employee', active: true, status: 'active',
  });
});

after(async () => {
  if (env) await env.cleanup();
  if (app) await deleteApp(app);
});

test('No schedule preserves the fixed daily login and its ten LOCAL points', () => {
  assert.deepEqual(selectLoginReward(null, NOW), {
    ...BASE, dayId: '2026-10-09',
  });
  assert.equal(BASE.amount, 10);
  assert.equal(BASE.unit, 'points');
  assert.equal(BASE.canGrantRewards, false);
  assert.equal(nextIraqDay(BEFORE_MIDNIGHT), '2026-10-10');
  assert.equal(nextIraqDay(AFTER_MIDNIGHT), '2026-10-11');
});

test('Manager schedules 50 COINS for two Eid days and returns to ten POINTS', async () => {
  assert.deepEqual(await edit(offer()), {
    outcome: 'scheduled-shadow-only', revision: 1,
  });
  const state = await policy();
  assert.equal(state.entries.length, 1);
  assert.equal(state.entries[0].kind, 'offer');
  assert.equal(state.entries[0].unit, 'coins');
  assert.equal(selectLoginReward(state, BEFORE_MIDNIGHT).amount, 10);
  const during = selectLoginReward(state, EID_START);
  assert.equal(during.amount, 50);
  assert.equal(during.unit, 'coins');
  assert.equal(during.source, 'eid_bonus_2026');
  assert.equal(during.isPromotion, true);
  assert.equal(during.canGrantRewards, false);
  assert.equal(selectLoginReward(state, EID_LAST_DAY).unit, 'coins');
  const after = selectLoginReward(state, AFTER_EID);
  assert.equal(after.amount, 10);
  assert.equal(after.unit, 'points');
  assert.equal(after.isPromotion, false);
  assert.equal((await audits()).length, 1);
});

test('Regular base edits wait until next Baghdad day; offer temporarily overrides', async () => {
  assert.equal((await edit(regular())).outcome, 'scheduled-shadow-only');
  assert.equal((await edit(offer('eid_more', '2026-10-11',
      '2026-10-12', 50, 'diamonds', 1))).outcome, 'scheduled-shadow-only');
  const state = await policy();
  assert.equal(selectLoginReward(state, BEFORE_MIDNIGHT).amount, 10);
  assert.equal(selectLoginReward(state, AFTER_MIDNIGHT).amount, 20);
  assert.equal(selectLoginReward(state, EID_START).amount, 50);
  assert.equal(selectLoginReward(state, EID_START).unit, 'diamonds');
  assert.equal(selectLoginReward(state, AFTER_EID).amount, 20);
  assert.equal(selectLoginReward(state, AFTER_EID).unit, 'points');
  assert.equal((await audits()).length, 2);
});

test('Only active general manager can alter schedule', async () => {
  for (const who of ['employee', 'deputy', 'member', 'fake']) {
    assert.equal((await edit(offer(), who)).outcome,
        'general-manager-required');
  }
  await db.collection('admins').doc('gm').update({active: false});
  assert.equal((await edit(offer())).outcome, 'general-manager-required');
  await db.collection('admins').doc('gm').update({
    active: true, status: 'temporarily_stopped',
  });
  assert.equal((await edit(offer())).outcome, 'general-manager-required');
  assert.equal(await policy(), null);
  assert.equal((await audits()).length, 0);
});

test('Reject malformed reward unit, zero, negative, too large or fraction', async () => {
  const wrong = [
    offer('bad1', '2026-10-11', '2026-10-12', 0),
    offer('bad2', '2026-10-11', '2026-10-12', -50),
    offer('bad3', '2026-10-11', '2026-10-12', 5001),
    offer('bad4', '2026-10-11', '2026-10-12', 0.5),
    offer('bad5', '2026-10-11', '2026-10-12', 50, 'gems'),
    offer('bad6', '2026-10-11', '2026-10-12', 50, 'coin'),
    regular('bad7', '2026-10-10', 50000),
  ];
  for (const item of wrong) {
    assert.equal((await edit(item)).outcome, 'invalid-amount-date-or-unit');
  }
  assert.equal(await policy(), null);
});

test('Start in the past, today or far future and invalid day formats denied', async () => {
  for (const item of [
    offer('old', '2026-10-08', '2026-10-09'),
    offer('today', '2026-10-09', '2026-10-10'),
    offer('reversed', '2026-10-12', '2026-10-11'),
    offer('invalidday', '2026-02-30', '2026-03-01'),
    offer('too_long', '2026-10-11', '2026-11-20'),
    regular('regular_old', '2026-10-09'),
    regular('regular_future', '2030-01-01'),
  ]) {
    const result = await edit(item);
    assert.ok(['invalid-amount-date-or-unit', 'must-start-future-day']
        .includes(result.outcome), JSON.stringify(result));
  }
  assert.equal(await policy(), null);
});

test('User cannot supply role, wallet debit, time, or change daily-login card', async () => {
  const invalid = [
    {...offer(), role: 'general_manager'},
    {...offer(), trustedNow: '2099-01-01'},
    {...offer(), adminUid: 'gm'},
    {...offer(), rewardClaimed: true},
    {...offer(), walletDebit: 99999},
    {...offer(), kind: 'weekly'},
    {...offer(), kind: 'survey'},
    {...offer(), kind: 'daily_login'},
  ];
  for (const item of invalid) {
    assert.equal((await edit(item)).outcome, 'invalid-command');
  }
  assert.equal(await policy(), null);
});

test('Overlapping promotions rejected, separated future offers supported', async () => {
  assert.equal((await edit(offer())).outcome, 'scheduled-shadow-only');
  assert.equal((await edit(offer('overlap', '2026-10-12',
      '2026-10-13', 30, 'coins', 1))).outcome, 'offer-overlap');
  assert.equal((await edit(offer('second', '2026-10-13',
      '2026-10-14', 60, 'points', 1))).outcome, 'scheduled-shadow-only');
  const state = await policy();
  assert.equal(state.entries.length, 2);
  const oct13 = selectLoginReward(state,
      new Date('2026-10-12T21:00:00Z'));
  assert.equal(oct13.amount, 60);
  assert.equal(oct13.unit, 'points');
  assert.equal((await audits()).length, 2);
});

test('Cancellation before start leaves normal reward and immutable history', async () => {
  assert.equal((await edit(offer())).outcome, 'scheduled-shadow-only');
  assert.equal((await edit({
    kind: 'cancel', id: 'eid_bonus_2026', expectedRevision: 1,
  })).outcome, 'scheduled-shadow-only');
  const state = await policy();
  assert.equal(state.entries[0].status, 'cancelled');
  assert.equal(selectLoginReward(state, EID_START).amount, 10);
  assert.equal((await edit({
    kind: 'cancel', id: 'eid_bonus_2026', expectedRevision: 2,
  })).outcome, 'already-cancelled');
  assert.equal((await audits()).length, 2);
});

test('After offer begins it cannot be edited or cancelled for that same day', async () => {
  assert.equal((await edit(offer())).outcome, 'scheduled-shadow-only');
  assert.equal((await edit({
    kind: 'cancel', id: 'eid_bonus_2026', expectedRevision: 1,
  }, 'gm', EID_START)).outcome, 'cannot-change-current-or-past');
  const state = await policy();
  assert.equal(selectLoginReward(state, EID_START).amount, 50);
  assert.equal(state.revision, 1);
  assert.equal((await audits()).length, 1);
});

test('Future normal changes can cancel but current base is never rewritten', async () => {
  assert.equal((await edit(regular())).outcome, 'scheduled-shadow-only');
  assert.equal((await edit({
    kind: 'cancel', id: 'base_20', expectedRevision: 1,
  })).outcome, 'scheduled-shadow-only');
  const state = await policy();
  assert.equal(selectLoginReward(state, AFTER_MIDNIGHT).amount, 10);
  assert.equal((await edit({
    kind: 'cancel', id: 'base_20', expectedRevision: 2,
  }, 'gm', AFTER_MIDNIGHT)).outcome, 'already-cancelled');
});

test('Historical rewards do not change when later regular default is scheduled', async () => {
  await edit(regular('base_20', '2026-10-10', 20));
  await edit(regular('base_30', '2026-10-14', 30, 'points', 1));
  const state = await policy();
  assert.equal(selectLoginReward(state, NOW).amount, 10);
  assert.equal(selectLoginReward(state, AFTER_MIDNIGHT).amount, 20);
  assert.equal(selectLoginReward(state,
      new Date('2026-10-13T21:00:00Z')).amount, 30);
  assert.equal(selectLoginReward(state, AFTER_EID).amount, 20);
});

test('Repeated and concurrent manager changes do not lose updates', async () => {
  const results = await Promise.all([
    edit(offer('eid_one')),
    edit(offer('eid_two')),
    edit(offer('eid_three')),
  ]);
  assert.deepEqual(results.map(x => x.outcome).sort(), [
    'scheduled-shadow-only', 'stale-policy-revision', 'stale-policy-revision',
  ]);
  assert.equal((await policy()).revision, 1);
  assert.equal((await policy()).entries.length, 1);
  assert.equal((await audits()).length, 1);
});

test('Stale revisions, repeated schedule IDs and double regular date blocked', async () => {
  assert.equal((await edit(regular())).outcome, 'scheduled-shadow-only');
  assert.equal((await edit(regular())).outcome, 'stale-policy-revision');
  assert.equal((await edit(regular('base_20', '2026-10-11',
      40, 'points', 1))).outcome, 'duplicate-schedule-id');
  assert.equal((await edit(regular('base_same', '2026-10-10',
      40, 'points', 1))).outcome, 'regular-date-conflict');
  assert.equal((await policy()).revision, 1);
  assert.equal((await audits()).length, 1);
});

test('Firestore clients cannot read or modify private shadow policy or audit', async () => {
  await edit(offer());
  for (const client of [normalUser, anonymousUser]) {
    await assertFails(getDoc(doc(client, CONTROL, CONTROL_ID)));
    await assertFails(setDoc(doc(client, CONTROL, CONTROL_ID),
        {revision: 10000, unit: 'coins'}));
    await assertFails(setDoc(doc(client, AUDIT, 'fake'),
        {role: 'general_manager'}));
  }
});

test('Neither personal, gift, admin, or user wallets are debited or credited', async () => {
  const collections = [
    ['admin_wallets', 'gm', {diamonds: 1000000, coins: 1000000}],
    ['admin_gift_wallets', 'gm', {diamonds: 800000, coins: 800000}],
    ['users', 'member', {points: 77, coins: 15, diamonds: 4}],
  ];
  for (const [coll, id, val] of collections) {
    await db.collection(coll).doc(id).set(val);
  }
  await edit(regular());
  await edit(offer('eid_bonus', '2026-10-11', '2026-10-12', 50,
      'coins', 1));
  for (const [coll, id, val] of collections) {
    assert.deepEqual((await db.collection(coll).doc(id).get()).data(), val);
  }
  assert.equal((await db.collection('deda_stage9_shadow_balances')
      .get()).size, 0);
});

test('Malformed policy is ignored for display and refused for all writes', async () => {
  const raw = {
    schemaVersion: 1, revision: 3,
    entries: [offer('bad7', '2026-10-10', '2026-10-11',
        999999, 'coins')],
  };
  await db.collection(CONTROL).doc(CONTROL_ID).set(raw);
  assert.equal(selectLoginReward(raw, EID_START).amount, 10);
  assert.equal(selectLoginReward(raw, EID_START).policyInvalid, true);
  assert.equal((await edit(offer('eid_bonus', '2026-10-11',
      '2026-10-12', 50, 'coins', 3))).outcome,
      'invalid-existing-policy');
  assert.equal((await audits()).length, 0);
});

test('Hard safety lock rejects absent/incorrect emulator environment', async () => {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  const project = process.env.GCLOUD_PROJECT;
  try {
    delete process.env.FIRESTORE_EMULATOR_HOST;
    await assert.rejects(edit(offer()),
        /STAGE11_EMULATOR_ONLY_NO_LIVE_PAYOUT/);
    process.env.FIRESTORE_EMULATOR_HOST = host;
    process.env.GCLOUD_PROJECT = 'real-project';
    await assert.rejects(edit(offer()),
        /STAGE11_EMULATOR_ONLY_NO_LIVE_PAYOUT/);
  } finally {
    process.env.FIRESTORE_EMULATOR_HOST = host;
    process.env.GCLOUD_PROJECT = project;
  }
});
