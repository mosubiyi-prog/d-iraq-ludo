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

    await t.test("new staff privileges fail closed until matching gateway fully activated",async()=>{
      const uid="qa_cand_unbound_staff";
      const privateUid="qa_cand_private_user";
      const phone="9647712345689";
      const mail="qa.cand.staff@example.invalid";
      const inviteId="qa_cand_claimed_invite";
      const adminId="DEDA-ADM-CAND-INVITE";
      const user=env.authenticatedContext(uid,{email:mail}).firestore();
      const legacyUid="qa_cand_legacy_staff";
      const legacy=env.authenticatedContext(legacyUid,{
        email:"qa.cand.legacy@example.invalid",
      }).firestore();
      await env.withSecurityRulesDisabled(async ctx=>{
        const db=ctx.firestore();
        await Promise.all([
          db.doc("admins/"+uid).set({
            role:"employee",status:"active",active:true,
            inviteId,adminId,phone,email:mail,permissions:{viewUsers:true},
          }),
          db.doc("admins/"+legacyUid).set({
            role:"employee",status:"active",active:true,
            email:"qa.cand.legacy@example.invalid",
            permissions:{viewUsers:true},
          }),
          db.doc("admin_entry_access/"+phone).set({
            accountKey:phone,accessType:"member",adminUid:"",
            adminId,inviteId,allowedRole:"employee",
            allowedAdminEmail:mail,active:true,status:"invited",
          }),
          db.doc("admin_invites/"+inviteId).set({
            status:"claimed",claimedUid:uid,claimCode:"12345678",
            activationCode:"12345678",email:mail,role:"employee",
            phone,adminId,createdByUid:managerUid,
          }),
          db.doc("users/"+privateUid).set({
            accountKey:"9647712345900",name:"Synthetic private user",
          }),
        ]);
      });
      const privateRef="users/"+privateUid;
      const F=require("firebase/compat/app").firestore.FieldValue;
      await assertFails(user.doc(privateRef).get());
      await assertSucceeds(legacy.doc(privateRef).get());

      await assertFails(user.doc("owner_place_notifications/qa_cand_prebind_notice").set({
  type:"admin_alert",accountKey:"9647712345900",
  ownerUid:"qa_private_owner",placeId:"qa_place_1",
  placeName:"QA place",approvalNumber:"",governorate:"Baghdad",
  titleAr:"تنبيه اختبار",titleEn:"Synthetic QA alert",
  bodyAr:"اختبار وهمي",bodyEn:"Synthetic QA only",
  sourceType:"admin",sourceId:"qa_alert",
  createdByUid:uid,
  createdByName:"QA Staff",createdByRole:"employee",
  createdAt:F.serverTimestamp(),
}));
      await assertSucceeds(legacy.doc("owner_place_notifications/qa_cand_legacy_notice").set({
  type:"admin_alert",accountKey:"9647712345900",
  ownerUid:"qa_private_owner",placeId:"qa_place_1",
  placeName:"QA place",approvalNumber:"",governorate:"Baghdad",
  titleAr:"تنبيه اختبار",titleEn:"Synthetic QA alert",
  bodyAr:"اختبار وهمي",bodyEn:"Synthetic QA only",
  sourceType:"admin",sourceId:"qa_alert",
  createdByUid:legacyUid,
  createdByName:"QA Staff",createdByRole:"employee",
  createdAt:F.serverTimestamp(),
}));

      // Exact client completion writes are allowed even while privilege
      // queries remain CLOSED; admin_entry_access.update uses isAdmin()
      // for the scoped self-bind, not hasAdminPermission().
      await assertSucceeds(user.runTransaction(async tx=>{
        const inviteRef=user.doc("admin_invites/"+inviteId);
        const entryRef=user.doc("admin_entry_access/"+phone);
        const auditRef=user.doc("admin_audit/qa_cand_staff_activation_audit");
        const invitation=await tx.get(inviteRef);
        const gateway=await tx.get(entryRef);
        assert.equal(invitation.data().claimedUid,uid);
        assert.equal(gateway.data().status,"invited");
        tx.update(entryRef,{
          adminUid:uid,adminId,status:"active",
          active:true,updatedAt:F.serverTimestamp(),
        });
        tx.update(inviteRef,{
          status:"completed",acceptedAt:F.serverTimestamp(),
          updatedAt:F.serverTimestamp(),
          activationCode:F.delete(),claimCode:F.delete(),
        });
        tx.set(auditRef,{
          action:"admin_invite_accepted",adminUid:uid,
          adminName:"QA staff",adminRole:"employee",inviteId,
          createdAt:F.serverTimestamp(),
        });
      }));
      await assertSucceeds(user.doc(privateRef).get());
      await assertSucceeds(legacy.doc(privateRef).get());

      await assertSucceeds(user.doc("owner_place_notifications/qa_cand_bound_notice").set({
  type:"admin_alert",accountKey:"9647712345900",
  ownerUid:"qa_private_owner",placeId:"qa_place_1",
  placeName:"QA place",approvalNumber:"",governorate:"Baghdad",
  titleAr:"تنبيه اختبار",titleEn:"Synthetic QA alert",
  bodyAr:"اختبار وهمي",bodyEn:"Synthetic QA only",
  sourceType:"admin",sourceId:"qa_alert",
  createdByUid:uid,
  createdByName:"QA Staff",createdByRole:"employee",
  createdAt:F.serverTimestamp(),
}));

      await assertSucceeds(manager.doc(privateRef).get());
      // A later access revocation must immediately close privileged reads.
      await env.withSecurityRulesDisabled(async ctx=>{
        await ctx.firestore().doc("admin_entry_access/"+phone)
          .update({active:false,status:"disabled"});
      });
      await assertFails(user.doc(privateRef).get());
      await assertFails(user.doc("owner_place_notifications/qa_cand_revoked_notice").set({
  type:"admin_alert",accountKey:"9647712345900",
  ownerUid:"qa_private_owner",placeId:"qa_place_1",
  placeName:"QA place",approvalNumber:"",governorate:"Baghdad",
  titleAr:"تنبيه اختبار",titleEn:"Synthetic QA alert",
  bodyAr:"اختبار وهمي",bodyEn:"Synthetic QA only",
  sourceType:"admin",sourceId:"qa_alert",
  createdByUid:uid,
  createdByName:"QA Staff",createdByRole:"employee",
  createdAt:F.serverTimestamp(),
}));
    });


    await t.test("missing role cannot inherit GM rights; explicit legacy aliases retain GM",async()=>{
      const missingUid="qa_candidate_roleless";
      const aliasUid="qa_candidate_explicit_alias";
      await env.withSecurityRulesDisabled(async ctx=>{
        const db=ctx.firestore();
        await Promise.all([
          db.doc("admins/"+missingUid).set({
            active:true,status:"active",email:"qa.roleless@example.invalid",
          }),
          db.doc("admins/"+aliasUid).set({
            active:true,status:"active",role:"manager",
            email:"qa.explicit.manager@example.invalid",
          }),
        ]);
      });
      const roleless=env.authenticatedContext(missingUid,{
        email:"qa.roleless@example.invalid",
      }).firestore();
      const alias=env.authenticatedContext(aliasUid,{
        email:"qa.explicit.manager@example.invalid",
      }).firestore();
      await assertFails(roleless.collection("admin_invites").get());
      await assertFails(roleless.collection("admins").get());
      await assertSucceeds(alias.collection("admin_invites").get());
      await assertSucceeds(manager.collection("admin_invites").get());
      console.log("PASS_CANDIDATE_DENIES_ROLELESS_GM_PRESERVES_EXPLICIT_LEGACY");
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
