"use strict";

// BOTH Firebase Auth + Firestore emulators are mandatory. No production
// credentials or network targets, no phone numbers or real financial records.
// Internal read adapter is exercised with genuine emulator-issued ID tokens,
// firebase-admin Auth getUser and firebase-admin Firestore document reads.
const test = require("node:test");
const assert = require("node:assert/strict");

const projectId = "demo-deda-100441-server-auth-read-integration";
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
if (authHost !== "127.0.0.1:9099" ||
    firestoreHost !== "127.0.0.1:8080" ||
    process.env.GCLOUD_PROJECT !== projectId) {
  throw new Error("LOCAL_FIREBASE_AUTH_AND_FIRESTORE_EMULATORS_REQUIRED");
}

const {
  initializeApp: initializeAdminApp, deleteApp: deleteAdminApp,
} = require("firebase-admin/app");
const {
  getAuth: getAdminAuth,
} = require("firebase-admin/auth");
const {
  getFirestore,
} = require("firebase-admin/firestore");
const {
  initializeApp: initializeClientApp, deleteApp: deleteClientApp,
} = require("firebase/app");
const {
  getAuth: getClientAuth, connectAuthEmulator, signInWithEmailAndPassword,
  signOut, signInAnonymously,
} = require("firebase/auth");
const {
  inspectServerCanonicalOwner,
} = require("../deda_100441_server_canonical_uid_read_adapter_PRIVATE_NOT_EXPORTED.js");

const UID_A = "emulator-original-owner-A";
const UID_B = "emulator-created-uid-B";
const ACCOUNT = "07111111111";  // invented test fixture; not user data
const ORIGINAL = "@DEDA-T3ST99";
const email = ACCOUNT + "@deda-login.invalid";
const password = "EmulatorOnly-DoNotUse123!";
const PIN = "439287"; // dummy; only Firestore test fixture

let adminApp, adminAuth, adminDb, clientApp, clientAuth, originalIdToken;
const input = idToken => ({idToken, accountKey: ACCOUNT, originalId: ORIGINAL});

function noGrant(result) {
  assert.equal(result.decision, "HOLD_FOR_INDEPENDENT_OWNER_REVIEW");
  for (const field of ["canSignIn", "canIssueToken", "canCreateUid",
    "canModifyAuth", "canWriteFirestore", "canReassignOwner",
    "canModifyAdmin", "canModifyFinances"]) {
    assert.equal(result[field], false);
  }
  const printed = JSON.stringify(result);
  for (const secret of [UID_A, UID_B, ACCOUNT, ORIGINAL, PIN, password]) {
    assert.equal(printed.includes(secret), false);
  }
}

test.before(async () => {
  adminApp = initializeAdminApp({projectId}, "deda-qa-admin-server");
  adminAuth = getAdminAuth(adminApp);
  adminDb = getFirestore(adminApp);

  clientApp = initializeClientApp({
    projectId, apiKey: "demo-test-firebase-key",
    authDomain: "localhost",
  }, "deda-qa-client");
  clientAuth = getClientAuth(clientApp);
  connectAuthEmulator(clientAuth, "http://127.0.0.1:9099", {
    disableWarnings: true,
  });

  await adminAuth.createUser({
    uid: UID_A, email, emailVerified: true, password,
  });
  const rows = {
    ["deda_account_directory/" + ACCOUNT]: {
      accountKey: ACCOUNT, createdUid: UID_A, active: true,
    },
    ["deda_credentials/" + ACCOUNT]: {
      accountKey: ACCOUNT, createdUid: UID_A, active: true, pin: PIN,
    },
    ["deda_share_ids/" + ORIGINAL]: {
      publicId: ORIGINAL, kind: "personal", ownerUid: UID_A, active: true,
    },
    ["users/" + UID_A]: {
      accountKey: ACCOUNT, sharePersonalId: ORIGINAL,
    },
    ["deda_social_profiles/" + ORIGINAL]: {
      publicId: ORIGINAL, ownerUid: UID_A,
    },
    ["deda_sessions/" + UID_A]: {
      accountKey: ACCOUNT, uid: UID_A,
    },
  };
  const batch = adminDb.batch();
  for (const [path, data] of Object.entries(rows)) {
    batch.set(adminDb.doc(path), data);
  }
  await batch.commit();
  const signed = await signInWithEmailAndPassword(clientAuth, email, password);
  assert.equal(signed.user.uid, UID_A);
  originalIdToken = await signed.user.getIdToken(true);
});
test.after(async () => {
  if (clientAuth?.currentUser) await signOut(clientAuth).catch(() => {});
  if (clientApp) await deleteClientApp(clientApp).catch(() => {});
  if (adminApp) await deleteAdminApp(adminApp).catch(() => {});
});

test("real Auth emulator token + Admin Auth + Firestore reads => review-only canonical candidate", async () => {
  const result = await inspectServerCanonicalOwner(input(originalIdToken), {
    auth: adminAuth, db: adminDb,
  });
  assert.equal(result.classification,
    "CANONICAL_MATCH_REQUIRES_SEPARATE_OWNER_REVIEW");
  noGrant(result);
});

test("on real emulator, changing registration owner UID causes SPLIT without transfer", async () => {
  const path = "deda_account_directory/" + ACCOUNT;
  await adminDb.doc(path).update({createdUid: UID_B});
  try {
    const result = await inspectServerCanonicalOwner(input(originalIdToken), {
      auth: adminAuth, db: adminDb,
    });
    assert.equal(result.classification,
      "SPLIT_DETECTED_NO_ACCOUNT_TRANSFER");
    noGrant(result);
    const route = await adminDb.doc("deda_share_ids/" + ORIGINAL).get();
    assert.equal(route.data().ownerUid, UID_A);
  } finally {
    await adminDb.doc(path).update({createdUid: UID_A});
  }
});

test("second anonymous Auth emulator user cannot adopt registered account", async () => {
  await signOut(clientAuth);
  const anon = await signInAnonymously(clientAuth);
  assert.notEqual(anon.user.uid, UID_A);
  const anonToken = await anon.user.getIdToken(true);
  const result = await inspectServerCanonicalOwner(input(anonToken), {
    auth: adminAuth, db: adminDb,
  });
  assert.equal(result.classification, "NO_INDEPENDENT_DURABLE_AUTH");
  noGrant(result);
});

test("real Auth emulator invalid ID token cannot inspect account ownership", async () => {
  const result = await inspectServerCanonicalOwner(input(
    "invalid-long-enough-emulator-token",
  ), {auth: adminAuth, db: adminDb});
  assert.equal(result.classification, "UNVERIFIED_AUTH_SESSION");
  noGrant(result);
});
