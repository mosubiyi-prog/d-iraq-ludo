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

function fixture({enabled = true} = {}) {
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
  const f = fixture();
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

test("server rate limit is per PHONE, not per anonymous replacement device", async () => {
  const f = fixture();
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
  const f=fixture();
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
