"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {securePinPreflight, PinDenied, rateDocumentId, validInput,
  WINDOW_MS, DAY_MS} = require("../../../functions/deda_secure_pin_gate_core");

const SECRET = "offline-qa-only-DO-NOT-DEPLOY-0123456789abcdef";
const ACCOUNT = "07712345678";
const PIN = "639284";
const UID_A = "uid_phone_A_123";
const UID_B = "uid_phone_B_456";
const mockRequest = (uid = UID_A, accountKey = ACCOUNT, pin = PIN) => ({
  auth: {uid, token: {firebase: {sign_in_provider: "anonymous"}}},
  app: {appId: "1:123:android:qa"},
  data: {accountKey, pin},
});

class FakeFirestore {
  constructor() { this.docs = new Map(); this.written = []; }
  doc(path) { return {path}; }
  seed(path, data) { this.docs.set(path, {...data}); }
  read(path) { return this.docs.get(path); }
  async runTransaction(fn) {
    const writes = [];
    const tx = {
      get: async (ref) => ({
        exists: this.docs.has(ref.path),
        data: () => this.docs.has(ref.path) ? {...this.docs.get(ref.path)} : undefined,
      }),
      set: (ref, data) => writes.push({op: "set", path: ref.path, data}),
      create: (ref, data) => {
        if (this.docs.has(ref.path)) throw new Error("already exists");
        writes.push({op: "create", path: ref.path, data});
      },
    };
    const result = await fn(tx);
    for (const write of writes) {
      if (write.op === "create" && this.docs.has(write.path)) {
        throw new Error("concurrent conflict");
      }
      this.docs.set(write.path, {...write.data});
      this.written.push(write.path);
    }
    return result;
  }
}
function fixture() {
  const db = new FakeFirestore();
  db.seed("deda_credentials/" + ACCOUNT, {
    accountKey: ACCOUNT, active: true, pin: PIN, createdUid: UID_A,
  });
  db.seed("deda_account_directory/" + ACCOUNT, {
    accountKey: ACCOUNT, active: true, createdUid: UID_A,
  });
  db.seed("deda_account_profiles/" + ACCOUNT, {
    accountKey: ACCOUNT, trustedInstallIds: ["copied_install_id_is_untrusted"],
  });
  db.seed("users/" + UID_A + "/wallet/original", {diamonds: 2000});
  const auth = {getUser: async (uid) => ({
    uid, disabled: false, email: null, providerData: [],
  })};
  return {db, auth};
}
const verify = (fixture, request = mockRequest(), nowMs = 10000000,
  secret = SECRET) => securePinPreflight({request, ...fixture, secret, nowMs});
const rejected = (promise) => assert.rejects(promise, (e) => e instanceof PinDenied);

test("correct PIN creates server-owned HOLD binding with zero wallet changes", async () => {
  const f = fixture();
  const response = await verify(f);
  assert.equal(response.status, "PIN_VERIFIED_HOLD");
  assert.equal(response.canRestoreAssets, false);
  const binding = f.db.read("deda_secure_account_bindings/" + UID_A);
  assert.equal(binding.uid, UID_A);
  assert.equal(binding.accountKey, ACCOUNT);
  assert.equal(binding.canCreditDiamonds, false);
  assert.equal(f.db.read("users/" + UID_A + "/wallet/original").diamonds, 2000);
  assert.equal(f.db.read("deda_sessions/" + UID_A), undefined);
  assert.equal(f.db.read("deda_auth_attempts/" + UID_A), undefined);
  assert.equal(f.db.written.every(path =>
    path.startsWith("deda_secure_account_bindings/") ||
    path.startsWith("deda_secure_pin_account_limits/")), true);
});

test("repeating the same verified UID never creates a new identity or credits", async () => {
  const f = fixture();
  await verify(f);
  const first = f.db.read("deda_secure_account_bindings/" + UID_A);
  await verify(f, mockRequest(), 10000001);
  assert.deepEqual(f.db.read("deda_secure_account_bindings/" + UID_A), first);
});

test("five wrong PINs lock the account centrally across different anonymous UIDs", async () => {
  const f = fixture();
  for (let i = 0; i < 5; i++) {
    await rejected(verify(f, mockRequest(i % 2 ? UID_A : UID_B, ACCOUNT, "000000")));
  }
  const limit = f.db.read("deda_secure_pin_account_limits/" +
    rateDocumentId(SECRET, ACCOUNT));
  assert.equal(limit.failures, 5);
  await rejected(verify(f, mockRequest(UID_B), 10000001));
  assert.equal(f.db.read("deda_secure_account_bindings/" + UID_B), undefined);
  await verify(f, mockRequest(UID_B), 10000000 + WINDOW_MS + 1);
  assert.equal(f.db.read("deda_secure_account_bindings/" + UID_B).status,
    "PIN_VERIFIED_HOLD");
});

test("daily account failure budget is not bypassed by waiting between windows", async () => {
  const f = fixture();
  for (let window = 0; window < 4; window++) {
    const now = 10000000 + window * (WINDOW_MS + 1000);
    for (let attempt = 0; attempt < 5; attempt++) {
      await rejected(verify(f, mockRequest(UID_A, ACCOUNT, "111111"), now));
    }
  }
  await rejected(verify(f, mockRequest(), 10000000 + 4 * (WINDOW_MS + 1000)));
  await verify(f, mockRequest(), 10000000 + DAY_MS + 1);
});

test("unknown account uses the same generic denial and HMAC-keyed rate record", async () => {
  const f = fixture();
  const key = "07700000000";
  await rejected(verify(f, mockRequest(UID_B, key, PIN)));
  const paths = f.db.written;
  assert.equal(paths.some(path => path.includes(key)), false);
  assert.equal(paths.length, 1);
});

test("copied install ID and client-supplied UID never act as identity proof", async () => {
  const f = fixture();
  const request = mockRequest(UID_B);
  request.data = {...request.data, installId: "copied_install_id_is_untrusted"};
  await rejected(verify(f, request));
  request.data = {...mockRequest(UID_B).data, uid: UID_A};
  await rejected(verify(f, request));
  assert.equal(f.db.written.length, 0);
});

test("Auth, app attestations, server Auth user and exact payload are mandatory", async () => {
  const f = fixture();
  const noApp = mockRequest(); delete noApp.app;
  await rejected(verify(f, noApp));
  const badProvider = mockRequest();
  badProvider.auth.token.firebase.sign_in_provider = "password";
  await rejected(verify(f, badProvider));
  const noAuth = mockRequest(); delete noAuth.auth;
  await rejected(verify(f, noAuth));
  const disabled = fixture(); disabled.auth.getUser = async uid => ({
    uid, disabled: true, email: null, providerData: [],
  });
  await rejected(verify(disabled));
  assert.equal(f.db.written.length + disabled.db.written.length, 0);
  assert.equal(validInput({accountKey: ACCOUNT, pin: PIN, installId: "x"}), false);
});

test("one UID cannot switch to a different account even with a correct other PIN", async () => {
  const f = fixture();
  await verify(f);
  const other = "07876543210";
  f.db.seed("deda_credentials/" + other, {accountKey: other, active: true, pin: "123456"});
  f.db.seed("deda_account_directory/" + other,
    {accountKey: other, active: true, createdUid: UID_B});
  f.db.seed("deda_account_profiles/" + other, {accountKey: other});
  await rejected(verify(f, mockRequest(UID_A, other, "123456")));
  assert.equal(f.db.read("deda_secure_account_bindings/" + UID_A).accountKey, ACCOUNT);
});

test("second phone gets separate PIN-verified HOLD, without transferring assets", async () => {
  const f = fixture();
  await verify(f, mockRequest(UID_A));
  await verify(f, mockRequest(UID_B));
  assert.equal(f.db.read("deda_secure_account_bindings/" + UID_A).accountKey, ACCOUNT);
  assert.equal(f.db.read("deda_secure_account_bindings/" + UID_B).accountKey, ACCOUNT);
  assert.equal(f.db.read("users/" + UID_A + "/wallet/original").diamonds, 2000);
  assert.equal(f.db.read("users/" + UID_B + "/wallet/original"), undefined);
});

test("server secret misconfiguration fails closed without reading/writing account", async () => {
  const f = fixture();
  await assert.rejects(verify(f, mockRequest(), 10000000, "bad"),
    /SECURE_PIN_GATE_CONFIG_MISSING/);
  assert.equal(f.db.written.length, 0);
});

test("all absent or inconsistent active account records deny safely", async () => {
  for (const field of ["deda_credentials", "deda_account_directory",
    "deda_account_profiles"]) {
    const f = fixture();
    f.db.docs.delete(field + "/" + ACCOUNT);
    await rejected(verify(f));
  }
  const f = fixture();
  f.db.seed("deda_account_directory/" + ACCOUNT, {
    accountKey: ACCOUNT, active: false, createdUid: UID_A,
  });
  await rejected(verify(f));
});

test("unexpected backend transaction failure is generic and leaves no binding", async () => {
  const f = fixture();
  f.db.runTransaction = async () => { throw new Error("sensitive-db-error"); };
  await assert.rejects(verify(f), /SECURE_PIN_GATE_BACKEND_UNAVAILABLE/);
  assert.equal(f.db.read("deda_secure_account_bindings/" + UID_A), undefined);
});
