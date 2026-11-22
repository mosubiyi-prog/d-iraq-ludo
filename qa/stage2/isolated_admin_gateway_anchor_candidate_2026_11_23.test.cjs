"use strict";
/* Synthetic TEST ONLY: a candidate Firestore rules file produced outside repo.
 * This is not an approved production ruleset or a Firebase deployment.
 */
const fs = require("node:fs");
const assert = require("node:assert/strict");
const {test} = require("node:test");
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require("@firebase/rules-unit-testing");

const project = "demo-deda-stage2-isolated-admin-anchor-qa";
const primary = "9647712345678";
const second = "9647712345679";
const third = "9647712345680";
const staffPhone = "9647712345681";
const managerUid = "qa_anchor_manager";
const outsiderUid = "qa_anchor_outsider";

test("candidate rules protect one immutable GM gateway against all clients",{
  timeout: 180000,
},async(t)=>{
  assert.equal(process.env.DEDA_EMULATOR_ONLY,"true");
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST,"127.0.0.1:8097");
  const path = process.env.DEDA_ADMIN_CANDIDATE_RULES_PATH;
  assert.ok(path && fs.existsSync(path),"candidate must be materialized outside repo");
  const env = await initializeTestEnvironment({
    projectId:project,
    firestore:{
      rules:fs.readFileSync(path,"utf8"),
      host:"127.0.0.1",port:8097,
    },
  });
  const manager = env.authenticatedContext(managerUid, {
    email:"qa.anchor.manager@example.invalid",
  }).firestore();
  const outsider = env.authenticatedContext(outsiderUid).firestore();
  const memberEntry = {
    accountKey:staffPhone, accessType:"member",
    allowedRole:"employee", allowedAdminEmail:"staff@example.invalid",
    status:"active",active:true,adminUid:"qa_anchor_staff",
    adminId:"DEDA-ADM-001",managedByUid:managerUid,
  };
  function managerEntry(phone){
    return {
      accountKey:phone,accessType:"general_manager_gateway",
      allowedRole:"general_manager",active:true,status:"active",
      managedByUid:managerUid,
    };
  }
  try{
    await env.withSecurityRulesDisabled(async ctx=>{
      const db=ctx.firestore();
      await Promise.all([
        db.doc("admins/"+managerUid).set({
          role:"general_manager",status:"active",active:true,
        }),
        db.doc("admin_gateway_protection/primary").set({
          accountKey:primary,createdBy:"trusted_migration",
        }),
        db.doc("admin_entry_access/"+primary).set(managerEntry(primary)),
        db.doc("admin_entry_access/"+second).set(managerEntry(second)),
        db.doc("admin_entry_access/"+staffPhone).set(memberEntry),
      ]);
    });
    await t.test("only trusted admin SDK can set or move the immutable anchor",async()=>{
      await assertSucceeds(manager.doc("admin_gateway_protection/primary").get());
      await assertFails(outsider.doc("admin_gateway_protection/primary").get());
      await assertFails(manager.doc("admin_gateway_protection/primary").update({
        accountKey:second,
      }));
      await assertFails(manager.doc("admin_gateway_protection/primary").delete());
      await assertFails(manager.doc("admin_gateway_protection/new").set({
        accountKey:third,
      }));
    });
    await t.test("GM cannot delete or suspend the protected primary gateway",async()=>{
      await assertFails(manager.doc("admin_entry_access/"+primary).delete());
      await assertFails(manager.doc("admin_entry_access/"+primary).update({
        status:"disabled",active:false,
      }));
      const live=await assertSucceeds(
        manager.doc("admin_entry_access/"+primary).get());
      assert.equal(live.data().status,"active");
    });
    await t.test("GM can remove other manager door and a subordinate member door",async()=>{
      await assertSucceeds(manager.doc("admin_entry_access/"+second).delete());
      await assertSucceeds(manager.doc("admin_entry_access/"+staffPhone).delete());
      assert.equal((await manager.doc("admin_entry_access/"+primary).get()).exists,true);
    });
    await t.test("missing anchor fails closed instead of allowing last gateway deletion",async()=>{
      await env.withSecurityRulesDisabled(async ctx=>{
        await ctx.firestore().doc("admin_gateway_protection/primary").delete();
        await ctx.firestore().doc("admin_entry_access/"+third)
          .set(managerEntry(third));
      });
      await assertFails(manager.doc("admin_entry_access/"+primary).delete());
      await assertFails(manager.doc("admin_entry_access/"+third).delete());
      await assertFails(manager.doc("admin_entry_access/"+third).update({
        status:"disabled",active:false,
      }));
    });
  }finally{await env.cleanup();}
});
