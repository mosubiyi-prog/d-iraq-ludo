"use strict";
/* Synthetic local Auth + real original Firestore Rules + real Admin SDK transactions.
 * Direct core invocation uses a FAKE App Check context by construction.
 * This does NOT certify production signed App Check or deployed cutover.
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp: initAdmin, deleteApp: deleteAdmin} =
  require("firebase-admin/app");
const {getAuth: adminAuth} = require("firebase-admin/auth");
const {getFirestore: adminDb} = require("firebase-admin/firestore");
const {initializeApp: initClient, deleteApp: deleteClient} =
  require("firebase/app");
const {getAuth, connectAuthEmulator, signInAnonymously} =
  require("firebase/auth");
const {getFirestore, connectFirestoreEmulator, doc, getDoc, setDoc} =
  require("firebase/firestore");
const {securePinPreflight} = require("../deda_secure_pin_gate_core");
const {recoverSafeProfile, RecoveryHold} =
  require("../deda_safe_profile_restore_core");

const PROJECT = "demo-deda-recovery-step2-private";
if (process.env.GCLOUD_PROJECT !== PROJECT ||
    process.env.DEDA_STEP2_EMULATOR_ONLY !== "true" ||
    !process.env.FIREBASE_AUTH_EMULATOR_HOST ||
    !process.env.FIRESTORE_EMULATOR_HOST) {
  throw Error("DEDA_STEP2_REFUSE_PRODUCTION");
}
const KEY = "07708887777";
const PIN = "782645";
const SECRET = "local-only-hmac-key-do-not-use-outside-emulator-20261030";
const now = () => Date.now();
const admin = initAdmin({projectId: PROJECT}, "step2-admin");
const db = adminDb(admin), auth = adminAuth(admin);
const clients = [];
async function phone() {
  const app = initClient({
    apiKey: "local-step2-api-key", appId: "1:12345:android:local",
    projectId: PROJECT,
  }, "step2-local-" + clients.length);
  const userAuth = getAuth(app);
  connectAuthEmulator(userAuth, "http://127.0.0.1:9099", {disableWarnings: true});
  const fs = getFirestore(app);
  connectFirestoreEmulator(fs, "127.0.0.1", 8080);
  const result = await signInAnonymously(userAuth);
  const client = {app, fs, uid: result.user.uid};
  clients.push(client);
  return client;
}
function request(client, data = {accountKey: KEY}) {
  return {
    auth: {uid: client.uid,
      token: {firebase: {sign_in_provider: "anonymous"}}},
    app: {appId: "1:12345:android:local-test-mock"},
    data,
  };
}
async function bind(client, pin = PIN) {
  return securePinPreflight({
    request: request(client, {accountKey: KEY, pin}), db, auth, secret: SECRET,
  });
}
async function restore(client, data = {accountKey: KEY}) {
  return recoverSafeProfile({request: request(client, data), db, auth});
}
let original, second, attacker;
test.before(async () => {
  original = await phone();
  second = await phone();
  attacker = await phone();
  const batch = db.batch();
  batch.set(db.doc("deda_credentials/" + KEY), {
    accountKey: KEY, pin: PIN, active: true, createdUid: original.uid,
  });
  batch.set(db.doc("deda_account_directory/" + KEY), {
    accountKey: KEY, active: true, createdUid: original.uid,
  });
  batch.set(db.doc("deda_account_profiles/" + KEY), {
    accountKey: KEY, name: "Original Test", phone: KEY, accountType: "user",
    trustedInstallIds: ["copyable-string"],
  });
  batch.set(db.doc("users/" + original.uid), {
    accountKey: KEY, name: "Original Test", phone: KEY,
    xp: 765, diamonds: 433, premiumId: "@DEDA-TEST-001",
  });
  batch.set(db.doc("users/" + original.uid + "/wallet/original"), {
    diamonds: 433, frames: ["owned-paid-frame"], coins: 120,
  });
  await batch.commit();
});
test.after(async () => {
  for (const c of clients) await deleteClient(c.app);
  await deleteAdmin(admin);
});
test("1: no PIN-binding = no cross-device profile restore", async () => {
  await assert.rejects(restore(second), e => e instanceof RecoveryHold);
  assert.equal((await db.doc("users/" + second.uid).get()).exists, false);
});
test("2: actual emulator Auth UID + Step1 PIN verification creates server binding", async () => {
  const res = await bind(second);
  assert.equal(res.status, "PIN_VERIFIED_HOLD");
  assert.equal((await db.doc("deda_secure_account_bindings/" + second.uid).get())
    .data().accountKey, KEY);
});
test("3: Step2 uses live Firestore transaction to copy only safe profile", async () => {
  const res = await restore(second);
  assert.equal(res.status, "PROFILE_RESTORED");
  assert.equal(res.fullAccountRecoveryComplete, false);
  const newDoc = (await db.doc("users/" + second.uid).get()).data();
  assert.equal(newDoc.name, "Original Test");
  assert.equal(newDoc.phone, KEY);
  for (const key of ["diamonds", "xp", "premiumId",
    "trustedInstallIds", "coins", "frames"]) assert.equal(key in newDoc, false);
  const originalDoc = (await db.doc("users/" + original.uid).get()).data();
  assert.equal(originalDoc.xp, 765);
  assert.equal(originalDoc.diamonds, 433);
});
test("4: concurrent recovery returns one immutable receipt with no wallet copy", async () => {
  const out = await Promise.all([restore(second), restore(second)]);
  assert.equal(out.every(x => x.status === "PROFILE_ALREADY_RESTORED"), true);
  const receipt = (await db.doc("deda_secure_profile_restore_receipts/" +
    second.uid).get()).data();
  assert.equal(receipt.canCopyAssets, false);
  assert.equal((await db.doc("users/" + second.uid + "/wallet/original").get())
    .exists, false);
});
test("5: copied installId or forged source UID rejected even with signed-in client", async () => {
  await assert.rejects(restore(attacker, {
    accountKey: KEY, installId: "copyable-string",
  }), e => e instanceof RecoveryHold);
  await assert.rejects(restore(attacker, {
    accountKey: KEY, uid: original.uid,
  }), e => e instanceof RecoveryHold);
  assert.equal((await db.doc("users/" + attacker.uid).get()).exists, false);
});
test("6: old published full Firestore Rules forbid mobile access to private receipts", async () => {
  for (const path of [
    "deda_secure_profile_restore_receipts/" + second.uid,
    "deda_secure_account_bindings/" + second.uid,
  ]) {
    await assert.rejects(getDoc(doc(second.fs, path)),
      e => e.code === "permission-denied");
    await assert.rejects(setDoc(doc(second.fs, path), {
      canCopyAssets: true, status: "FAKE",
    }), e => e.code === "permission-denied");
  }
});
test("7: original finances remain unchanged after cross-device profile restore", async () => {
  const sourceWallet = (await db.doc("users/" + original.uid +
    "/wallet/original").get()).data();
  assert.deepEqual(sourceWallet, {
    diamonds: 433, frames: ["owned-paid-frame"], coins: 120,
  });
  const targetWallet = await db.doc("users/" + second.uid +
    "/wallet/original").get();
  assert.equal(targetWallet.exists, false);
});
