import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { before, beforeEach, after, test } from 'node:test';
import {
  initializeTestEnvironment, assertFails, assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  collection, doc, getDoc, getDocs, setDoc, updateDoc,
  deleteDoc, serverTimestamp, Timestamp, writeBatch,
} from 'firebase/firestore';

// Demo project and local emulator ONLY; no production credentials or deploy.
let environment, generalManager, employee, oldAlias, stopped, ordinary, stranger;
const path = 'admin_daily_schedule_previews';

function proposed(overrides = {}) {
  return {
    slotId: 'open_map', action: 'open_map',
    titleAr: 'فتح الخارطة مجددًا', titleEn: 'فتح الخارطة مجددًا',
    targetCount: 1, rewardUnit: 'points', rewardAmount: 5, url: '',
    status: 'pending', revision: 1,
    effectiveAt: Timestamp.fromDate(new Date(Date.now() + 6 * 3600000)),
    createdByUid: 'gm', updatedByUid: 'gm',
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    ...overrides,
  };
}

before(async () => {
  environment = await initializeTestEnvironment({
    projectId: 'demo-deda-daily-task-preview',
    firestore: { rules: readFileSync('firestore.rules', 'utf8') },
  });
  generalManager = environment.authenticatedContext('gm').firestore();
  employee = environment.authenticatedContext('employee').firestore();
  oldAlias = environment.authenticatedContext('legacyManager').firestore();
  stopped = environment.authenticatedContext('stopped').firestore();
  ordinary = environment.authenticatedContext('user').firestore();
  stranger = environment.unauthenticatedContext().firestore();
});

beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    for (const [uid, role, active] of [
      ['gm', 'general_manager', true],
      ['employee', 'employee', true],
      ['legacyManager', 'manager', true],
      ['stopped', 'general_manager', false],
    ]) {
      await setDoc(doc(db, 'admins', uid), {
        role, active, status: active ? 'active' : 'stopped',
      });
    }
  });
});

after(async () => {
  if (environment) await environment.cleanup();
});

test('The previews are private to the active general manager only', async () => {
  await assertSucceeds(getDocs(collection(generalManager, path)));
  for (const db of [employee, oldAlias, stopped, ordinary, stranger]) {
    await assertFails(getDocs(collection(db, path)));
    await assertFails(getDoc(doc(db, path, 'preview_open_map')));
  }
});

test('An admin may stage and read a pending, non-published change', async () => {
  const item = doc(generalManager, path, 'preview_open_map');
  await assertSucceeds(setDoc(item, proposed()));
  const saved = await assertSucceeds(getDoc(item));
  assert.equal(saved.data().status, 'pending');
  assert.equal(saved.data().revision, 1);
  assert.equal(saved.data().slotId, 'open_map');
  await assertFails(deleteDoc(item));
});

test('Only the chosen slot can be updated and cancelled before activation', async () => {
  const item = doc(generalManager, path, 'preview_open_map');
  await assertSucceeds(setDoc(item, proposed()));
  await assertSucceeds(updateDoc(item, {
    titleAr: 'تعديل فتح الخارطة', titleEn: 'تعديل فتح الخارطة',
    revision: 2, updatedByUid: 'gm', updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(item, {
    status: 'cancelled', revision: 3,
    updatedByUid: 'gm', updatedAt: serverTimestamp(),
  }));
  const result = await assertSucceeds(getDoc(item));
  assert.equal(result.data().status, 'cancelled');
  assert.equal(result.data().revision, 3);
  assert.equal(result.data().slotId, 'open_map');
  // A cancellation is not a deletion and cannot edit the prior payout config.
  await assertFails(updateDoc(item, {
    status: 'active', revision: 4,
    updatedByUid: 'gm', updatedAt: serverTimestamp(),
  }));
});

test('A user, disabled manager or deputy cannot forge a scheduled change', async () => {
  for (const db of [ordinary, employee, oldAlias, stopped, stranger]) {
    await assertFails(setDoc(doc(db, path, 'preview_open_map'), proposed()));
  }
  await assertFails(setDoc(doc(generalManager, path, 'preview_open_map'),
    proposed({ createdByUid: 'someone-else' })));
});

test('Unknown slots, login replacement and public publish flags are rejected', async () => {
  for (const [docId, fields] of [
    ['preview_daily_login', { slotId: 'daily_login' }],
    ['preview_fake', { slotId: 'fake' }],
    ['preview_open_map', { action: 'invented_task' }],
    ['preview_open_map', { status: 'active' }],
    ['preview_open_map', { published: true }],
    ['preview_open_map', { userWalletDebit: 5 }],
    ['preview_open_map', { rewardAmount: 900000 }],
  ]) {
    await assertFails(setDoc(doc(generalManager, path, docId), proposed(fields)));
  }
});

test('Past and implausibly distant activation timestamps are rejected', async () => {
  for (const offset of [-3600000, 3 * 86400000]) {
    const effectiveAt = Timestamp.fromDate(new Date(Date.now() + offset));
    await assertFails(setDoc(doc(generalManager, path, 'preview_open_map'),
      proposed({ effectiveAt })));
  }
});

test('Expired private preview can be replaced for a new day, not cancelled retroactively', async () => {
  const item = doc(generalManager, path, 'preview_open_map');
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), path, 'preview_open_map'),
      proposed({
        status: 'pending',
        effectiveAt: Timestamp.fromDate(new Date(Date.now() - 86400000)),
      }));
  });
  await assertFails(updateDoc(item, {
    status: 'cancelled', revision: 2,
    updatedByUid: 'gm', updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(item, {
    status: 'pending', revision: 2,
    effectiveAt: Timestamp.fromDate(new Date(Date.now() + 5 * 3600000)),
    updatedByUid: 'gm', updatedAt: serverTimestamp(),
  }));
  const saved = await assertSucceeds(getDoc(item));
  assert.equal(saved.data().revision, 2);
  assert.equal(saved.data().status, 'pending');
});

test('Manager edit needs next revision and original identity', async () => {
  const item = doc(generalManager, path, 'preview_open_map');
  await assertSucceeds(setDoc(item, proposed()));
  for (const changes of [
    { revision: 3 },
    { revision: 2, slotId: 'long_trip' },
    { revision: 2, createdByUid: 'someone-else' },
    { revision: 2, status: 'cancelled', rewardAmount: 500 },
  ]) {
    await assertFails(updateDoc(item, {
      ...changes, updatedAt: serverTimestamp(), updatedByUid: 'gm',
    }));
  }
  assert.equal((await assertSucceeds(getDoc(item))).data().revision, 1);
});

test('Audit batch failure never creates an orphan preview', async () => {
  const item = doc(generalManager, path, 'preview_open_map');
  const batch = writeBatch(generalManager);
  batch.set(item, proposed());
  batch.set(doc(generalManager, 'admin_audit', 'invalid-preview-audit'), {
    action: 'daily_schedule_preview_created', adminUid: 'forged',
    createdAt: serverTimestamp(),
  });
  await assertFails(batch.commit());
  assert.equal((await assertSucceeds(getDoc(item))).exists(), false);
});

test('Real manager can save a preview and admin audit atomically', async () => {
  const item = doc(generalManager, path, 'preview_open_map');
  const batch = writeBatch(generalManager);
  batch.set(item, proposed());
  batch.set(doc(generalManager, 'admin_audit', 'valid-preview-audit'), {
    action: 'daily_schedule_preview_created', adminUid: 'gm',
    createdAt: serverTimestamp(),
  });
  await assertSucceeds(batch.commit());
  assert.equal((await assertSucceeds(getDoc(item))).exists(), true);
});
