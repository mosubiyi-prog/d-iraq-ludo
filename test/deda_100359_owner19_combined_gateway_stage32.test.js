"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {createOwner19Gateway, callableFactory, OWNER_NAMES} =
  require("../tools/deda_100359_owner19_combined_gateway_private_2026_10_19.js");
const {createApprovedSaleCatalog} = require(
  "../tools/deda_stage18_private_atomic_identifier_checkout_2026_10_19.js");

const private100 = Object.freeze(Array.from({length: 100},
  (_, i) => "X" + String(i).padStart(3, "0")));
const db = {runTransaction: async () => {throw Error("unexpected mutation");}};
const who = (data = {}) => ({auth: {uid: "test_user_1"},
  app: {appId: "test-app-check"}, data});

test("original catalog has real 4-12 character suffix support; never needs public copy", () => {
  assert.equal(private100.length, 100);
  assert.ok(private100.some(name => name.length === 4));
  const sale = createApprovedSaleCatalog({
    reservedSuffixes: [...private100], approvedSuffixes: ["SALE01"],
  });
  assert.equal(sale.allows("@DEDA-SALE01"), true);
  assert.equal(sale.allows("@DEDA-X000"), false);
  assert.throws(() => createApprovedSaleCatalog({
    reservedSuffixes: ["SALE01", ...private100.slice(0, 99)],
    approvedSuffixes: ["SALE01"],
  }), /reserved-identifier-cannot-be-listed/);
  assert.throws(() => createApprovedSaleCatalog({
    reservedSuffixes: private100,
    approvedSuffixes: ["FOUR"],
  }), /invalid-approved-sale/);
});

test("all real card, ID and admin calls default closed and never mutate DB", async () => {
  const app = createOwner19Gateway({
    db, exclusiveSuffixes: [...private100], approvedSellableSuffixes: [],
  });
  for (const [method, enabled] of Object.entries(app.enabled)) {
    assert.equal(enabled, false, method);
    await assert.rejects(app.handle(method, who()), /unavailable/);
  }
  for (const [method, enabled] of Object.entries(app.stage16.enabled)) {
    assert.equal(enabled, false, method);
  }
  assert.equal(app.saleInventoryReady, false);
});

test("missing/duplicate private 100 and missing approved sale inventory fail closed", () => {
  assert.throws(() => createOwner19Gateway({
    db, exclusiveSuffixes: private100.slice(0, 99),
    approvedSellableSuffixes: [],
  }), /failed-precondition/);
  assert.throws(() => createOwner19Gateway({
    db, exclusiveSuffixes: [...private100.slice(0, 99), private100[0]],
    approvedSellableSuffixes: [],
  }), /failed-precondition/);
  assert.throws(() => createOwner19Gateway({
    db, exclusiveSuffixes: private100,
  }), /failed-precondition/);
});

test("real methods require both auth and AppCheck before even reading", async () => {
  const app = createOwner19Gateway({db, exclusiveSuffixes: [...private100],
    approvedSellableSuffixes: [], flags: {readExclusive: true}});
  await assert.rejects(app.handle("readExclusive", {data: {}}), /unauthenticated/);
  await assert.rejects(app.handle("readExclusive", {
    auth: {uid: "test_user_1"}, data: {},
  }), /permission-denied/);
  await assert.rejects(app.handle("gmGift", who({
    identifier: "@DEDA-X000", color: "gold",
    recipientOriginalId: "@DEDA-ABC234",
  })), /unavailable/);
});

test("manager grant color and ID are strictly validated before any server write", async () => {
  const app = createOwner19Gateway({db, exclusiveSuffixes: [...private100],
    approvedSellableSuffixes: [], flags: {gmGift: true}});
  await assert.rejects(app.handle("gmGift", who({
    identifier: "@DEDA-X000", color: "fake",
    recipientOriginalId: "@DEDA-ABC234",
  })), /invalid-argument/);
  await assert.rejects(app.handle("gmGift", who({
    identifier: "@DEDA-X000", color: "gold",
    recipientOriginalId: "@DEDA-ABC234", price: 0,
  })), /invalid-argument/);
});

test("callables declare enforced AppCheck, private secret and expected names", () => {
  const app = createOwner19Gateway({
    db, exclusiveSuffixes: [...private100], approvedSellableSuffixes: [],
  });
  const recorded = [];
  class HttpsError extends Error {
    constructor(code, message) {super(message);this.code=code;}
  }
  const callables = callableFactory(app, {
    onCall: (opts, cb) => {recorded.push(opts);return cb;},
    HttpsError,
    secret: {value: () => "fake-secret-never-used"},
  });
  assert.equal(Object.keys(OWNER_NAMES).length, 4);
  for (const functionName of Object.values(OWNER_NAMES)) {
    assert.equal(typeof callables[functionName], "function");
  }
  assert.equal(callables.dedaPremiumReadCards instanceof Function, true);
  assert.ok(recorded.every(opts => opts.enforceAppCheck === true));
  assert.ok(recorded.filter(opts => Array.isArray(opts.secrets)).length === 4);
  assert.equal(fs.readFileSync("functions/index.js", "utf8")
    .includes("deda_100359_owner19_combined_gateway_private"), false);
});
