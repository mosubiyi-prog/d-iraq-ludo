"use strict";

// Source-only QA; Node 20 + dependencies from functions/package.json needed.
// Not deployed, no actual Firebase access. These mocks DO NOT replace emulator
// tests for Firestore security rules, transaction retries or App Check.
const {test} = require("node:test");
const assert = require("node:assert/strict");

process.env.DEDA_RECOVERY_JOURNAL_SERVER_ENABLED = "true";
const {__privateVerifiedCompletionForQaOnly: complete} = require(
    "./deda_recovery_journal_completion_CANDIDATE_NOT_EXPORTED.js");

const uid = "linkedOriginalUID123";
const accountKey = "9647712345678";
const originalId = "@DEDA-ABC123";
const intentId = "private_recovery_intent_20261104";
const code = "originalBackupReadback";
const receiptId = "verifiedReceipt2026_0001";
const operationKey = `deda_guardian_v1/${uid}/${intentId}/${code}`;
const id = `${intentId}_${code}`;
const rowPath = `deda_recovery_journals/${uid}/steps/${id}`;
const attestationPath = `deda_recovery_server_attestations/${uid}/receipts/${id}`;

function request(patch = {}) {
  return {
    auth: {uid, token: {
      email: `${accountKey}@deda-login.invalid`,
      firebase: {sign_in_provider: "password"},
    }},
    data: {accountKey, originalUid: uid, originalId,
      intentId, code, operationKey, receiptId},
    ...patch,
  };
}
function fixture({attestation = true, verified = false} = {}) {
  const store = new Map([
    [`deda_account_directory/${accountKey}`,
      {accountKey, active: true, createdUid: uid}],
    [`users/${uid}`, {accountKey, sharePersonalId: originalId}],
    [`deda_share_ids/${originalId}`,
      {publicId: originalId, ownerUid: uid, kind: "personal", active: true}],
    [`deda_sessions/${uid}`, {uid, accountKey}],
    [rowPath, {ownerUid: uid, accountKey, originalId, intentId, code,
      operationKey, state: verified ? "verified" : "reserved",
      ...(verified ? {receiptId} : {})}],
    ...(attestation ? [[attestationPath, {
      ownerUid: uid, accountKey, originalId, intentId, code,
      operationKey, receiptId, serverVerified: true,
      issuedBy: "deda-approved-domain-verifier-v1",
      sourceRevision: "serverSourceRevision0001",
    }]] : []),
  ]);
  let writes = 0;
  const db = {
    doc: (path) => ({path, get: async () => snapshot(path)}),
    runTransaction: async (fn) => fn({
      get: async (ref) => snapshot(ref.path),
      update: (ref, fields) => {
        writes++;
        store.set(ref.path, {...store.get(ref.path), ...fields});
      },
    }),
  };
  function snapshot(path) {
    const data = store.get(path);
    return {exists: !!data, data: () => data};
  }
  return {db, store, writes: () => writes};
}

test("no attestation => cannot mark verified", async () => {
  const f = fixture({attestation: false});
  await assert.rejects(complete(request(), f.db), /trusted-server-readback-missing/);
  assert.equal(f.writes(), 0);
  assert.equal(f.store.get(rowPath).state, "reserved");
});

test("valid independent server attestation permits one verified transition", async () => {
  const f = fixture();
  const r = await complete(request(), f.db);
  assert.deepEqual(r, {verified: true, receiptId});
  assert.equal(f.writes(), 1);
  assert.equal(f.store.get(rowPath).state, "verified");
});

test("same verified receipt is idempotent", async () => {
  const f = fixture({verified: true});
  const r = await complete(request(), f.db);
  assert.equal(r.verified, true);
  assert.equal(f.writes(), 0);
});

test("other UID/credential cannot complete original user's row", async () => {
  const f = fixture();
  const requestWithWrongUid = request({auth: {
    uid: "other-uid", token: request().auth.token,
  }});
  await assert.rejects(complete(requestWithWrongUid, f.db),
      /original-owner-completion-proof-required/);
  assert.equal(f.writes(), 0);
});

test("PIN-only anonymous provider is never treated as linked original UID", async () => {
  const f = fixture();
  const x = request();
  x.auth.token.firebase.sign_in_provider = "anonymous";
  await assert.rejects(complete(x, f.db),
      /original-owner-completion-proof-required/);
  assert.equal(f.writes(), 0);
});

test("wrong receiptId is not proof even for correct Firebase owner", async () => {
  const f = fixture();
  const x = request();
  x.data.receiptId = "forgedReceipt2026ABC";
  await assert.rejects(complete(x, f.db), /trusted-server-readback-missing/);
  assert.equal(f.writes(), 0);
});

test("missing original owner route fails before journal write", async () => {
  const f = fixture();
  f.store.delete(`deda_share_ids/${originalId}`);
  await assert.rejects(complete(request(), f.db),
      /original-owner-server-provenance-missing/);
  assert.equal(f.writes(), 0);
});

test("attestation for different operation is not accepted", async () => {
  const f = fixture();
  f.store.get(attestationPath).operationKey = "wrong-op";
  await assert.rejects(complete(request(), f.db), /trusted-server-readback-missing/);
  assert.equal(f.writes(), 0);
});

test("client cannot claim verification on forbidden code", async () => {
  const f = fixture();
  const x = request();
  x.data.code = "linkedPinReissue";
  await assert.rejects(complete(x, f.db),
      /original-owner-completion-proof-required/);
  assert.equal(f.writes(), 0);
});
