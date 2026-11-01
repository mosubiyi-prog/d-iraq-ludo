"use strict";
/* Real local Auth/Firestore emulator integration for the new server PIN core.
 * App Check JWT / callable transport is NOT tested here. No live user data.
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp: initAdmin, deleteApp: deleteAdmin} = require("firebase-admin/app");
const {getAuth: adminAuth} = require("firebase-admin/auth");
const {getFirestore: adminFirestore} = require("firebase-admin/firestore");
const {initializeApp: initClient, deleteApp: deleteClient} = require("firebase/app");
const {getAuth, connectAuthEmulator, signInAnonymously} = require("firebase/auth");
const {getFirestore, connectFirestoreEmulator, doc, getDoc, setDoc} =
  require("firebase/firestore");
const {securePinPreflight, PinDenied} = require("../deda_secure_pin_gate_core");

const PROJECT = "demo-deda-secure-pin-private-qa";
if (process.env.GCLOUD_PROJECT !== PROJECT ||
    process.env.DEDA_SECURE_PIN_EMULATOR_ONLY !== "true" ||
    !process.env.FIREBASE_AUTH_EMULATOR_HOST ||
    !process.env.FIRESTORE_EMULATOR_HOST) {
  throw Error("REFUSE_NON_LOCAL_EMULATOR_PIN_TEST");
}
const KEY = "disposable-qa-rate-secret-NEVER-real-production-key-20261030";
const KEY1 = "07705551111";
const KEY2 = "07705552222";
const PIN1 = "684295";
const PIN2 = "837142";
const adminApp = initAdmin({projectId: PROJECT}, "secure-pin-test-admin");
const db = adminFirestore(adminApp);
const auth = adminAuth(adminApp);
const clients = [];

async function phone() {
  const app = initClient({
    apiKey: "demo-deda-secure-pin-local-only",
    projectId: PROJECT,
    appId: "1:123456:android:private-emulator-qa",
  }, "secure-pin-phone-" + clients.length);
  const userAuth = getAuth(app);
  connectAuthEmulator(userAuth, "http://127.0.0.1:9099", {disableWarnings: true});
  const clientDb = getFirestore(app);
  connectFirestoreEmulator(clientDb, "127.0.0.1", 8080);
  const signed = await signInAnonymously(userAuth);
  const item = {app, userAuth, clientDb, uid: signed.user.uid};
  clients.push(item);
  return item;
}
async function seedAccount(key, pin, createdUid) {
  const batch = db.batch();
  batch.set(db.doc("deda_credentials/" + key),
    {accountKey: key, pin, active: true, createdUid});
  batch.set(db.doc("deda_account_directory/" + key),
    {accountKey: key, active: true, createdUid});
  batch.set(db.doc("deda_account_profiles/" + key),
    {accountKey: key, trustedInstallIds: ["copied-id-is-not-proof"]});
  await batch.commit();
}
function request(phoneClient, accountKey, pin, extras = {}) {
  return {
    auth: {uid: phoneClient.uid,
      token: {firebase: {sign_in_provider: "anonymous"}}},
    // Core-level fixture only; unlike the deployed callable, NOT real App Check.
    app: {appId: "1:123456:android:private-emulator-qa"},
    data: {accountKey, pin, ...extras},
  };
}
function call(phoneClient, key, pin, extras) {
  return securePinPreflight({
    db, auth, secret: KEY, request: request(phoneClient, key, pin, extras),
  });
}
function denied(value) {
  return assert.rejects(value, err => err instanceof PinDenied);
}
let a, b, attacker;
test.before(async () => {
  a = await phone(); b = await phone(); attacker = await phone();
  await seedAccount(KEY1, PIN1, a.uid);
  await seedAccount(KEY2, PIN2, b.uid);
  await db.doc("users/" + a.uid + "/wallet/original").set({diamonds: 420, xp: 65});
});
test.after(async () => {
  for (const c of clients) await deleteClient(c.app);
  await deleteAdmin(adminApp);
});
test("real emulator transaction creates hold-only server binding for original PIN", async () => {
  const result = await call(a, KEY1, PIN1);
  assert.equal(result.status, "PIN_VERIFIED_HOLD");
  const docRef = await db.doc("deda_secure_account_bindings/" + a.uid).get();
  assert.equal(docRef.exists, true);
  assert.equal(docRef.data().canRestoreAssets, false);
});
test("real second anonymous Auth UID may bind same account, no wallet migration", async () => {
  const result = await call(b, KEY1, PIN1);
  assert.equal(result.serverOwned, true);
  assert.equal((await db.doc("deda_secure_account_bindings/" + b.uid).get()).data().accountKey, KEY1);
  assert.equal((await db.doc("users/" + a.uid + "/wallet/original").get()).data().diamonds, 420);
  assert.equal((await db.doc("users/" + b.uid + "/wallet/original").get()).exists, false);
});
test("copied install ID and injected UID cannot bypass PIN on real Firestore", async () => {
  await denied(call(attacker, KEY1, "000000", {installId: "copied-id-is-not-proof"}));
  await denied(call(attacker, KEY1, PIN1, {uid: a.uid}));
  assert.equal((await db.doc("deda_secure_account_bindings/" + attacker.uid).get()).exists, false);
});
test("account-wide lock stops correct PIN from different UID after five failures", async () => {
  for (let i = 0; i < 5; i++) await denied(call(attacker, KEY2, "000000"));
  await denied(call(a, KEY2, PIN2));
  assert.equal((await db.doc("deda_secure_account_bindings/" + attacker.uid).get()).exists, false);
});
test("already-bound UID cannot silently switch to another canonical account", async () => {
  await denied(call(a, KEY2, PIN2));
  assert.equal((await db.doc("deda_secure_account_bindings/" + a.uid).get()).data().accountKey, KEY1);
});
test("simultaneous legitimate rechecks are idempotent on actual Firestore transactions", async () => {
  const outcomes = await Promise.all([call(b, KEY1, PIN1), call(b, KEY1, PIN1)]);
  assert.equal(outcomes.every(x => x.status === "PIN_VERIFIED_HOLD"), true);
  assert.equal((await db.collection("deda_secure_account_bindings").get()).size, 2);
});
test("original full Firestore Rules deny mobile reads/writes to both backend namespaces", async () => {
  for (const path of [
    "deda_secure_account_bindings/" + a.uid,
    "deda_secure_pin_account_limits/synthetic",
  ]) {
    await assert.rejects(getDoc(doc(a.clientDb, path)),
      err => err.code === "permission-denied");
    await assert.rejects(setDoc(doc(a.clientDb, path), {faked: true}),
      err => err.code === "permission-denied");
  }
});
