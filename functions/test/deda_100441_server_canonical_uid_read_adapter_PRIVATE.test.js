"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  inspectServerCanonicalOwner,
} = require("../deda_100441_server_canonical_uid_read_adapter_PRIVATE_NOT_EXPORTED.js");

const OWNER = "deda-original-owner-A";
const OTHER = "deda-second-session-B";
const THIRD = "deda-social-owner-C";
const ACCOUNT = "07111111111"; // synthetic, not a real phone
const ORIGINAL = "@DEDA-ABC123";
const TOKEN = "test-token-do-not-log-00000000000000000000";
const PIN = "123456"; // never supplied as input, copied or returned

function baseline() {
  return {
    ["deda_account_directory/" + ACCOUNT]: {
      accountKey: ACCOUNT, active: true, createdUid: OWNER,
    },
    ["deda_credentials/" + ACCOUNT]: {
      accountKey: ACCOUNT, active: true, createdUid: OWNER, pin: PIN,
    },
    ["deda_share_ids/" + ORIGINAL]: {
      publicId: ORIGINAL, kind: "personal", active: true, ownerUid: OWNER,
    },
    ["users/" + OWNER]: {accountKey: ACCOUNT, sharePersonalId: ORIGINAL},
    ["deda_social_profiles/" + ORIGINAL]: {
      publicId: ORIGINAL, ownerUid: OWNER,
    },
    ["deda_sessions/" + OWNER]: {uid: OWNER, accountKey: ACCOUNT},
  };
}

function harness({
  rows = baseline(),
  uid = OWNER,
  provider = "password",
  decodedEmail = ACCOUNT + "@deda-login.invalid",
  recordEmail = ACCOUNT + "@deda-login.invalid",
  linkedProviders = [],
  disabled = false,
  customClaims = {},
  authError = false,
  recordError = false,
  dbError = false,
} = {}) {
  const calls = {verify: [], getUser: [], reads: [], writes: []};
  const auth = {
    async verifyIdToken(token, checkRevoked) {
      calls.verify.push({tokenIsCorrect: token === TOKEN, checkRevoked});
      if (authError) throw Error("AUTH_REVOKED_OR_EXPIRED");
      return {
        uid, email: decodedEmail,
        firebase: {sign_in_provider: provider},
      };
    },
    async getUser(arg) {
      calls.getUser.push(arg);
      if (recordError) throw Error("AUTH_RECORD_UNAVAILABLE");
      return {
        uid: arg, email: recordEmail, disabled,
        providerData: linkedProviders.map(providerId => ({providerId})),
        customClaims,
      };
    },
  };
  const db = {
    doc(path) {
      calls.reads.push(path);
      return {
        async get() {
          if (dbError) throw Error("FIRESTORE_NETWORK_OR_PERMISSIONS");
          const data = rows[path];
          return data
            ? {exists: true, data: () => structuredClone(data)}
            : {exists: false, data: () => undefined};
        },
      };
    },
  };
  return {deps: {auth, db}, calls};
}

const input = Object.freeze({idToken: TOKEN, accountKey: ACCOUNT, originalId: ORIGINAL});
function noAuthority(out) {
  assert.equal(out.decision, "HOLD_FOR_INDEPENDENT_OWNER_REVIEW");
  for (const k of [
    "canSignIn", "canIssueToken", "canCreateUid", "canModifyAuth",
    "canWriteFirestore", "canReassignOwner", "canModifyAdmin", "canModifyFinances",
  ]) assert.equal(out[k], false, k);
  assert.equal(out.serverInternalOnly, true);
  assert.equal(Object.isFrozen(out), true);
  const s = JSON.stringify(out);
  for (const secret of [OWNER, OTHER, THIRD, ACCOUNT, ORIGINAL, TOKEN, PIN]) {
    assert.equal(s.includes(secret), false);
  }
}

test("verified password and seven coherent Firestore documents are REVIEW ONLY", async () => {
  const t = harness();
  const out = await inspectServerCanonicalOwner(input, t.deps);
  assert.equal(out.classification, "CANONICAL_MATCH_REQUIRES_SEPARATE_OWNER_REVIEW");
  noAuthority(out);
  assert.deepEqual(t.calls.verify, [{tokenIsCorrect: true, checkRevoked: true}]);
  assert.deepEqual(t.calls.getUser, [OWNER]);
  assert.equal(t.calls.reads.length, 7);
  assert(t.calls.reads.includes("users/" + OWNER));
  assert(t.calls.reads.includes("admins/" + OWNER));
  assert.equal(t.calls.writes.length, 0);
});

test("three-way split A original route, B register, C social + auth is detected", async () => {
  const rows = baseline();
  rows["deda_account_directory/" + ACCOUNT].createdUid = OTHER;
  rows["deda_credentials/" + ACCOUNT].createdUid = OTHER;
  rows["deda_social_profiles/" + ORIGINAL].ownerUid = THIRD;
  rows["users/" + THIRD] = {accountKey: ACCOUNT, sharePersonalId: ORIGINAL};
  rows["deda_sessions/" + THIRD] = {uid: THIRD, accountKey: ACCOUNT};
  const t = harness({
    rows, uid: THIRD, provider: "google.com",
    linkedProviders: ["google.com"], decodedEmail: "genuine@example.test",
    recordEmail: "genuine@example.test",
  });
  const out = await inspectServerCanonicalOwner(input, t.deps);
  assert.equal(out.classification, "SPLIT_DETECTED_NO_ACCOUNT_TRANSFER");
  noAuthority(out);
  assert(!t.calls.reads.includes("users/" + OWNER));
  assert(t.calls.reads.includes("users/" + THIRD));
});

test("Google canonical review rejects each partial UID split without reading PIN into result", async () => {
  // These cases can pass the smaller client-side directory/route/user/session
  // checks. The sensitive credentials and social owners MUST be inspected on
  // the trusted server, never fetched directly by Flutter.
  for (const [path, field, value] of [
    ["deda_credentials/" + ACCOUNT, "createdUid", OTHER],
    ["deda_social_profiles/" + ORIGINAL, "ownerUid", THIRD],
  ]) {
    const rows = baseline();
    rows[path][field] = value;
    const t = harness({
      rows, provider: "google.com", linkedProviders: ["google.com"],
      decodedEmail: "linked@example.test", recordEmail: "linked@example.test",
    });
    const out = await inspectServerCanonicalOwner(input, t.deps);
    assert.equal(out.classification, "SPLIT_DETECTED_NO_ACCOUNT_TRANSFER",
      path);
    noAuthority(out);
    assert.equal(t.calls.reads.length, 7);
    assert.equal(t.calls.writes.length, 0);
  }

  const healthy = harness({
    provider: "google.com", linkedProviders: ["google.com"],
    decodedEmail: "linked@example.test", recordEmail: "linked@example.test",
  });
  const status = await inspectServerCanonicalOwner(input, healthy.deps);
  assert.equal(status.classification,
    "CANONICAL_MATCH_REQUIRES_SEPARATE_OWNER_REVIEW");
  noAuthority(status); // Even perfect records never authorize sign-in.
});

test("different live linked Firebase UID is classified SPLIT, even if PIN known", async () => {
  const rows = baseline();
  rows["users/" + OTHER] = {accountKey: ACCOUNT, sharePersonalId: ORIGINAL};
  rows["deda_sessions/" + OTHER] = {uid: OTHER, accountKey: ACCOUNT};
  const t = harness({rows, uid: OTHER});
  const out = await inspectServerCanonicalOwner(input, t.deps);
  assert.equal(out.classification, "SPLIT_DETECTED_NO_ACCOUNT_TRANSFER");
  noAuthority(out);
});

test("anonymous Firebase UID cannot even trigger private account reads", async () => {
  const t = harness({uid: OTHER, provider: "anonymous"});
  const out = await inspectServerCanonicalOwner(input, t.deps);
  assert.equal(out.classification, "NO_INDEPENDENT_DURABLE_AUTH");
  assert.equal(t.calls.reads.length, 0);
  noAuthority(out);
});

test("revoked/expired/invalid Firebase ID token stops before all account reads", async () => {
  const t = harness({authError: true});
  const out = await inspectServerCanonicalOwner(input, t.deps);
  assert.equal(out.classification, "UNVERIFIED_AUTH_SESSION");
  assert.equal(t.calls.getUser.length, 0);
  assert.equal(t.calls.reads.length, 0);
  noAuthority(out);
});

test("unknown Auth user is not given fallback anonymous or PIN login", async () => {
  const t = harness({recordError: true});
  const out = await inspectServerCanonicalOwner(input, t.deps);
  assert.equal(out.classification, "UNVERIFIED_AUTH_SESSION");
  assert.equal(t.calls.reads.length, 0);
  noAuthority(out);
});

test("disabled Firebase Auth user cannot access the server account records", async () => {
  const t = harness({disabled: true});
  const out = await inspectServerCanonicalOwner(input, t.deps);
  assert.equal(out.classification, "NO_INDEPENDENT_DURABLE_AUTH");
  assert.equal(t.calls.reads.length, 0);
  noAuthority(out);
});

test("password token may not claim another accountKey or forged email", async () => {
  for (const t of [
    harness({decodedEmail: "other@deda-login.invalid"}),
    harness({recordEmail: "other@deda-login.invalid"}),
    harness({uid: OTHER}),
  ]) {
    // In the last case the UID is different but same account email; it is
    // classified SPLIT by immutable server records, never authorized.
    const out = await inspectServerCanonicalOwner(input, t.deps);
    assert.notEqual(out.classification,
      "CANONICAL_MATCH_REQUIRES_SEPARATE_OWNER_REVIEW");
    noAuthority(out);
  }
});

test("Google or phone sign-in requires linked provider in Admin Auth user record", async () => {
  for (const provider of ["google.com", "phone"]) {
    const rejected = harness({provider, linkedProviders: []});
    const out = await inspectServerCanonicalOwner(input, rejected.deps);
    assert.equal(out.classification, "NO_INDEPENDENT_DURABLE_AUTH");
    assert.equal(rejected.calls.reads.length, 0);
    noAuthority(out);

    const accepted = harness({provider, linkedProviders: [provider]});
    const reviewed = await inspectServerCanonicalOwner(input, accepted.deps);
    assert.equal(reviewed.classification,
      "CANONICAL_MATCH_REQUIRES_SEPARATE_OWNER_REVIEW");
    noAuthority(reviewed);
  }
});

test("UID with admins document cannot acquire owner or general manager access", async () => {
  const rows = baseline();
  rows["admins/" + OWNER] = {role: "general_manager", active: true};
  for (const t of [
    harness({rows}),
    harness({customClaims: {admin: true}}),
  ]) {
    const out = await inspectServerCanonicalOwner(input, t.deps);
    assert.equal(out.classification, "ADMIN_PRINCIPAL_REQUIRES_SEPARATE_REVIEW");
    noAuthority(out);
  }
});

test("missing social, route, session or credential holds instead of reconstructing", async () => {
  for (const key of [
    "deda_social_profiles/" + ORIGINAL,
    "deda_share_ids/" + ORIGINAL,
    "deda_sessions/" + OWNER,
    "deda_credentials/" + ACCOUNT,
  ]) {
    const rows = baseline();
    delete rows[key];
    const t = harness({rows});
    const out = await inspectServerCanonicalOwner(input, t.deps);
    assert.equal(out.classification, "INCOMPLETE_OR_LEGACY_ACCOUNT_PROOF");
    noAuthority(out);
  }
});

test("missing account registration never creates one or a phantom UID", async () => {
  const t = harness({rows: {}});
  const out = await inspectServerCanonicalOwner(input, t.deps);
  assert.equal(out.classification, "INCOMPLETE_OR_LEGACY_ACCOUNT_PROOF");
  noAuthority(out);
});

test("Firestore unavailable fails closed without any ownership or token grant", async () => {
  const t = harness({dbError: true});
  const out = await inspectServerCanonicalOwner(input, t.deps);
  assert.equal(out.classification, "SERVER_EVIDENCE_UNAVAILABLE");
  noAuthority(out);
});

test("strict request shape rejects PIN, premium alias and malformed account", async () => {
  for (const wrong of [
    null, {}, {idToken: TOKEN, accountKey: ACCOUNT, originalId: "@DEDA-ABCD"},
    {...input, idToken: ""},
    {...input, accountKey: "0/../../anything"},
    {...input, originalId: "../../admins"},
  ]) {
    const t = harness();
    const out = await inspectServerCanonicalOwner(wrong, t.deps);
    assert.equal(out.classification, "INVALID_OR_UNVERIFIED_REQUEST");
    assert.equal(t.calls.verify.length, 0);
    assert.equal(t.calls.reads.length, 0);
    noAuthority(out);
  }
});

test("client-asserted ownerUid, createdUid, admin and PIN never affect server result", async () => {
  const t = harness();
  const out = await inspectServerCanonicalOwner({
    ...input,
    claimedUid: OTHER, pin: PIN,
    admin: true, createdUid: OTHER,
    trustedInstallIds: ["attacker-string"],
  }, t.deps);
  assert.equal(out.classification,
    "CANONICAL_MATCH_REQUIRES_SEPARATE_OWNER_REVIEW");
  noAuthority(out);
});

test("all results are redacted and state classification never implies access", async () => {
  const variants = [
    harness(),
    harness({authError: true}),
    harness({provider: "anonymous"}),
    harness({dbError: true}),
  ];
  for (const t of variants) {
    const out = await inspectServerCanonicalOwner(input, t.deps);
    noAuthority(out);
  }
});
