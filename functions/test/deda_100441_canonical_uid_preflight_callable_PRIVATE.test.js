"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");

const {
  createPrivateCanonicalUidPreflightCallable,
  consumeAccountScopedLimit,
} = require("../deda_100441_canonical_uid_preflight_callable_PRIVATE_NOT_EXPORTED.js");

const UID = "deda-original-owner-qa";
const UID_B = "deda-other-owner-qa";
const ACCOUNT = "07111111111"; // artificial
const ACCOUNT_B = "07222222222"; // artificial
const ORIGINAL = "@DEDA-T3ST99";
const TOKEN = "synthetic.firebase.id-token-0123456789";
const SERVER_KEY = "private-testing-only-32-byte-secret-key-not-deployed";
const NOW = Date.UTC(2026, 10, 8, 12);
const AUTH_EMAIL = ACCOUNT + "@deda-login.invalid";

class HttpsError extends Error {
  constructor(code, message) {
    super(message); this.code = code;
  }
}

function rows() {
  return new Map(Object.entries({
    ["deda_account_directory/" + ACCOUNT]: {
      accountKey: ACCOUNT, createdUid: UID, active: true,
    },
    ["deda_credentials/" + ACCOUNT]: {
      accountKey: ACCOUNT, createdUid: UID, active: true,
      pin: "777777",
    },
    ["deda_share_ids/" + ORIGINAL]: {
      publicId: ORIGINAL, kind: "personal", active: true, ownerUid: UID,
    },
    ["users/" + UID]: {
      accountKey: ACCOUNT, sharePersonalId: ORIGINAL,
    },
    ["deda_social_profiles/" + ORIGINAL]: {
      publicId: ORIGINAL, ownerUid: UID,
    },
    ["deda_sessions/" + UID]: {
      uid: UID, accountKey: ACCOUNT,
    },
  }));
}
function harness({
  enabled = true, app = true, authContext = true, uid = UID,
  decodedUid = uid, provider = "password", recordEmail = AUTH_EMAIL,
  tokenEmail = AUTH_EMAIL, linkedProviders = [], userDisabled = false,
  accountRows = rows(), limiterKey = SERVER_KEY,
  verifyThrows = false, getThrows = false, dbThrows = false,
  now = () => NOW,
} = {}) {
  const state = {
    rows: accountRows,
    limits: new Map(),
    reads: [],
    writes: [],
    authChecks: [],
    userReads: [],
    options: null,
  };
  const auth = {
    async verifyIdToken(token, revoked) {
      state.authChecks.push({token, revoked});
      if (verifyThrows) throw new Error("invalid_or_revoked_token");
      return {
        uid: decodedUid, email: tokenEmail,
        firebase: {sign_in_provider: provider},
      };
    },
    async getUser(askedUid) {
      state.userReads.push(askedUid);
      if (getThrows) throw Error("unknown_user");
      return {
        uid: askedUid, disabled: userDisabled,
        email: recordEmail,
        providerData: linkedProviders.map(providerId => ({providerId})),
      };
    },
  };
  const db = {
    doc(path) {
      return {
        path,
        async get() {
          state.reads.push(path);
          if (dbThrows) throw Error("firestore_unavailable");
          const value = state.rows.get(path);
          return value === undefined ? {exists:false} : {
            exists:true, data:()=>structuredClone(value),
          };
        },
      };
    },
    async runTransaction(fn) {
      if (dbThrows) throw Error("limiter_unavailable");
      const tx = {
        async get(ref) {
          state.reads.push(ref.path);
          const value = state.limits.get(ref.path);
          return value === undefined ? {exists:false} : {
            exists:true, data:()=>structuredClone(value),
          };
        },
        set(ref, data) {
          if (!ref.path.startsWith("deda_100441_uid_preflight_rate_limits/")) {
            throw Error("attempted_user_data_write");
          }
          state.writes.push({path:ref.path, data});
          state.limits.set(ref.path, structuredClone(data));
        },
      };
      return await fn(tx);
    },
  };
  const onCall = (options, fn) => {
    state.options = options;
    return fn;
  };
  const callable = createPrivateCanonicalUidPreflightCallable({
    onCall, HttpsError, auth, db, limiterKey, now, enabled,
  });
  const request = {
    auth: authContext ? {
      uid, token: {firebase:{sign_in_provider: provider}},
    } : null,
    app: app ? {appId:"fake-app-check-verified-by-functions-framework"} : null,
    rawRequest: {headers:{authorization:"Bearer " + TOKEN}},
    data: {accountKey: ACCOUNT, originalId: ORIGINAL},
  };
  return {callable, request, auth, db, state};
}
async function rejected(task) {
  await assert.rejects(task, e =>
    e instanceof HttpsError && e.code === "permission-denied" &&
    e.message === "owner-review-unavailable"
  );
}
function publicIsSafe(response) {
  assert.deepEqual(response, {status:"review_required"});
  for (const secret of [UID,UID_B,ACCOUNT,ACCOUNT_B,ORIGINAL,TOKEN,"777777"]) {
    assert(!JSON.stringify(response).includes(secret));
  }
}

test("private Callable is OFF by default, even with syntactically valid Auth + AppCheck", async () => {
  const t = harness({enabled: false});
  await rejected(() => t.callable(t.request));
  assert.equal(t.state.reads.length,0);
  assert.equal(t.state.writes.length,0);
  assert.equal(t.state.authChecks.length,0);
});

test("future-only Callable uses least-privilege existing recovery identity and mandatory App Check", () => {
  const t = harness();
  assert.equal(t.state.options.enforceAppCheck,true);
  assert.equal(t.state.options.timeoutSeconds,25);
  assert.equal(t.state.options.minInstances,0);
  assert.equal(t.state.options.maxInstances,2);
  assert.equal(t.state.options.region,"us-central1");
  assert(/deda-recovery-runtime@/.test(t.state.options.serviceAccount));
});

test("verified canonical UID returns only generic review, never authorization", async () => {
  const t = harness();
  publicIsSafe(await t.callable(t.request));
  assert.deepEqual(t.state.authChecks.map(x=>x.revoked),[true,true]);
  assert.deepEqual(t.state.userReads,[UID]);
  assert.equal(t.state.writes.length,1);
  assert(t.state.writes[0].path.startsWith("deda_100441_uid_preflight_rate_limits/"));
  assert(!t.state.writes[0].path.includes(ACCOUNT));
});

test("three-way A/B/C split returns SAME public generic response", async () => {
  const t = harness();
  t.state.rows.get("deda_account_directory/" + ACCOUNT).createdUid = UID_B;
  t.state.rows.get("deda_credentials/" + ACCOUNT).createdUid = UID_B;
  t.state.rows.get("deda_social_profiles/" + ORIGINAL).ownerUid = "deda-third-qa-owner";
  const response = await t.callable(t.request);
  publicIsSafe(response);
  assert.equal(t.state.writes.length,1);
});

test("account missing and canonical account have identical public responses", async () => {
  const yes = harness();
  const none = harness({accountRows: new Map()});
  const a = await yes.callable(yes.request);
  const b = await none.callable(none.request);
  publicIsSafe(a);
  assert.deepEqual(b, a);
  assert.equal(none.state.writes.length,1);
});

test("anonymous Auth is rejected before any user/account Firestore read", async () => {
  const t = harness({provider:"anonymous"});
  await rejected(() => t.callable(t.request));
  assert.equal(t.state.reads.length,0);
  assert.equal(t.state.writes.length,0);
});

test("App Check missing must reject even if password auth session is valid", async () => {
  const t = harness({app:false});
  await rejected(() => t.callable(t.request));
  assert.equal(t.state.authChecks.length,0);
  assert.equal(t.state.reads.length,0);
});

test("Firebase Callable auth missing cannot fall back to typed UID or token", async () => {
  const t = harness({authContext:false});
  await rejected(() => t.callable(t.request));
  assert.equal(t.state.authChecks.length,0);
});

test("raw bearer token absent, malformed or client-supplied cannot be used", async () => {
  for (const value of [undefined,"Bearer ","Token "+TOKEN,
    "Bearer "+TOKEN+" SPACE","bearer "+TOKEN]) {
    const t = harness();
    t.request.rawRequest.headers.authorization = value;
    await rejected(() => t.callable(t.request));
    assert.equal(t.state.authChecks.length,0);
    assert.equal(t.state.reads.length,0);
  }
});

test("raw Firebase token must match framework-authenticated callable UID", async () => {
  const t = harness({decodedUid:UID_B});
  await rejected(() => t.callable(t.request));
  assert.equal(t.state.reads.length,0);
  assert.equal(t.state.writes.length,0);
});

test("revoked token and nonexistent Auth user are generically denied", async () => {
  for (const cfg of [{verifyThrows:true},{getThrows:true}]) {
    const t = harness(cfg);
    await rejected(() => t.callable(t.request));
    if (cfg.verifyThrows) assert.equal(t.state.reads.length,0);
    else assert.equal(t.state.writes.length,1);
  }
});

test("malformed and unexpected client fields including PIN and UID deny before Auth", async () => {
  const d = {accountKey:ACCOUNT,originalId:ORIGINAL};
  for (const value of [
    {...d, pin:"777777"},
    {...d, ownerUid: UID},
    {...d, admin:true},
    {...d, idToken:TOKEN},
    {...d, accountKey:"some-injected-path"},
    {...d, originalId:"@DEDA-ABCD"},
    {accountKey:ACCOUNT},
    null,
    [],
  ]) {
    const t = harness();
    t.request.data = value;
    await rejected(() => t.callable(t.request));
    assert.equal(t.state.reads.length,0);
  }
});

test("missing or unsafe server-only HMAC limiter key fails closed", async () => {
  for (const k of [null,"","short-key",Buffer.alloc(4)]) {
    const t = harness({limiterKey:k});
    await rejected(() => t.callable(t.request));
    assert.equal(t.state.authChecks.length,0);
    assert.equal(t.state.reads.length,0);
  }
});

test("sixth attempt per account within one hour is denied without extra account read", async () => {
  const t = harness();
  for (let i=0;i<5;i++) publicIsSafe(await t.callable(t.request));
  const readsBefore = t.state.reads.length;
  await rejected(() => t.callable(t.request));
  assert.equal(t.state.writes.length,5);
  assert.equal(t.state.reads.length,readsBefore+1); // limiter only
});

test("second Auth UID cannot bypass the per-account throttling ledger", async () => {
  const t = harness();
  for (let i=0;i<5;i++) publicIsSafe(await t.callable(t.request));
  const second = {...t.request,auth:{uid:UID_B,
    token:{firebase:{sign_in_provider:"password"}}}};
  // Even when its own bearer token is valid for the changed identity,
  // limiter remains account-bound. The mock doesn't forge new records.
  const t2 = harness({uid:UID_B,decodedUid:UID_B});
  t2.state.limits = t.state.limits; // injected test shared server state
  // The mocked db holds a reference to t2.state.limits, so this is shared.
  await rejected(() => t2.callable({...t2.request,auth:second.auth}));
  assert.equal(t2.state.writes.length,0);
});

test("day rate limit holds after hourly window reset", async () => {
  let tick = NOW;
  const t = harness({now:()=>tick});
  for(let hour=0;hour<3;hour++){
    tick = NOW+hour*60*60*1000;
    for(let i=0;i<4;i++) publicIsSafe(await t.callable(t.request));
  }
  tick = NOW+3*60*60*1000;
  await rejected(()=>t.callable(t.request));
  assert.equal(t.state.writes.length,12);
});

test("limit ledger never stores plaintext phone, PIN, original ID or UID", async () => {
  const t = harness();
  publicIsSafe(await t.callable(t.request));
  const asText = JSON.stringify(t.state.writes);
  for (const val of [ACCOUNT,ORIGINAL,UID,TOKEN,"777777"]) {
    assert(!asText.includes(val));
  }
  assert(/^[0-9a-f]{64}$/.test(t.state.writes[0].path.split("/")[1]));
});

test("corrupt ledger and missing Firestore permissions fail closed", async () => {
  const t = harness();
  publicIsSafe(await t.callable(t.request));
  const docPath = t.state.writes[0].path;
  t.state.limits.set(docPath, {version:1,windowStartMs:NOW,
    windowCount:-1,dayBucket:Math.floor(NOW/(24*60*60*1000)),
    dayCount:1,lastAttemptMs:NOW});
  await rejected(()=>t.callable(t.request));
  assert.equal(t.state.writes.length,1);
  const failed = harness({dbThrows:true});
  await rejected(()=>failed.callable(failed.request));
  assert.equal(failed.state.writes.length,0);
});

test("backward server clock never resets a previous attempt ledger", async () => {
  let tick=NOW;
  const t=harness({now:()=>tick});
  publicIsSafe(await t.callable(t.request));
  tick=NOW-60000;
  await rejected(()=>t.callable(t.request));
  assert.equal(t.state.writes.length,1);
});

test("existing admin principal is not treated as owner permissions", async () => {
  const t = harness();
  t.state.rows.set("admins/"+UID,{role:"general_manager",active:true});
  publicIsSafe(await t.callable(t.request));
  assert.equal(t.state.writes.length,1);
});

test("no wallet, friend, gift, league, social or account write occurs", async () => {
  const t = harness();
  publicIsSafe(await t.callable(t.request));
  assert.equal(t.state.writes.length,1);
  assert(t.state.writes.every(x => x.path.startsWith(
    "deda_100441_uid_preflight_rate_limits/"
  )));
  assert(t.state.reads.every(x =>
    !/wallet|diamonds|gift|friend|league|reward/.test(x)
  ));
});

test("invalid trusted construction fails before creating a Callable handler", () => {
  assert.throws(() => createPrivateCanonicalUidPreflightCallable({}),
    /trusted-server-dependencies-required/);
});

test("one account/day bucket is isolated from another synthetic account", async () => {
  const t = harness();
  publicIsSafe(await t.callable(t.request));
  // Separate token provider record email mismatch means public generic,
  // but the limiter document is still independent and opaque.
  const t2 = harness();
  t2.state.limits = t.state.limits;
  t2.request.data.accountKey = ACCOUNT_B;
  // The second phone's account does not match its linked Auth provider,
  // so access fails, but the account-scoped anti-abuse attempt is still
  // counted in a distinct opaque ledger.
  await rejected(()=>t2.callable(t2.request));
  assert.equal(t.state.limits.size,2);
});
