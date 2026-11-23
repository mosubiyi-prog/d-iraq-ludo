"use strict";
/*
 * Stage2 administrator rules integration gate. Synthetic, throwaway data
 * against the checked-in Firestore rules on LOCAL EMULATOR ONLY.
 * This does not invoke Firebase production, Admin SDK, Cloud Functions or
 * DEDA wallets, and does not assert Flutter UI/device success.
 */
const fs = require("node:fs");
const {createHash} = require("node:crypto");
const assert = require("node:assert/strict");
const { test } = require("node:test");
const firebase = require("firebase/compat/app");
require("firebase/compat/firestore");
const {
  initializeTestEnvironment, assertSucceeds, assertFails
} = require("@firebase/rules-unit-testing");

const project = "demo-deda-stage2-isolated-admin-private-qa";
const account = "9647712345678";
const secondaryAccount = "9647712345679";
const managerUid = "qa_manager_uid";
const staffUid = "qa_staff_uid";
const publicUid = "qa_public_uid";
const outsiderUid = "qa_outsider_uid";
const gmEmail = "qa.manager@example.invalid";
const staffEmail = "qa.staff@example.invalid";
const sent = () => firebase.firestore.FieldValue.serverTimestamp();
const expires = () => firebase.firestore.Timestamp.fromDate(
  new Date(Date.now() + 3600000));
const makeInvitation = (id, phone, email = staffEmail) => ({
  adminId: id,
  displayName: "QA Staff Person",
  email,
  phone,
  department: "Support",
  role: "employee",
  governorate: "",
  permissions: {supportRead: true},
  status: "pending",
  activationCode: "12345678",
  createdByUid: managerUid,
  createdByName: "QA General Manager",
  createdAt: sent(),
  updatedAt: sent(),
  expiresAt: expires(),
});
const recovery = () => ({
  requesterUid: publicUid,
  accountKey: account,
  phone: "07712345678",
  fullName: "QA Staff Member",
  email: staffEmail,
  targetAdminUid: staffUid,
  targetAdminId: "DEDA-ADM-QA-STAFF",
  targetRole: "employee",
  status: "new",
  createdAt: sent(),
  updatedAt: sent(),
});

test("actual checked-in Firestore rules: secondary admin isolation + release holds",{
  timeout: 180000,
}, async (t) => {
  assert.equal(process.env.DEDA_EMULATOR_ONLY, "true");
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, "127.0.0.1:8097");
  const env = await initializeTestEnvironment({
    projectId: project,
    firestore: {
      rules: fs.readFileSync("firestore.rules", "utf8"),
      host: "127.0.0.1", port: 8097,
    },
  });
  const manager = env.authenticatedContext(managerUid, {email: gmEmail})
    .firestore();
  const staff = env.authenticatedContext(staffUid, {email: staffEmail})
    .firestore();
  const publicDb = env.authenticatedContext(publicUid)
    .firestore();
  const outsider = env.authenticatedContext(outsiderUid, {
    email: "not.staff@example.invalid",
  }).firestore();
  try {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await Promise.all([
        db.doc("admins/" + managerUid).set({
          role: "general_manager", active: true, status: "active",
          email: gmEmail, displayName: "QA General Manager",
        }),
        db.doc("admins/" + staffUid).set({
          role: "employee", active: true, status: "active",
          email: staffEmail, displayName: "QA Staff Member",
          adminId: "DEDA-ADM-QA-STAFF", phone: account,
          permissions: {supportRead: true},
        }),
        db.doc("deda_sessions/" + publicUid).set({
          uid: publicUid, accountKey: account,
        }),
        db.doc("admin_entry_access/" + account).set({
          accountKey: account, accessType: "member",
          allowedRole: "employee", allowedAdminEmail: staffEmail,
          active: true, status: "active", adminUid: staffUid,
          adminId: "DEDA-ADM-QA-STAFF",
        }),
        db.doc("admin_entry_access/" + secondaryAccount).set({
          accountKey: secondaryAccount, accessType: "general_manager_gateway",
          allowedRole: "general_manager", active: true, status: "active",
          managedByUid: managerUid,
        }),
      ]);
    });

    await t.test("unrelated users cannot read admin team or pending invite", async () => {
      await assertFails(outsider.collection("admins").get());
      await assertFails(outsider.doc("admins/" + staffUid).get());
      await assertSucceeds(manager.collection("admins").get());
      await assertFails(outsider.doc("admin_invites/private_pending").get());
    });

    await t.test("owner's public UID reads only its own entry gateway", async () => {
      await assertSucceeds(publicDb.doc("admin_entry_access/" + account).get());
      await assertFails(outsider.doc("admin_entry_access/" + account).get());
    });

    await t.test("manager may create a valid subordinate invite; outsider cannot", async () => {
      await assertSucceeds(manager.doc("admin_invites/private_pending").set(
        makeInvitation("DEDA-ADM-QA-INVITE", account)));
      await assertFails(outsider.doc("admin_invites/private_forged").set(
        makeInvitation("DEDA-ADM-QA-FORGED", secondaryAccount)));
    });

    await t.test("wrong code/email cannot claim, intended staff may claim", async () => {
      const ref = staff.doc("admin_invites/private_pending");
      await assertFails(ref.update({
        status: "claimed", claimedUid: staffUid,
        claimCode: "00000000", claimedAt: sent(), updatedAt: sent(),
      }));
      await assertFails(outsider.doc("admin_invites/private_pending").update({
        status: "claimed", claimedUid: outsiderUid,
        claimCode: "12345678", claimedAt: sent(), updatedAt: sent(),
      }));
      await assertSucceeds(ref.update({
        status: "claimed", claimedUid: staffUid,
        claimCode: "12345678", claimedAt: sent(), updatedAt: sent(),
      }));
      const claimed = await assertSucceeds(ref.get());
      assert.equal(claimed.data().claimedUid, staffUid);
    });

    await t.test("requester owns recovery request; GM decides, staff cannot", async () => {
      const path = "admin_recovery_requests/qa_recovery";
      await assertSucceeds(publicDb.doc(path).set(recovery()));
      await assertFails(outsider.doc(path).get());
      await assertSucceeds(publicDb.doc(path).get());
      await assertFails(staff.doc(path).update({
        status: "ready", decisionByUid: staffUid,
        decisionByName: "Not GM", decisionAt: sent(),
        updatedAt: sent(), rejectionReason: "",
        recoveryPin: "123456",
        recoveryPinIssuedAt: sent(), recoveryPinExpiresAt: expires(),
      }));
      await assertSucceeds(manager.doc(path).update({
        status: "ready", decisionByUid: managerUid,
        decisionByName: "QA General Manager", decisionAt: sent(),
        updatedAt: sent(), rejectionReason: "",
        recoveryPin: "123456",
        recoveryPinIssuedAt: sent(), recoveryPinExpiresAt: expires(),
      }));
      await assertFails(manager.doc(path).update({status: "rejected"}));
    });

    await t.test("release-hold observation: two concurrent emails are not server-unique", async () => {
      const email = "qa.duplicate@example.invalid";
      // Existing rules don't enforce uniqueness of the email across docs.
      const first = manager.doc("admin_invites/parallel_one");
      const second = manager.doc("admin_invites/parallel_two");
      await Promise.all([
        assertSucceeds(first.set(makeInvitation("DEDA-ADM-PARA", account, email))),
        assertSucceeds(second.set(makeInvitation("DEDA-ADM-PARB",
          secondaryAccount, email))),
      ]);
      assert.equal((await first.get()).data().email,
        (await second.get()).data().email);
      console.log("RELEASE_HOLD_DUPLICATE_ADMIN_INVITE_EMAIL_ALLOWED_BY_CURRENT_RULES");
    });


    await t.test("two isolated managers racing on SHA256 email key: one invite only", async () => {
      const sameEmail = "qa.atomic.race@example.invalid";
      const key = "e_" + createHash("sha256").update(sameEmail).digest("hex");
      assert.match(key, /^e_[0-9a-f]{64}$/);
      const ref = manager.doc("admin_invites/" + key);
      async function attempt(phone, id) {
        return manager.runTransaction(async (tx) => {
          const existing = await tx.get(ref);
          if (existing.exists) throw new Error("email-already-invited");
          tx.set(ref, makeInvitation(id, phone, sameEmail));
          return id;
        });
      }
      const outcomes = await Promise.allSettled([
        attempt(account, "DEDA-ADM-RACE-1"),
        attempt(secondaryAccount, "DEDA-ADM-RACE-2"),
      ]);
      const successful = outcomes.filter((o) => o.status === "fulfilled");
      const rejected = outcomes.filter((o) => o.status === "rejected");
      assert.equal(successful.length, 1, "exactly one atomic invitation wins");
      assert.equal(rejected.length, 1, "parallel duplicate must fail closed");
      const winner = (await ref.get()).data();
      assert.equal(winner.email, sameEmail);
      assert.equal(winner.adminId, successful[0].value);
      console.log("PASS_ISOLATED_INVITATION_SHA256_ATOMIC_ONE_WINNER");
    });


    await t.test("release-hold: invited staff profile can access users before gateway bound", async()=>{
      const partialUid = "qa_unbound_staff_uid";
      const partialPhone = "9647712345688";
      const privateUid = "qa_other_private_user";
      await env.withSecurityRulesDisabled(async ctx=>{
        const db=ctx.firestore();
        await Promise.all([
          db.doc("admins/"+partialUid).set({
            role:"employee",status:"active",active:true,
            inviteId:"qa_unbound_staff_invite",
            phone:partialPhone,adminId:"DEDA-ADM-QA-UNBOUND",
            email:"qa.unbound@example.invalid",permissions:{viewUsers:true},
          }),
          db.doc("admin_entry_access/"+partialPhone).set({
            accountKey:partialPhone,accessType:"member",
            allowedRole:"employee",allowedAdminEmail:"qa.unbound@example.invalid",
            inviteId:"qa_unbound_staff_invite",adminId:"DEDA-ADM-QA-UNBOUND",
            adminUid:"",active:true,status:"invited",
          }),
          db.doc("users/"+privateUid).set({
            accountKey:"9647712345998",name:"QA private user",
          }),
        ]);
      });
      const partial=env.authenticatedContext(partialUid,{
        email:"qa.unbound@example.invalid",
      }).firestore();
      // This is a diagnostic safety failure in the checked-in rules,
      // NOT acceptable production behavior. The candidate below denies it.
      await assertSucceeds(partial.doc("users/"+privateUid).get());
      console.log("RELEASE_HOLD_UNBOUND_INVITEE_ADMIN_DATA_ACCESS_ALLOWED_BY_CURRENT_RULES");

      await assertSucceeds(partial.doc("owner_place_notifications/qa_prebinding_notice").set({
  type:"admin_alert",accountKey:"9647712345900",
  ownerUid:"qa_private_owner",placeId:"qa_place_1",
  placeName:"QA place",approvalNumber:"",governorate:"Baghdad",
  titleAr:"تنبيه اختبار",titleEn:"Synthetic QA alert",
  bodyAr:"اختبار وهمي",bodyEn:"Synthetic QA only",
  sourceType:"admin",sourceId:"qa_alert",
  createdByUid:partialUid,
  createdByName:"QA Staff",createdByRole:"employee",
  createdAt:sent(),
}));
      console.log("RELEASE_HOLD_UNBOUND_INVITEE_CAN_CREATE_OWNER_ALERT_CURRENT_RULES");

      await assertSucceeds(partial.doc("admin_audit/qa_unbound_forged_audit").set({
        action:"admin_invite_accepted",inviteId:"not-the-claimed-invite",
        adminUid:partialUid,adminRole:"employee",
        createdAt:sent(),
      }));
      console.log("RELEASE_HOLD_UNBOUND_INVITEE_CAN_FORGE_ADMIN_AUDIT");


    });


    await t.test("GM-only account deletion request status + audit remain atomic; users untouched", async () => {
      const requestPath = "account_deletion_requests/qa_isolated_status_review";
      const auditPath = "admin_audit/qa_isolated_status_review_audit";
      await env.withSecurityRulesDisabled(async (ctx) => {
        await Promise.all([
          ctx.firestore().doc(requestPath).set({
            requesterUid: publicUid, accountKey: account,
            name: "QA synthetic requester", phone: "07712345678",
            reason: "User requested account review",
            status: "new", createdAt: sent(), updatedAt: sent(),
          }),
          ctx.firestore().doc("users/" + publicUid).set({
            accountKey: account, name: "QA account must remain",
          }),
        ]);
      });
      const requestRef = manager.doc(requestPath);
      const deniedUpdate = {
        status: "reviewing", updatedAt: sent(),
        reviewedByUid: staffUid, reviewedByName: "Unauthorized",
        reviewedByRole: "employee", reviewNote: "Not allowed",
      };
      await assertSucceeds(manager.collection("account_deletion_requests")
        .orderBy("createdAt", "desc").limit(51).get());
      await assertSucceeds(publicDb.doc(requestPath).get());
      await assertFails(staff.doc(requestPath).get());
      await assertFails(outsider.doc(requestPath).get());
      await assertFails(staff.doc(requestPath).update(deniedUpdate));
      await assertFails(publicDb.doc(requestPath).update({
        ...deniedUpdate, reviewedByUid: publicUid,
      }));
      await assertSucceeds(manager.runTransaction(async (tx) => {
        const before = await tx.get(requestRef);
        assert.equal(before.data().status, "new");
        tx.update(requestRef, {
          status: "reviewing", updatedAt: sent(),
          reviewedByUid: managerUid, reviewedByName: "QA General Manager",
          reviewedByRole: "general_manager",
          reviewNote: "Verified QA review only",
        });
        tx.set(manager.doc(auditPath), {
          action: "account_deletion_status_changed",
          adminUid: managerUid, adminName: "QA General Manager",
          adminRole: "general_manager",
          details: {requestId: "qa_isolated_status_review",
            oldStatus: "new", newStatus: "reviewing",
            statusOnlyNoAccountDeletion: true},
          createdAt: sent(),
        });
      }));
      const reviewed = await assertSucceeds(requestRef.get());
      assert.equal(reviewed.data().status, "reviewing");
      const audit = await assertSucceeds(manager.doc(auditPath).get());
      assert.equal(audit.data().details.statusOnlyNoAccountDeletion, true);
      const user = await assertSucceeds(publicDb.doc("users/" + publicUid).get());
      assert.equal(user.exists, true);
      console.log("PASS_SYNTHETIC_ACCOUNT_DELETION_STATUS_ONLY_ATOMIC_AUDIT_NO_USER_DELETE");
    });


    await t.test("GM can atomically archive and remove only one owner-approved place, notify and audit", async () => {
      const id = "qa_owner_place_delete";
      const requestRef = manager.doc("place_deletion_requests/" + id);
      const placeRef = manager.doc("published_places/" + id);
      const trashRef = manager.doc("admin_trash_places/" + id);
      const noticeRef = manager.doc("owner_place_notifications/deletion_approved_" + id);
      const auditRef = manager.doc("admin_audit/qa_place_delete_atomic_audit");
      const noticeAuditRef = manager.doc("admin_audit/qa_place_delete_owner_audit");
      await env.withSecurityRulesDisabled(async ctx => {
        const db = ctx.firestore();
        await Promise.all([
          db.doc("place_deletion_requests/" + id).set({
            placeId:id, requesterUid:publicUid, accountKey:account,
            placeName:"QA Baghdad place", approvalNumber:"DEDA-QA-45",
            governorate:"Baghdad",address:"QA synthetic street",
            phone:"07712345678", reason:"Owner requested removal",
            status:"new", createdAt:sent(),updatedAt:sent(),
          }),
          db.doc("published_places/" + id).set({
            ownerUid:publicUid, accountKey:account, placeName:"QA Baghdad place",
            approvalNumber:"DEDA-QA-45", governorate:"Baghdad",
            published:true, status:"approved",
          }),
        ]);
      });
      await assertSucceeds(manager.collection("place_deletion_requests")
        .orderBy("updatedAt","desc").limit(51).get());
      await assertFails(staff.doc("place_deletion_requests/" + id).get());
      await assertFails(outsider.doc("place_deletion_requests/" + id).get());
      await assertFails(staff.doc("place_deletion_requests/" + id)
        .update({status:"deleted",updatedAt:sent(),reviewedByUid:staffUid,
          reviewedByName:"QA Staff",reviewedByRole:"employee",
          reviewNote:"Unauthorized action"}));
      await assertFails(publicDb.doc("published_places/" + id).delete());

      await assertSucceeds(manager.runTransaction(async tx => {
        const req = await tx.get(requestRef);
        const published = await tx.get(placeRef);
        const archived = await tx.get(trashRef);
        const existingNotice = await tx.get(noticeRef);
        assert.equal(req.data().status,"new");
        assert.equal(published.exists,true);
        assert.equal(archived.exists,false);
        assert.equal(existingNotice.exists,false);
        tx.set(trashRef,{
          ...published.data(),originalId:id,
          trashKind:"owner_requested_place_deletion",
          deletedFromCollection:"published_places",
          deletionRequestId:id,deletedAt:sent(),
          deletedByUid:managerUid,deletedByName:"QA General Manager",
          deletedByRole:"general_manager",
        });
        tx.delete(placeRef);
        tx.update(requestRef,{
          status:"deleted",updatedAt:sent(),reviewedByUid:managerUid,
          reviewedByName:"QA General Manager",reviewedByRole:"general_manager",
          reviewNote:"Owner confirmed removal",completedAt:sent(),
        });
        tx.set(noticeRef,{
          type:"deletion_approved",accountKey:account,
          ownerUid:publicUid,placeId:id,placeName:"QA Baghdad place",
          approvalNumber:"DEDA-QA-45",governorate:"Baghdad",
          titleAr:"تمت الموافقة على حذف المكان",titleEn:"Place deletion approved",
          bodyAr:"تمت إزالة المكان بناءً على طلبك",bodyEn:"Requested place removed",
          sourceType:"place_deletion_requests",sourceId:id,
          createdByUid:managerUid,createdByName:"QA General Manager",
          createdByRole:"general_manager",createdAt:sent(),
        });
        tx.set(auditRef,{action:"place_deletion_status_changed",
          adminUid:managerUid,adminName:"QA General Manager",
          adminRole:"general_manager",createdAt:sent(),
          details:{requestId:id,newStatus:"deleted",placeArchived:true}});
        tx.set(noticeAuditRef,{action:"owner_notification_sent",
          adminUid:managerUid,adminName:"QA General Manager",
          adminRole:"general_manager",createdAt:sent(),
          notificationType:"deletion_approved",sourceId:id});
      }));
      const request = await assertSucceeds(requestRef.get());
      assert.equal(request.data().status,"deleted");
      const trash = await assertSucceeds(trashRef.get());
      assert.equal(trash.data().originalId,id);
      assert.equal(trash.data().ownerUid,publicUid);
      assert.equal(trash.data().approvalNumber,"DEDA-QA-45");
      assert.equal(trash.data().trashKind,"owner_requested_place_deletion");
      const notice = await assertSucceeds(publicDb.doc(
        "owner_place_notifications/deletion_approved_" + id).get());
      assert.equal(notice.data().type,"deletion_approved");
      assert.equal((await assertSucceeds(auditRef.get())).data()
        .details.placeArchived,true);
      assert.equal((await assertSucceeds(noticeAuditRef.get())).data()
        .notificationType,"deletion_approved");
      await env.withSecurityRulesDisabled(async ctx => {
        const db = ctx.firestore();
        assert.equal((await db.doc("published_places/"+id).get()).exists,false);
        assert.equal((await db.doc("users/"+publicUid).get()).exists,true);
      });
      console.log("PASS_OWNER_PLACE_DELETION_ATOMIC_ARCHIVE_REMOVE_OWNER_NOTICE_TWO_AUDITS_NO_USER_DELETE");
    });

    await t.test("rejected owner place request notifies without removing the published place", async () => {
      const id="qa_owner_place_reject";
      const requestRef=manager.doc("place_deletion_requests/"+id);
      const placeRef=manager.doc("published_places/"+id);
      const noticeRef=manager.doc("owner_place_notifications/deletion_rejected_"+id);
      await env.withSecurityRulesDisabled(async ctx => {
        const db=ctx.firestore();
        await Promise.all([
          db.doc("place_deletion_requests/"+id).set({
            placeId:id,requesterUid:publicUid,accountKey:account,
            placeName:"QA retained place",approvalNumber:"DEDA-QA-46",
            governorate:"Baghdad",address:"QA road",phone:"07712345678",
            reason:"Owner deletion request",status:"reviewing",
            createdAt:sent(),updatedAt:sent(),
          }),
          db.doc("published_places/"+id).set({
            ownerUid:publicUid,accountKey:account,
            placeName:"QA retained place",approvalNumber:"DEDA-QA-46",
            governorate:"Baghdad",published:true,status:"approved",
          }),
        ]);
      });
      await assertSucceeds(manager.runTransaction(async tx => {
        const before=await tx.get(requestRef);
        const existingNotice=await tx.get(noticeRef);
        assert.equal(before.data().status,"reviewing");
        assert.equal(existingNotice.exists,false);
        tx.update(requestRef,{status:"rejected",updatedAt:sent(),
          reviewedByUid:managerUid,reviewedByName:"QA General Manager",
          reviewedByRole:"general_manager",reviewNote:"Owner proof incomplete",
          closedAt:sent()});
        tx.set(noticeRef,{
          type:"deletion_rejected",accountKey:account,
          ownerUid:publicUid,placeId:id,placeName:"QA retained place",
          approvalNumber:"DEDA-QA-46",governorate:"Baghdad",
          titleAr:"تم رفض طلب الحذف",titleEn:"Place deletion request rejected",
          bodyAr:"لم تتم الموافقة على حذف المكان",bodyEn:"Deletion not approved",
          sourceType:"place_deletion_requests",sourceId:id,
          createdByUid:managerUid,createdByName:"QA General Manager",
          createdByRole:"general_manager",createdAt:sent(),
        });
        tx.set(manager.doc("admin_audit/qa_place_reject_audit"),{
          action:"place_deletion_status_changed",adminUid:managerUid,
          adminName:"QA General Manager",adminRole:"general_manager",
          createdAt:sent(),details:{requestId:id,newStatus:"rejected"}});
        tx.set(manager.doc("admin_audit/qa_place_reject_notice_audit"),{
          action:"owner_notification_sent",adminUid:managerUid,
          adminName:"QA General Manager",adminRole:"general_manager",
          createdAt:sent(),notificationType:"deletion_rejected",sourceId:id});
      }));
      assert.equal((await assertSucceeds(requestRef.get())).data().status,
        "rejected");
      assert.equal((await assertSucceeds(placeRef.get())).exists,true);
      assert.equal((await assertSucceeds(publicDb.doc(
        "owner_place_notifications/deletion_rejected_"+id).get()))
        .data().type,"deletion_rejected");
      console.log("PASS_OWNER_PLACE_REJECTION_ATOMIC_REQUEST_NOTICE_AND_AUDIT_NO_REMOVAL");
    });

    await t.test("GM winner request review + prize_sent audit atomic, never credits gifts", async () => {
      const id="prize_v1_"+account;
      const managerRef=manager.doc("prize_winner_requests/"+id);
      const staffRef=staff.doc("prize_winner_requests/"+id);
      const publicRef=publicDb.doc("prize_winner_requests/"+id);
      const auditRef=manager.doc("admin_audit/qa_prize_v1_review_atomic");
      await env.withSecurityRulesDisabled(async ctx => {
        const db=ctx.firestore();
        await db.doc("prize_winner_requests/"+id).set({
          ownerUid:publicUid,cycleId:"prize_v1",accountKey:account,
          name:"QA Winner",phone:"07712345678",dedaId:"@DEDA-QA1234",
          rewardCode:"DEDA123456789012",pointsAtCompletion:25000,
          completedThresholds:[5000,10000,15000,20000,25000],
          finalReservedPoints:25000,status:"new",adminMessage:"",
          prizeDetails:"",userReply:"",createdAt:sent(),updatedAt:sent(),
        });
      });
      await assertSucceeds(manager.collection("prize_winner_requests")
        .orderBy("updatedAt","desc").limit(500).get());
      await assertFails(staff.collection("prize_winner_requests").get());
      await assertFails(outsider.collection("prize_winner_requests").get());
      await assertFails(staffRef.update({
        status:"approved",adminMessage:"Unapproved staff action",prizeDetails:"",
        adminByUid:staffUid,adminByName:"QA Staff Member",
        adminByRole:"employee",adminUpdatedAt:sent(),updatedAt:sent(),
      }));
      await assertSucceeds(manager.runTransaction(async tx => {
        const request=await tx.get(managerRef);
        assert.equal(request.data().status,"new");
        tx.update(managerRef,{
          status:"prize_sent",adminMessage:"Proof checked",
          prizeDetails:"External prize instructions delivered",
          adminByUid:managerUid,adminByName:"QA General Manager",
          adminByRole:"general_manager",adminUpdatedAt:sent(),
          updatedAt:sent(),prizeSentAt:sent(),
        });
        tx.set(auditRef,{
          action:"prize_winner_status_changed",
          adminUid:managerUid,adminName:"QA General Manager",
          adminRole:"general_manager",createdAt:sent(),
          details:{sourceCollection:"prize_winner_requests",sourceId:id,
            targetAccountKey:account,targetDedaId:"@DEDA-QA1234",
            oldStatus:"new",newStatus:"prize_sent",
            statusOnlyNoDiamondTransfer:true},
        });
      }));
      assert.equal((await assertSucceeds(managerRef.get())).data().status,"prize_sent");
      assert.equal((await assertSucceeds(auditRef.get())).data()
        .details.statusOnlyNoDiamondTransfer,true);
      await env.withSecurityRulesDisabled(async ctx => {
        const db=ctx.firestore();
        assert.equal((await db.collection("deda_diamond_gifts").get()).empty,true);
        assert.equal((await db.doc("deda_sessions/"+publicUid).get())
          .data().accountKey,account);
      });
      await assertFails(managerRef.update({
        status:"delivered",winnerConfirmedAt:sent(),deliveredAt:sent(),
        updatedAt:sent(),
      }));
      await assertFails(outsider.doc("prize_winner_requests/"+id).update({
        status:"delivered",winnerConfirmedAt:sent(),deliveredAt:sent(),
        updatedAt:sent(),
      }));
      await assertSucceeds(publicRef.update({
        status:"delivered",winnerConfirmedAt:sent(),deliveredAt:sent(),
        updatedAt:sent(),
      }));
      assert.equal((await assertSucceeds(managerRef.get())).data().status,"delivered");
      console.log("PASS_PRIZE_WINNER_REVIEW_ATOMIC_AUDIT_ZERO_DIAMONDS_WINNER_ONLY_CONFIRM");
    });

    await t.test("winner's answer to needs_info is owner-only, no admin spoof", async () => {
      const id="prize_v1_"+secondaryAccount;
      const owner=env.authenticatedContext("qa_other_prize_owner").firestore();
      await env.withSecurityRulesDisabled(async ctx => {
        const db=ctx.firestore();
        await Promise.all([
          db.doc("deda_sessions/qa_other_prize_owner").set({
            uid:"qa_other_prize_owner",accountKey:secondaryAccount}),
          db.doc("prize_winner_requests/"+id).set({
            ownerUid:"qa_other_prize_owner",cycleId:"prize_v1",
            accountKey:secondaryAccount,name:"QA Second Winner",
            phone:"07712345679",dedaId:"@DEDA-QA1235",
            rewardCode:"DEDA123456789013",pointsAtCompletion:25000,
            completedThresholds:[5000,10000,15000,20000,25000],
            finalReservedPoints:25000,status:"needs_info",
            adminMessage:"Proof requested",prizeDetails:"",userReply:"",
            createdAt:sent(),updatedAt:sent(),
          }),
        ]);
      });
      const userUpdate={status:"reviewing",
        userReply:"Proof submitted by account owner",
        userReplyAt:sent(),updatedAt:sent()};
      await assertFails(publicDb.doc("prize_winner_requests/"+id)
        .update(userUpdate));
      await assertFails(outsider.doc("prize_winner_requests/"+id)
        .update(userUpdate));
      await assertSucceeds(owner.doc("prize_winner_requests/"+id)
        .update(userUpdate));
      assert.equal((await assertSucceeds(
        manager.doc("prize_winner_requests/"+id).get()))
        .data().status,"reviewing");
      console.log("PASS_PRIZE_NEEDS_INFO_REPLY_OWNER_ONLY_ADMIN_NOT_INTERCEPTED");
    });

    await t.test("weekly league GM pause/freeze/notice and increasing plan are atomic; XP and gifts untouched", async () => {
      const week="2026-11-21";
      const id="@DEDA-QA1234";
      const scorePath="deda_weekly_direct_weeks/"+week+"/scores/"+id;
      const control="deda_weekly_direct_control/active";
      const reviewPath="deda_weekly_direct_reviews/"+week+"/users/"+id;
      const noticePath="deda_weekly_direct_notices/"+week+"/users/"+id;
      const planPath="deda_weekly_direct_prize_plans/"+week;
      const why="QA verified league pause and participant review";
      const base=[150,100,50,10,10,10,10,10,10,10];
      const raised=[160,100,50,10,10,10,10,10,10,10];
      const notice="Your weekly league points are held for review only.";
      const freed="Your weekly league review has been completed.";
      await env.withSecurityRulesDisabled(async ctx => {
        const db=ctx.firestore();
        await db.doc("users/"+publicUid).set({
          accountKey:account,sharePersonalId:id,
        });
        await db.doc("deda_weekly_direct_accounts/"+id).set({
          accountKey:account,publicId:id,createdByUid:publicUid,
          createdAt:sent(),
        });
        await db.doc(scorePath).set({
          weekId:week,weekStart:firebase.firestore.Timestamp.fromDate(
            new Date("2026-11-21T03:00:00.000Z")),
          publicId:id,displayName:"QA League Participant",
          claimedKeys:[week+"|open_map"],lastClaimKey:week+"|open_map",
          completedTasks:1,weeklyXp:20,updatedAt:sent(),
        });
      });
      await assertFails(staff.doc(control).set({
        weekId:week,paused:true,reason:why,updatedAt:sent(),
        updatedBy:staffUid,
      }));
      await assertSucceeds(manager.runTransaction(async tx => {
        const c=manager.doc(control);
        const ev=manager.doc("deda_weekly_direct_admin_events/qa_league_pause");
        const old=await tx.get(c);
        assert.equal(old.exists,false);
        tx.set(c,{weekId:week,paused:true,reason:why,
          updatedAt:sent(),updatedBy:managerUid});
        tx.set(ev,{action:"pause",weekId:week,publicId:"",
          reason:why,createdAt:sent(),createdBy:managerUid});
      }));
      await assertFails(staff.doc(reviewPath).set({
        weekId:week,publicId:id,frozen:true,notice,reason:why,
        updatedAt:sent(),updatedBy:staffUid,
      }));
      await assertFails(manager.doc(noticePath).set({
        weekId:week,publicId:id,frozen:true,notice,
        updatedAt:sent(),updatedBy:managerUid,
      }));
      await assertSucceeds(manager.runTransaction(async tx => {
        const score=await tx.get(manager.doc(scorePath));
        const previous=await tx.get(manager.doc(reviewPath));
        assert.equal(score.data().weeklyXp,20);
        assert.equal(previous.exists,false);
        tx.set(manager.doc(reviewPath),{
          weekId:week,publicId:id,frozen:true,reason:why,notice,
          updatedAt:sent(),updatedBy:managerUid,
        });
        tx.set(manager.doc(noticePath),{
          weekId:week,publicId:id,frozen:true,notice,
          updatedAt:sent(),updatedBy:managerUid,
        });
        tx.set(manager.doc("deda_weekly_direct_admin_events/qa_league_freeze"),{
          action:"freeze",weekId:week,publicId:id,
          reason:why,createdAt:sent(),createdBy:managerUid,
        });
      }));
      await assertSucceeds(publicDb.doc(noticePath).get());
      await assertFails(outsider.doc(noticePath).get());
      await assertSucceeds(manager.runTransaction(async tx => {
        const controlState=await tx.get(manager.doc(control));
        const existing=await tx.get(manager.doc(planPath));
        assert.equal(controlState.data().paused,true);
        assert.equal(existing.exists,false);
        tx.set(manager.doc(planPath),{
          weekId:week,amounts:raised,reason:why,
          updatedAt:sent(),updatedBy:managerUid,
        });
        tx.set(manager.doc("deda_weekly_direct_admin_events/qa_league_prizes"),{
          action:"prizes_increase",weekId:week,publicId:"",
          reason:why,createdAt:sent(),createdBy:managerUid,
        });
      }));
      await assertFails(manager.doc(planPath).set({
        weekId:week,amounts:base,reason:why,
        updatedAt:sent(),updatedBy:managerUid,
      }));
      await assertFails(staff.doc(planPath).update({
        amounts:raised,reason:why,updatedAt:sent(),updatedBy:staffUid,
      }));
      await assertSucceeds(manager.runTransaction(async tx => {
        const r=await tx.get(manager.doc(reviewPath));
        assert.equal(r.data().frozen,true);
        tx.set(manager.doc(reviewPath),{
          weekId:week,publicId:id,frozen:false,reason:why,notice:freed,
          updatedAt:sent(),updatedBy:managerUid,
        });
        tx.set(manager.doc(noticePath),{
          weekId:week,publicId:id,frozen:false,notice:freed,
          updatedAt:sent(),updatedBy:managerUid,
        });
        tx.set(manager.doc("deda_weekly_direct_admin_events/qa_league_release"),{
          action:"unfreeze",weekId:week,publicId:id,reason:why,
          createdAt:sent(),createdBy:managerUid,
        });
      }));
      await assertSucceeds(manager.runTransaction(async tx => {
        const c=manager.doc(control);
        const old=await tx.get(c);
        assert.equal(old.data().paused,true);
        tx.set(c,{weekId:week,paused:false,reason:why,
          updatedAt:sent(),updatedBy:managerUid});
        tx.set(manager.doc("deda_weekly_direct_admin_events/qa_league_resume"),{
          action:"resume",weekId:week,publicId:"",
          reason:why,createdAt:sent(),createdBy:managerUid,
        });
      }));
      await assertFails(manager.doc(planPath).set({
        weekId:week,amounts:[170,100,50,10,10,10,10,10,10,10],
        reason:why,updatedAt:sent(),updatedBy:managerUid,
      }));
      await env.withSecurityRulesDisabled(async ctx => {
        const db=ctx.firestore();
        assert.equal((await db.doc(scorePath).get()).data().weeklyXp,20);
        assert.equal((await db.collection("deda_diamond_gifts").get()).empty,true);
        assert.deepEqual((await db.doc(planPath).get()).data().amounts,raised);
        assert.equal((await db.doc(reviewPath).get()).data().frozen,false);
        assert.equal((await db.doc(noticePath).get()).data().frozen,false);
      });
      console.log("PASS_LEAGUE_GM_ATOMIC_PAUSE_FREEZE_NOTICE_PLAN_RESUME_NO_WALLET_OR_XP");
    });

    await t.test("release hold: active roleless admin is treated as general manager",async()=>{
      const missingUid="qa_roleless_legacy_account";
      await env.withSecurityRulesDisabled(async ctx=>{
        await ctx.firestore().doc("admins/"+missingUid).set({
          active:true,status:"active",email:"qa.roleless@example.invalid",
        });
      });
      const roleless=env.authenticatedContext(missingUid,{
        email:"qa.roleless@example.invalid",
      }).firestore();
      // Current rules: !keys.hasAny(['role']) grants GM access.
      // This is an observation, NOT an approval to ship as safe.
      await assertSucceeds(roleless.collection("admin_invites").get());
      await assertSucceeds(roleless.collection("admins").get());
      console.log("RELEASE_HOLD_ROLELESS_ADMIN_GENERAL_MANAGER_ALLOWED_BY_CURRENT_RULES");
    });

    await t.test("release-hold observation: rules permit manager deleting final gateway", async () => {
      // This records existing RULES behavior, not a desired safety property:
      // client anchor checks alone cannot defend against legacy clients.
      await assertSucceeds(manager.doc("admin_entry_access/" + secondaryAccount)
        .delete());
      console.log("RELEASE_HOLD_LAST_GM_GATEWAY_DELETE_ALLOWED_BY_CURRENT_RULES");
    });
  } finally {
    await env.cleanup();
  }
});
