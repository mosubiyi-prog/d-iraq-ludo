"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {initializeTestEnvironment, assertSucceeds, assertFails}
  = require("@firebase/rules-unit-testing");
const {doc, setDoc, getDoc, updateDoc, serverTimestamp, Timestamp}
  = require("firebase/firestore");

// Firestore Emulator ONLY. No Auth/Firestore cloud connection or real phones.
// The server-issued grant is SEEDED using the test-only admin bypass because
// its authenticating, rate-limited server issuer is not implemented/deployed.
const uid = "original-owner-100436-linked-uid";
const otherUid = "attacker-or-admin-uid";
const account = "9647712345678";
const otherAccount = "9647700000011";
const originalId = "@DEDA-ABC123";
const install = "a".repeat(48);
const otherInstall = "b".repeat(48);
const email = account + "@deda-login.invalid";
const grantPath = "deda_recovery_session_bootstrap_grants/" + uid +
    "/installs/" + install;
const sessionPath = "deda_sessions/" + uid;
const journalPath = "deda_recovery_journals/" + uid +
    "/steps/owner_second_phone_20261104_0001_originalBackupReadback";
const operationKey = "deda_guardian_v1/" + uid +
    "/owner_second_phone_20261104_0001/originalBackupReadback";
let base, qa;
const linked = (env = qa, id = uid, mail = email, provider = "password") =>
  env.authenticatedContext(id, {
    email: mail, firebase: {sign_in_provider: provider},
  }).firestore();
const ref = (db, path) => doc(db, path);
const data = (installId = install, accountKey = account) => ({
  uid, accountKey, installId, signedInAt: serverTimestamp(),
  lastSeenAt: serverTimestamp(),
});
const createJournal = (db) => setDoc(ref(db, journalPath), {
  ownerUid: uid, accountKey: account, originalId,
  intentId: "owner_second_phone_20261104_0001",
  code: "originalBackupReadback", operationKey, state: "reserved",
  createdAt: serverTimestamp(),
});
async function seed({
  grant = true, priorSession = false, admin = false, credentials = true,
  directory = true, user = true, route = true,
  grantPatch = {}, accountKey = account,
} = {}) {
  await qa.clearFirestore();
  await qa.withSecurityRulesDisabled(async ctx => {
    const db = ctx.firestore();
    if (directory) await setDoc(ref(db, "deda_account_directory/" + account), {
      accountKey: account, active: true, createdUid: uid,
    });
    if (credentials) await setDoc(ref(db, "deda_credentials/" + account), {
      accountKey: account, active: true, pin: "123456",
      createdUid: uid,
    });
    if (user) await setDoc(ref(db, "users/" + uid), {
      accountKey: account, sharePersonalId: originalId,
    });
    if (route) await setDoc(ref(db, "deda_share_ids/" + originalId), {
      publicId: originalId, active: true, ownerUid: uid, kind: "personal",
    });
    if (priorSession) await setDoc(ref(db, sessionPath), {
      uid, accountKey, installId: otherInstall,
      signedInAt: Timestamp.now(), lastSeenAt: Timestamp.now(),
    });
    if (admin) await setDoc(ref(db, "admins/" + uid), {
      active: true, role: "general_manager", status: "active",
    });
    if (grant) {
      const now = Date.now();
      await setDoc(ref(db, grantPath), {
        ownerUid: uid, accountKey: account, originalId, installId: install,
        purpose: "linked_uid_new_device_session_v1",
        state: "approved",
        issuedAt: Timestamp.fromMillis(now - 30_000),
        expiresAt: Timestamp.fromMillis(now + 120_000),
        ...grantPatch,
      });
    }
  });
}

test.before(async () => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST || "", /^127\.0\.0\.1:/);
  const baseline = fs.readFileSync("firestore.rules", "utf8");
  const candidate = fs.readFileSync(
      process.env.DEDA_JOURNAL_EMULATOR_RULES, "utf8");
  assert.doesNotMatch(baseline, /dedaLinkedOriginalOwnerSessionBootstrap/);
  assert.match(candidate, /dedaLinkedOriginalOwnerSessionBootstrap/);
  base = await initializeTestEnvironment({
    projectId: "demo-deda-100436-bootstrap-original", 
    firestore: {rules: baseline},
  });
  qa = await initializeTestEnvironment({
    projectId: "demo-deda-100436-bootstrap-pilot",
    firestore: {rules: candidate},
  });
});
test.after(async () => {
  if (base) await base.cleanup();
  if (qa) await qa.cleanup();
});

test("new phone without server grant is rejected even with correct UID/email", async () => {
  await seed({grant: false});
  await assertFails(setDoc(ref(linked(), sessionPath), data()));
  await assertFails(createJournal(linked()));
});
test("new phone after server-issued grant creates SAME UID session and can reserve journal", async () => {
  await seed();
  const db = linked();
  await assertSucceeds(setDoc(ref(db, sessionPath), data()));
  const session = await assertSucceeds(getDoc(ref(db, sessionPath)));
  assert.equal(session.data().uid, uid);
  assert.equal(session.data().accountKey, account);
  assert.equal(session.data().installId, install);
  await assertSucceeds(createJournal(db));
  const journal = await assertSucceeds(getDoc(ref(db, journalPath)));
  assert.equal(journal.data().state, "reserved");
});
test("old trusted source session can update to replacement install only on same account", async () => {
  await seed({priorSession: true});
  const db = linked();
  await assertSucceeds(setDoc(ref(db, sessionPath), data()));
  assert.equal((await getDoc(ref(db, sessionPath))).data().installId, install);
  await assertFails(setDoc(ref(db, sessionPath), data(install, otherAccount)));
});
test("original unmodified 100436 rules reject same new-phone proof", async () => {
  // The unmodified rules contain no session grant authorization.
  const db = linked(base);
  await assertFails(setDoc(ref(db, sessionPath), data()));
});
test("forged uid, phone, provider and staff account never borrow original session", async () => {
  await seed();
  await assertFails(setDoc(ref(linked(qa, otherUid), sessionPath), data()));
  await assertFails(setDoc(ref(linked(qa, uid, "other@example.com"), sessionPath), data()));
  await assertFails(setDoc(ref(linked(qa, uid, email, "anonymous"), sessionPath), data()));
  await assertFails(setDoc(ref(linked(qa, uid, "admin@example.com"), sessionPath), data()));
  await assertFails(setDoc(ref(linked(), sessionPath), {...data(), uid: otherUid}));
});
test("manager role on same Auth principal remains explicitly separated", async () => {
  await seed({admin: true});
  await assertFails(setDoc(ref(linked(), sessionPath), data()));
});
test("a different installID or malformed installId cannot use original's grant", async () => {
  await seed();
  await assertFails(setDoc(ref(linked(), sessionPath), data(otherInstall)));
  await assertFails(setDoc(ref(linked(), sessionPath), data("bad-device")));
});
test("expired, not-yet-issued or longer-than-five-minute grants fail", async () => {
  const now = Date.now();
  for (const patch of [
    {expiresAt: Timestamp.fromMillis(now - 1000)},
    {issuedAt: Timestamp.fromMillis(now + 50_000)},
    {issuedAt: Timestamp.fromMillis(now - 30_000),
      expiresAt: Timestamp.fromMillis(now + 600_000)},
    {state: "pending"},
    {purpose: "grant-admin-role"},
  ]) {
    await seed({grantPatch: patch});
    await assertFails(setDoc(ref(linked(), sessionPath), data()));
  }
});
test("missing directory, original credentials, user or original-ID route fail", async () => {
  for (const patch of [
    {directory: false}, {credentials: false},
    {user: false}, {route: false},
  ]) {
    await seed(patch);
    await assertFails(setDoc(ref(linked(), sessionPath), data()));
  }
});
test("server grant cannot be forged, read, listed, updated or deleted by client", async () => {
  await seed();
  const db = linked();
  const g = ref(db, grantPath);
  await assertFails(getDoc(g));
  await assertFails(setDoc(g, {state: "approved"}));
  await assertFails(updateDoc(g, {state: "approved"}));
});
test("pre-existing old anonymous PIN attempt remains valid, no legacy regression", async () => {
  await qa.clearFirestore();
  const previousUid = "legacy-phone-anonymous-uid";
  await qa.withSecurityRulesDisabled(async ctx => {
    const db = ctx.firestore();
    await setDoc(ref(db, "deda_credentials/" + account), {
      accountKey: account, active: true, pin: "123456", createdUid: uid,
    });
    await setDoc(ref(db, "deda_auth_attempts/" + previousUid), {
      accountKey: account, pin: "123456", uid: previousUid,
    });
  });
  const db = linked(qa, previousUid, "", "anonymous");
  await assertSucceeds(setDoc(ref(db, "deda_sessions/" + previousUid), {
    uid: previousUid, accountKey: account, installId: otherInstall,
    signedInAt: serverTimestamp(), lastSeenAt: serverTimestamp(),
  }));
  assert.equal((await getDoc(ref(db, "deda_sessions/" + previousUid))).data().uid,
      previousUid);
});
