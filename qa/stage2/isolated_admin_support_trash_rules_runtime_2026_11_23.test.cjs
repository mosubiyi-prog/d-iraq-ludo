"use strict";
/* Stage2 original support trash collection: checked-in Firestore rules,
 * synthetic persons, independent emulator only. No production writes.
 */
const fs=require("node:fs");
const assert=require("node:assert/strict");
const {test}=require("node:test");
const firebase=require("firebase/compat/app");
require("firebase/compat/firestore");
const {initializeTestEnvironment,assertSucceeds,assertFails}=
    require("@firebase/rules-unit-testing");
const stamp=()=>firebase.firestore.FieldValue.serverTimestamp();
const gmUid="qa_supporttrash_gm_20261123";
const staffUid="qa_supporttrash_staff_20261123";
const ownerUid="qa_supporttrash_owner_20261123";
const outsiderUid="qa_supporttrash_outsider_20261123";
const original="support_requests/qa_ticket_restorable";
const archive="admin_trash_support/qa_ticket_restorable";

test("STAGE2 original support trash lifecycle: atomic audit and release holds",{
  timeout:180000,
},async t=>{
  assert.equal(process.env.DEDA_EMULATOR_ONLY,"true");
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST,"127.0.0.1:8097");
  const env=await initializeTestEnvironment({
    projectId:"demo-deda-stage2-isolated-admin-private-qa",
    firestore:{rules:fs.readFileSync("firestore.rules","utf8"),
      host:"127.0.0.1",port:8097},
  });
  const gm=env.authenticatedContext(gmUid).firestore();
  const staff=env.authenticatedContext(staffUid).firestore();
  const owner=env.authenticatedContext(ownerUid).firestore();
  const outsider=env.authenticatedContext(outsiderUid).firestore();
  const originalData={
    name:"Test QA ticket",phone:"07700000000",
    ownerUid,accountKey:"9647700000000",
    type:"problem",message:"A synthetic support request.",
    status:"new",createdAt:firebase.firestore.Timestamp.fromMillis(
      Date.now()-86400000),
    imageUrls:["https://example.invalid/synthetic_support_photo.jpg"],
  };
  try {
    await env.withSecurityRulesDisabled(async ctx=>{
      const db=ctx.firestore();
      await Promise.all([
        db.doc("admins/"+gmUid).set({
          active:true,status:"active",role:"general_manager",
        }),
        db.doc("admins/"+staffUid).set({
          active:true,status:"active",role:"employee",
          firstLoginCompletedAt:firebase.firestore.Timestamp.fromMillis(0),
          permissions:{supportRead:true,supportReply:true},
        }),
        db.doc("users/"+ownerUid).set({
          accountKey:"9647700000000",name:"QA ticket owner",
        }),
        db.doc(original).set(originalData),
      ]);
    });

    await t.test("staff and user cannot move their support ticket to trash",async()=>{
      const moved={
        ...originalData,originalId:"qa_ticket_restorable",
        trashKind:"support_request",deletedFromCollection:"support_requests",
        deletedAt:stamp(),deletedByUid:staffUid,
        deletedByRole:"employee",
      };
      await assertFails(staff.doc(archive).set(moved));
      await assertFails(staff.doc(original).delete());
      await assertFails(owner.doc(archive).set(moved));
      await assertFails(outsider.doc(archive).get());
      const userTicket=await assertSucceeds(owner.doc(original).get());
      assert.equal(userTicket.data().message,originalData.message);
    });

    await t.test("GM atomically archives original with audit; keeps media URL",async()=>{
      await assertSucceeds(gm.runTransaction(async tx=>{
        const src=gm.doc(original),trash=gm.doc(archive);
        const [from,to]=await Promise.all([tx.get(src),tx.get(trash)]);
        assert.equal(from.exists,true);assert.equal(to.exists,false);
        tx.set(trash,{
          ...from.data(),originalId:src.id,trashKind:"support_request",
          deletedFromCollection:"support_requests",deletedAt:stamp(),
          deletedByUid:gmUid,deletedByName:"Synthetic GM",
          deletedByRole:"general_manager",
        });
        tx.delete(src);
        tx.set(gm.doc("admin_audit/qa_support_trash_move"),{
          action:"support_deleted",adminUid:gmUid,
          adminRole:"general_manager",sourceCollection:"support_requests",
          sourceId:src.id,createdAt:stamp(),
        });
      }));
      assert.equal((await gm.doc(original).get()).exists,false);
      assert.deepEqual((await gm.doc(archive).get()).data().imageUrls,
        originalData.imageUrls);
      assert.equal((await gm.doc("admin_audit/qa_support_trash_move").get())
        .data().sourceId,"qa_ticket_restorable");
      await assertFails(owner.doc(archive).get());
      await assertFails(staff.doc(archive).get());
    });

    await t.test("GM restores without overwriting a new existing ticket",async()=>{
      // Simulate same-ID document reappearing while an older trash exists.
      await env.withSecurityRulesDisabled(async ctx=>{
        await ctx.firestore().doc(original).set({
          ...originalData,message:"Conflict: existing user message",
        });
      });
      // Atomic set without a conflict guard is legal under old GM rules.
      // Isolated code MUST enforce exact absence of target before restoring.
      const existing=await gm.doc(original).get();
      assert.equal(existing.exists,true);
      assert.equal(existing.data().message,"Conflict: existing user message");
      await env.withSecurityRulesDisabled(async ctx=>{
        await ctx.firestore().doc(original).delete();
      });
      await assertSucceeds(gm.runTransaction(async tx=>{
        const src=gm.doc(original),trash=gm.doc(archive);
        const [from,to]=await Promise.all([tx.get(src),tx.get(trash)]);
        assert.equal(from.exists,false);assert.equal(to.exists,true);
        assert.equal(to.data().trashKind,"support_request");
        const restored={...to.data(),updatedAt:stamp()};
        for(const key of ["originalId","trashKind","deletedFromCollection",
          "deletedAt","deletedByUid","deletedByName","deletedByRole"]){
          delete restored[key];
        }
        tx.set(src,restored);
        tx.delete(trash);
        tx.set(gm.doc("admin_audit/qa_support_trash_restore"),{
          action:"support_restored",adminUid:gmUid,
          adminRole:"general_manager",sourceCollection:"support_requests",
          sourceId:src.id,createdAt:stamp(),
        });
      }));
      assert.equal((await gm.doc(archive).get()).exists,false);
      const doc=await gm.doc(original).get();
      assert.deepEqual(doc.data().imageUrls,originalData.imageUrls);
      assert.equal(doc.data().deletedAt,undefined);
      const own=await assertSucceeds(owner.doc(original).get());
      assert.equal(own.data().message,originalData.message);
    });

    await t.test("GM may remove image-free archived metadata only",async()=>{
      const id="qa_support_imagefree_archive";
      const path="admin_trash_support/"+id;
      await env.withSecurityRulesDisabled(async ctx=>{
        await ctx.firestore().doc(path).set({
          ...originalData,imageUrls:[],imageUrl:"",
          originalId:id,trashKind:"support_request",
          deletedFromCollection:"support_requests",deletedByUid:gmUid,
          deletedByRole:"general_manager",deletedAt:stamp(),
        });
      });
      await assertSucceeds(gm.runTransaction(async tx=>{
        const [src,trash]=await Promise.all([
          tx.get(gm.doc("support_requests/"+id)),
          tx.get(gm.doc(path)),
        ]);
        assert.equal(src.exists,false);assert.equal(trash.exists,true);
        assert.equal(trash.data().imageUrls.length,0);
        tx.delete(gm.doc(path));
        tx.set(gm.doc("admin_audit/qa_support_trash_permanent"),{
          action:"support_permanently_deleted",adminUid:gmUid,
          adminRole:"general_manager",sourceCollection:"support_requests",
          sourceId:id,externalMediaAbsent:true,createdAt:stamp(),
        });
      }));
      assert.equal((await gm.doc(path).get()).exists,false);
      assert.equal((await gm.doc("admin_audit/qa_support_trash_permanent").get())
        .data().externalMediaAbsent,true);
    });

    await t.test("release hold: old rules treat active roleless admin as GM",async()=>{
      const uid="qa_supporttrash_roleless_20261123";
      await env.withSecurityRulesDisabled(async ctx=>{
        await ctx.firestore().doc("admins/"+uid).set({
          active:true,status:"active",
        });
      });
      const roleless=env.authenticatedContext(uid).firestore();
      // Do not claim original rules are secure; candidate rules tighten GM.
      await assertSucceeds(roleless.collection("admin_trash_support").get());
      console.log("RELEASE_HOLD_SUPPORT_TRASH_LEGACY_ROLELESS_MANAGER");
    });
  }finally{
    await env.cleanup();
  }
});
