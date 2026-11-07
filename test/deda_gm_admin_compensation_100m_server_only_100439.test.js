"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {OLD_CAP, NEW_CAP, ADDITION,
  allocateApprovedManagerCompensation: allocate} =
  require("../tools/deda_gm_admin_compensation_100m_server_only_100439.js");

const UID = "manager_owner_100439";
const walletPath = "deda_admin_diamond_wallets/" + UID;
const auditPath = "deda_gm_admin_compensation_allocations/" + UID;
const approvalPath = "deda_gm_admin_compensation_approvals/" + UID;
const now = new Date("2026-11-07T03:00:00Z");

class Ref { constructor(path) { this.path=path; } }
class FakeDB {
  constructor() {
    this.docs = new Map();
    this.writes = [];
  }
  collection(path) {
    return {doc: id => new Ref(path + "/" + id)};
  }
  put(path,data) { this.docs.set(path, structuredClone(data)); }
  get(path) { return this.docs.get(path); }
  async runTransaction(fn) {
    const queued = [];
    const tx = {
      get: async ref => {
        const value = this.docs.get(ref.path);
        return {exists: value !== undefined,
          data: () => value === undefined ? undefined : structuredClone(value)};
      },
      update: (ref, patch) => queued.push(["update",ref.path,patch]),
      create: (ref, value) => queued.push(["create",ref.path,value]),
      set: () => {throw Error("unexpected overwrite");},
    };
    const result = await fn(tx);
    for(const [kind,path,data] of queued) {
      if(kind==="create") {
        assert.ok(!this.docs.has(path));
        this.docs.set(path,structuredClone(data));
      } else {
        assert.ok(this.docs.has(path));
        this.docs.set(path,{...this.docs.get(path),...structuredClone(data)});
      }
      this.writes.push({kind,path});
    }
    return result;
  }
}
function fixture({balance=900000, approved=true, role="general_manager"} = {}) {
  const db = new FakeDB();
  db.put("admins/"+UID,{role,active:true,status:"active"});
  db.put(walletPath,{adminUid:UID,initialBalance:OLD_CAP,
    balance,createdAt:now});
  if(approved) db.put(approvalPath,{
    adminUid:UID,ownerApproved:true,provenanceReviewed:true,
    status:"approved",scope:"gm_admin_compensation_only",
    fromCapDiamonds:OLD_CAP,toCapDiamonds:NEW_CAP,addDiamonds:ADDITION,
    approvedBy:"owner-review-100439",
  });
  db.put("deda_diamond_gift_balances/@DEDA-ABC123",{balance:75});
  return db;
}
test("verified admin gift wallet ends with exactly 100m, crediting only the remaining shortfall", async()=>{
  const db=fixture();
  const result=await allocate(db,{uid:UID,now});
  assert.equal(result.diamondsAdded,99_100_000);
  assert.equal(result.balance,100_000_000);
  assert.equal(db.get(walletPath).initialBalance,100_000_000);
  assert.equal(db.get(walletPath).balance,100_000_000);
  assert.equal(db.get(auditPath).balanceBefore,900000);
  assert.equal(db.get(auditPath).balanceAfter,100_000_000);
  assert.equal(db.get(auditPath).addDiamonds,99_100_000);
  assert.equal(db.get(auditPath).capIncreaseDiamonds,99_000_000);
  assert.deepEqual(db.writes.map(x=>x.path),[walletPath,auditPath]);
  assert.equal(db.get("deda_diamond_gift_balances/@DEDA-ABC123").balance,75);
});
test("retries cannot mint twice, even if the manager spent diamonds afterwards",async()=>{
  const db=fixture({balance:100});
  await allocate(db,{uid:UID,now});
  db.put(walletPath,{...db.get(walletPath),balance:98_000_000});
  const beforeWrites=db.writes.length;
  const second=await allocate(db,{uid:UID,now});
  assert.equal(second.alreadyAllocated,true);
  assert.equal(second.diamondsAdded,0);
  assert.equal(second.balance,98_000_000);
  assert.equal(db.writes.length,beforeWrites);
});
test("no missing approval, no non-manager, no bogus wallet, no unknown UID",async()=>{
  for(const db of [
    fixture({approved:false}),fixture({role:"user"}),
    fixture({balance:-1}),fixture({balance:OLD_CAP+1})
  ]) {
    await assert.rejects(allocate(db,{uid:UID,now}), /gm-compensation-100m-denied/);
    assert.equal(db.writes.length,0);
  }
  const db=fixture();
  await assert.rejects(allocate(db,{uid:"fake",now}), /gm-compensation-100m-denied/);
  assert.equal(db.writes.length,0);
});
test("partial audit conflict fails closed without repairing or creating a second receipt",async()=>{
  const db=fixture();
  db.put(auditPath,{adminUid:UID,toCapDiamonds:NEW_CAP,addDiamonds:ADDITION});
  await assert.rejects(allocate(db,{uid:UID,now}), /allocation-receipt-wallet-conflict/);
  assert.equal(db.writes.length,0);
});
