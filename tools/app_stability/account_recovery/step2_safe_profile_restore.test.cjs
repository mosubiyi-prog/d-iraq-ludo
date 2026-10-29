"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {recoverSafeProfile, RecoveryHold, TTL_MS} =
  require("../../../functions/deda_safe_profile_restore_core");
const ACCOUNT = "07712345678";
const OLD = "oldOwnerUid123";
const NEW = "newPhoneUid456";
const NOW = 8_000_000;
class Db {
  constructor() { this.docs = new Map(); this.writes = []; }
  doc(path) { return {path}; }
  seed(path, data) { this.docs.set(path, {...data}); }
  read(path) { return this.docs.get(path); }
  async runTransaction(fn) {
    const changes = [];
    const tx = {
      get: async (ref) => ({exists: this.docs.has(ref.path),
        data: () => this.docs.get(ref.path)}),
      create: (ref, data) => changes.push({path: ref.path, data: {...data},
        mustNotExist: true}),
    };
    const result = await fn(tx);
    for (const item of changes) {
      if (item.mustNotExist && this.docs.has(item.path)) {
        throw new Error("already-exists");
      }
      this.docs.set(item.path, item.data);
      this.writes.push(item.path);
    }
    return result;
  }
}
function fixture() {
  const db = new Db();
  db.seed("deda_secure_account_bindings/" + NEW, {
    uid: NEW, accountKey: ACCOUNT, status: "PIN_VERIFIED_HOLD",
    createdAtMs: NOW - 5_000, canMigrate: false, canRestoreAssets: false,
  });
  db.seed("deda_account_directory/" + ACCOUNT, {
    accountKey: ACCOUNT, active: true, createdUid: OLD,
  });
  db.seed("deda_account_profiles/" + ACCOUNT, {
    accountKey: ACCOUNT, name: "Test Owner", phone: ACCOUNT,
    accountType: "user", trustedInstallIds: ["copyable-old-install"],
  });
  db.seed("users/" + OLD, {
    accountKey: ACCOUNT, name: "Test Owner", phone: ACCOUNT,
    accountType: "user", sharePersonalId: "@DEDA-EXAMPLE",
    premiumId: "@DEDA-GOLD", xp: 912, diamonds: 555,
  });
  db.seed("users/" + OLD + "/wallet/original", {
    diamonds: 555, frames: ["paid-frame"], coins: 800,
  });
  const auth = {getUser: async (uid) => ({
    uid, disabled: false, email: null, providerData: [],
  })};
  return {db, auth};
}
function req(uid = NEW, accountKey = ACCOUNT) {
  return {auth: {uid, token: {firebase: {sign_in_provider: "anonymous"}}},
    app: {appId: "1:demo:android:secure"},
    data: {accountKey}};
}
const run = (f, request = req(), nowMs = NOW) =>
  recoverSafeProfile({...f, request, nowMs});
const rejected = async p => assert.rejects(p, e => e instanceof RecoveryHold);
test("1: verified PIN binding copies ONLY profile fields to different UID", async () => {
  const f = fixture();
  const r = await run(f);
  assert.equal(r.status, "PROFILE_RESTORED");
  assert.equal(r.fullAccountRecoveryComplete, false);
  assert.equal(r.diamondsRestored, false);
  const restored = f.db.read("users/" + NEW);
  assert.equal(restored.name, "Test Owner");
  assert.equal(restored.accountType, "user");
  assert.equal(restored.accountKey, ACCOUNT);
  for (const name of ["xp", "diamonds", "premiumId", "sharePersonalId",
    "trustedInstallIds", "frames", "coins"]) {
    assert.equal(Object.hasOwn(restored, name), false, name);
  }
  assert.equal(f.db.read("users/" + OLD).diamonds, 555);
  assert.deepEqual(f.db.read("users/" + OLD + "/wallet/original"),
    {diamonds: 555, frames: ["paid-frame"], coins: 800});
  assert.deepEqual(f.db.writes.sort(), [
    "deda_secure_profile_restore_receipts/" + NEW, "users/" + NEW].sort());
});
test("2: repeat restore is idempotent and never credits anything", async () => {
  const f = fixture();
  await run(f);
  const before = [...f.db.writes];
  const r = await run(f);
  assert.equal(r.status, "PROFILE_ALREADY_RESTORED");
  assert.deepEqual(f.db.writes, before);
});
test("3: owner app already wrote equivalent safe profile: no overwrite", async () => {
  const f = fixture();
  f.db.seed("users/" + NEW, {
    accountKey: ACCOUNT, name: "Test Owner", phone: ACCOUNT,
    accountType: "user", extraLocal: "KEEP",
  });
  const r = await run(f);
  assert.equal(r.status, "PROFILE_ALREADY_PRESENT");
  assert.equal(f.db.read("users/" + NEW).extraLocal, "KEEP");
  assert.equal(f.db.writes.length, 1);
});
test("4: conflict with target UID or account refused without any mutation", async () => {
  const f = fixture();
  f.db.seed("users/" + NEW, {accountKey: "07799999999", name: "Other"});
  await rejected(run(f));
  assert.equal(f.db.writes.length, 0);
});
test("5: changed source after first restore fails closed", async () => {
  const f = fixture();
  await run(f);
  f.db.seed("deda_account_profiles/" + ACCOUNT, {
    accountKey: ACCOUNT, name: "Changed", phone: ACCOUNT, accountType: "user",
  });
  f.db.seed("users/" + OLD, {accountKey: ACCOUNT, name: "Changed"});
  await rejected(run(f));
  assert.equal(f.db.writes.length, 2);
});
test("6: expired, missing or malformed server PIN binding denied", async () => {
  const f = fixture();
  await rejected(run(f, req(), NOW + TTL_MS + 1));
  f.db.docs.delete("deda_secure_account_bindings/" + NEW);
  await rejected(run(f));
  f.db.seed("deda_secure_account_bindings/" + NEW, {
    uid: NEW, accountKey: ACCOUNT, status: "PIN_VERIFIED_HOLD",
    createdAtMs: NOW, canMigrate: true, canRestoreAssets: false,
  });
  await rejected(run(f));
});
test("13: a fresh server PIN recheck renews an old binding for profile restore", async () => {
  const f = fixture();
  const binding = f.db.read("deda_secure_account_bindings/" + NEW);
  binding.lastVerifiedAtMs = NOW + TTL_MS + 1000;
  const afterOriginalExpiry = NOW + TTL_MS + 2000;
  const response = await run(f, req(), afterOriginalExpiry);
  assert.equal(response.status, "PROFILE_RESTORED");
  assert.equal(response.diamondsRestored, false);
});
test("7: copied installation ID cannot confer new recovery entitlement", async () => {
  const f = fixture();
  f.db.docs.delete("deda_secure_account_bindings/" + NEW);
  const request = req();
  request.data.installId = "copyable-old-install";
  await rejected(run(f, request));
  assert.equal(f.db.writes.length, 0);
});
test("8: source creator mismatch, missing or inactive directory refuse", async () => {
  for (const state of ["absent", "inactive", "other"]) {
    const f = fixture();
    if (state === "absent") f.db.docs.delete("users/" + OLD);
    if (state === "inactive") f.db.seed("deda_account_directory/" + ACCOUNT, {
      accountKey: ACCOUNT, active: false, createdUid: OLD,
    });
    if (state === "other") f.db.seed("users/" + OLD, {
      accountKey: "07700000000", name: "Test Owner",
    });
    await rejected(run(f));
  }
});
test("9: unsigned / no App Check / malformed client account key denies", async () => {
  const f = fixture();
  const missing = req(); delete missing.app;
  await rejected(run(f, missing));
  const notAnonymous = req();
  notAnonymous.auth.token.firebase.sign_in_provider = "password";
  await rejected(run(f, notAnonymous));
  const extra = req(); extra.data.pin = "123456";
  await rejected(run(f, extra));
  assert.equal(f.db.writes.length, 0);
});
test("10: source profile values are validated and monetary fields never copied", async () => {
  for (const profile of [
    {accountKey: ACCOUNT, name: "", phone: ACCOUNT, accountType: "user"},
    {accountKey: ACCOUNT, name: "Test Owner", phone: "07900000000", accountType: "user"},
    {accountKey: ACCOUNT, name: "Test Owner", phone: ACCOUNT, accountType: "admin"},
  ]) {
    const f = fixture();
    f.db.seed("deda_account_profiles/" + ACCOUNT, profile);
    await rejected(run(f));
    assert.equal(f.db.read("users/" + NEW), undefined);
  }
});
test("11: source wallet and premium asset snapshots cannot be rewritten", async () => {
  const f = fixture();
  const originalWallet = JSON.stringify(f.db.read("users/" + OLD + "/wallet/original"));
  await run(f);
  assert.equal(JSON.stringify(f.db.read("users/" + OLD + "/wallet/original")),
    originalWallet);
  assert.equal(f.db.read("users/" + NEW + "/wallet/original"), undefined);
  assert.equal(f.db.read("deda_secure_profile_restore_receipts/" + NEW)
    .canCreditDiamonds, false);
});
test("12: backend outage does not report a successful restoration", async () => {
  const f = fixture();
  f.db.runTransaction = async () => {throw new Error("unsafe internal details");};
  await assert.rejects(run(f), /RECOVERY_PROFILE_BACKEND_UNAVAILABLE/);
  assert.equal(f.db.writes.length, 0);
});
