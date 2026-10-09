import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {before, beforeEach, after, test} from 'node:test';
import {
  initializeTestEnvironment, assertFails, assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, serverTimestamp, Timestamp,
} from 'firebase/firestore';

const nodeRequire = createRequire(import.meta.url);
const fnRequire = createRequire(
    new URL('../../functions/package.json', import.meta.url));
const {initializeApp, deleteApp} = fnRequire('firebase-admin/app');
const {getFirestore, Timestamp: AdminTimestamp} = fnRequire('firebase-admin/firestore');
const {
  PROJECT, SHADOW_COLLECTIONS, eventId, ledgerId,
} = nodeRequire('../../functions/deda_daily_reward_shadow_ledger.js');
const {iraqDayId, midnightUtcForIraqDay} = nodeRequire(
    '../../functions/deda_daily_task_publisher.js');
const {
  SLOT, PROOF_KIND, makeVerifier,
} = nodeRequire('../../functions/deda_daily_task_share_verifier.js');

const UID = 'user-sender-1';
const RECIPIENT_UID = 'user-recipient-2';
const SENDER_ID = '@DEDA-ABC234';
const RECIPIENT_ID = '@DEDA-DEF567';
const SOURCE_ID = 'share_proof_01';

let env, adminApp, db, owner, opponent, anonymous, verify;
let actualNow, dayId, startUtc;

function validRequest(
    shareId = SOURCE_ID, overrides = {}) {
  return {
    auth: {
      uid: UID,
      token: {firebase: {sign_in_provider: 'password'}},
    },
    app: {appId: '1:123456789:android:trusted-emulator-app'},
    data: {shareId, confirm: true},
    ...overrides,
  };
}

function shareRecord(changes = {}) {
  return {
    senderUid: UID,
    senderPublicId: SENDER_ID,
    senderName: 'مستخدم تجريبي',
    recipientPublicId: RECIPIENT_ID,
    shareType: 'current',
    placeName: '',
    placeId: '',
    latitude: 31.99,
    longitude: 44.99,
    durationMinutes: 30,
    status: 'pending',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    expiresAt: Timestamp.fromDate(new Date(Date.now() + 30 * 60000)),
    ...changes,
  };
}

async function createShare(id = SOURCE_ID, changes = {}) {
  return assertSucceeds(setDoc(doc(owner, 'deda_location_shares', id),
      shareRecord(changes)));
}

async function seedCore({action = SLOT, configUpdates = {}} = {}) {
  actualNow = new Date();
  dayId = iraqDayId(actualNow);
  startUtc = midnightUtcForIraqDay(dayId);
  await db.collection('users').doc(UID).set({
    name: 'مستخدم تجريبي', sharePersonalId: SENDER_ID,
    accountKey: '9647000000001',
  });
  await db.collection('users').doc(RECIPIENT_UID).set({
    name: 'مستلم تجريبي', sharePersonalId: RECIPIENT_ID,
    accountKey: '9647000000002',
  });
  for (const [id, uid] of [[SENDER_ID, UID],
    [RECIPIENT_ID, RECIPIENT_UID]]) {
    await db.collection('deda_share_ids').doc(id).set({
      publicId: id, ownerUid: uid,
      active: true, kind: 'personal',
      displayName: uid,
    });
  }
  await db.collection('deda_daily_published_task_slots').doc(SLOT).set({
    slotId: SLOT,
    action,
    titleAr: 'شارك موقعك الشخصي',
    titleEn: 'شارك موقعك الشخصي',
    effectiveDay: dayId,
    publicationId: dayId.replace(/-/g, '') + '__' + SLOT,
    effectiveAt: AdminTimestamp.fromDate(startUtc),
    publishedAt: AdminTimestamp.fromDate(startUtc),
    sourcePreviewRevision: 4,
    targetCount: 1,
    rewardUnit: 'points',
    rewardAmount: 5,
    rewardsEnabled: false,
    rewardClaimMode: 'disabled_until_verified_server_ledger',
    ...configUpdates,
  });
  verify = makeVerifier({db, serverNow: () => new Date()});
}

async function shadowBalance(uid = UID) {
  const snapshot = await db.collection(SHADOW_COLLECTIONS.balances).doc(uid).get();
  return snapshot.exists ? snapshot.data() : null;
}

async function shadowCount() {
  return (await db.collection(SHADOW_COLLECTIONS.ledger).get()).size;
}

before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'EMULATOR_ONLY');
  assert.equal(process.env.GCLOUD_PROJECT, PROJECT);
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: {rules: readFileSync('firestore.rules', 'utf8')},
  });
  adminApp = initializeApp({projectId: PROJECT}, 'stage10-share-proof');
  db = getFirestore(adminApp);
  owner = env.authenticatedContext(UID).firestore();
  opponent = env.authenticatedContext('attacker').firestore();
  anonymous = env.unauthenticatedContext().firestore();
});

beforeEach(async () => {
  await env.clearFirestore();
  await seedCore();
});

after(async () => {
  if (env) await env.cleanup();
  if (adminApp) await deleteApp(adminApp);
});

test('Real authenticated Firestore location share qualifies only the owner', async () => {
  await createShare();
  const result = await verify(validRequest());
  assert.deepEqual(result, {
    outcome: 'verified-personal-share', shadow: 'shadow-recorded',
  });
  const evidence = await db.collection(SHADOW_COLLECTIONS.events)
      .doc(eventId(UID, dayId, SLOT)).get();
  assert.equal(evidence.data().fixtureSource, PROOF_KIND);
  assert.equal(evidence.data().sourceShareId, SOURCE_ID);
  assert.equal(evidence.data().serverVerified, true);
  assert.equal((await shadowBalance()).points, 5);
  assert.equal(await shadowCount(), 1);
  const entry = (await db.collection(SHADOW_COLLECTIONS.ledger)
      .doc(ledgerId(UID, dayId, SLOT, 4)).get()).data();
  assert.equal(entry.amount, 5);
  assert.equal(entry.shadowOnly, true);
});

test('The server cannot verify a claimed share document that does not exist', async () => {
  assert.deepEqual(await verify(validRequest()), {outcome: 'no-valid-share'});
  assert.equal(await shadowBalance(), null);
  assert.equal(await shadowCount(), 0);
});

test('Sender cannot forge a different sender UID through Firestore rules', async () => {
  await assertFails(setDoc(
      doc(owner, 'deda_location_shares', SOURCE_ID),
      shareRecord({senderUid: 'another-user'})));
  await assertFails(setDoc(
      doc(opponent, 'deda_location_shares', 'share_other_01'),
      shareRecord()));
  assert.equal((await verify(validRequest())).outcome, 'no-valid-share');
});

test('Client cannot forge server-side createdAt or report an invalid share', async () => {
  await assertFails(setDoc(
      doc(owner, 'deda_location_shares', SOURCE_ID),
      shareRecord({createdAt: Timestamp.fromDate(new Date('2030-01-01'))})));
  await assertFails(setDoc(
      doc(owner, 'deda_location_shares', 'share_wrong_kind'),
      shareRecord({shareType: 'invented'})));
  await assertFails(setDoc(
      doc(owner, 'deda_location_shares', 'share_wrong_duration'),
      shareRecord({durationMinutes: 999})));
  assert.equal(await shadowCount(), 0);
});

test('Signed-out, anonymous or unverified app client gets no evidence', async () => {
  await createShare();
  assert.equal((await verify(validRequest(SOURCE_ID, {auth: null})))
      .outcome, 'auth-required');
  const request = validRequest();
  request.auth.token.firebase.sign_in_provider = 'anonymous';
  assert.equal((await verify(request)).outcome, 'auth-required');
  assert.equal((await verify(validRequest(SOURCE_ID, {app: null})))
      .outcome, 'app-check-required');
  assert.equal(await shadowCount(), 0);
});

test('Extra client-set identity, timestamps or raw completion flags are refused', async () => {
  await createShare();
  for (const malicious of [
    {shareId: SOURCE_ID, confirm: true, uid: UID},
    {shareId: SOURCE_ID, confirm: true, trustedNow: new Date().toISOString()},
    {shareId: SOURCE_ID, confirm: true, serverVerified: true},
    {shareId: SOURCE_ID, confirm: true, rewardAmount: 5000},
    {shareId: SOURCE_ID, confirm: true, action: SLOT},
    {shareId: SOURCE_ID, confirm: 'true'},
    {shareId: 'deda_location_shares/evil', confirm: true},
  ]) {
    const result = await verify(validRequest(SOURCE_ID, {data: malicious}));
    assert.equal(result.outcome, 'invalid-request');
  }
  assert.equal(await shadowCount(), 0);
});

test('Claim for another persons persisted share is refused even with same client payload', async () => {
  await createShare();
  const forged = validRequest();
  forged.auth.uid = RECIPIENT_UID;
  assert.equal((await verify(forged)).outcome, 'no-valid-share');
  assert.equal(await shadowCount(), 0);
});

test('Recipient inactive, different owner or same sender account is rejected', async () => {
  await createShare();
  for (const changes of [
    {active: false},
    {ownerUid: UID},
    {kind: 'place'},
  ]) {
    await db.collection('deda_share_ids').doc(RECIPIENT_ID)
        .update({...changes});
    assert.equal((await verify(validRequest())).outcome, 'no-valid-share');
    await db.collection('deda_share_ids').doc(RECIPIENT_ID).update({
      active: true, ownerUid: RECIPIENT_UID, kind: 'personal',
    });
  }
  assert.equal(await shadowCount(), 0);
});

test('Altered source after creation, wrong type or misleading fields are rejected', async () => {
  await db.collection('deda_location_shares').doc(SOURCE_ID).set({
    senderUid: UID, senderPublicId: SENDER_ID,
    senderName: 'مستخدم تجريبي', recipientPublicId: RECIPIENT_ID,
    shareType: 'place', placeId: 'abc', placeName: 'fake',
    latitude: 31.99, longitude: 44.99, durationMinutes: 30,
    status: 'pending', createdAt: AdminTimestamp.fromDate(new Date()),
    expiresAt: AdminTimestamp.fromDate(new Date(Date.now() + 1800000)),
  });
  assert.equal((await verify(validRequest())).outcome, 'no-valid-share');
  await db.collection('deda_location_shares').doc(SOURCE_ID).update({
    shareType: 'current', placeId: '', placeName: '',
    latitude: 9999,
  });
  assert.equal((await verify(validRequest())).outcome, 'no-valid-share');
  assert.equal(await shadowCount(), 0);
});

test('No override for Telegram and no grant on inactive or future configuration', async () => {
  await createShare();
  for (const changes of [
    {action: 'visit_telegram'},
    {rewardAmount: 9000},
    {rewardsEnabled: true},
    {effectiveDay: '2099-01-01'},
    {sourcePreviewRevision: 0},
  ]) {
    await db.collection('deda_daily_published_task_slots').doc(SLOT)
        .update(changes);
    assert.equal((await verify(validRequest())).outcome, 'inactive-task');
    await db.collection('deda_daily_published_task_slots').doc(SLOT).update({
      action: SLOT, rewardAmount: 5, rewardsEnabled: false,
      effectiveDay: dayId, sourcePreviewRevision: 4,
    });
  }
  assert.equal(await shadowCount(), 0);
});

test('Repeated and concurrent claim with one persisted share grants once', async () => {
  await createShare();
  const results = await Promise.all([
    verify(validRequest()), verify(validRequest()), verify(validRequest()),
  ]);
  assert.deepEqual(results.map(r => r.shadow).sort(),
      ['already-recorded', 'already-recorded', 'shadow-recorded']);
  assert.equal((await shadowBalance()).points, 5);
  assert.equal(await shadowCount(), 1);
});

test('Second verified personal share same day cannot double-claim reward', async () => {
  await createShare();
  await createShare('share_proof_02');
  assert.equal((await verify(validRequest())).shadow, 'shadow-recorded');
  assert.equal((await verify(validRequest('share_proof_02'))).outcome,
      'already-verified-different-share');
  assert.equal((await shadowBalance()).points, 5);
  assert.equal(await shadowCount(), 1);
});

test('Direct writes to private server evidence and ledger are blocked', async () => {
  await createShare();
  await verify(validRequest());
  for (const client of [owner, opponent, anonymous]) {
    await assertFails(setDoc(doc(client, SHADOW_COLLECTIONS.events,
        eventId(UID, dayId, SLOT)), {serverVerified: true, uid: UID}));
    await assertFails(setDoc(doc(client, SHADOW_COLLECTIONS.ledger, 'fake'),
        {amount: 999999}));
    await assertFails(getDoc(doc(client, SHADOW_COLLECTIONS.events,
        eventId(UID, dayId, SLOT))));
  }
});

test('Server proof does not change real users, admin or gift wallet balances', async () => {
  await db.collection('admin_wallets').doc('manager').set({
    points: 1000000, diamonds: 1000000,
  });
  await db.collection('admin_gift_wallets').doc('manager').set({
    diamonds: 900000, coins: 500000,
  });
  await db.collection('users').doc(UID).update({
    points: 55, diamonds: 10, coins: 27,
  });
  const refs = [
    db.collection('admin_wallets').doc('manager'),
    db.collection('admin_gift_wallets').doc('manager'),
    db.collection('users').doc(UID),
  ];
  const before = await Promise.all(refs.map(async ref =>
    (await ref.get()).data()));
  await createShare();
  assert.equal((await verify(validRequest())).shadow, 'shadow-recorded');
  const after = await Promise.all(refs.map(async ref =>
    (await ref.get()).data()));
  assert.deepEqual(after, before);
});

test('Cannot start verification outside the named Firestore emulator project', async () => {
  const old = process.env.FIRESTORE_EMULATOR_HOST;
  try {
    delete process.env.FIRESTORE_EMULATOR_HOST;
    await assert.rejects(verify(validRequest()),
        /STAGE10_EMULATOR_ONLY_DO_NOT_PAY/);
  } finally {
    process.env.FIRESTORE_EMULATOR_HOST = old;
  }
});
