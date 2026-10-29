"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  readReviewedRecovery, RecoveryReviewRequired, signReview, FRESH_MS,
} = require("../../../functions/deda_recovery_verified_view_core");

const KEY = "07712345678";
const UID = "newPhone123456";
const OLD = "oldPhone987654";
const SECRET = "DISPOSABLE_QA_SERVER_RECOVERY_KEY_Never_Production_20261030";
const NOW = Date.now();
const BASELINE = "a".repeat(64);
class MemoryDb {
  constructor() {this.docs = new Map(); this.writes = [];}
  doc(path) {return {path};}
  seed(path, value) {this.docs.set(path, structuredClone(value));}
  read(path) {return this.docs.get(path);}
  async runTransaction(job, options) {
    if (!options || options.readOnly !== true) throw Error("WRITE_TRANSACTIONS_FORBIDDEN");
    return job({
      get: async ref => ({
        exists: this.docs.has(ref.path),
        data: () => structuredClone(this.docs.get(ref.path)),
      }),
      set: () => {throw Error("WRITE_REJECTED");},
      create: () => {throw Error("WRITE_REJECTED");},
    });
  }
}
function req(uid = UID, key = KEY) {
  return {auth: {uid, token: {firebase: {sign_in_provider: "anonymous"}}},
    app: {appId: "1:demo:android:private"},
    data: {accountKey: key}};
}
function fixture() {
  const db = new MemoryDb();
  const auth = {getUser: async uid => ({
    uid, disabled: false, email: null, providerData: [],
  })};
  db.seed("deda_secure_account_bindings/" + UID, {
    uid: UID, accountKey: KEY, status: "PIN_VERIFIED_HOLD",
    canRestoreAssets: false, canMigrate: false,
    createdAtMs: NOW - 90_000, lastVerifiedAtMs: NOW - 10_000,
  });
  db.seed("deda_account_directory/" + KEY, {
    accountKey: KEY, active: true, createdUid: OLD,
  });
  db.seed("deda_progress_migrations/" + KEY, {
    accountKey: KEY, format: 1, phase: "cutover-complete",
    migrationId: "migrationQa123", settlementId: "settlementQa123",
  });
  db.seed("deda_verified_progress/" + KEY, {
    accountKey: KEY, format: 1, version: 3,
    initializedBy: BASELINE,
    balances: {points: 320, coins: 45, xp: 600, earnedDiamonds: 52},
  });
  const review = {
    accountKey: KEY, issuer: "deda-reviewed-recovery-v1",
    status: "SERVER_RECONCILED_REVIEW_ONLY",
    legacyWriterFenced: true, paymentProviderReviewed: true,
    idAndFramesReviewed: true,
    reviewId: "reviewQa123",
    migrationId: "migrationQa123", progressVersion: 3,
    progressBaseline: BASELINE,
    legacyWriterFenceId: "legacyFenceQa123",
    settlementId: "settlementQa123",
    points: 320, coins: 45, xp: 600, earnedDiamonds: 52,
    diamondGiftBalance: 5, premiumId: "@DEDA-ABC123",
    frameIds: ["frame_gold", "frame_royal"],
    reviewedAtMs: NOW - 5000,
  };
  review.signature = signReview(SECRET, KEY, review);
  db.seed("deda_recovery_authoritative_reviews/" + KEY, review);
  return {db, auth};
}
function read(f, request = req(), secret = SECRET, nowMs = NOW) {
  return readReviewedRecovery({db: f.db, auth: f.auth, request, secret, nowMs});
}
const reject = promise => assert.rejects(promise, e =>
  e instanceof RecoveryReviewRequired);
test("1: server-reviewed progress and frame snapshot is read-only, no wallet mutation", async () => {
  const f = fixture();
  f.db.seed("users/" + OLD + "/wallet/original", {diamonds: 99});
  const result = await read(f);
  assert.equal(result.status, "REVIEWED_SERVER_SNAPSHOT_READ_ONLY");
  assert.equal(result.points, 320);
  assert.equal(result.xp, 600);
  assert.equal(result.coins, 45);
  assert.equal(result.earnedDiamonds, 52);
  assert.equal(result.separatelyReviewedGiftDiamonds, 5);
  assert.equal(result.premiumId, "@DEDA-ABC123");
  assert.deepEqual(result.frameIds, ["frame_gold", "frame_royal"]);
  assert.equal(result.walletWritePerformed, false);
  assert.equal(result.fullRecoveryComplete, false);
  assert.equal(f.db.read("users/" + OLD + "/wallet/original").diamonds, 99);
  assert.equal(f.db.writes.length, 0);
});
test("2: repeated reads never credit diamonds nor copy owned frames", async () => {
  const f = fixture();
  const first = await read(f);
  const second = await read(f);
  assert.deepEqual(first, second);
  assert.equal(f.db.read("users/" + UID), undefined);
  assert.equal(f.db.writes.length, 0);
});
test("3: no independent signed review fails closed rather than manufacturing zeros", async () => {
  const f = fixture();
  f.db.docs.delete("deda_recovery_authoritative_reviews/" + KEY);
  await reject(read(f));
  assert.equal(f.db.writes.length, 0);
});
test("4: forged unreviewed frame or diamond record is rejected", async () => {
  const f = fixture();
  const p = "deda_recovery_authoritative_reviews/" + KEY;
  const r = f.db.read(p);
  f.db.seed(p, {...r, frameIds: ["frame_royal", "frame_gold"]});
  await reject(read(f));
  f.db.seed(p, {...r, diamondGiftBalance: 1000000});
  await reject(read(f));
});
test("5: editing signed approval flags breaks signature even if values match", async () => {
  const f = fixture();
  const path = "deda_recovery_authoritative_reviews/" + KEY;
  const r = f.db.read(path);
  r.paymentProviderReviewed = false;
  await reject(read(f));
  r.paymentProviderReviewed = true;
  r.legacyWriterFenced = false;
  await reject(read(f));
});
test("6: account-shared review never authorizes unrelated anonymous UID", async () => {
  const f = fixture();
  await reject(read(f, req("attackerUid432")));
});
test("7: expired PIN binding cannot reveal recovered values", async () => {
  const f = fixture();
  await reject(read(f, req(), SECRET, NOW + FRESH_MS + 15000));
});
test("8: rerun fresh PIN permits reviewed display without creating new UID", async () => {
  const f = fixture();
  const bind = f.db.read("deda_secure_account_bindings/" + UID);
  bind.lastVerifiedAtMs = NOW + FRESH_MS + 20000;
  f.db.seed("deda_secure_account_bindings/" + UID, bind);
  const r = await read(f, req(), SECRET, NOW + FRESH_MS + 25000);
  assert.equal(r.points, 320);
  assert.equal(r.walletWritePerformed, false);
});
test("9: modified verified progress ledger is caught by review signature mismatch", async () => {
  const f = fixture();
  f.db.seed("deda_verified_progress/" + KEY, {
    accountKey: KEY, format: 1, version: 4, initializedBy: BASELINE,
    balances: {points: 9000, xp: 600, coins: 45, earnedDiamonds: 52},
  });
  await reject(read(f));
});
test("10: migration phase pending or settlement divergence is rejected", async () => {
  const f = fixture();
  const path = "deda_progress_migrations/" + KEY;
  const original = f.db.read(path);
  f.db.seed(path, {...original, phase: "pending"});
  await reject(read(f));
  f.db.seed(path, {...original, settlementId: "differentSettlement"});
  await reject(read(f));
});
test("11: malformed app attestation, injected balances or forged uid deny", async () => {
  const f = fixture();
  const noApp = req(); delete noApp.app;
  await reject(read(f, noApp));
  const injected = req(); injected.data.earnedDiamonds = 999;
  await reject(read(f, injected));
  const badProvider = req(); badProvider.auth.token.firebase.sign_in_provider = "password";
  await reject(read(f, badProvider));
});
test("12: tampered review account or signature never exposes progress", async () => {
  const f = fixture();
  const path = "deda_recovery_authoritative_reviews/" + KEY;
  const r = f.db.read(path);
  f.db.seed(path, {...r, accountKey: "07799999999"});
  await reject(read(f));
  f.db.seed(path, {...r, signature: "b".repeat(64)});
  await reject(read(f));
});
test("13: wrong or absent HMAC secret fails closed before returning account", async () => {
  const f = fixture();
  await assert.rejects(read(f, req(), "bad"), /VERIFIED_RECOVERY_SECRET_MISSING/);
});
test("14: previously unverified account wallet cannot masquerade as ledger", async () => {
  const f = fixture();
  f.db.docs.delete("deda_verified_progress/" + KEY);
  f.db.seed("users/" + OLD + "/wallet/original", {diamonds: 999999});
  await reject(read(f));
});
test("15: database failure cannot be represented as successful restoration", async () => {
  const f = fixture();
  f.db.runTransaction = async () => {throw Error("internal");};
  await assert.rejects(read(f), /RECOVERY_REVIEWED_SNAPSHOT_UNAVAILABLE/);
});
