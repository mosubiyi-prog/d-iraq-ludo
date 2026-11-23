"use strict";
/*
 * Isolated Users card rules QA. Real repository rules, disposable emulator,
 * synthetic accounts only. No user data, Firebase production or Play.
 */
const fs = require("node:fs");
const assert = require("node:assert/strict");
const {test} = require("node:test");
const firebase = require("firebase/compat/app");
require("firebase/compat/firestore");
const {initializeTestEnvironment,assertSucceeds,assertFails} =
    require("@firebase/rules-unit-testing");

const managerUid="qa_users_manager_20261123";
const staffUid="qa_users_staff_20261123";
const publicUid="qa_users_profile_20261123";
const outsiderUid="qa_users_outsider_20261123";
const accountKey="9647700000000";
const stamp=()=>firebase.firestore.FieldValue.serverTimestamp();

test("stage2 users read-only directory, linked history and audited view",{
  timeout:180000,
},async t=>{
  assert.equal(process.env.DEDA_EMULATOR_ONLY,"true");
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST,"127.0.0.1:8097");
  const env=await initializeTestEnvironment({
    projectId:"demo-deda-stage2-isolated-admin-private-qa",
    firestore:{rules:fs.readFileSync("firestore.rules","utf8"),
      host:"127.0.0.1",port:8097},
  });
  const manager=env.authenticatedContext(managerUid).firestore();
  const staff=env.authenticatedContext(staffUid).firestore();
  const user=env.authenticatedContext(publicUid).firestore();
  const outsider=env.authenticatedContext(outsiderUid).firestore();
  const userPath="users/"+publicUid;
  const placePath="published_places/qa_private_place";
  const requestPath="place_requests/qa_user_request";
  const supportPath="support_requests/qa_user_support";
  try {
    await env.withSecurityRulesDisabled(async ctx=>{
      const db=ctx.firestore();
      await Promise.all([
        db.doc("admins/"+managerUid).set({
          active:true,status:"active",role:"general_manager",
        }),
        db.doc("admins/"+staffUid).set({
          active:true,status:"active",role:"employee",
          permissions:{viewUsers:true},
        }),
        db.doc(userPath).set({
          name:"QA customer",phone:"07700000000",
          accountType:"member",accountKey,
        }),
        db.doc(placePath).set({
          placeName:"Private synthetic place",ownerUid:publicUid,
          accountKey,published:false,approvalNumber:"QA-1",
        }),
        db.doc(requestPath).set({
          placeName:"Synthetic request",ownerUid:publicUid,
          accountKey,status:"pending",createdAt:stamp(),
        }),
        db.doc(supportPath).set({
          message:"Synthetic support message",ownerUid:publicUid,
          accountKey,status:"new",createdAt:stamp(),
        }),
      ]);
    });

    await t.test("only a privileged admin can enumerate the directory",async()=>{
      const byId=firebase.firestore.FieldPath.documentId();
      await assertSucceeds(manager.collection("users")
        .orderBy(byId).limit(50).get());
      await assertSucceeds(staff.collection("users")
        .orderBy(byId).limit(50).get());
      await assertFails(outsider.collection("users").get());
      await assertSucceeds(user.doc(userPath).get());
      await assertFails(outsider.doc(userPath).get());
    });

    await t.test("GM can read linked user history, but staff cannot escalate",async()=>{
      for(const [collection,path] of [
        ["published_places",placePath],
        ["place_requests",requestPath],
        ["support_requests",supportPath],
      ]){
        await assertSucceeds(manager.doc(path).get());
        await assertSucceeds(manager.collection(collection)
          .where("ownerUid","==",publicUid).limit(50).get());
        await assertSucceeds(manager.collection(collection)
          .where("accountKey","==",accountKey).limit(50).get());
        await assertFails(staff.collection(collection)
          .where("ownerUid","==",publicUid).limit(50).get());
      }
    });

    await t.test("audited read cannot mutate public user or forge admin identity",async()=>{
      const auditPath="admin_audit/qa_user_read_only_receipt";
      await assertSucceeds(manager.doc(auditPath).set({
        action:"read_user_account",ownerUid:publicUid,
        sourceCollection:"users",sourceId:publicUid,
        adminUid:managerUid,adminRole:"general_manager",
        createdAt:stamp(),
      }));
      await assertFails(outsider.doc("admin_audit/qa_user_forged_read").set({
        action:"read_user_account",ownerUid:publicUid,
        adminUid:managerUid,createdAt:stamp(),
      }));
      await assertFails(manager.doc(userPath).update({
        name:"illicit admin profile write",
      }));
      await assertFails(manager.doc(userPath).delete());
      const current=await assertSucceeds(user.doc(userPath).get());
      assert.equal(current.data().name,"QA customer");
      const receipt=await assertSucceeds(manager.doc(auditPath).get());
      assert.equal(receipt.data().adminUid,managerUid);
    });
  }finally{
    await env.cleanup();
  }
});
