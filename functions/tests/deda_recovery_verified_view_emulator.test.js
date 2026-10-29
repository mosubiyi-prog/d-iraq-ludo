"use strict";
/*
 * Local Firebase Auth + Firestore Emulator tests, synthetic identity only.
 * App Check context is mocked at core boundary; no live app attestation.
 * NO legacy wallet, diamond, prize, ID or frame writes.
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp: initAdmin, deleteApp: deleteAdmin} = require("firebase-admin/app");
const {getAuth: adminAuth} = require("firebase-admin/auth");
const {getFirestore: adminDb} = require("firebase-admin/firestore");
const {initializeApp: initClient, deleteApp: deleteClient} = require("firebase/app");
const {getAuth, connectAuthEmulator, signInAnonymously} = require("firebase/auth");
const {getFirestore, connectFirestoreEmulator, doc, getDoc, setDoc} =
  require("firebase/firestore");
const {readReviewedRecovery, signReview, RecoveryReviewRequired} =
  require("../deda_recovery_verified_view_core");
const PROJECT = "demo-deda-recovery-reviewed-view-private";
if (process.env.GCLOUD_PROJECT !== PROJECT ||
    process.env.DEDA_REVIEWED_RECOVERY_EMULATOR_ONLY !== "true" ||
    !process.env.FIREBASE_AUTH_EMULATOR_HOST ||
    !process.env.FIRESTORE_EMULATOR_HOST) {
  throw Error("DEDA_REVIEWED_RECOVERY_REFUSE_NON_LOCAL");
}
const KEY = "07704440011", PIN = "123498";
const SECRET = "DISPOSABLE_VIEW_REVIEW_SECRET_DO_NOT_USE_FOR_REAL_USERS";
const BASELINE = "a".repeat(64);
const admin = initAdmin({projectId: PROJECT}, "reviewed-recovery-admin");
const db = adminDb(admin), auth = adminAuth(admin);
const clients = [];
async function phone() {
  const app = initClient({
    apiKey: "private-deda-local-only",
    appId: "1:444:android:qa",
    projectId: PROJECT,
  }, "reviewed-recovery-phone-" + clients.length);
  const userAuth = getAuth(app);
  connectAuthEmulator(userAuth, "http://127.0.0.1:9099", {disableWarnings: true});
  const clientDb = getFirestore(app);
  connectFirestoreEmulator(clientDb, "127.0.0.1", 8080);
  const signed = await signInAnonymously(userAuth);
  const client = {app, db: clientDb, uid: signed.user.uid};
  clients.push(client);
  return client;
}
function request(client, data = {accountKey: KEY}) {
  return {
    auth: {uid: client.uid,
      token: {firebase: {sign_in_provider: "anonymous"}}},
    app: {appId: "synthetic-app-check-not-production"},
    data,
  };
}
async function view(client, data = {accountKey: KEY}) {
  return readReviewedRecovery({
    request: request(client, data), auth, db, secret: SECRET,
  });
}
let owner, other, stranger;
test.before(async () => {
  owner = await phone();
  other = await phone();
  stranger = await phone();
  const reviewedAtMs = Date.now() - 1000;
  const review = {
    accountKey: KEY, issuer: "deda-reviewed-recovery-v1",
    status: "SERVER_RECONCILED_REVIEW_ONLY",
    legacyWriterFenced: true, paymentProviderReviewed: true,
    idAndFramesReviewed: true,
    reviewId: "review_20261030", migrationId: "migration_20261030",
    progressVersion: 4, progressBaseline: BASELINE,
    legacyWriterFenceId: "fence_20261030", settlementId: "settlement_20261030",
    points: 155, xp: 375, coins: 20, earnedDiamonds: 40,
    diamondGiftBalance: 10, premiumId: "@DEDA-LOCAL999",
    frameIds: ["frame_one", "frame_two"], reviewedAtMs,
  };
  review.signature = signReview(SECRET, KEY, review);
  const batch = db.batch();
  batch.set(db.doc("deda_account_directory/" + KEY), {
    accountKey: KEY, active: true, createdUid: owner.uid,
  });
  batch.set(db.doc("deda_secure_account_bindings/" + other.uid), {
    accountKey: KEY, uid: other.uid, status: "PIN_VERIFIED_HOLD",
    createdAtMs: Date.now() - 4000, lastVerifiedAtMs: Date.now() - 1000,
    canMigrate: false, canRestoreAssets: false,
  });
  batch.set(db.doc("deda_progress_migrations/" + KEY), {
    accountKey: KEY, format: 1, phase: "cutover-complete",
    migrationId: review.migrationId, settlementId: review.settlementId,
  });
  batch.set(db.doc("deda_verified_progress/" + KEY), {
    accountKey: KEY, format: 1, version: 4, initializedBy: BASELINE,
    balances: {points: 155, xp: 375, coins: 20, earnedDiamonds: 40},
  });
  batch.set(db.doc("deda_recovery_authoritative_reviews/" + KEY), review);
  batch.set(db.doc("users/" + owner.uid), {accountKey: KEY, diamonds: 225});
  batch.set(db.doc("users/" + owner.uid + "/wallet/original"), {
    diamonds: 225, frames: ["original_unchanged"],
  });
  await batch.commit();
});
test.after(async () => {
  for(const c of clients) await deleteClient(c.app);
  await deleteAdmin(admin);
});
test("1: second Firebase anonymous UID reads server-reconciled progress", async () => {
  const result = await view(other);
  assert.equal(result.status, "REVIEWED_SERVER_SNAPSHOT_READ_ONLY");
  assert.equal(result.points, 155);
  assert.equal(result.xp, 375);
  assert.equal(result.earnedDiamonds, 40);
  assert.equal(result.walletWritePerformed, false);
  assert.equal(result.fullRecoveryComplete, false);
});
test("2: repeated view leaves original wallet and target wallet untouched", async () => {
  const results = await Promise.all([view(other), view(other)]);
  assert.deepEqual(results[0], results[1]);
  const originalWallet = (await db.doc("users/" + owner.uid + "/wallet/original").get()).data();
  assert.deepEqual(originalWallet, {
    diamonds: 225, frames: ["original_unchanged"],
  });
  assert.equal((await db.doc("users/" + other.uid + "/wallet/original").get()).exists, false);
});
test("3: unrelated UID cannot access a valid canonical recovery review", async () => {
  await assert.rejects(view(stranger),
    err => err instanceof RecoveryReviewRequired);
});
test("4: malicious client cannot read, forge or modify server review via original rules", async () => {
  const record = doc(other.db, "deda_recovery_authoritative_reviews/" + KEY);
  await assert.rejects(getDoc(record), err => err.code === "permission-denied");
  await assert.rejects(setDoc(record, {
    points: 999999, premiumId: "@DEDA-IMPERSONATED",
  }), err => err.code === "permission-denied");
});
test("5: drift in verified progress blocks a second-device recovery view", async () => {
  const target = db.doc("deda_verified_progress/" + KEY);
  await target.set({
    format: 1, accountKey: KEY, version: 5,
    initializedBy: BASELINE,
    balances: {points: 9999, xp: 375, coins: 20, earnedDiamonds: 40},
  });
  await assert.rejects(view(other), err => err instanceof RecoveryReviewRequired);
});
