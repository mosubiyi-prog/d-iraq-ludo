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
