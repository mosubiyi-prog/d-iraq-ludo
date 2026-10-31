'use strict';
// Authorized offline safety audit of the repository's Firestore rule candidate.
// This test must NEVER connect to production. Synthetic PIN and account only.
const test = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');
const {createRequire} = require('node:module');
const req = createRequire(resolve(__dirname, '../functions/package.json'));
const {initializeTestEnvironment, assertSucceeds, assertFails} =
    req('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, serverTimestamp} = req('firebase/firestore');
const project = 'demo-deda-100421-pin-cross-device-security';
assert.equal(process.env.GCLOUD_PROJECT, project);
assert.match(process.env.FIRESTORE_EMULATOR_HOST || '',
    /^(127\.0\.0\.1|localhost):[0-9]{2,5}$/);
assert.equal(process.env.GOOGLE_APPLICATION_CREDENTIALS, undefined,
    'do not run this security audit using production credentials');

const account = '07700000000';
const foreign = '07700000001';
const oldUid = 'synthetic-original-device';
const newUid = 'synthetic-replacement-device';
const otherUid = 'synthetic-foreign-device';
const originalId = '@DEDA-AB3C5D';
const pin = '123456'; // TEST FIXTURE ONLY, never any real DEDA account secret.
let env;
const signed = uid => env.authenticatedContext(uid).firestore();
const credentials = () => ({
  accountKey: account, pin, active: true, createdUid: oldUid,
  createdAt: serverTimestamp(), updatedAt: serverTimestamp()
});
const attempt = (uid, key=account, pass=pin) => ({
  uid, accountKey: key, pin: pass, createdAt: serverTimestamp()
});
const session = (uid, key=account, installId='untrusted-replacement') => ({
  uid, accountKey: key, installId, signedInAt: serverTimestamp(),
  lastSeenAt: serverTimestamp()
});

test.before(async () => {
  env = await initializeTestEnvironment({
    projectId: project, firestore: {
      host: '127.0.0.1', port: 8080,
      rules: readFileSync(resolve(__dirname, '../firestore.rules'), 'utf8')
    }
  });
});
test.after(async () => { if (env) await env.cleanup(); });
test.beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async ctx => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'deda_credentials', account), credentials());
    await setDoc(doc(db, 'deda_credentials', foreign), {
      ...credentials(), accountKey: foreign, pin: '654321',
      createdUid: otherUid,
    });
    await setDoc(doc(db, 'deda_account_directory', account), {
      accountKey: account, active: true, createdUid: oldUid
    });
    await setDoc(doc(db, 'deda_account_profiles', account), {
      accountKey: account, name: 'Synthetic Owner',
      phone: account, accountType: 'user',
      trustedInstallIds: ['original-trusted-device'],
    });
    await setDoc(doc(db, 'users', oldUid), {
      accountKey: account, name: 'Synthetic Owner',
      sharePersonalId: originalId,
    });
    await setDoc(doc(db, 'deda_share_ids', originalId), {
      publicId: originalId, kind: 'personal',
      active: true, ownerUid: oldUid,
    });
  });
});

test('wrong PIN does not establish a server session on a new anonymous UID', async () => {
  const db = signed(newUid);
  await assertFails(setDoc(doc(db, 'deda_auth_attempts', newUid),
    attempt(newUid, account, '000000')));
  await assertFails(setDoc(doc(db, 'deda_sessions', newUid),
    session(newUid)));
  await assertFails(getDoc(doc(db, 'deda_account_profiles', account)));
});

test('correct demo PIN authenticates a different Firebase UID without sharing its original UID', async () => {
  const db = signed(newUid);
  await assertSucceeds(setDoc(doc(db, 'deda_auth_attempts', newUid),
    attempt(newUid)));
  await assertSucceeds(setDoc(doc(db, 'deda_sessions', newUid),
    session(newUid)));
  await assertSucceeds(getDoc(doc(db, 'deda_account_profiles', account)));
  await assertFails(getDoc(doc(db, 'users', oldUid)));
  const own = await getDoc(doc(db, 'deda_sessions', newUid));
  assert.equal(own.data().accountKey, account);
  assert.equal(own.data().uid, newUid);
});

test('new UID may create its projection only after PIN-proven session', async () => {
  const db = signed(newUid);
  const target = doc(db, 'users', newUid);
  const projection = {
    accountKey: account, name: 'Synthetic Owner', phone: account,
    accountType: 'user', authMethod: 'deda_pin_firestore_v1',
    sharePersonalId: originalId,
  };
  await assertFails(setDoc(target, projection));
  await assertSucceeds(setDoc(doc(db, 'deda_auth_attempts', newUid),
    attempt(newUid)));
  await assertSucceeds(setDoc(doc(db, 'deda_sessions', newUid),
    session(newUid)));
  await assertSucceeds(setDoc(target, projection));
  const own = await assertSucceeds(getDoc(target));
  assert.equal(own.data().sharePersonalId, originalId);
});

test('other account cannot gain this owner session by submitting its different PIN', async () => {
  const db = signed(otherUid);
  await assertFails(setDoc(doc(db, 'deda_auth_attempts', otherUid),
    attempt(otherUid, account, '654321')));
  await assertFails(setDoc(doc(db, 'deda_sessions', otherUid),
    session(otherUid, account)));
});

test('after PIN proof, the candidate permits trusting a new installation (security review required)', async () => {
  const db = signed(newUid);
  await assertSucceeds(setDoc(doc(db, 'deda_auth_attempts', newUid),
    attempt(newUid)));
  await assertSucceeds(setDoc(doc(db, 'deda_sessions', newUid),
    session(newUid)));
  const ref = doc(db, 'deda_account_profiles', account);
  const snapshot = await getDoc(ref);
  const existing = snapshot.data().trustedInstallIds;
  await assertSucceeds(setDoc(ref, {
    trustedInstallIds: [...existing, 'untrusted-replacement'],
    updatedAt: serverTimestamp(), lastSeenAt: serverTimestamp(),
  }, {merge:true}));
  const updated = await assertSucceeds(getDoc(ref));
  assert(updated.data().trustedInstallIds.includes('untrusted-replacement'));
  console.log('AUDIT: PIN-only new-device trust is supported; no SMS possession proof.');
});

test('same six-digit PIN can authorize a second synthetic anonymous UID: no global attempt gate in candidate', async () => {
  const db1 = signed(newUid);
  const db2 = signed('synthetic-third-new-uid');
  await assertSucceeds(setDoc(doc(db1, 'deda_auth_attempts', newUid),
    attempt(newUid)));
  await assertSucceeds(setDoc(doc(db2, 'deda_auth_attempts', 'synthetic-third-new-uid'),
    attempt('synthetic-third-new-uid')));
  console.log('AUDIT: no server-enforced cumulative attempt threshold is shown by these rules.');
});
