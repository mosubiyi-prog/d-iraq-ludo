"use strict";
// Local-only fixture for the REAL FlutterFire browser integration test.
// Uses Admin SDK against Firestore/Auth emulators for demo- project only.
// Does not connect to any production Firebase project or account.
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");

const projectId = "demo-deda-100436-journal-qa";
const uid = "deda-100436-flutterfire-original-uid";
const accountKey = "9647712345678";
const originalId = "@DEDA-ABC123";
const pin = "123456";
async function main() {
  assert.equal(process.env.GCLOUD_PROJECT || process.env.GCLOUD_PROJECT_ID ||
      projectId, projectId);
  assert.match(process.env.FIREBASE_AUTH_EMULATOR_HOST || "", /^127\.0\.0\.1:9099$/);
  assert.match(process.env.FIRESTORE_EMULATOR_HOST || "", /^127\.0\.0\.1:8098$/);
  const app = initializeApp({projectId}, "deda-flutterfire-qa-seed");
  try {
    await getAuth(app).createUser({
      uid, email: accountKey + "@deda-login.invalid",
      password: pin, emailVerified: false,
    });
    const db = getFirestore(app);
    const now = Timestamp.now();
    await Promise.all([
      db.doc("deda_recovery_session_grant_limits/" + uid).set({
        ownerUid: uid, count: 0,
        windowStartedAt: Timestamp.fromMillis(Date.now()-1000),
        updatedAt: Timestamp.fromMillis(Date.now()-1000),
      }),
      db.doc("deda_account_directory/" + accountKey).set({
        accountKey, createdUid: uid, active: true,
      }),
      db.doc("deda_credentials/" + accountKey).set({
        accountKey, createdUid: uid, pin, active: true,
      }),
      db.doc("users/" + uid).set({
        accountKey, sharePersonalId: originalId,
        name: "DEDA test original owner", accountType: "user",
      }),
      db.doc("deda_share_ids/" + originalId).set({
        publicId: originalId, kind: "personal",
        ownerUid: uid, active: true,
      }),
      db.doc("deda_account_profiles/" + accountKey).set({
        accountKey, name: "DEDA test original owner",
        phone: accountKey, accountType: "user",
        trustedInstallIds: ["a".repeat(48)],
      }),
      db.doc("deda_sessions/" + uid).set({
        uid, accountKey, installId: "a".repeat(48),
        signedInAt: now, lastSeenAt: now,
      }),
    ]);
    const auth = await getAuth(app).getUser(uid);
    const session = await db.doc("deda_sessions/" + uid).get();
    assert.equal(auth.uid, uid);
    assert.equal(session.data()?.uid, uid);
    console.log("PASS_DEMO_FLUTTERFIRE_UID_AND_SERVER_FIXTURE_SEEDED");
  } finally {
    await deleteApp(app);
  }
}
main().catch((error) => {
  console.error("FAIL_DEMO_FLUTTERFIRE_SEED", error.message);
  process.exitCode = 1;
});
