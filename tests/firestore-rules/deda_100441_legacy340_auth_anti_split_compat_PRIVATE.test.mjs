// DEDA 100441 — Firebase LOCAL EMULATOR only; no production credentials.
// 100340 exact PIN source commit acbc821402d4b1bb20a66cdbe199c31a46599d3b
// Legacy compatibility tests model Firestore requests from that source.
// No handset APK execution, no actual user account, no real PIN or phone.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {before, after, beforeEach, test} from 'node:test';
import {initializeTestEnvironment, assertFails, assertSucceeds} from '@firebase/rules-unit-testing';
import {doc, getDoc, setDoc, updateDoc, writeBatch, serverTimestamp} from 'firebase/firestore';

const require = createRequire(import.meta.url);
const {inspectCanonicalUid} = require(
  '../../functions/deda_100441_canonical_uid_anti_split_preflight_PRIVATE_NOT_EXPORTED.js'
);
const PROJECT = 'demo-deda-100441-legacy340-anti-split';
const ACCOUNT = '07111111111';  // totally synthetic; NOT a real account
const ACCOUNT_OTHER = '07222222222';
const PIN = '683204';  // synthetic emulator-only fixture
const ORIGINAL = '@DEDA-ABC123';
const A = 'auth-owner-original-A';
const B = 'auth-second-device-B';
const C = 'auth-third-device-C';
const INSTALL_A = 'synthetic-original-install';
const INSTALL_B = 'synthetic-new-install';
let env;

const dbFor = uid => env.authenticatedContext(uid).firestore();
const accountRef = db => doc(db, 'deda_account_directory', ACCOUNT);
const credsRef = db => doc(db, 'deda_credentials', ACCOUNT);
const sessionRef = (db, uid) => doc(db, 'deda_sessions', uid);
const userRef = (db, uid) => doc(db, 'users', uid);

function registration(account = ACCOUNT, ownerUid = A) {
  return {
    directory: {accountKey: account, active: true, createdUid: ownerUid,
      createdAt: serverTimestamp(), updatedAt: serverTimestamp()},
    credentials: {accountKey: account, active: true, createdUid: ownerUid,
      pin: PIN, createdAt: serverTimestamp(), updatedAt: serverTimestamp()},
  };
}
function session(account, uid, installId) {
  return {uid, accountKey: account, installId,
    signedInAt: serverTimestamp(), lastSeenAt: serverTimestamp()};
}
function user(account, id) {
  return {accountKey: account, name: 'QA only', phone: account,
    accountType: 'user', authMethod: 'deda_pin_firestore_v1',
    trustedInstallIds: [id], updatedAt: serverTimestamp(),
    lastSeenAt: serverTimestamp()};
}
function snapshot(liveUid, provider, socialUid = A) {
  return {
    accountKey: ACCOUNT,
    originalId: ORIGINAL,
    directory: {accountKey: ACCOUNT, active: true, createdUid: A},
    credentials: {accountKey: ACCOUNT, active: true, createdUid: A},
    user: {accountKey: ACCOUNT, sharePersonalId: ORIGINAL},
    route: {publicId: ORIGINAL, active: true, kind: 'personal', ownerUid: A},
    social: {publicId: ORIGINAL, ownerUid: socialUid},
    liveAuthUid: liveUid,
    authProvider: provider,
    session: {uid: liveUid, accountKey: ACCOUNT},
  };
}
function mustNeverAuthorize(out) {
  assert.equal(out.canSignIn, false);
  assert.equal(out.canCreateUid, false);
  assert.equal(out.canReassignOwner, false);
  assert.equal(out.canWriteFirestore, false);
  assert.equal(out.canModifyFinances, false);
  assert.equal(out.canModifyAdmin, false);
}
async function provePin(db, uid, account = ACCOUNT, pin = PIN) {
  await assertSucceeds(setDoc(doc(db, 'deda_auth_attempts', uid), {
    uid, accountKey: account, pin, createdAt: serverTimestamp(),
  }));
}
async function openSession(db, uid, install = INSTALL_A, account = ACCOUNT) {
  await assertSucceeds(setDoc(sessionRef(db, uid), session(account, uid, install)));
}
async function seedLegacyAccount() {
  // Only TEST fixture seeding bypasses Firestore rules. Production is NEVER accessed.
  await env.withSecurityRulesDisabled(async ctx => {
    const db = ctx.firestore();
    const r = registration();
    const batch = writeBatch(db);
    batch.set(credsRef(db), r.credentials);
    batch.set(accountRef(db), r.directory);
    batch.set(sessionRef(db, A), session(ACCOUNT, A, INSTALL_A));
    batch.set(userRef(db, A), {...user(ACCOUNT, INSTALL_A), sharePersonalId: ORIGINAL});
    batch.set(doc(db, 'deda_account_profiles', ACCOUNT), {
      accountKey: ACCOUNT, name: 'QA only', phone: ACCOUNT,
      accountType: 'user', trustedInstallIds: [INSTALL_A],
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
      lastSeenAt: serverTimestamp(),
    });
    batch.set(doc(db, 'deda_share_ids', ORIGINAL), {
      publicId: ORIGINAL, kind: 'personal', active: true,
      ownerUid: A, displayName: 'QA only',
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    });
    batch.set(doc(db, 'deda_social_profiles', ORIGINAL), {
      publicId: ORIGINAL, ownerUid: A, displayName: 'QA only',
    });
    await batch.commit();
  });
}
before(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: {rules: readFileSync('firestore.rules', 'utf8')},
  });
});
after(async () => {if (env) await env.cleanup();});
beforeEach(async () => {await env.clearFirestore();});

test('100340 first-time registration still creates one directory and PIN credential atomically', async () => {
  const db = dbFor(A);
  const data = registration();
  const batch = writeBatch(db);
  batch.set(credsRef(db), data.credentials);
  batch.set(accountRef(db), data.directory);
  await assertSucceeds(batch.commit());
  assert.equal((await assertSucceeds(getDoc(accountRef(db)))).data().createdUid, A);
  await assertFails(getDoc(credsRef(db)));
  await provePin(db, A);
  await openSession(db, A);
  await assertSucceeds(setDoc(userRef(db, A), user(ACCOUNT, INSTALL_A)));
  assert.equal((await assertSucceeds(getDoc(userRef(db, A)))).data().accountKey, ACCOUNT);
  assert.equal((await assertSucceeds(getDoc(sessionRef(db, A)))).data().uid, A);
  mustNeverAuthorize(inspectCanonicalUid({...snapshot(A, 'anonymous'), route: null}));
});

test('100340 returning original UID can still verify PIN, refresh session and read own profile', async () => {
  await seedLegacyAccount();
  const db = dbFor(A);
  await provePin(db, A);
  await openSession(db, A);
  await assertSucceeds(getDoc(userRef(db, A)));
  await assertSucceeds(getDoc(doc(db, 'deda_account_profiles', ACCOUNT)));
  await assertSucceeds(getDoc(doc(db, 'deda_share_ids', ORIGINAL)));
  const owner = (await assertSucceeds(getDoc(doc(db, 'deda_share_ids', ORIGINAL)))).data();
  assert.equal(owner.ownerUid, A);
  const out = inspectCanonicalUid(snapshot(A, 'anonymous'));
  assert.equal(out.detail, 'NO_DURABLE_AUTH_PROVIDER');
  mustNeverAuthorize(out);
});

test('100340 second anonymous phone CAN pass same PIN under a distinct UID; new preflight BLOCKS ownership', async () => {
  await seedLegacyAccount();
  const second = dbFor(B);
  await provePin(second, B);
  await openSession(second, B, INSTALL_B);
  await assertSucceeds(setDoc(userRef(second, B), user(ACCOUNT, INSTALL_B)));
  const secondRow = (await assertSucceeds(getDoc(userRef(second, B)))).data();
  assert.equal(secondRow.accountKey, ACCOUNT);
  assert.equal((await assertSucceeds(getDoc(sessionRef(second, B)))).data().accountKey, ACCOUNT);
  const checked = inspectCanonicalUid(snapshot(B, 'anonymous'));
  assert.equal(checked.status, 'SPLIT');
  assert.equal(checked.detail, 'LIVE_AUTH_UID_NOT_CANONICAL');
  mustNeverAuthorize(checked);
  const before = (await assertSucceeds(getDoc(doc(second, 'deda_share_ids', ORIGINAL)))).data();
  assert.equal(before.ownerUid, A);
  await assertFails(updateDoc(doc(second, 'deda_share_ids', ORIGINAL), {
    displayName: 'must-not-steal', updatedAt: serverTimestamp(),
  }));
  const original = dbFor(A);
  assert.equal((await assertSucceeds(getDoc(doc(original, 'deda_share_ids', ORIGINAL)))).data().ownerUid, A);
  assert.equal((await assertSucceeds(getDoc(accountRef(original)))).data().createdUid, A);
});

test('100340 incorrect PIN fails at Firestore server; credential remains unreadable to any client', async () => {
  await seedLegacyAccount();
  const second = dbFor(B);
  await assertFails(setDoc(doc(second, 'deda_auth_attempts', B), {
    uid: B, accountKey: ACCOUNT, pin: '000000',
    createdAt: serverTimestamp(),
  }));
  await assertFails(getDoc(credsRef(second)));
  await assertFails(getDoc(credsRef(dbFor(A))));
  await assertFails(setDoc(sessionRef(second, B),
    session(ACCOUNT, B, INSTALL_B)));
});

test('existing number cannot register duplicate canonical directory/credential from other UID', async () => {
  await seedLegacyAccount();
  const second = dbFor(B);
  const r = registration(ACCOUNT, B);
  const batch = writeBatch(second);
  batch.set(credsRef(second), r.credentials);
  batch.set(accountRef(second), r.directory);
  await assertFails(batch.commit());
  assert.equal((await assertSucceeds(getDoc(accountRef(dbFor(A))))).data().createdUid, A);
});

test('legacy trusted-install session under another UID is NOT independent proof for future recovery', async () => {
  await seedLegacyAccount();
  const newUid = dbFor(C);
  // Existing rules permit a listed installation string instead of PIN.
  // This documents the compatibility hazard; DO NOT change live rules abruptly.
  await openSession(newUid, C, INSTALL_A);
  const out = inspectCanonicalUid(snapshot(C, 'anonymous'));
  assert.equal(out.status, 'SPLIT');
  mustNeverAuthorize(out);
  assert.equal((await assertSucceeds(getDoc(accountRef(dbFor(A))))).data().createdUid, A);
});

test('separate ordinary accounts remain isolated; no global block on legacy user logins', async () => {
  await seedLegacyAccount();
  const other = dbFor('other-independent-user');
  const batch = writeBatch(other);
  const r = registration(ACCOUNT_OTHER, 'other-independent-user');
  batch.set(doc(other, 'deda_credentials', ACCOUNT_OTHER), r.credentials);
  batch.set(doc(other, 'deda_account_directory', ACCOUNT_OTHER), r.directory);
  await assertSucceeds(batch.commit());
  await provePin(other, 'other-independent-user', ACCOUNT_OTHER);
  await openSession(other, 'other-independent-user', 'other-independent-install', ACCOUNT_OTHER);
  await assertSucceeds(setDoc(userRef(other, 'other-independent-user'),
    user(ACCOUNT_OTHER, 'other-independent-install')));
  assert.equal((await assertSucceeds(getDoc(
    doc(other, 'deda_account_directory', ACCOUNT_OTHER)))).data().createdUid,
  'other-independent-user');
  assert.equal((await assertSucceeds(getDoc(accountRef(dbFor(A))))).data().createdUid, A);
});
