"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {createHash} = require("node:crypto");
const {createPrivate100AdminReader} =
  require("../tools/deda_stage19_private_exclusive_catalog_reader_2026_10_19.js");

class Ref {
  constructor(path) {this.path = path;}
  doc(id) {return new Ref(this.path + "/" + id);}
  collection(id) {return new Ref(this.path + "/" + id);}
}
class DummyDb {
  constructor() {this.docs = new Map(); this.reads = [];}
  collection(id) {return new Ref(id);}
  put(path, value) {this.docs.set(path, value);}
  runTransaction(fn) {
    return fn({
      get: async (ref) => {
        this.reads.push(ref.path);
        const row = this.docs.get(ref.path);
        return {exists: row !== undefined, data: () => row};
      },
    });
  }
}
const suffixes = Array.from({length:100}, (_, n) =>
  "A" + String(n+1).padStart(3,"0"));
const hash = (s) => createHash("sha256").update(s).digest("hex");
const orig = "@DEDA-X1Y2Z3", account = "account_A";
function setup(manager = true) {
  const db = new DummyDb();
  db.put("users/uid_A", {accountKey: account, sharePersonalId: orig});
  db.put("deda_sessions/uid_A", {uid: "uid_A", accountKey: account});
  db.put("deda_share_ids/" + orig, {
    kind: "personal", publicId: orig, active: true, ownerUid: "uid_A",
  });
  db.put("admins/uid_A", {active: true, status: "active",
    role: manager ? "general_manager" : "employee"});
  db.put("admin_entry_access/" + account, {
    accountKey: account, active: true, status: "active",
    allowedRole: manager ? "general_manager" : "employee",
    accessType: "general_manager_gateway",
  });
  return db;
}

test("read requires exactly 100 unique 4-12 char private suffixes", () => {
  assert.throws(() => createPrivate100AdminReader(setup(), suffixes.slice(1)),
    /owner-private-100-required/);
  assert.throws(() => createPrivate100AdminReader(
      setup(), [suffixes[0], ...suffixes.slice(0,99)]),
    /owner-private-100-required/);
  assert.throws(() => createPrivate100AdminReader(setup(), [
    ...suffixes.slice(0,99), "bad name",
  ]), /owner-private-100-required/);
});

test("unverified user or non-general manager cannot access private catalog", async () => {
  const db = setup(false);
  const reader = createPrivate100AdminReader(db,suffixes);
  await assert.rejects(reader.readForGeneralManager("uid_A"),
    /verified-general-manager-only/);
  assert.equal(db.reads.filter(x =>
    x.startsWith("deda_owned_identifier_registry/")).length, 0);
  const unknown = createPrivate100AdminReader(setup(),suffixes);
  await assert.rejects(unknown.readForGeneralManager("not_logged_in"),
    /verified-admin-session-required/);
});

test("active verified general manager sees 100 IDs once in exact private source order", async () => {
  const db = setup();
  const result = await createPrivate100AdminReader(db,suffixes)
    .readForGeneralManager("uid_A");
  assert.equal(result.serverConfirmed, true);
  assert.equal(result.total, 100);
  assert.equal(result.identifiers.length, 100);
  assert.equal(result.identifiers[0].sequence, 1);
  assert.equal(result.identifiers[0].identifier, "@DEDA-A001");
  assert.equal(result.identifiers[99].identifier, "@DEDA-A100");
  assert.equal(result.identifiers[0].status, "available");
  assert.equal(result.identifiers[0].permanentColor, null);
  assert.deepEqual(result.history, []);
});

test("gifted identifier keeps one permanent color and has immutable dated history", async () => {
  const db = setup();
  const id = "@DEDA-A001", recipient = "@DEDA-Z9Y8X7", recipientKey="account_B";
  db.put("deda_owned_identifier_registry/" + id, {
    identifier:id, accountKey: recipientKey, originalId:recipient,
    status:"owned", acquisition:"general_manager_gift", assignedColor:"royal",
  });
  db.put("deda_owned_identifier_aliases/" + id, {
    identifier:id, accountKey: recipientKey, originalId:recipient,
    kind:"permanent_alias",
  });
  db.put("deda_admin_identifier_grants/" + hash(recipientKey + ":" + id), {
    accountKey:recipientKey, identifier:id, originalId:recipient,
    color:"royal",createdAt:new Date("2026-10-19T11:00:00.000Z"),
  });
  const result = await createPrivate100AdminReader(db,suffixes)
    .readForGeneralManager("uid_A");
  assert.equal(result.identifiers[0].status,"gifted");
  assert.equal(result.identifiers[0].permanentColor,"royal");
  assert.equal(result.identifiers[0].ownerOriginalId,recipient);
  assert.deepEqual(result.history, [{
    identifier:id, recipientOriginalId:recipient, color:"royal",
    kind:"gifted",grantedAt:"2026-10-19T11:00:00.000Z",
  }]);
});

test("tampered fixed color or missing audit receipt fail closed", async () => {
  const db=setup(), id="@DEDA-A001";
  db.put("deda_owned_identifier_aliases/" + id, {
    identifier:id, accountKey:"account_B",
    originalId:"@DEDA-Z9Y8X7", kind:"permanent_alias",
  });
  db.put("deda_owned_identifier_registry/"+id,{
    identifier:id,status:"owned",accountKey:"account_B",
    originalId:"@DEDA-Z9Y8X7",assignedColor:"purple",
    acquisition:"general_manager_gift",
  });
  const r=createPrivate100AdminReader(db,suffixes);
  await assert.rejects(r.readForGeneralManager("uid_A"),
    /invalid-exclusive-color-or-ownership/);
  db.put("deda_owned_identifier_registry/"+id,{
    identifier:id,status:"owned",accountKey:"account_B",
    originalId:"@DEDA-Z9Y8X7",assignedColor:"pink",
    acquisition:"general_manager_gift",
  });
  await assert.rejects(r.readForGeneralManager("uid_A"),
    /exclusive-grant-audit-proof-missing/);
});

test("expired session denies catalog before reading confidential identifiers", async () => {
  const db=setup();
  db.put("deda_sessions/uid_A", {uid:"uid_B",accountKey:account});
  await assert.rejects(createPrivate100AdminReader(db,suffixes)
      .readForGeneralManager("uid_A"),
    /verified-admin-session-required/);
  assert.equal(db.reads.filter(x=>
    x.startsWith("deda_owned_identifier_registry/")).length,0);
});

test("production Cloud Functions do not import stage19 exclusive catalogue", () => {
  const fs=require("node:fs");
  const live=fs.readFileSync("functions/index.js","utf8");
  assert.equal(live.includes("deda_stage19_private_exclusive_catalog_reader"),false);
});
