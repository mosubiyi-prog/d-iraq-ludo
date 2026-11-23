"use strict";
/* Read-state parity of the original support/place inbox: real checked-in
 * Firestore rules on a disposable local emulator. All records are synthetic.
 */
const fs=require("node:fs");
const assert=require("node:assert/strict");
const {test}=require("node:test");
const firebase=require("firebase/compat/app");
require("firebase/compat/firestore");
const {initializeTestEnvironment,assertSucceeds,assertFails}=
    require("@firebase/rules-unit-testing");
const stamp=()=>firebase.firestore.FieldValue.serverTimestamp();
const gmUid="qa_view_gm_20261123";
const staffUid="qa_view_staff_20261123";
const ownerUid="qa_view_customer_20261123";
const outsiderUid="qa_view_outsider_20261123";
const support="support_requests/qa_view_support";
const place="place_requests/qa_view_place";

test("stage2 inbox firstViewed/lastViewed with audit, never public UID writes",{
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
  try{
    await env.withSecurityRulesDisabled(async ctx=>{
      const db=ctx.firestore();
      const created=firebase.firestore.Timestamp.fromMillis(
        Date.now()-60*60*1000);
      await Promise.all([
        db.doc("admins/"+gmUid).set({
          active:true,status:"active",role:"general_manager",
        }),
        db.doc("admins/"+staffUid).set({
          active:true,status:"active",role:"employee",
          firstLoginCompletedAt:firebase.firestore.Timestamp.fromMillis(0),
          permissions:{supportRead:true,viewPlaceRequests:true},
        }),
        db.doc("users/"+ownerUid).set({
          accountKey:"9647700000000",name:"QA owner",
        }),
        db.doc(support).set({
          name:"QA owner",ownerUid,accountKey:"9647700000000",
          type:"problem",status:"new",message:"Synthetic QA message.",
          createdAt:created,
        }),
        db.doc(place).set({
          placeName:"QA place",ownerUid,accountKey:"9647700000000",
          status:"pending",governorate:"Kirkuk",createdAt:created,
        }),
      ]);
    });

    async function recordView(db,path,uid,auditId,role){
      const doc=db.doc(path),audit=db.doc("admin_audit/"+auditId);
      return db.runTransaction(async tx=>{
        const snap=await tx.get(doc);
        assert.equal(snap.exists,true);
        assert.equal(snap.data().firstViewedAt,undefined);
        tx.update(doc,{
          firstViewedAt:stamp(),firstViewedByUid:uid,
          firstViewedByName:"QA Admin",firstViewedByRole:role,
          lastViewedAt:stamp(),lastViewedByUid:uid,
          lastViewedByName:"QA Admin",lastViewedByRole:role,
        });
        tx.set(audit,{
          action:"request_viewed",adminUid:uid,adminName:"QA Admin",
          adminRole:role,sourceCollection:path.split("/")[0],
          sourceId:path.split("/")[1],createdAt:stamp(),
        });
      });
    }

    await t.test("GM opens support, first/last view saved with atomic audit",async()=>{
      await assertSucceeds(recordView(gm,support,gmUid,"qa_first_support","general_manager"));
      const now=await assertSucceeds(gm.doc(support).get());
      assert.equal(now.data().firstViewedByUid,gmUid);
      assert.equal(now.data().lastViewedByUid,gmUid);
      const audit=await assertSucceeds(gm.doc("admin_audit/qa_first_support").get());
      assert.equal(audit.data().action,"request_viewed");
      assert.equal(audit.data().sourceCollection,"support_requests");
      assert.equal((await assertSucceeds(owner.doc(support).get()))
        .data().firstViewedByUid,gmUid);
    });

    await t.test("release hold: original place rules exceed evaluation budget for staff",async()=>{
      // This is a verified rules limitation, not a permission grant.
      // Do not silently mark a scoped staff view as successful.
      await assertFails(recordView(staff,place,staffUid,
        "qa_forbidden_staff_first_view","employee"));
      assert.equal((await gm.doc(place).get()).data().firstViewedAt,undefined);
      console.log("RELEASE_HOLD_STAFF_PLACE_FIRST_VIEW_RULES_EXPR_LIMIT");
    });

    await t.test("GM opens place with first/last view and atomic audit",async()=>{
      await assertSucceeds(recordView(gm,place,gmUid,
        "qa_first_place","general_manager"));
      const now=await assertSucceeds(gm.doc(place).get());
      assert.equal(now.data().firstViewedByRole,"general_manager");
      const audit=await assertSucceeds(gm.doc("admin_audit/qa_first_place").get());
      assert.equal(audit.data().adminUid,gmUid);
    });

    await t.test("owner and outsider cannot forge admin viewed metadata",async()=>{
      await assertFails(owner.doc(support).update({
        firstViewedByUid:ownerUid,lastViewedByUid:ownerUid,
      }));
      await assertFails(owner.doc(place).update({
        firstViewedAt:stamp(),firstViewedByUid:ownerUid,
      }));
      await assertFails(outsider.doc(support).update({
        firstViewedAt:stamp(),firstViewedByUid:outsiderUid,
      }));
      await assertFails(outsider.doc("admin_audit/qa_forged_view").set({
        action:"request_viewed",adminUid:gmUid,createdAt:stamp(),
      }));
      assert.equal((await gm.doc(support).get()).data().firstViewedByUid,gmUid);
      assert.equal((await gm.doc(place).get()).data().firstViewedByUid,gmUid);
    });
  }finally{
    await env.cleanup();
  }
});
