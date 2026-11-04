"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require("@firebase/rules-unit-testing");
const {
  doc, collection, getDoc, getDocs, setDoc, updateDoc, deleteDoc,
  serverTimestamp, runTransaction, Timestamp,
} = require("firebase/firestore");

// ONLY demo- project IDs with local emulator. No live Firebase credentials.
const PROJECT_BASE = "demo-deda-100436-journal-baseline";
const PROJECT_QA = "demo-deda-100436-journal-candidate";
const uid = "original-linked-uid-100436";
const strangerUid = "not-the-original-uid";
const account = "9647712345678";
const otherAccount = "9647700000011";
const original = "@DEDA-ABC123";
const intent = "original_login_20261104_001";
const code = "originalBackupReadback";
const step = `${intent}_${code}`;
const op = `deda_guardian_v1/${uid}/${intent}/${code}`;
const docPath = `deda_recovery_journals/${uid}/steps/${step}`;
const attestationPath =
    `deda_recovery_server_attestations/${uid}/receipts/${step}`;
const email = `${account}@deda-login.invalid`;

let baseEnv, qaEnv;
const linkedContext = (environment, id = uid, address = email,
    provider = "password") => environment.authenticatedContext(id, {
  email: address, firebase: {sign_in_provider: provider},
});
const owner = () => linkedContext(qaEnv).firestore();
const stranger = () => linkedContext(qaEnv, strangerUid).firestore();
const row = (db) => doc(db, docPath);
const reservation = (extra = {}) => ({
  ownerUid: uid, accountKey: account, originalId: original,
  intentId: intent, code, operationKey: op, state: "reserved",
  createdAt: serverTimestamp(), ...extra,
});

async function seed({session = true, directory = true,
    route = true, profile = true} = {}) {
  await qaEnv.clearFirestore();
  await qaEnv.withSecurityRulesDisabled(async ctx => {
    const db = ctx.firestore();
    if (directory) await setDoc(doc(db, "deda_account_directory", account), {
      accountKey: account, active: true, createdUid: uid,
    });
    if (profile) await setDoc(doc(db, "users", uid), {
      accountKey: account, sharePersonalId: original,
    });
    if (route) await setDoc(doc(db, "deda_share_ids", original), {
      publicId: original, kind: "personal", ownerUid: uid, active: true,
    });
    if (session) await setDoc(doc(db, "deda_sessions", uid), {
      uid, accountKey: account, installId: "existing-original-install",
      signedInAt: Timestamp.now(), lastSeenAt: Timestamp.now(),
    });
  });
}

test.before(async () => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST || "", /127\.0\.0\.1:/);
  const baseline = fs.readFileSync("firestore.rules", "utf8");
  const candidate = fs.readFileSync(
      process.env.DEDA_JOURNAL_EMULATOR_RULES, "utf8");
  assert.doesNotMatch(baseline, /match \/deda_recovery_journals/);
  assert.match(candidate, /match \/deda_recovery_journals/);
  baseEnv = await initializeTestEnvironment({
    projectId: PROJECT_BASE, firestore: {rules: baseline},
  });
  qaEnv = await initializeTestEnvironment({
    projectId: PROJECT_QA, firestore: {rules: candidate},
  });
});

test.after(async () => {
  if (baseEnv) await baseEnv.cleanup();
  if (qaEnv) await qaEnv.cleanup();
});

test("current 100436 rules deny new recovery journal operations", async () => {
  const db = linkedContext(baseEnv).firestore();
  await assertFails(getDoc(row(db)));
  await assertFails(setDoc(row(db), reservation()));
});

test("new verified original owner can read a MISSING row (reservation prerequisite)", async () => {
  await seed();
  const snapshot = await assertSucceeds(getDoc(row(owner())));
  assert.equal(snapshot.exists(), false);
});

test("linked original UID may atomically create & read only its reserved row", async () => {
  await seed();
  const db = owner();
  await assertSucceeds(runTransaction(db, async tx => {
    const item = await tx.get(row(db));
    assert.equal(item.exists(), false);
    tx.set(row(db), reservation());
  }));
  const saved = await assertSucceeds(getDoc(row(db)));
  assert.equal(saved.data().operationKey, op);
  assert.equal(saved.data().state, "reserved");
  assert.ok(saved.data().createdAt instanceof Timestamp);
});

test("same UID two devices: only ONE atomic reservation is ever created", async () => {
  await seed();
  const a = owner(), b = owner();
  const createOnce = db => runTransaction(db, async tx => {
    const prev = await tx.get(row(db));
    if (prev.exists()) return false;
    tx.set(row(db), reservation());
    return true;
  });
  const decisions = await Promise.all([
    assertSucceeds(createOnce(a)), assertSucceeds(createOnce(b)),
  ]);
  assert.deepEqual(decisions.sort(), [false, true]);
  const snap = await assertSucceeds(getDoc(row(a)));
  assert.equal(snap.data().state, "reserved");
  await assertFails(setDoc(row(b), reservation()));
});

test("other UID may not read or create original owner's journal", async () => {
  await seed();
  await assertSucceeds(setDoc(row(owner()), reservation()));
  await assertFails(getDoc(row(stranger())));
  await assertFails(setDoc(row(stranger()), reservation()));
});

test("anonymous, false email and admin-like provider cannot access", async () => {
  await seed();
  for (const db of [
    qaEnv.authenticatedContext(uid, {
      firebase: {sign_in_provider: "anonymous"},
    }).firestore(),
    linkedContext(qaEnv, uid, "manager@example.com").firestore(),
    qaEnv.unauthenticatedContext().firestore(),
  ]) {
    await assertFails(getDoc(row(db)));
    await assertFails(setDoc(row(db), reservation()));
  }
});

test("missing original route or directory or session fails closed", async () => {
  for (const missing of [
    {route: false}, {directory: false}, {session: false}, {profile: false},
  ]) {
    await seed(missing);
    await assertFails(setDoc(row(owner()), reservation()));
    await assertFails(getDoc(row(owner())));
  }
});

test("client cannot self-mark completed, add gift/diamond, or update receipt", async () => {
  await seed();
  const db = owner();
  await assertFails(setDoc(row(db), reservation({
    state: "verified", receiptId: "fakeReceipt012345",
    verifiedAt: serverTimestamp(),
  })));
  await assertFails(setDoc(row(db), reservation({diamondBalance: 999999})));
  await assertSucceeds(setDoc(row(db), reservation()));
  await assertFails(updateDoc(row(db), {
    state: "verified", receiptId: "fakeReceipt012345",
    verifiedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(row(db), {state: "reserved"}));
  const existing = await assertSucceeds(getDoc(row(db)));
  assert.equal(existing.data().state, "reserved");
});

test("client cannot delete, list, or bypass with malformed ID/operation", async () => {
  await seed();
  const db = owner();
  await assertSucceeds(setDoc(row(db), reservation()));
  await assertFails(deleteDoc(row(db)));
  await assertFails(getDocs(collection(db,
      "deda_recovery_journals", uid, "steps")));
  const alternate = doc(db, "deda_recovery_journals", uid,
      "steps", "another_step");
  await assertFails(setDoc(alternate, reservation()));
  await assertFails(setDoc(doc(db,
      "deda_recovery_journals", uid, "steps", intent + "_linkedPinReissue"),
      reservation({code: "linkedPinReissue",
        operationKey: `deda_guardian_v1/${uid}/${intent}/linkedPinReissue`})));
});

test("server-only attestation cannot be read or written by client", async () => {
  await seed();
  const db = owner();
  const p = doc(db, attestationPath);
  await assertFails(getDoc(p));
  await assertFails(setDoc(p, {
    receiptId: "forgedReceipt2026", serverVerified: true,
  }));
});

test("new phone session rule still rejects untrusted password-linked UID without original PIN proof", async () => {
  await seed({session: false});
  // CURRENT rules still require existing deda_auth_attempts(uid) or a
  // trusted installation. The journal does NOT bypass these requirements.
  const db = owner();
  await assertFails(setDoc(doc(db, "deda_sessions", uid), {
    uid, accountKey: account, installId: "new-device-not-trusted",
    signedInAt: serverTimestamp(), lastSeenAt: serverTimestamp(),
  }));
  await assertFails(setDoc(row(db), reservation()));
});

test("pre-link original anonymous UID is explicitly denied by candidate journal", async () => {
  await seed();
  const db = linkedContext(qaEnv, uid, email, "anonymous").firestore();
  await assertFails(setDoc(row(db), reservation({
    code: "beforeUidLinkCheckpoint",
    operationKey: `deda_guardian_v1/${uid}/${intent}/beforeUidLinkCheckpoint`,
  })));
});

test("parent administration proof does not grant journal ownership", async () => {
  await seed();
  const db = linkedContext(qaEnv, strangerUid,
      "admin@example.com", "password").firestore();
  await assertFails(getDoc(row(db)));
});
