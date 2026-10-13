"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {approvalNoticeFields, recordApprovalBellNotice} =
    require("../deda_owner_approval_bell.js");

const approved = {
  ownerUid: "user-firebase-uid",
  accountKey: "9647700000000",
  placeName: "صيدلية",
  approvalNumber: "DEDA-2026-0000017",
  approvalDate: "13/10/2026",
  governorate: "بغداد",
  status: "approved",
  requestType: "create",
};
const before = {status: "pending"};

class FakeDB {
  constructor() {
    this.rows = new Map();
  }
  collection(name) {
    assert.equal(name, "owner_place_notifications");
    return {doc: (id) => ({
      create: async (value) => {
        if (this.rows.has(id)) {
          const error = new Error("already exists");
          error.code = 6;
          throw error;
        }
        this.rows.set(id, value);
      },
    })};
  }
}

test("first approval creates a real record for the actual owner only", async () => {
  const item = approvalNoticeFields(before, approved, "approved_place_01");
  assert.equal(item.id, "heartbeat_approval_approved_place_01");
  assert.equal(item.data.accountKey, approved.accountKey);
  assert.equal(item.data.ownerUid, approved.ownerUid);
  assert.equal(item.data.placeName, "صيدلية");
  assert.equal(item.data.approvalNumber, approved.approvalNumber);
  assert.equal(item.data.titleAr, "تم اعتماد مكانك");
  assert.equal(item.data.createdAt, undefined);
});

test("rejected, pending, already approved and edits are not new approval", () => {
  for (const [prev, next] of [
    [before, {...approved, status: "rejected"}],
    [before, {...approved, status: "reviewing"}],
    [{status: "approved"}, approved],
    [before, {...approved, requestType: "update"}],
  ]) {
    assert.equal(approvalNoticeFields(prev, next, "approved_place_01"), null);
  }
});

test("incomplete or invalid owner details never create a notice", async () => {
  const db = new FakeDB();
  for (const invalid of [
    {...approved, accountKey: ""},
    {...approved, ownerUid: ""},
    {...approved, approvalNumber: ""},
    {...approved, placeName: ""},
  ]) {
    const result = await recordApprovalBellNotice(db, {
      before, after: invalid, requestId: "approved_place_01", stamp: "NOW",
    });
    assert.equal(result.outcome, "ignored");
  }
  assert.equal(db.rows.size, 0);
});

test("replayed triggers create one notice without overwriting read state", async () => {
  const db = new FakeDB();
  const args = {before, after: approved, requestId: "approved_place_01", stamp: "NOW"};
  const first = await recordApprovalBellNotice(db, args);
  assert.equal(first.outcome, "created");
  const id = "heartbeat_approval_approved_place_01";
  db.rows.get(id).readAt = "READ_BY_USER";
  const second = await recordApprovalBellNotice(db, args);
  assert.equal(second.outcome, "already-created");
  assert.equal(db.rows.get(id).readAt, "READ_BY_USER");
  assert.equal(db.rows.size, 1);
});

test("other database errors do not falsely claim success", async () => {
  const db = {collection: () => ({doc: () => ({create: async () => {
    const err = new Error("permission denied");
    err.code = 7;
    throw err;
  }})})};
  await assert.rejects(() => recordApprovalBellNotice(db, {
    before, after: approved, requestId: "approved_place_01", stamp: "NOW",
  }), /permission denied/);
});
