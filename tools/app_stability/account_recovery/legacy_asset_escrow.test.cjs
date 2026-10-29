"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  captureLegacyAccountEscrow, RecoveryEscrowHold, hmac,
  FRESH_MS, MAX_ESCROW_BYTES,
} = require("../../../functions/deda_recovery_asset_escrow_core");

const KEY = "07712345678";
const OLD = "originalPhoneUid123";
const NEW = "secondPhoneUid456";
const NOW = 40_000_000;
const SECRET = "LOCAL_TEST_HMAC_SECRET_32_BYTES_20261030_DO_NOT_DEPLOY";
const ID = "@DEDA-OLDUSER99";

class MemoryFirestore {
  constructor() {this.docs = new Map(); this.writes = [];}
  doc(path) {return {path};}
  seed(path, data) {this.docs.set(path, structuredClone(data));}
  read(path) {return this.docs.get(path);}
  async runTransaction(action) {
    const staged = [];
    const tx = {
      get: async ref => ({
        exists: this.docs.has(ref.path),
        data: () => structuredClone(this.docs.get(ref.path)),
      }),
      create: (ref, value) => {
        staged.push({path: ref.path, value: structuredClone(value)});
      },
    };
    const value = await action(tx);
    for (const write of staged) {
      if (this.docs.has(write.path)) throw new Error("transaction-conflict");
      this.docs.set(write.path, write.value);
      this.writes.push(write.path);
    }
    return value;
  }
}
function fixture() {
  const db = new MemoryFirestore();
  db.seed("deda_secure_account_bindings/" + NEW, {
    uid: NEW, accountKey: KEY, status: "PIN_VERIFIED_HOLD",
    createdAtMs: NOW - 60_000, canMigrate: false, canRestoreAssets: false,
  });
  db.seed("deda_account_directory/" + KEY, {
    accountKey: KEY, active: true, createdUid: OLD,
  });
  db.seed("deda_account_profiles/" + KEY, {
    accountKey: KEY, name: "Original Test", phone: KEY,
    trustedInstallIds: ["client_may_copy_this"],
  });
  db.seed("users/" + OLD, {
    accountKey: KEY, name: "Original Test",
    sharePersonalId: ID, diamonds: 410, level: 7,
    premiumId: "@DEDA-PREMIUM42",
    purchasedFrames: ["gold"], fcmTokens: ["secret-fcm-token"],
    trustedInstallIds: ["client_may_copy_this"],
  });
  db.seed("users/" + OLD + "/wallet/original", {
    diamonds: 410, coins: 70, frames: ["gold"],
  });
  db.seed("users/" + NEW, {
    accountKey: KEY, name: "Original Test",
  });
  db.seed("deda_share_ids/" + ID, {
    publicId: ID, kind: "personal", ownerUid: OLD, active: true,
  });
  db.seed("deda_diamond_gift_balances/" + ID, {
    balance: 22, lastClaimGiftId: "GIFT-A",
  });
  const auth = {getUser: async uid => ({
    uid, email: null, disabled: false, providerData: [],
  })};
  return {db, auth};
}
function request(uid = NEW, key = KEY) {
  return {
    auth: {uid, token: {firebase: {sign_in_provider: "anonymous"}}},
    app: {appId: "1:123:android:private-test"},
    data: {accountKey: key},
  };
}
function call(f, req = request(), nowMs = NOW, secret = SECRET) {
  return captureLegacyAccountEscrow({
    ...f, request: req, nowMs, secret,
  });
}
function escrowPath(uid = NEW, key = KEY) {
  return "deda_secure_legacy_recovery_escrow/" +
    hmac(SECRET, "recovery-escrow-v1", key + ":" + uid);
}
async function denied(promise) {
  return assert.rejects(promise, err => err instanceof RecoveryEscrowHold);
}
test("1: saves exactly one immutable private candidate copy, not spendable funds", async () => {
  const f = fixture();
  const oldWallet = structuredClone(f.db.read("users/" + OLD + "/wallet/original"));
  const outcome = await call(f);
  assert.equal(outcome.status, "LEGACY_SNAPSHOT_ESCROWED_NO_TRANSFER");
  assert.equal(outcome.accountAssetsTransferred, false);
  assert.equal(outcome.fullRecoveryComplete, false);
  assert.equal(outcome.categories.originalWallet, "CANDIDATE_UNVERIFIED");
  assert.equal(outcome.categories.localTaskPoints, "NOT_AVAILABLE_TO_SERVER");
  const copy = f.db.read(escrowPath());
  assert.equal(copy.status, "UNTRUSTED_ESCROW_NO_TRANSFER");
  assert.equal(copy.canRestoreDiamonds, false);
  assert.equal(copy.untrustedSnapshot.originalWalletCandidate.diamonds, 410);
  assert.equal(copy.untrustedSnapshot.originalUserCandidate.premiumId,
    "@DEDA-PREMIUM42");
  assert.deepEqual(f.db.read("users/" + OLD + "/wallet/original"), oldWallet);
  assert.deepEqual(f.db.writes, [escrowPath()]);
});
test("2: same source replay is idempotent, no second escrow or wallet write", async () => {
  const f = fixture();
  await call(f);
  const result = await call(f);
  assert.equal(result.status, "LEGACY_SNAPSHOT_ALREADY_ESCROWED");
  assert.equal(result.replay, true);
  assert.equal(f.db.writes.length, 1);
});
test("3: source spends or changes after escrow cause HOLD, not overwrite", async () => {
  const f = fixture();
  await call(f);
  f.db.seed("users/" + OLD + "/wallet/original", {
    diamonds: 300, coins: 70, frames: ["gold"],
  });
  await denied(call(f));
  assert.equal(f.db.read(escrowPath()).untrustedSnapshot
    .originalWalletCandidate.diamonds, 410);
  assert.equal(f.db.writes.length, 1);
});
test("4: wrong or missing server PIN binding denies copied install ID", async () => {
  const f = fixture();
  f.db.docs.delete("deda_secure_account_bindings/" + NEW);
  const req = request();
  req.data.installId = "client_may_copy_this";
  await denied(call(f, req));
  await denied(call(f));
  assert.equal(f.db.writes.length, 0);
});
test("5: expired proof, wrong account and forged UID never authorize snapshots", async () => {
  const f = fixture();
  await denied(call(f, request(), NOW + FRESH_MS + 1));
  const another = request("attackerUid999");
  await denied(call(f, another));
  const mismatched = request(NEW, "07744445555");
  await denied(call(f, mismatched));
  assert.equal(f.db.writes.length, 0);
});
test("6: target UID bound to another account cannot receive an escrow", async () => {
  const f = fixture();
  f.db.seed("users/" + NEW, {accountKey: "07777777777"});
  await denied(call(f));
  assert.equal(f.db.writes.length, 0);
});
test("7: inactive directory or wrong source UID account fails closed", async () => {
  const f = fixture();
  f.db.seed("deda_account_directory/" + KEY, {
    accountKey: KEY, active: false, createdUid: OLD,
  });
  await denied(call(f));
  const f2 = fixture();
  f2.db.seed("users/" + OLD, {accountKey: "07799999999", diamonds: 999});
  await denied(call(f2));
});
test("8: alias owner mismatch never proves gift ownership", async () => {
  const f = fixture();
  f.db.seed("deda_share_ids/" + ID, {
    publicId: ID, kind: "personal", ownerUid: "someoneElseUid",
    active: true,
  });
  const result = await call(f);
  assert.equal(result.categories.personalId, "ALIAS_OWNERSHIP_CONFLICT");
  assert.equal(result.categories.giftBalance, "MISSING");
  assert.equal(f.db.read(escrowPath()).untrustedSnapshot.giftBalanceCandidate,
    null);
});
test("9: no raw PIN, FCM token or copyable install ID retained in escrow", async () => {
  const f = fixture();
  await call(f);
  const serialized = JSON.stringify(f.db.read(escrowPath()));
  for (const forbidden of [
    "client_may_copy_this", "secret-fcm-token", "rawPin", "password",
  ]) assert.equal(serialized.includes(forbidden), false);
});
test("10: no Auth or no App Check or injected asset selection rejected", async () => {
  const f = fixture();
  const noApp = request();
  delete noApp.app;
  await denied(call(f, noApp));
  const invalid = request();
  invalid.data.diamonds = 1000000;
  await denied(call(f, invalid));
  const raw = request();
  raw.auth.token.firebase.sign_in_provider = "password";
  await denied(call(f, raw));
  assert.equal(f.db.writes.length, 0);
});
test("11: missing source wallet recorded as missing without zero-credit", async () => {
  const f = fixture();
  f.db.docs.delete("users/" + OLD + "/wallet/original");
  const result = await call(f);
  assert.equal(result.categories.originalWallet, "MISSING");
  assert.equal(result.diamondsCredited, false);
  assert.equal(f.db.read(escrowPath()).untrustedSnapshot.originalWalletCandidate,
    null);
});
test("12: too-large snapshot fails closed; neither source nor escrow modified", async () => {
  const f = fixture();
  f.db.seed("users/" + OLD + "/wallet/original", {
    diamonds: 410, frames: ["A".repeat(MAX_ESCROW_BYTES + 1)],
  });
  await denied(call(f));
  assert.equal(f.db.writes.length, 0);
});
test("13: missing secret fails before any account access", async () => {
  const f = fixture();
  await assert.rejects(call(f, request(), NOW, "tiny"),
    /ESCROW_SECRET_NOT_CONFIGURED/);
  assert.equal(f.db.writes.length, 0);
});
test("14: backend failure is generic, never returns account or currency values", async () => {
  const f = fixture();
  f.db.runTransaction = async () => {throw new Error("raw database secrets");};
  await assert.rejects(call(f), /RECOVERY_ESCROW_BACKEND_UNAVAILABLE/);
});
test("15: no verified progress receipt cannot be inferred from legacy wallet", async () => {
  const f = fixture();
  const outcome = await call(f);
  assert.equal(outcome.categories.progress, "MISSING");
  assert.equal(outcome.categories.migration, "MISSING");
  assert.equal(outcome.diamondsCredited, false);
  assert.equal(outcome.framesGranted, false);
});
