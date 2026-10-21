"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {readVerifiedPublicAlias} = require("../deda_qa32_public_alias_resolver_NOT_EXPORTED.js");
const origin = "@DEDA-ABC123", premium = "@DEDA-IRAQI";

function mockDb(docs, calls = []) {
  return {doc(path) {
    calls.push(path);
    return {async get() {
      const item = docs[path];
      return {exists: Boolean(item), data: () => item};
    }};
  }};
}
function fixture(kind = "gifted") {
  const records = {
    ["deda_share_ids/" + origin]: {publicId: origin, kind: "personal",
      active: true, ownerUid: "stable-owner-uid"},
    ["deda_stage71_active_identifier/" + origin]: {
      originalId: origin, activeId: premium},
    ["deda_stage71_granted_registry/" + premium]: {
      identifier: premium, recipientOriginalId: origin,
      kind, group: "001", baseColor: "gold"},
  };
  if (kind === "gifted") {
    records["deda_stage74_id_gift_receipts/" + premium] = {
      identifier: premium, originalId: origin,
      group: "001", receivedAt: {seconds: 1792569600},
    };
  }
  return records;
}
test("authenticated friend sees ONLY verified active ID and fixed foil", async () => {
  const result = await readVerifiedPublicAlias(mockDb(fixture()), origin, "friend-uid");
  assert.deepEqual(Object.keys(result).sort(), [
    "displayId", "permanentColor", "requestedId", "serverConfirmed"].sort());
  assert.equal(result.requestedId, origin);
  assert.equal(result.displayId, premium);
  assert.equal(result.permanentColor, "gold");
  assert.equal(result.serverConfirmed, true);
  assert.equal("ownerUid" in result, false);
  assert.equal("accountKey" in result, false);
  assert.equal("diamonds" in result, false);
});
test("unauthenticated read is rejected before any private Firestore reads", async () => {
  const calls = [];
  await assert.rejects(
      readVerifiedPublicAlias(mockDb(fixture(), calls), origin, null),
      /AUTH_REQUIRED/);
  assert.equal(calls.length, 0);
});
test("same original account may return to permanent ID without fake foil", async () => {
  const data = fixture();
  data["deda_stage71_active_identifier/" + origin].activeId = origin;
  const result = await readVerifiedPublicAlias(mockDb(data), origin, "friend-uid");
  assert.equal(result.serverConfirmed, false);
  assert.equal(result.displayId, null);
  assert.equal(result.permanentColor, null);
});
test("gift unreceived or forged receipt must never become public alias", async () => {
  const data = fixture();
  delete data["deda_stage74_id_gift_receipts/" + premium];
  await assert.rejects(
      readVerifiedPublicAlias(mockDb(data), origin, "friend-uid"),
      /GIFT_NOT_RECEIVED/);
  data["deda_stage74_id_gift_receipts/" + premium] = {
    identifier: premium, originalId: "@DEDA-OTHER1",
    group: "001", receivedAt: {seconds: 100},
  };
  await assert.rejects(
      readVerifiedPublicAlias(mockDb(data), origin, "friend-uid"),
      /GIFT_NOT_RECEIVED/);
});
test("manager self-used ID is read-only visible without gift receipt", async () => {
  const result = await readVerifiedPublicAlias(mockDb(fixture("self_used")),
      origin, "friend-uid");
  assert.equal(result.displayId, premium);
  assert.equal(result.serverConfirmed, true);
});
test("cross-account forged ownership, local color and unlisted alias rejected", async () => {
  const data = fixture();
  data["deda_stage71_granted_registry/" + premium].recipientOriginalId =
      "@DEDA-DEF456";
  await assert.rejects(
      readVerifiedPublicAlias(mockDb(data), origin, "friend-uid"),
      /UNVERIFIED_OWNER/);
  data["deda_stage71_granted_registry/" + premium].recipientOriginalId = origin;
  data["deda_stage71_granted_registry/" + premium].baseColor = "magenta";
  await assert.rejects(
      readVerifiedPublicAlias(mockDb(data), origin, "friend-uid"),
      /UNVERIFIED_OWNER/);
});
test("invalid input is denied and no owner's identity is disclosed", async () => {
  await assert.rejects(
      readVerifiedPublicAlias(mockDb(fixture()), "@DEDA-INVALID-EXTRA", "viewer"),
      /ORIGINAL_ID_INVALID/);
  const empty = await readVerifiedPublicAlias(mockDb({}), origin, "viewer");
  assert.deepEqual(empty, {
    requestedId: origin, displayId: null,
    permanentColor: null, serverConfirmed: false,
  });
});
