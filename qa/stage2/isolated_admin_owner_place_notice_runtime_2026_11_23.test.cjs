"use strict";
/*
 * Stage2 manual owner notice: checked-in Firestore rules on throwaway emulator.
 * Synthetic actors/places only. Deliberately exposes legacy rule gap;
 * never enables isolated admin feature or changes production rules.
 */
const fs=require("node:fs");
const assert=require("node:assert/strict");
const {test}=require("node:test");
const firebase=require("firebase/compat/app");
require("firebase/compat/firestore");
const {initializeTestEnvironment,assertSucceeds,assertFails}=
    require("@firebase/rules-unit-testing");
const sent=()=>firebase.firestore.FieldValue.serverTimestamp();
const gmUid="qa_notice_gm_20261123";
const staffUid="qa_notice_unprivileged_staff_20261123";
const ownerUid="qa_notice_place_owner_20261123";
const outsiderUid="qa_notice_outsider_20261123";
const accountKey="9647800000000";
function payload(uid,type="place_report"){
  return {
    type,accountKey,ownerUid,
    placeId:"qa_owner_place",placeName:"QA private location",
    approvalNumber:"QA-24",governorate:"Kirkuk",
    titleAr:"Synthetic owner notification",
    titleEn:"Synthetic owner notification",
    bodyAr:"Synthetic owner notification body",
    bodyEn:"Synthetic owner notification body",
    sourceType:"published_places",sourceId:"qa_owner_place",
    createdByUid:uid,createdByName:"QA Admin",createdByRole:"general_manager",
    createdAt:sent(),
  };
}

test("isolated owner place notices use current rules only; show existing gaps",{
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
  try {
    await env.withSecurityRulesDisabled(async ctx=>{
      const db=ctx.firestore();
      await Promise.all([
        db.doc("admins/"+gmUid).set({
          role:"general_manager",active:true,status:"active",
        }),
        db.doc("admins/"+staffUid).set({
          role:"employee",active:true,status:"active",permissions:{},
        }),
        db.doc("users/"+ownerUid).set({
          name:"QA place owner",accountKey,
        }),
        db.doc("published_places/qa_owner_place").set({
          placeName:"QA private location",accountKey,ownerUid,
          governorate:"Kirkuk",approvalNumber:"QA-24",published:true,
        }),
      ]);
    });

    await t.test("GM atomic notification and audit, owner can view",async()=>{
      const notice=gm.doc("owner_place_notifications/qa_notice_receipt");
      const audit=gm.doc("admin_audit/qa_notice_audit_receipt");
      await assertSucceeds(gm.runTransaction(async tx=>{
        const source=await tx.get(gm.doc("published_places/qa_owner_place"));
        assert.equal(source.data().accountKey,accountKey);
        tx.set(notice,payload(gmUid));
        tx.set(audit,{
          action:"owner_notification_sent",adminUid:gmUid,
          adminName:"QA Admin",adminRole:"general_manager",
          notificationType:"place_report",
          sourceType:"published_places",sourceId:"qa_owner_place",
          accountKey,title:"Synthetic owner notification",
          createdAt:sent(),
        });
      }));
      assert.equal((await assertSucceeds(owner.doc(notice.path).get()))
        .data().type,"place_report");
      await assertFails(outsider.doc(notice.path).get());
      assert.equal((await assertSucceeds(gm.doc(audit.path).get()))
        .data().adminUid,gmUid);
      const published=await assertSucceeds(owner.doc(
        "published_places/qa_owner_place").get());
      assert.equal(published.data().ownerUid,ownerUid);
    });

    await t.test("anonymous outsider and invalid payload cannot notify",async()=>{
      await assertFails(outsider.doc(
        "owner_place_notifications/qa_outsider_notice").set(
        payload(outsiderUid)));
      await assertFails(owner.doc(
        "owner_place_notifications/qa_owner_sends").set(payload(ownerUid)));
      await assertFails(gm.doc(
        "owner_place_notifications/qa_invalid_type").set(
        payload(gmUid,"phishing")));
      await assertFails(gm.doc(
        "owner_place_notifications/qa_forged_uid").set(
        payload(staffUid)));
      await assertFails(gm.doc(
        "owner_place_notifications/qa_changed_fields").set({
        ...payload(gmUid),rewardsEnabled:true,
      }));
      await assertFails(outsider.doc("admin_audit/qa_forged_notice_audit")
        .set({adminUid:gmUid,action:"owner_notification_sent"}));
    });

    await t.test("document pre-existing unchecked legacy staff grant",async()=>{
      // Known gap: checked-in rule permits ANY active admin to write a
      // notification, independent of viewPlaceRequests. Our isolated UI
      // requires server proof, but cannot harden malicious old clients.
      await assertSucceeds(staff.doc(
        "owner_place_notifications/qa_legacy_scope_gap").set({
        ...payload(staffUid),createdByRole:"employee",
      }));
      console.log("RELEASE_HOLD_LEGACY_RULE_PERMITS_ROLELESS_PERMISSION_STAFF_OWNER_NOTICE");
    });
  } finally {
    await env.cleanup();
  }
});
