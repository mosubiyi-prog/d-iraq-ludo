"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {createLazyOwner19Callables} = require(
  "../tools/deda_100359_owner19_lazy_server_callables_PRIVATE_NOT_EXPORTED_2026_10_19.js");
class HttpsError extends Error {
  constructor(code, message) {super(message);this.code = code;}
}
let seen;
function make(flags = {}) {
  const calls = {secret: 0, decrypt: 0, manifest: 0, db: 0, sale: 0};
  const result = createLazyOwner19Callables({
    onCall: (opts, handler) => {
      assert.equal(opts.enforceAppCheck, true);
      assert.equal(opts.secrets.length, 1);
      return handler;
    },
    HttpsError, flags,
    secret: {value: () => {calls.secret++; return "test-secret-not-real";}},
    readEncryptedManifest: () => {calls.manifest++; return {mock: true};},
    decryptPrivate100: () => {
      calls.decrypt++;
      return Array.from({length: 100},
        (_, i) => "X" + String(i).padStart(3, "0"));
    },
    getFirestore: () => {
      calls.db++;return {runTransaction: async () => {
        seen = "attempted";
        throw Error("expected-no-write");
      }};
    },
    approvedGroup002: () => {calls.sale++; return [];},
  });
  return {result, calls};
}
const authorized = data => ({auth: {uid: "verified_1"},
  app: {appId: "appcheck-ok"}, data});

test("all 11 callable names exist, all AppCheck enforced, no eager secrets", () => {
  const {result, calls} = make();
  assert.equal(Object.keys(result).length, 11);
  assert.equal(typeof result.dedaStage19Exclusive100Read, "function");
  assert.equal(typeof result.dedaStage19Exclusive100SelfUse, "function");
  assert.equal(typeof result.dedaStage19Exclusive100Grant, "function");
  assert.equal(typeof result.dedaPremiumBuyIdentifier, "function");
  assert.equal(typeof result.dedaPremiumBuyCard, "function");
  assert.equal(calls.secret, 0);
  assert.equal(calls.decrypt, 0);
});
test("unauthenticated or missing AppCheck never touches catalog or secret", async () => {
  const {result, calls} = make({readExclusive: true});
  await assert.rejects(result.dedaStage19Exclusive100Read({data: {}}),
    error => error.code === "unauthenticated");
  await assert.rejects(result.dedaStage19Exclusive100Read({
    auth: {uid: "verified_1"}, data: {},
  }), error => error.code === "permission-denied");
  assert.deepEqual(calls, {secret: 0, decrypt: 0, manifest: 0, db: 0, sale: 0});
});
test("owner feature not launched means no secret or catalog even for real auth", async () => {
  const {result, calls} = make();
  await assert.rejects(result.dedaStage19Exclusive100Read(authorized({})),
    error => error.code === "unavailable");
  await assert.rejects(result.dedaStage19Exclusive100Grant(
    authorized({identifier: "@DEDA-X000", color:"gold",
      recipientOriginalId:"@DEDA-ABC234"})),
    error => error.code === "unavailable");
  assert.equal(calls.secret, 0);
  assert.equal(calls.decrypt, 0);
});
test("authenticated approved manager use loads server-only catalog; no data spills on failure", async () => {
  const {result, calls} = make({gmSelfUse: true});
  await assert.rejects(result.dedaStage19Exclusive100SelfUse(
    authorized({identifier:"@DEDA-X000", color:"gold"})),
    error => error.code === "internal" &&
      !error.message.includes("test-secret") &&
      !error.message.includes("expected-no-write"));
  assert.equal(calls.secret, 1);
  assert.equal(calls.manifest, 1);
  assert.equal(calls.decrypt, 1);
  assert.equal(calls.db, 1);
  assert.equal(seen,"attempted");
});
