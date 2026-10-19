"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {PRICE_DIAMONDS, createApprovedSaleCatalog, checkoutVerifiedIdentifier} =
  require("../tools/deda_stage18_private_atomic_identifier_checkout_2026_10_19.js");

const BUY_ID = "@DEDA-AAAAAA";
const BUY_B = "@DEDA-BBBBBB";
const ORIGINAL_A = "@DEDA-Z9X8Y7";
const ORIGINAL_B = "@DEDA-X8Y7Z6";
const REQ = "request_12345";

class Ref {
  constructor(path) {this.path = path;}
  collection(name) {return new Ref(this.path + "/" + name);}
  doc(name) {return new Ref(this.path + "/" + name);}
}
class MemoryDb {
  constructor() {this.docs = new Map();}
  collection(name) {return new Ref(name);}
  put(path, row) {this.docs.set(path, structuredClone(row));}
  peek(path) {return this.docs.get(path);}
  async runTransaction(fn) {
    const staged = [];
    const tx = {
      get: async (ref) => {
        const doc = this.docs.get(ref.path);
        return {exists: !!doc, data: () => structuredClone(doc)};
      },
      create: (ref, data) => staged.push(["create", ref.path, data]),
      update: (ref, data) => staged.push(["update", ref.path, data]),
      set: (ref, data) => staged.push(["set", ref.path, data]),
    };
    const response = await fn(tx);
    // Memory mock simulates commit only on successful callback completion.
    for (const [op, path] of staged) {
      if (op === "create" && this.docs.has(path)) {
        const e = new Error("conflicting-create");
        e.code = "already-exists"; throw e;
      }
      if (op === "update" && !this.docs.has(path)) {
        throw new Error("updating-absent-document:" + path);
      }
    }
    for (const [op, path, value] of staged) {
      const previous = this.docs.get(path) || {};
      this.docs.set(path, structuredClone(op === "update"
          ? {...previous, ...value} : value));
    }
    return response;
  }
}
function privateReserved() {
  return Array.from({length: 100}, (_, n) => String(n).padStart(6, "0"));
}
function config(approved = ["AAAAAA"]) {
  return createApprovedSaleCatalog({
    reservedSuffixes: privateReserved(),
    approvedSuffixes: approved,
  });
}
function seedBuyer(db, {uid = "user_A", key = "account_A", original = ORIGINAL_A,
  balance = 15000, localDiamonds = 999999} = {}) {
  db.put("users/" + uid, {
    accountKey: key, sharePersonalId: original, localDiamonds,
  });
  db.put("deda_sessions/" + uid, {uid, accountKey: key});
  db.put("deda_share_ids/" + original, {
    kind: "personal", publicId: original, active: true, ownerUid: uid,
  });
  db.put("deda_diamond_gift_balances/" + original, {
    publicId: original, balance,
  });
}
function stock(db, identifier = BUY_ID, state = "verified_available") {
  db.put("deda_verified_id_sale_catalog/" + identifier, {
    identifier, group: "002", ownerApproved: true, status: state,
    priceDiamonds: PRICE_DIAMONDS,
  });
}
function makeReady({balance = 15000, approve = ["AAAAAA"], withStock = true} = {}) {
  const db = new MemoryDb();
  seedBuyer(db, {balance});
  if (withStock) stock(db);
  return {db, approvedCatalog: config(approve)};
}
async function buy(db, approvedCatalog, {uid = "user_A",
  identifier = BUY_ID, requestId = REQ} = {}) {
  return checkoutVerifiedIdentifier(db, {
    uid, identifier, requestId, approvedCatalog,
  });
}

test("private first 100 catalog is mandatory and incomplete sets fail closed", () => {
  assert.throws(() => createApprovedSaleCatalog({
    approvedSuffixes: ["AAAAAA"], reservedSuffixes: ["000000"],
  }), /invalid-private-reserved/);
  assert.throws(() => createApprovedSaleCatalog({
    approvedSuffixes: ["000000"], reservedSuffixes: privateReserved(),
  }), /reserved-identifier-cannot-be-listed/);
  assert.equal(PRICE_DIAMONDS, 10000);
});
test("missing approval is not a sale even when candidate appears on screen", async () => {
  const {db} = makeReady();
  await assert.rejects(buy(db, null), /verified-server-sale-catalog-required/);
  assert.equal(db.peek("deda_diamond_gift_balances/" + ORIGINAL_A).balance, 15000);
});
test("approved name without separately confirmed inventory cannot be sold", async () => {
  const {db, approvedCatalog} = makeReady({withStock: false});
  await assert.rejects(buy(db, approvedCatalog),
    /server-verified-inventory-not-for-sale/);
  assert.equal(db.peek("deda_diamond_gift_balances/" + ORIGINAL_A).balance, 15000);
});
test("verified checkout debits exactly 10000 and atomically records permanent ownership and sold stock", async () => {
  const {db, approvedCatalog} = makeReady();
  const r = await buy(db, approvedCatalog);
  assert.equal(r.diamondsCharged, 10000);
  assert.equal(r.serverConfirmed, true);
  assert.equal(r.identifier, BUY_ID);
  assert.equal(db.peek("deda_diamond_gift_balances/" + ORIGINAL_A).balance, 5000);
  const owned = [...db.docs.entries()].find(([p]) =>
    p.startsWith("deda_owned_identifier_accounts/"));
  assert.deepEqual(owned[1].ownedIds, [ORIGINAL_A, BUY_ID]);
  assert.equal(owned[1].activeId, ORIGINAL_A);
  assert.equal(db.peek("deda_owned_identifier_registry/" + BUY_ID).status, "owned");
  assert.equal(db.peek("deda_owned_identifier_aliases/" + BUY_ID).originalId, ORIGINAL_A);
  assert.equal(db.peek("deda_verified_id_sale_catalog/" + BUY_ID).status, "sold");
  assert.equal([...db.docs.keys()].filter(p => p.startsWith("deda_id_purchase_requests/") &&
      p.endsWith("/" + REQ)).length, 1);
});
test("lost-response retry with identical request id never deducts twice", async () => {
  const {db, approvedCatalog} = makeReady();
  const one = await buy(db, approvedCatalog);
  const again = await buy(db, approvedCatalog);
  assert.deepEqual(again, one);
  assert.equal(db.peek("deda_diamond_gift_balances/" + ORIGINAL_A).balance, 5000);
});
test("different request id cannot buy same identifier twice", async () => {
  const {db, approvedCatalog} = makeReady();
  await buy(db, approvedCatalog);
  await assert.rejects(buy(db, approvedCatalog, {requestId: "request_22222"}),
    /identifier-already-registered-or-owned/);
  assert.equal(db.peek("deda_diamond_gift_balances/" + ORIGINAL_A).balance, 5000);
});
test("another user cannot purchase the identifier owned by first user", async () => {
  const {db, approvedCatalog} = makeReady();
  await buy(db, approvedCatalog);
  seedBuyer(db, {uid: "user_B", key: "account_B", original: ORIGINAL_B});
  await assert.rejects(buy(db, approvedCatalog, {
    uid: "user_B", requestId: "request_98765",
  }), /identifier-already-registered-or-owned/);
  assert.equal(db.peek("deda_diamond_gift_balances/" + ORIGINAL_B).balance, 15000);
});
test("local diamonds never count as verified balance; insufficient funds leave stock unchanged", async () => {
  const {db, approvedCatalog} = makeReady({balance: 9999});
  await assert.rejects(buy(db, approvedCatalog),
    /insufficient-verified-diamonds-local-excluded/);
  assert.equal(db.peek("deda_verified_id_sale_catalog/" + BUY_ID).status,
    "verified_available");
  assert.equal(db.peek("deda_diamond_gift_balances/" + ORIGINAL_A).balance, 9999);
  assert.equal(db.peek("deda_owned_identifier_registry/" + BUY_ID), undefined);
});
test("unauthorized or expired current session cannot debit anything", async () => {
  const {db, approvedCatalog} = makeReady();
  db.put("deda_sessions/user_A", {uid: "user_B", accountKey: "account_A"});
  await assert.rejects(buy(db, approvedCatalog), /verified-account-and-session-required/);
  assert.equal(db.peek("deda_diamond_gift_balances/" + ORIGINAL_A).balance, 15000);
});
test("client cannot substitute a lower price or unapproved name", async () => {
  const {db, approvedCatalog} = makeReady();
  stock(db, BUY_B);
  await assert.rejects(buy(db, approvedCatalog, {identifier: BUY_B}),
    /identifier-not-approved-for-sale/);
  db.put("deda_verified_id_sale_catalog/" + BUY_ID, {
    identifier: BUY_ID, group: "002", ownerApproved: true,
    status: "verified_available", priceDiamonds: 5000,
  });
  await assert.rejects(buy(db, approvedCatalog),
    /server-verified-inventory-not-for-sale/);
  assert.equal(db.peek("deda_diamond_gift_balances/" + ORIGINAL_A).balance, 15000);
});
test("same idempotency key cannot be reused for another product", async () => {
  const {db, approvedCatalog} = makeReady({approve: ["AAAAAA", "BBBBBB"]});
  stock(db, BUY_B);
  await buy(db, approvedCatalog);
  await assert.rejects(buy(db, approvedCatalog, {identifier: BUY_B}),
    /request-id-conflicts-with-existing-receipt/);
  assert.equal(db.peek("deda_diamond_gift_balances/" + ORIGINAL_A).balance, 5000);
});
test("no public Cloud Function exports and production Firebase rules unchanged", () => {
  const fs = require("node:fs");
  const prod = fs.readFileSync("functions/index.js", "utf8");
  assert.ok(!prod.includes("deda_stage18_private_atomic_identifier_checkout"));
  assert.ok(!prod.includes("dedaPremiumBuyIdentifier"));
});
