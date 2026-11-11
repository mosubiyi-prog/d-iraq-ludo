"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  accountKeyForPhone, createOwnerPinVerifyCallable,
} = require("../deda_owner_pin_verify_private_v1.js");

const account = "07712345678";
const originalUid = "original-owner-uid-100436";
const originalId = "@DEDA-AB1234";
const email = `${account}@deda-login.invalid`;
const correctPin = "482751";

class FakeDb {
  constructor() {
    this.docs = new Map();
    this.writes = [];
    this.reads = [];
  }
  put(path, data) { this.docs.set(path, {...data}); }
  collection(name) {
    return {doc: (id) => {
      const path = `${name}/${id}`;
      return {
        path, get: async () => this.snapshot(path),
      };
    }};
  }
  snapshot(path) {
    this.reads.push(path);
    const exists = this.docs.has(path);
    return {exists, data: () => exists ? {...this.docs.get(path)} : undefined};
  }
  async runTransaction(cb) {
    const updates = [];
    const tx = {
      get: (ref) => Promise.resolve(this.snapshot(ref.path)),
      set: (ref, value) => updates.push({path: ref.path, value}),
    };
    const result = await cb(tx);
    for (const write of updates) {
      this.put(write.path, write.value);
      this.writes.push(write.path);
    }
    return result;
  }
}

class FakeHttpsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function fixture({enabled = true, allowLegacyCustomTokensForQa = false} = {}) {
  const db = new FakeDb();
  db.put(`deda_account_directory/${account}`,
    {accountKey:account, active:true, createdUid:originalUid, authEmail:email});
  const synced = {toMillis:()=>1770000000000};
  db.put(`deda_credentials/${account}`,
    {accountKey:account, active:true, pin:correctPin, createdUid:originalUid,
      pinSyncVersion:1, updatedAt:synced, pinSyncedAt:synced});
  db.put(`users/${originalUid}`,
    {accountKey:account, sharePersonalId:originalId});
  db.put(`deda_share_ids/${originalId}`,
    {publicId:originalId, ownerUid:originalUid, kind:"personal", active:true});
  let nowMs = 1770000000000;
  const authUser = {uid:originalUid, disabled:false, email};
  const auth = {
    user:authUser, tokens:[],
    async getUser(_uid) { return this.user; },
    async createCustomToken(uid) {
      this.tokens.push(uid);
      return "private-test-token";
    },
  };
  let options;
  const fn = createOwnerPinVerifyCallable({
    onCall: (opts, handler) => {options = opts; return handler;},
    HttpsError: FakeHttpsError, db, auth, now: () => nowMs, enabled,
    allowLegacyCustomTokensForQa,
  });
  const request = {
    app:{appId:"test-app"},
    auth:{uid:"replacement-anonymous-uid",
      token:{firebase:{sign_in_provider:"anonymous"}}},
    data:{phone:account,pin:correctPin},
  };
  return {
    db, auth, fn, request, get options() {return options;},
    tick(ms) {nowMs += ms;},
  };
}

async function denied(f, data = f.request) {
  await assert.rejects(() => f.fn(data), (e) =>
    e.code === "permission-denied" &&
    e.message === "owner-verification-unavailable");
}

test("callable disabled by default and not exported from production index", async () => {
  const f = fixture({enabled:false});
  await denied(f);
  assert.equal(f.db.reads.length, 0);
  assert.equal(f.auth.tokens.length, 0);
});

test("AppCheck and caller anonymous Auth are required before any Firestore read", async () => {
  const f = fixture();
  await denied(f, {...f.request, app:null});
  await denied(f, {...f.request, auth:null});
  await denied(f, {...f.request,
    auth:{uid:"some-other-auth", token:{firebase:{sign_in_provider:"password"}}}});
  assert.equal(f.db.reads.length, 0);
  assert.equal(f.auth.tokens.length, 0);
  assert.equal(f.options.enforceAppCheck, true);
});

test("preserves accountKey digits rather than silently changing owner route", () => {
  assert.equal(accountKeyForPhone("0771 234 5678"), account);
  assert.equal(accountKeyForPhone("9647712345678"), "9647712345678");
  assert.equal(accountKeyForPhone("5555"), null);
  assert.equal(accountKeyForPhone("07712345678garbage"), null);
});

test("bad PIN and malformed request cannot mint tokens or expose account existence", async () => {
  const f = fixture();
  await denied(f, {...f.request, data:{phone:account,pin:"000000"}});
  await denied(f, {...f.request, data:{phone:account,pin:"123"}});
  assert.equal(f.auth.tokens.length, 0);
  assert.equal(f.db.docs.get(`deda_owner_pin_verify_limits/${account}`).windowAttempts,1);
});

test("valid linked canonical owner gets a token only for original UID and ID", async () => {
  const f = fixture({allowLegacyCustomTokensForQa:true});
  const result = await f.fn(f.request);
  assert.deepEqual(result, {
    customToken:"private-test-token", originalUid, originalId, accountKey:account,
  });
  assert.deepEqual(f.auth.tokens, [originalUid]);
  assert.deepEqual(f.db.writes, [`deda_owner_pin_verify_limits/${account}`]);
  assert.equal(f.db.docs.get(`deda_credentials/${account}`).pin,correctPin);
});

test("missing or inactive directory fails closed", async () => {
  const f = fixture();
  f.db.docs.delete(`deda_account_directory/${account}`);
  await denied(f);
  f.db.put(`deda_account_directory/${account}`,
    {accountKey:account,active:false,createdUid:originalUid});
  await denied(f);
  assert.equal(f.auth.tokens.length,0);
});

test("directory and credential must each point to the same original UID", async () => {
  const f = fixture();
  f.db.put(`deda_credentials/${account}`,
    {accountKey:account,active:true,pin:correctPin,createdUid:"foreign-uid"});
  await denied(f);
  assert.equal(f.auth.tokens.length,0);
});

test("original personal ID must be exact, active and routed to same UID", async () => {
  const f = fixture();
  f.db.put(`deda_share_ids/${originalId}`,
    {publicId:originalId,ownerUid:"foreign",kind:"personal",active:true});
  await denied(f);
  assert.equal(f.auth.tokens.length,0);
});

test("admin record is never eligible for owner-token issuance", async () => {
  const f = fixture();
  f.db.put(`admins/${originalUid}`,{role:"general_manager",active:true});
  await denied(f);
  assert.equal(f.auth.tokens.length,0);
});

test("unlinked or disabled Firebase Auth original UID cannot get token", async () => {
  const f = fixture();
  f.auth.user = {uid:originalUid,email:null,disabled:false};
  await denied(f);
  f.auth.user = {uid:originalUid,email,disabled:true};
  await denied(f);
  assert.equal(f.auth.tokens.length,0);
});

test("original anonymous UID cannot prelink with linked-password proof before provider enrollment", async () => {
  // A/B/C protection: the old phone's UID can be canonical yet anonymous.
  // Existing linked-password proof is NOT an initial enrollment service.
  // Do not change this test to mint tokens or accept PIN-only ownership.
  const f = fixture();
  f.request.auth.uid = originalUid;
  f.request.data.proofMode = "linked-password";
  f.auth.user = {uid:originalUid, email:null, disabled:false};
  await denied(f);
  assert.equal(f.auth.tokens.length,0);
  assert.equal(f.db.writes.every(path =>
    path.startsWith("deda_owner_pin_verify_limits/")), true);
  assert.equal(f.db.docs.get(`deda_credentials/${account}`).createdUid,
    originalUid);
  assert.equal(f.db.docs.get(`deda_account_directory/${account}`).createdUid,
    originalUid);
});

function originalAnonymousOldPhone(f = fixture()) {
  f.request.auth.uid = originalUid;
  f.request.data = {
    phone: account, pin: correctPin, originalId,
    proofMode: "original-anonymous-prelink",
  };
  f.auth.user = {uid: originalUid, disabled: false,
    email: null, providerData: []};
  delete f.db.docs.get(`deda_account_directory/${account}`).authEmail;
  const credentials = f.db.docs.get(`deda_credentials/${account}`);
  delete credentials.pinSyncVersion;
  delete credentials.pinSyncedAt;
  f.db.put(`deda_social_profiles/${originalId}`,
    {publicId: originalId, ownerUid: originalUid});
  f.db.put(`deda_sessions/${originalUid}`,
    {uid: originalUid, accountKey: account});
  return f;
}

test("original anonymous phone proves old PIN on SAME UID without Auth change", async () => {
  const f = originalAnonymousOldPhone();
  const response = await f.fn(f.request);
  assert.deepEqual(response, {verified: true});
  assert.equal(f.db.docs.get(`deda_credentials/${account}`).pin, correctPin);
  assert.equal(f.auth.tokens.length, 0);
  assert.deepEqual(f.db.writes, [`deda_owner_pin_verify_limits/${account}`]);
  assert.equal(f.db.docs.get(`deda_account_directory/${account}`).createdUid,
    originalUid);
});

test("original phone rechecks server proof after archive without UID migration", async () => {
  const f = originalAnonymousOldPhone();
  assert.deepEqual(await f.fn(f.request), {verified: true});
  assert.deepEqual(await f.fn(f.request), {verified: true});
  assert.equal(f.auth.tokens.length, 0);
  assert.deepEqual(f.db.writes, [
    `deda_owner_pin_verify_limits/${account}`,
    `deda_owner_pin_verify_limits/${account}`,
  ]);
});

test("original anonymous prelink rejects foreign UID even with correct PIN", async () => {
  for (const uid of ["replacement-new-uid", "deda-third-social-uid"]) {
    const f = originalAnonymousOldPhone();
    f.request.auth.uid = uid;
    await denied(f);
    assert.equal(f.auth.tokens.length, 0);
    assert(f.db.writes.every(p => p.startsWith("deda_owner_pin_verify_limits/")));
  }
});

test("original anonymous prelink refuses split registration and social/session UID", async () => {
  for (const [path, field] of [
    [`deda_account_directory/${account}`, "createdUid"],
    [`deda_credentials/${account}`, "createdUid"],
    [`deda_share_ids/${originalId}`, "ownerUid"],
    [`deda_social_profiles/${originalId}`, "ownerUid"],
    [`deda_sessions/${originalUid}`, "uid"],
  ]) {
    const f = originalAnonymousOldPhone();
    f.db.docs.get(path)[field] = "different-owner-uid";
    await denied(f);
    assert.equal(f.auth.tokens.length, 0, path);
  }
});

test("original anonymous prelink refuses missing social/session/route or manager", async () => {
  for (const path of [
    `deda_social_profiles/${originalId}`,
    `deda_sessions/${originalUid}`,
    `deda_share_ids/${originalId}`,
  ]) {
    const f = originalAnonymousOldPhone();
    f.db.docs.delete(path);
    await denied(f);
    assert.equal(f.auth.tokens.length, 0, path);
  }
  const admin = originalAnonymousOldPhone();
  admin.db.put(`admins/${originalUid}`, {active: true});
  await denied(admin);
});

test("original anonymous prelink refuses account, PIN and original ID mismatch", async () => {
  const invalid = [
    {phone: "07712345670"},
    {pin: "123456"},
    {pin: "abcdef"},
    {originalId: "@DEDA-NOTMINE"},
    {originalId: "bad"},
    {extraField: "unexpected"},
  ];
  for (const update of invalid) {
    const f = originalAnonymousOldPhone();
    f.request.data = {...f.request.data, ...update};
    await denied(f);
    assert.equal(f.auth.tokens.length, 0);
  }
});

test("original anonymous prelink refuses previously-linked and unsynced PIN states", async () => {
  const linked = originalAnonymousOldPhone();
  linked.auth.user.email = email;
  await denied(linked);
  const linkedProvider = originalAnonymousOldPhone();
  linkedProvider.auth.user.providerData.push({providerId: "password"});
  await denied(linkedProvider);
  const linkedDirectory = originalAnonymousOldPhone();
  linkedDirectory.db.docs.get(`deda_account_directory/${account}`).authEmail = email;
  await denied(linkedDirectory);
  const rotated = originalAnonymousOldPhone();
  rotated.db.docs.get(`deda_credentials/${account}`).pinSyncVersion = 1;
  await denied(rotated);
  const locked = originalAnonymousOldPhone();
  locked.db.put(`deda_pin_recovery_locks/${account}`, {locked: true});
  await denied(locked);
});

test("original anonymous prelink cannot act from Google/password provider or disabled gate", async () => {
  for (const provider of ["google.com", "password"]) {
    const f = originalAnonymousOldPhone();
    f.request.auth.token.firebase.sign_in_provider = provider;
    await denied(f);
    assert.equal(f.auth.tokens.length, 0);
  }
  const disabled = originalAnonymousOldPhone(fixture({enabled: false}));
  await denied(disabled);
  assert.equal(disabled.db.reads.length, 0);
  assert.equal(disabled.db.writes.length, 0);
  const noAppCheck = originalAnonymousOldPhone();
  noAppCheck.request.app = null;
  await denied(noAppCheck);
  assert.equal(noAppCheck.db.reads.length, 0);
});

test("server rate limit is per PHONE, not per anonymous replacement device", async () => {
  const f = fixture({allowLegacyCustomTokensForQa:true});
  for (let i=0;i<5;i++) {
    await denied(f, {...f.request,
      auth:{...f.request.auth,uid:`device-${i}`},
      data:{phone:account,pin:"000000"}});
  }
  await denied(f);
  assert.equal(f.db.docs.get(`deda_owner_pin_verify_limits/${account}`).windowAttempts,5);
  assert.equal(f.auth.tokens.length,0);
  f.tick(15*60*1000+1);
  const result = await f.fn(f.request);
  assert.equal(result.originalUid,originalUid);
});

test("daily cap remains after 15-minute rate windows", async () => {
  const f=fixture();
  for (let i=0;i<20;i++) {
    await denied(f, {...f.request,data:{phone:account,pin:"000000"}});
    f.tick(16*60*1000);
  }
  await denied(f);
  assert.equal(f.auth.tokens.length,0);
});

test("server Auth failure never returns a client token", async () => {
  const f=fixture();
  f.auth.getUser=async ()=>{throw Error("transient-backend-error");};
  await denied(f);
  assert.equal(f.auth.tokens.length,0);
});

test("stale PIN sync marker rejects even otherwise valid owner and correct PIN",async()=>{
  const f=fixture();
  const credential=f.db.docs.get(`deda_credentials/${account}`);
  delete credential.pinSyncVersion;
  await denied(f);
  assert.equal(f.auth.tokens.length,0);
});
test("automatic PIN-only recovery invalidates linked-owner proof until synchronized",async()=>{
  const f=fixture();
  const credential=f.db.docs.get(`deda_credentials/${account}`);
  credential.pin="777888";
  credential.updatedAt={toMillis:()=>1770000001000};
  await denied(f,{...f.request,data:{phone:account,pin:"777888"}});
  assert.equal(f.auth.tokens.length,0);
});
test("manual PIN rotation lock prevents token minting even with correct PIN",async()=>{
  const f=fixture();
  f.db.put(`deda_pin_recovery_locks/${account}`,{
    originalUid,requestId:"request-in-progress",
  });
  await denied(f);
  assert.equal(f.auth.tokens.length,0);
});

test("after synchronized PIN rotation old PIN fails, new PIN returns the original UID",async()=>{
  const f=fixture({allowLegacyCustomTokensForQa:true});
  const credential=f.db.docs.get(`deda_credentials/${account}`);
  credential.pin="654321";
  credential.pinSyncVersion=1;
  credential.updatedAt={toMillis:()=>1770000001000};
  credential.pinSyncedAt={toMillis:()=>1770000001000};
  await denied(f,{...f.request,data:{phone:account,pin:correctPin}});
  assert.equal(f.auth.tokens.length,0);
  const result=await f.fn({...f.request,data:{phone:account,pin:"654321"}});
  assert.equal(result.originalUid,originalUid);
  assert.equal(result.originalId,originalId);
  assert.deepEqual(f.auth.tokens,[originalUid]);
});

test("production never creates a custom Auth token from PIN-only request", async()=>{
  const f=fixture();
  await denied(f);
  assert.equal(f.auth.tokens.length,0);
  const proof=await f.fn({...f.request,
    data:{...f.request.data,proofMode:"linked-password"}});
  assert.deepEqual(proof,{originalUid,originalId,accountKey:account});
  assert.equal(f.auth.tokens.length,0);
});

test("linked-password proof returns original UID/ID but never creates a token", async()=>{
  const f=fixture();
  const result=await f.fn({...f.request,
    data:{...f.request.data,proofMode:"linked-password"}});
  assert.deepEqual(result,{originalUid,originalId,accountKey:account});
  assert.equal(f.auth.tokens.length,0);
  assert.deepEqual(f.db.writes,[`deda_owner_pin_verify_limits/${account}`]);
});

test("existing same-UID password Auth checks PIN on server without minting token", async()=>{
  const f=fixture();
  const request={...f.request,
    auth:{uid:originalUid,token:{firebase:{sign_in_provider:"password"}}},
    data:{phone:account,pin:correctPin,proofMode:"linked-password"}};
  const result=await f.fn(request);
  assert.deepEqual(result,{originalUid,originalId,accountKey:account});
  assert.equal(f.auth.tokens.length,0);
  assert.deepEqual(f.db.writes,[`deda_owner_pin_verify_limits/${account}`]);
});

test("foreign password UID cannot claim original account through known PIN",async()=>{
  const f=fixture({allowLegacyCustomTokensForQa:true});
  await denied(f,{...f.request,
    auth:{uid:"foreign-password-principal",token:{firebase:{sign_in_provider:"password"}}},
    data:{phone:account,pin:correctPin,proofMode:"linked-password"}});
  assert.equal(f.auth.tokens.length,0);
});
test("linked-password proof refuses non-password provider and unverified modes",async()=>{
  const f=fixture();
  await denied(f,{...f.request,
    auth:{uid:originalUid,token:{firebase:{sign_in_provider:"google.com"}}},
    data:{phone:account,pin:correctPin,proofMode:"linked-password"}});
  await denied(f,{...f.request,
    auth:{uid:originalUid,token:{firebase:{sign_in_provider:"password"}}},
    data:{phone:account,pin:correctPin}});
  assert.equal(f.auth.tokens.length,0);
});
test("linked password mode rejects wrong PIN before any owner data is returned",async()=>{
  const f=fixture();
  await denied(f,{...f.request,
    auth:{uid:originalUid,token:{firebase:{sign_in_provider:"password"}}},
    data:{phone:account,pin:"999999",proofMode:"linked-password"}});
  assert.equal(f.auth.tokens.length,0);
});

test("linked-password proof rejects old PIN after canonical rotation",async()=>{
  const f=fixture();
  const cred=f.db.docs.get(`deda_credentials/${account}`);
  cred.pin="654321";
  cred.updatedAt={toMillis:()=>1770000001000};
  cred.pinSyncedAt={toMillis:()=>1770000001000};
  await denied(f,{...f.request,data:{phone:account,pin:correctPin,
    proofMode:"linked-password"}});
  assert.equal(f.auth.tokens.length,0);
  const proof=await f.fn({...f.request,data:{phone:account,pin:"654321",
    proofMode:"linked-password"}});
  assert.deepEqual(proof,{originalUid,originalId,accountKey:account});
  assert.equal(f.auth.tokens.length,0);
});
