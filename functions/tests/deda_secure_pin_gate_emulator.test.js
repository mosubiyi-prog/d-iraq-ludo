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

const {canonicalOriginalHold, CanonicalDenied, originalLockDocumentId} =
  require("../deda_canonical_account_proof_core");
const {rateDocumentId} = require("../deda_secure_pin_gate_core");

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


const ORIGINAL = "@DEDA-AB3C5D";
const holdOriginal = (phoneClient, accountKey=KEY1, pin=PIN1, extras={}) =>
  canonicalOriginalHold({
    db, auth, secret:KEY, request:request(phoneClient,accountKey,pin,extras),
  });
async function seedOriginal() {
  await db.doc("users/"+a.uid).set({
    accountKey:KEY1,sharePersonalId:ORIGINAL,
  },{merge:true});
  await db.doc("deda_share_ids/"+ORIGINAL).set({
    publicId:ORIGINAL,kind:"personal",active:true,ownerUid:a.uid,
  });
}

test("canonical original is server-attested identically for two anonymous UIDs without wallet migration", async()=>{
  await seedOriginal();
  const x=await holdOriginal(a);
  const y=await holdOriginal(b);
  assert.equal(x.canonicalOriginalId,ORIGINAL);
  assert.equal(y.canonicalOriginalId,ORIGINAL);
  assert.equal(x.canRestoreAssets,false);
  assert.equal(y.canMigrate,false);
  const mapping=await db.doc("deda_secure_canonical_accounts/"+rateDocumentId(KEY,KEY1)).get();
  assert.equal(mapping.data().sourceOwnerUid,a.uid);
  assert.equal(mapping.data().originalId,ORIGINAL);
  const locked=await db.doc("deda_secure_original_id_owners/"+
    originalLockDocumentId(KEY,ORIGINAL)).get();
  assert.equal(locked.exists,true);
  assert.equal(locked.data().accountHash,rateDocumentId(KEY,KEY1));
  assert.equal(locked.data().sourceOwnerUid,a.uid);
  assert.equal(locked.data().canMigrate,false);
  assert.equal((await db.doc("users/"+a.uid+"/wallet/original").get()).data().diamonds,420);
  assert.equal((await db.doc("users/"+b.uid+"/wallet/original").get()).exists,false);
});

test("canonical proof rejects absent or revoked original route, preserving mapping", async()=>{
  await db.doc("deda_share_ids/"+ORIGINAL).update({active:false});
  await assert.rejects(holdOriginal(b),e=>e instanceof CanonicalDenied);
  await db.doc("deda_share_ids/"+ORIGINAL).update({active:true});
  const mapping=await db.doc("deda_secure_canonical_accounts/"+rateDocumentId(KEY,KEY1)).get();
  assert.equal(mapping.data().originalId,ORIGINAL);
});

test("canonical proof rejects conflicting owner original and never rewrites mapping", async()=>{
  await db.doc("users/"+a.uid).update({sharePersonalId:"@DEDA-ZZ9999"});
  await assert.rejects(holdOriginal(a),e=>e instanceof CanonicalDenied);
  await db.doc("users/"+a.uid).update({sharePersonalId:ORIGINAL});
  assert.equal((await holdOriginal(a)).canonicalOriginalId,ORIGINAL);
});

test("canonical proof rejects copied UID, account-format alias and injected route", async()=>{
  await assert.rejects(holdOriginal(attacker,KEY1,PIN1,{ownerUid:a.uid}),
    e=>e.name==="PinDenied");
  // The PIN account key is exact: no silent 07 ↔ 9647 merge.
  await assert.rejects(holdOriginal(attacker,"9647705551111",PIN1),
    e=>e.name==="PinDenied");
  assert.equal((await db.doc("deda_secure_account_bindings/"+attacker.uid).get()).exists,false);
});

test("original account mapping cannot be changed or read by a mobile user", async()=>{
  const mapped="deda_secure_canonical_accounts/"+rateDocumentId(KEY,KEY1);
  await assert.rejects(getDoc(doc(b.clientDb,mapped)),
    e=>e.code==="permission-denied");
  await assert.rejects(setDoc(doc(b.clientDb,mapped),{
    originalId:"@DEDA-ZZ9999",sourceOwnerUid:b.uid,
  }),e=>e.code==="permission-denied");
});

test("tampered canonical mapping makes new device proof fail closed", async()=>{
  const ref=db.doc("deda_secure_canonical_accounts/"+rateDocumentId(KEY,KEY1));
  await ref.update({originalId:"@DEDA-ZZ9999"});
  await assert.rejects(holdOriginal(b),e=>e instanceof CanonicalDenied);
  await ref.update({originalId:ORIGINAL});
  assert.equal((await holdOriginal(b)).canonicalOriginalId,ORIGINAL);
});


test("one original ID cannot bind two different PIN accounts from the same creator UID", async()=>{
  // Legacy installation could create multiple numbers using one Firebase UID.
  // Source route ownership alone then passes; the server original-ID lock
  // MUST reject binding an already reserved public ID to another account.
  const otherKey="07905553333",otherPin="629415";
  const newcomer=await phone();
  await seedAccount(otherKey,otherPin,a.uid);
  await db.doc("users/"+a.uid).update({accountKey:otherKey});
  try {
    await assert.rejects(holdOriginal(newcomer,otherKey,otherPin),
      e=>e instanceof CanonicalDenied);
    assert.equal((await db.doc("deda_secure_canonical_accounts/"+
      rateDocumentId(KEY,otherKey)).get()).exists,false);
    const locked=(await db.doc("deda_secure_original_id_owners/"+
      originalLockDocumentId(KEY,ORIGINAL)).get()).data();
    assert.equal(locked.accountHash,rateDocumentId(KEY,KEY1));
    assert.equal(locked.sourceOwnerUid,a.uid);
  } finally {
    await db.doc("users/"+a.uid).update({accountKey:KEY1});
  }
  assert.equal((await holdOriginal(b)).canonicalOriginalId,ORIGINAL);
});

test("canonical mapping and original lock must both exist: no auto-repair", async()=>{
  const lockRef=db.doc("deda_secure_original_id_owners/"+
    originalLockDocumentId(KEY,ORIGINAL));
  const snap=await lockRef.get(),value=snap.data();
  await lockRef.delete();
  try {
    await assert.rejects(holdOriginal(b),e=>e instanceof CanonicalDenied);
    assert.equal((await db.doc("deda_secure_canonical_accounts/"+
      rateDocumentId(KEY,KEY1)).get()).data().originalId,ORIGINAL);
  } finally {await lockRef.set(value);}
  assert.equal((await holdOriginal(b)).canonicalOriginalId,ORIGINAL);
});

test("tampered original ID lock and changed owner account are rejected",async()=>{
  const lockRef=db.doc("deda_secure_original_id_owners/"+
    originalLockDocumentId(KEY,ORIGINAL));
  const snapshot=await lockRef.get(),original=snapshot.data();
  await lockRef.update({accountHash:rateDocumentId(KEY,"07700000000")});
  try {
    await assert.rejects(holdOriginal(a),e=>e instanceof CanonicalDenied);
  } finally {await lockRef.set(original);}
  assert.equal((await holdOriginal(a)).canonicalOriginalId,ORIGINAL);
});

test("no anonymous app may read, overwrite or invent original-ID lock",async()=>{
  const path="deda_secure_original_id_owners/"+
    originalLockDocumentId(KEY,ORIGINAL);
  await assert.rejects(getDoc(doc(attacker.clientDb,path)),
    e=>e.code==="permission-denied");
  await assert.rejects(setDoc(doc(attacker.clientDb,path),{
    accountHash:rateDocumentId(KEY,KEY2),originalId:ORIGINAL,
    sourceOwnerUid:attacker.uid,
  }),e=>e.code==="permission-denied");
});

test("account limiter namespace and original-ID lock use distinct HMAC domains",()=>{
  assert.notEqual(originalLockDocumentId(KEY,ORIGINAL),
    rateDocumentId(KEY,KEY1));
  assert.notEqual(originalLockDocumentId(KEY,ORIGINAL),
    originalLockDocumentId(KEY,"@DEDA-ZZ9999"));
});
