"use strict";
/* Real local anonymous Auth + unchanged original Firestore Rules + Admin
 * Firestore transactions. Test fixture App Check context is synthetic;
 * this is NOT signed production App Check or live account migration.
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp: initAdmin, deleteApp: deleteAdmin} =
  require("firebase-admin/app");
const {getFirestore: getDb} = require("firebase-admin/firestore");
const {getAuth: getAdminAuth} = require("firebase-admin/auth");
const {initializeApp: initClient, deleteApp: deleteClient} =
  require("firebase/app");
const {getAuth, connectAuthEmulator, signInAnonymously} =
  require("firebase/auth");
const {getFirestore, connectFirestoreEmulator, doc, getDoc, setDoc} =
  require("firebase/firestore");
const {securePinPreflight} = require("../deda_secure_pin_gate_core");
const {captureLegacyAccountEscrow, RecoveryEscrowHold, hmac} =
  require("../deda_recovery_asset_escrow_core");

const PROJECT = "demo-deda-asset-escrow-private-qa";
if (process.env.GCLOUD_PROJECT !== PROJECT ||
    process.env.DEDA_ASSET_ESCROW_EMULATOR_ONLY !== "true" ||
    !process.env.FIREBASE_AUTH_EMULATOR_HOST ||
    !process.env.FIRESTORE_EMULATOR_HOST) {
  throw Error("REFUSE_REAL_DATA_OR_NON_EMULATOR_RUN");
}
const KEY = "07704445555";
const PIN = "714826";
const SECRET = "qa-never-production-escrow-hmac-secret-20261030";
const STEP1_SECRET = "qa-never-production-pin-hmac-secret-20261030";
const PUBLIC_ID = "@DEDA-LOCAL777";
const app = initAdmin({projectId: PROJECT}, "asset-escrow-test-admin");
const db = getDb(app);
const adminAuth = getAdminAuth(app);
const phones = [];
async function anonymousPhone() {
  const client = initClient({
    apiKey: "local-test-key", projectId: PROJECT,
    appId: "1:123456:android:qa",
  }, "escrow-phone-" + phones.length);
  const auth = getAuth(client);
  connectAuthEmulator(auth, "http://127.0.0.1:9099", {
    disableWarnings: true,
  });
  const store = getFirestore(client);
  connectFirestoreEmulator(store, "127.0.0.1", 8080);
  const credentials = await signInAnonymously(auth);
  const item = {client, uid: credentials.user.uid, store};
  phones.push(item);
  return item;
}
function req(phone, data = {accountKey: KEY}) {
  return {
    auth: {uid: phone.uid,
      token: {firebase: {sign_in_provider: "anonymous"}}},
    app: {appId: "local-app-check-fixture-not-real"},
    data,
  };
}
async function verifiedPin(phone, pin = PIN) {
  return securePinPreflight({
    request: req(phone, {accountKey: KEY, pin}),
    db, auth: adminAuth, secret: STEP1_SECRET,
  });
}
async function escrow(phone, data = {accountKey: KEY}) {
  return captureLegacyAccountEscrow({
    request: req(phone, data), db, auth: adminAuth, secret: SECRET,
  });
}
function escrowPath(uid) {
  return "deda_secure_legacy_recovery_escrow/" +
    hmac(SECRET, "recovery-escrow-v1", KEY + ":" + uid);
}
let original, second, stranger;
test.before(async () => {
  original = await anonymousPhone();
  second = await anonymousPhone();
  stranger = await anonymousPhone();
  const batch = db.batch();
  batch.set(db.doc("deda_credentials/" + KEY), {
    accountKey: KEY, pin: PIN, active: true, createdUid: original.uid,
  });
  batch.set(db.doc("deda_account_directory/" + KEY), {
    accountKey: KEY, active: true, createdUid: original.uid,
  });
  batch.set(db.doc("deda_account_profiles/" + KEY), {
    accountKey: KEY, name: "First Device", phone: KEY,
    accountType: "user", trustedInstallIds: ["copyable-install"],
  });
  batch.set(db.doc("users/" + original.uid), {
    accountKey: KEY, name: "First Device", sharePersonalId: PUBLIC_ID,
    diamonds: 190, premiumId: "@DEDA-LIMITED", xp: 250,
    purchasedFrames: ["blue"], trustedInstallIds: ["copyable-install"],
  });
  batch.set(db.doc("users/" + original.uid + "/wallet/original"), {
    diamonds: 190, coins: 110, frames: ["blue"],
  });
  batch.set(db.doc("users/" + second.uid), {
    accountKey: KEY, name: "First Device",
  });
  batch.set(db.doc("deda_share_ids/" + PUBLIC_ID), {
    publicId: PUBLIC_ID, ownerUid: original.uid,
    active: true, kind: "personal",
  });
  batch.set(db.doc("deda_diamond_gift_balances/" + PUBLIC_ID), {
    balance: 45, lastClaimGiftId: "giftTest",
  });
  await batch.commit();
});
test.after(async () => {
  for (const p of phones) await deleteClient(p.client);
  await deleteAdmin(app);
});
test("1: anonymous second phone without server PIN binding cannot escrow data", async () => {
  await assert.rejects(escrow(second), e => e instanceof RecoveryEscrowHold);
  assert.equal((await db.doc(escrowPath(second.uid)).get()).exists, false);
});
test("2: server PIN verifies new anonymous UID before escrow", async () => {
  const result = await verifiedPin(second);
  assert.equal(result.status, "PIN_VERIFIED_HOLD");
});
test("3: real Firestore transaction captures exact legacy candidate once", async () => {
  const result = await escrow(second);
  assert.equal(result.status, "LEGACY_SNAPSHOT_ESCROWED_NO_TRANSFER");
  assert.equal(result.diamondsCredited, false);
  const copy = (await db.doc(escrowPath(second.uid)).get()).data();
  assert.equal(copy.untrustedSnapshot.originalWalletCandidate.diamonds, 190);
  assert.equal(copy.untrustedSnapshot.originalUserCandidate.premiumId,
    "@DEDA-LIMITED");
  assert.equal(copy.canMigrate, false);
});
test("4: repeat escrow never duplicates assets, returns same private doc", async () => {
  const result = await escrow(second);
  assert.equal(result.replay, true);
  const escrowDocs = await db.collection("deda_secure_legacy_recovery_escrow").get();
  assert.equal(escrowDocs.size, 1);
});
test("5: copied install and UID injection without proof never creates escrow", async () => {
  await assert.rejects(escrow(stranger, {
    accountKey: KEY, installId: "copyable-install",
  }), e => e instanceof RecoveryEscrowHold);
  await assert.rejects(escrow(stranger, {
    accountKey: KEY, uid: original.uid,
  }), e => e instanceof RecoveryEscrowHold);
  assert.equal((await db.doc(escrowPath(stranger.uid)).get()).exists, false);
});
test("6: original wallet and target wallet untouched by authenticated escrow", async () => {
  assert.deepEqual(
    (await db.doc("users/" + original.uid + "/wallet/original").get()).data(),
    {diamonds: 190, coins: 110, frames: ["blue"]},
  );
  assert.equal((await db.doc("users/" + second.uid + "/wallet/original").get())
    .exists, false);
});
test("7: original unchanged Firestore Rules forbid mobile reading/writing escrow", async () => {
  const path = escrowPath(second.uid);
  await assert.rejects(getDoc(doc(second.store, path)),
    err => err.code === "permission-denied");
  await assert.rejects(setDoc(doc(second.store, path), {
    status: "CAN_TRANSFER", canMigrate: true,
  }), err => err.code === "permission-denied");
});
