"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {createHash} = require("node:crypto");
const {createStage19ManagerActions} =
  require("../tools/deda_stage19_private_fixed_color_manager_actions_2026_10_19.js");

class Ref {
  constructor(path) {this.path = path;}
  doc(id) {return new Ref(this.path + "/" + id);}
  collection(id) {return new Ref(this.path + "/" + id);}
}
class MemoryDb {
  constructor() {this.docs=new Map();}
  collection(id) {return new Ref(id);}
  put(path,row) {this.docs.set(path,structuredClone(row));}
  peek(path) {return this.docs.get(path);}
  async runTransaction(fn) {
    const pending=[];
    const tx={
      get: async ref=>{
        const x=this.docs.get(ref.path);
        return {exists:x!==undefined,data:()=>structuredClone(x)};
      },
      create:(ref,value)=>pending.push(["create",ref.path,value]),
      update:(ref,value)=>pending.push(["update",ref.path,value]),
    };
    const result=await fn(tx);
    for(const [op,path] of pending) {
      if(op==="create" && this.docs.has(path))throw Error("concurrent-create");
      if(op==="update" && !this.docs.has(path))throw Error("update-missing");
    }
    for(const [op,path,value] of pending) {
      this.docs.set(path,structuredClone(
        op==="create" ? value : {...this.docs.get(path),...value}));
    }
    return result;
  }
}
const names=Array.from({length:100},(_,n)=>
  "A"+String(n+1).padStart(3,"0"));
const id="@DEDA-A001";
const orig="@DEDA-X1Y2Z3",recipientOrig="@DEDA-Z9Y8X7";
const key="account_A", recipientKey="account_B";
const hash=s=>createHash("sha256").update(s).digest("hex");

function seed() {
  const db=new MemoryDb();
  db.put("users/uid_A",{accountKey:key,sharePersonalId:orig});
  db.put("deda_sessions/uid_A",{uid:"uid_A",accountKey:key});
  db.put("deda_share_ids/"+orig,{
    kind:"personal",active:true,publicId:orig,ownerUid:"uid_A",
  });
  db.put("admin_entry_access/"+key,{
    accountKey:key,active:true,status:"active",
    allowedRole:"general_manager",accessType:"general_manager_gateway",
  });
  db.put("users/uid_B",{accountKey:recipientKey,sharePersonalId:recipientOrig});
  db.put("deda_share_ids/"+recipientOrig,{
    kind:"personal",active:true,publicId:recipientOrig,ownerUid:"uid_B",
  });
  return db;
}
const actions=db=>createStage19ManagerActions(db,names);

test("owner-private 100 mandatory, only catalog-listed four colors allowed", async()=>{
  assert.throws(()=>createStage19ManagerActions(seed(), names.slice(0,99)),
    /verified-private-100-admin-catalog-required/);
  const db=seed();
  await assert.rejects(actions(db).selfUse({
    adminUid:"uid_A",identifier:"@DEDA-OUTSIDE",color:"gold",
  }), /invalid-admin-reserved-id-or-color/);
  await assert.rejects(actions(db).selfUse({
    adminUid:"uid_A",identifier:id,color:"orange",
  }), /invalid-admin-reserved-id-or-color/);
});

test("self-use atomically locks chosen permanent color and keeps original ID",async()=>{
  const db=seed();
  const result=await actions(db).selfUse({
    adminUid:"uid_A",identifier:id,color:"diamond",
  });
  assert.equal(result.serverConfirmed,true);
  assert.equal(result.permanentColor,"diamond");
  const registry=db.peek("deda_owned_identifier_registry/"+id);
  assert.equal(registry.assignedColor,"diamond");
  assert.equal(registry.acquisition,"general_manager_self_use");
  assert.equal(db.peek("deda_owned_identifier_aliases/"+id).originalId,orig);
  const ledger=db.peek("deda_owned_identifier_accounts/"+hash(key));
  assert.deepEqual(ledger.ownedIds,[orig,id]);
  assert.equal(ledger.activeId,id);
  const history=db.peek("deda_admin_identifier_grants/"+hash(key+":"+id));
  assert.equal(history.kind,"self_used");
  assert.equal(history.color,"diamond");
  assert.ok(history.createdAt instanceof Date);
  assert.equal(db.peek("users/uid_A").sharePersonalId,orig);
});

test("second self-use can never change color or grant same ID twice",async()=>{
  const db=seed(),svc=actions(db);
  await svc.selfUse({adminUid:"uid_A",identifier:id,color:"royal"});
  await assert.rejects(svc.selfUse({
    adminUid:"uid_A",identifier:id,color:"pink",
  }),/exclusive-id-used-or-gifted/);
  assert.equal(db.peek("deda_owned_identifier_registry/"+id).assignedColor,
    "royal");
});

test("revoked or unauthorized manager may not reserve or lock color",async()=>{
  const db=seed();
  db.put("admin_entry_access/"+key,{
    accountKey:key,active:true,status:"active",
    allowedRole:"employee",accessType:"general_manager_gateway",
  });
  await assert.rejects(actions(db).selfUse({
    adminUid:"uid_A",identifier:id,color:"gold",
  }),/verified-general-manager-required/);
  assert.equal(db.peek("deda_owned_identifier_registry/"+id),undefined);
});

test("manager gift locks exact color for verified recipient only",async()=>{
  const db=seed();
  const result=await actions(db).gift({
    adminUid:"uid_A",recipientOriginalId:recipientOrig,
    identifier:id,color:"pink",
  });
  assert.equal(result.serverConfirmed,true);
  assert.equal(result.permanentColor,"pink");
  const registry=db.peek("deda_owned_identifier_registry/"+id);
  assert.equal(registry.assignedColor,"pink");
  assert.equal(registry.accountKey,recipientKey);
  assert.equal(registry.acquisition,"general_manager_gift");
  const target=db.peek("deda_owned_identifier_accounts/"+hash(recipientKey));
  assert.deepEqual(target.ownedIds,[recipientOrig,id]);
  assert.equal(target.activeId,recipientOrig);
  assert.equal(db.peek("deda_admin_identifier_grants/"+
    hash(recipientKey+":"+id)).color,"pink");
});

test("previous gifted ID cannot be re-gifted with another color",async()=>{
  const db=seed(),svc=actions(db);
  await svc.gift({adminUid:"uid_A",recipientOriginalId:recipientOrig,
    identifier:id,color:"gold"});
  await assert.rejects(svc.gift({
    adminUid:"uid_A",recipientOriginalId:orig,identifier:id,color:"pink",
  }),/identifier-globally-reserved-or-owned/);
  assert.equal(db.peek("deda_owned_identifier_registry/"+id).assignedColor,"gold");
});

test("no stage19 grants exported through production functions",()=>{
  const fs=require("node:fs");
  assert.ok(!fs.readFileSync("functions/index.js","utf8")
    .includes("deda_stage19_private_fixed_color_manager_actions"));
});
