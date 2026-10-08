import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import {
  initializeTestEnvironment, assertFails, assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  collection, deleteDoc, doc, getDoc, getDocs, setDoc,
  serverTimestamp, updateDoc, writeBatch,
} from 'firebase/firestore';

// Runs only inside the LOCAL Firestore emulator. No production credentials.
// All demo-* project IDs are rejected by real Firebase services.
const projectId = 'demo-deda-phase2-drafts';
let env;
let manager, otherManager, employee, province, stopped, normal, stranger;

function taskDraft(uid = 'manager', overrides = {}) {
  return {
    cycle: 'daily', action: 'open_map', titleAr: 'فتح الخارطة اليوم',
    titleEn: 'Open the map today', targetCount: 1,
    rewardUnit: 'points', rewardAmount: 10, url: '',
    status: 'draft', revision: 1,
    createdByUid: uid, updatedByUid: uid,
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    ...overrides,
  };
}

function surveyDraft(uid = 'manager', overrides = {}) {
  return {
    titleAr: 'رأيك يهمنا', titleEn: 'رأيك يهمنا',
    questions: [{
      type: 'rating_5', promptAr: 'ما رأيك بالخارطة؟',
      promptEn: 'ما رأيك بالخارطة؟', optionsAr: [], optionsEn: [],
      required: true,
    }],
    rewardUnit: 'coins', rewardAmount: 25,
    durationDays: 14, status: 'draft',
    rewardPolicy: 'once_per_account_on_verified_submission',
    revision: 1, createdByUid: uid, updatedByUid: uid,
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    ...overrides,
  };
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId,
    firestore: { rules: readFileSync('firestore.rules', 'utf8') },
  });
  manager = env.authenticatedContext('manager').firestore();
  otherManager = env.authenticatedContext('manager2').firestore();
  employee = env.authenticatedContext('employee').firestore();
  province = env.authenticatedContext('province').firestore();
  stopped = env.authenticatedContext('stopped').firestore();
  normal = env.authenticatedContext('user').firestore();
  stranger = env.unauthenticatedContext().firestore();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const [id, role, active, status] of [
      ['manager', 'general_manager', true, 'active'],
      ['manager2', 'general_manager', true, 'active'],
      ['employee', 'employee', true, 'active'],
      ['province', 'province_agent', true, 'active'],
      ['stopped', 'general_manager', false, 'disabled'],
      ['user', 'ordinary_user', false, 'active'],
    ]) {
      await setDoc(doc(db, 'admins', id), { role, active, status });
    }
  });
});

after(async () => {
  if (env) await env.cleanup();
});

test('Only active general managers can read task/survey draft lists', async () => {
  for (const name of ['admin_task_drafts', 'admin_survey_drafts']) {
    await assertSucceeds(getDocs(collection(manager, name)));
    for (const db of [employee, province, stopped, normal, stranger]) {
      await assertFails(getDocs(collection(db, name)));
      await assertFails(getDoc(doc(db, name, 'arbitrary-id')));
    }
  }
});

test('Manager can atomically create both types with audit, no public payout', async () => {
  for (const [path, draft] of [
    ['admin_task_drafts', taskDraft()],
    ['admin_survey_drafts', surveyDraft()],
  ]) {
    const itemRef = doc(manager, path, 'draft-1');
    const auditRef = doc(manager, 'admin_audit', path + '-create');
    const batch = writeBatch(manager);
    batch.set(itemRef, draft);
    batch.set(auditRef, {
      action: path === 'admin_task_drafts'
        ? 'task_draft_created' : 'admin_survey_draft_created',
      adminUid: 'manager', createdAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
    const read = await assertSucceeds(getDoc(itemRef));
    assert.equal(read.data().status, 'draft');
    assert.equal(read.data().revision, 1);
    await assertFails(getDoc(doc(normal, path, 'draft-1')));
    await assertFails(deleteDoc(itemRef));
  }
});

test('A non-manager cannot create drafts, even with a forged audit entry', async () => {
  for (const [path, draft] of [
    ['admin_task_drafts', taskDraft('employee')],
    ['admin_survey_drafts', surveyDraft('employee')],
  ]) {
    await assertFails(setDoc(doc(employee, path, 'forbidden'), draft));
    await assertFails(setDoc(doc(normal, path, 'forbidden'), draft));
    await assertFails(setDoc(doc(stopped, path, 'forbidden'), draft));
  }
});

test('Draft-only status and rigid schema reject payout / publish fields', async () => {
  for (const [path, draft] of [
    ['admin_task_drafts', taskDraft()],
    ['admin_survey_drafts', surveyDraft()],
  ]) {
    const ref = doc(manager, path, 'attack');
    await assertFails(setDoc(ref, { ...draft, status: 'active' }));
    await assertFails(setDoc(ref, { ...draft, claimAvailable: true }));
    await assertFails(setDoc(ref, { ...draft, userWalletDebit: 10 }));
    await assertFails(setDoc(ref, { ...draft, rewardAmount: -1 }));
    await assertFails(setDoc(ref, { ...draft, createdByUid: 'another' }));
  }
});

test('Two managers cannot overwrite concurrent revisions or creators', async () => {
  for (const [path, data] of [
    ['admin_task_drafts', taskDraft()],
    ['admin_survey_drafts', surveyDraft()],
  ]) {
    const ref = doc(manager, path, 'edit');
    await assertSucceeds(setDoc(ref, data));
    const anotherRef = doc(otherManager, path, 'edit');
    await assertSucceeds(updateDoc(anotherRef, {
      revision: 2, updatedByUid: 'manager2',
      updatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(ref, {
      revision: 2, updatedByUid: 'manager',
      updatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(ref, { status: 'active', revision: 3,
      updatedByUid: 'manager', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref, { createdByUid: 'manager2', revision: 3,
      updatedByUid: 'manager', updatedAt: serverTimestamp() }));
    const current = await assertSucceeds(getDoc(ref));
    assert.equal(current.data().revision, 2);
    assert.equal(current.data().createdByUid, 'manager');
    assert.equal(current.data().status, 'draft');
  }
});

test('Audit write failure rolls back draft creation atomically', async () => {
  const ref = doc(manager, 'admin_survey_drafts', 'rollback');
  const batch = writeBatch(manager);
  batch.set(ref, surveyDraft());
  batch.set(doc(manager, 'admin_audit', 'invalid-audit'), {
    action: 'admin_survey_draft_created',
    adminUid: 'not-the-manager', createdAt: serverTimestamp(),
  });
  await assertFails(batch.commit());
  const snapshot = await assertSucceeds(getDoc(ref));
  assert.equal(snapshot.exists(), false);
});

test('Survey policy permits coins or diamonds but never pays balances', async () => {
  for (const [unit, amount] of [['coins', 15000], ['diamonds', 55]]) {
    const ref = doc(manager, 'admin_survey_drafts', unit);
    await assertSucceeds(setDoc(ref, surveyDraft('manager', {
      rewardUnit: unit, rewardAmount: amount,
    })));
    const snapshot = await assertSucceeds(getDoc(ref));
    assert.equal(snapshot.data().rewardUnit, unit);
    assert.equal(snapshot.data().rewardAmount, amount);
    assert.equal(snapshot.data().rewardPolicy,
      'once_per_account_on_verified_submission');
    // This section intentionally has no client claim or transfer API.
    await assertFails(setDoc(doc(normal, 'admin_survey_drafts', 'user-claim'), {
      ...surveyDraft('user'), rewardUnit: unit,
    }));
  }
  await assertFails(setDoc(doc(manager, 'admin_survey_drafts', 'too-big'),
    surveyDraft('manager', { rewardAmount: 1000001 })));
});

test('Question types, choices, and counts are checked by security rules', async () => {
  const ref = doc(manager, 'admin_survey_drafts', 'invalid-questions');
  const base = surveyDraft();
  await assertFails(setDoc(ref, { ...base, questions: [] }));
  await assertFails(setDoc(ref, { ...base,
    questions: Array(5).fill(base.questions[0]) }));
  await assertFails(setDoc(ref, { ...base,
    questions: [{ ...base.questions[0], type: 'instant_reward' }] }));
  await assertFails(setDoc(ref, { ...base,
    questions: [{
      ...base.questions[0], type: 'choice',
      optionsAr: ['نعم', 4], optionsEn: ['نعم', 4],
    }] }));
  await assertSucceeds(setDoc(ref, { ...base,
    questions: [{
      ...base.questions[0], type: 'choice',
      optionsAr: ['نعم', 'لا'], optionsEn: ['نعم', 'لا'],
    }] }));
});


test('APK 100321 exact Arabic survey write with full audit succeeds for 1 and 3 rating questions', async () => {
  const prompts = [
    'ما رأيك باستخدام خارطة DEDA؟',
    'ما رأيك بالمهام اليومية؟',
    'ما رأيك بالأسئلة المرورية؟',
  ];
  for (const [count, unit, amount] of [[1, 'none', 0], [3, 'diamonds', 10]]) {
    const path = 'apk100321-' + count;
    const questions = prompts.slice(0, count).map(promptAr => ({
      type: 'rating_5', promptAr, promptEn: promptAr,
      optionsAr: [], optionsEn: [], required: true,
    }));
    const draft = surveyDraft('manager', {
      titleAr: 'آراء المستخدمين عن DEDA',
      titleEn: 'آراء المستخدمين عن DEDA',
      questions, rewardUnit: unit, rewardAmount: amount,
      durationDays: 14,
    });
    const batch = writeBatch(manager);
    batch.set(doc(manager, 'admin_survey_drafts', path), draft);
    batch.set(doc(manager, 'admin_audit', path + '-audit'), {
      action: 'admin_survey_draft_created',
      adminUid: 'manager',
      adminName: 'مدير عام',
      adminRole: 'general_manager',
      sourceCollection: 'admin_survey_drafts',
      sourceId: path,
      questionCount: count,
      createdAt: serverTimestamp(),
    });
    console.log('APK_100321_SURVEY_SAVE_START: question_count=' + count);
    await assertSucceeds(batch.commit());
    console.log('APK_100321_SURVEY_SAVE_OK: question_count=' + count);
    const saved = await assertSucceeds(getDoc(doc(manager, 'admin_survey_drafts', path)));
    assert.equal(saved.exists(), true);
    assert.equal(saved.data().questions.length, count);
    assert.equal(saved.data().rewardAmount, amount);
  }
});

test('Four Arabic rating questions and five-option choice rules keep limits without 1000-expression overflow', async () => {
  const allRatings = Array.from({length: 4}, (_, i) => ({
    type: 'rating_5',
    promptAr: 'تقييم خارطة ديدا وسرعتها رقم ' + (i + 1),
    promptEn: 'تقييم خارطة ديدا وسرعتها رقم ' + (i + 1),
    optionsAr: [], optionsEn: [], required: true,
  }));
  console.log('FOUR_RATINGS_START');
  await assertSucceeds(setDoc(doc(manager, 'admin_survey_drafts', 'max-four-ratings'),
    surveyDraft('manager', {questions: allRatings})));
  console.log('FOUR_RATINGS_PASS');
  const fiveChoices = [
    'ممتاز جداً', 'جيد جداً', 'جيد', 'مقبول', 'يحتاج تطوير',
  ];
  const allChoices = Array.from({length: 4}, (_, i) => ({
    type: 'choice',
    promptAr: 'اختيار رأي عن خارطة ديدا رقم ' + (i + 1),
    promptEn: 'اختيار رأي عن خارطة ديدا رقم ' + (i + 1),
    optionsAr: fiveChoices, optionsEn: fiveChoices, required: true,
  }));
  console.log('FOUR_CHOICES_START');
  await assertSucceeds(setDoc(doc(manager, 'admin_survey_drafts', 'max-four-choices'),
    surveyDraft('manager', {questions: allChoices})));
  console.log('FOUR_CHOICES_PASS');
});



test('Four-question survey can be created with the real manager audit batch', async () => {
  const choices = ['ممتاز', 'جيد', 'مقبول', 'ضعيف', 'سيئ'];
  const questions = Array.from({ length: 4 }, (_, i) => ({
    type: i % 2 == 0 ? 'choice' : 'rating_5',
    promptAr: 'سؤال عن أداء التطبيق رقم ' + (i + 1),
    promptEn: 'سؤال عن أداء التطبيق رقم ' + (i + 1),
    optionsAr: i % 2 == 0 ? choices : [],
    optionsEn: i % 2 == 0 ? choices : [],
    required: true,
  }));
  const batch = writeBatch(manager);
  batch.set(doc(manager, 'admin_survey_drafts', 'four-real-batch'),
    surveyDraft('manager', { questions, rewardUnit: 'diamonds', rewardAmount: 10 }));
  batch.set(doc(manager, 'admin_audit', 'four-real-batch-audit'), {
    action: 'admin_survey_draft_created',
    adminUid: 'manager', adminName: 'مدير عام', adminRole: 'general_manager',
    sourceCollection: 'admin_survey_drafts', sourceId: 'four-real-batch',
    questionCount: 4, createdAt: serverTimestamp(),
  });
  await assertSucceeds(batch.commit());
  const snap = await assertSucceeds(getDoc(doc(manager, 'admin_survey_drafts', 'four-real-batch')));
  assert.equal(snap.data().questions.length, 4);
  assert.equal(snap.data().rewardAmount, 10);
  await assertFails(setDoc(doc(manager, 'admin_survey_drafts', 'five-rejected'),
    surveyDraft('manager', { questions: [...questions, questions[0]] })));
});

test('Choice option validator rejects empty, overlength and non-string fields', async () => {
  const base = surveyDraft();
  for (const values of [
    ['موافق', ''], ['موافق', 'أ'.repeat(71)], ['موافق', 123],
  ]) {
    console.log('INVALID_CHOICE_TEST:', JSON.stringify(values));
    const badQuestion = {
      type: 'choice', promptAr: 'هل أعجبك تطبيق ديدا؟',
      promptEn: 'هل أعجبك تطبيق ديدا؟',
      optionsAr: values, optionsEn: values, required: true,
    };
    await assertFails(setDoc(doc(manager, 'admin_survey_drafts', 'bad-choice'), {
      ...base, questions: [badQuestion],
    }));
  }
});
