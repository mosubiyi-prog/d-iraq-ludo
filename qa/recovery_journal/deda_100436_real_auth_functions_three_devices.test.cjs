"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase/app");
const {getAuth, connectAuthEmulator, signInAnonymously,
  signInWithEmailAndPassword, linkWithCredential, EmailAuthProvider,
  getIdToken, signOut} = require("firebase/auth");
const {getFirestore, connectFirestoreEmulator, doc, setDoc, getDoc,
  updateDoc, deleteDoc, serverTimestamp} = require("firebase/firestore");
const {getFunctions, connectFunctionsEmulator, httpsCallable}
  = require("firebase/functions");
const {initializeApp: adminInitialize, deleteApp: adminDelete}
  = require("firebase-admin/app");
const {getFirestore: adminDbFor} = require("firebase-admin/firestore");

// Real Auth Emulator: independent Firebase apps model different phones.
// Real Functions Emulator: httpsCallable carries the REAL Auth ID token.
// Real Firestore Emulator: candidate security rules, real transactions.
//
// This QA Functions wrapper BYPASSES AppCheck locally on demo- projects.
// It is NOT an AppCheck proof. Never export this wrapper in production.
// These tests do NOT invoke the original Flutter app or published Firebase.

// Match the Firebase CLI project exactly: Auth token audience, Functions
// callable endpoint and Admin SDK Firestore all must share one demo project.
const PROJECT = "demo-deda-100436-journal-qa";
const accountKey = "9647712345678";
const pin = "123456";
const email = accountKey + "@deda-login.invalid";
const originalId = "@DEDA-ABC123";
const install = letter => letter.repeat(48);
const apps = [];
const clients = [];

function client(name) {
  const app = initializeApp({
    apiKey: "fake-demo-api-key",
    authDomain: PROJECT + ".firebaseapp.com",
    projectId: PROJECT,
    appId: "1:1234567890:web:" + name,
  }, name);
  apps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, "http://127.0.0.1:9099",
      {disableWarnings: true});
  const db = getFirestore(app);
  connectFirestoreEmulator(db, "127.0.0.1", 8098);
  const functions = getFunctions(app, "us-central1");
  connectFunctionsEmulator(functions, "127.0.0.1", 5001);
  const out = {name, auth, db, functions};
  clients.push(out);
  return out;
}

function requestGrant(c, id) {
  return httpsCallable(c.functions,
      "dedaIssueLinkedOriginalUidDeviceGrantQa")({
    accountKey, originalId, installId: id,
  });
}
function ownUser(c, uid) {
  return getDoc(doc(c.db, "users", uid));
}
function sessionData(uid, deviceId) {
  return {
    uid, accountKey, installId: deviceId,
    signedInAt: serverTimestamp(), lastSeenAt: serverTimestamp(),
  };
}
const sessionDoc = (c, uid) => doc(c.db, "deda_sessions", uid);

test("Auth+Functions+Firestore: original PIN link and three independent devices preserve ORIGINAL UID", {
  timeout: 120000,
}, async (t) => {
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, "127.0.0.1:9099");
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, "127.0.0.1:8098");
  assert.equal(process.env.DEDA_LINKED_OWNER_GRANT_ISSUER_ENABLED, "true");
  const admApp = adminInitialize({projectId: PROJECT},
      "deda-100436-real-auth-three-phones-admin");
  const dbAdmin = adminDbFor(admApp);
  try {
    const first = client("original_phone");
    // Fail CLOSED if Firebase CLI silently started with allow-all rules.
    // Unauthenticated reads of deda_sessions are forbidden by 100436 rules.
    await assert.rejects(
      getDoc(doc(first.db, "deda_sessions", "unauthenticated-uid")),
      /permission-denied/i,
    );
    console.log("QA_CONFIRMED_FIRESTORE_RULES_DENY_UNAUTH_READ");
    const oldAnon = await signInAnonymously(first.auth);
    const originalUid = oldAnon.user.uid;
    assert.ok(originalUid && originalUid.length > 10);
    assert.equal(first.auth.currentUser.isAnonymous, true);

    // Seed ONLY original-phone canonical records via Emulator Admin SDK.
    // No actual client can invent a new preexisting owner directory/route.
    await Promise.all([
      dbAdmin.doc("deda_credentials/" + accountKey).set({
        accountKey, pin, createdUid: originalUid, active: true,
      }),
      dbAdmin.doc("deda_account_directory/" + accountKey).set({
        accountKey, createdUid: originalUid, active: true,
      }),
      dbAdmin.doc("users/" + originalUid).set({
        accountKey, sharePersonalId: originalId,
        name: "Original Owner", accountType: "user",
      }),
      dbAdmin.doc("deda_account_profiles/" + accountKey).set({
        accountKey, name: "Original Owner", phone: accountKey,
        accountType: "user", trustedInstallIds: [install("a")],
      }),
      dbAdmin.doc("deda_share_ids/" + originalId).set({
        publicId: originalId, kind: "personal",
        ownerUid: originalUid, active: true,
      }),
    ]);

    await t.test("original anonymous UID proves six-digit PIN on actual Firestore Rules", async () => {
      const attempt=doc(first.db,"deda_auth_attempts",originalUid);
      await setDoc(attempt,{
        uid:originalUid,accountKey,pin,
        createdAt:serverTimestamp(),
      });
      await setDoc(sessionDoc(first,originalUid),
          sessionData(originalUid,install("a")));
      assert.equal((await getDoc(sessionDoc(first,originalUid))).data().uid,
          originalUid);
    });

    await t.test("original device links Email/Password to existing UID, not a new account", async () => {
      const credential=EmailAuthProvider.credential(email,pin);
      const linked=await linkWithCredential(first.auth.currentUser,credential);
      assert.equal(linked.user.uid,originalUid);
      assert.equal(first.auth.currentUser.uid,originalUid);
      assert.equal(first.auth.currentUser.isAnonymous,false);
      assert.equal(first.auth.currentUser.email,email);
    });

    const second=client("replacement_phone_two");
    const third=client("replacement_phone_three");

    await t.test("wrong PIN rejected by actual Auth Emulator; cannot enter account", async () => {
      await assert.rejects(
        signInWithEmailAndPassword(second.auth,email,"000000"));
      assert.equal(second.auth.currentUser,null);
    });

    await t.test("independent phones 2 and 3 sign in with correct PIN to SAME UID", async () => {
      const [a,b]=await Promise.all([
        signInWithEmailAndPassword(second.auth,email,pin),
        signInWithEmailAndPassword(third.auth,email,pin),
      ]);
      assert.equal(a.user.uid,originalUid);
      assert.equal(b.user.uid,originalUid);
      assert.equal(first.auth.currentUser.uid,originalUid);
      assert.equal(second.auth.currentUser.uid,originalUid);
      assert.equal(third.auth.currentUser.uid,originalUid);
      assert.equal((await getIdToken(a.user,true)).length>50,true);
      assert.equal((await getIdToken(b.user,true)).length>50,true);
    });

    await t.test("without grant, replacement phone cannot overwrite same UID session", async () => {
      await assert.rejects(setDoc(sessionDoc(second,originalUid),
          sessionData(originalUid,install("b"))));
    });

    await t.test("App Check enforcement rejects valid Auth token when App Check token is MISSING", async () => {
      // The raw candidate callable sets enforceAppCheck:true, unlike the
      // QA-only bypass callable used for the actual 3-phone identity tests.
      // This tests denial of a missing token in Functions Emulator; it does
      // NOT verify a genuine Play Integrity attestation from an Android app.
      const guarded = httpsCallable(second.functions,
          "dedaIssueLinkedOriginalUidDeviceGrant");
      await assert.rejects(
        guarded({accountKey, originalId, installId: install("b")}),
        (error) => {
          assert.match(String(error.code || ""),
              /functions\/(unauthenticated|permission-denied)/);
          return true;
        },
      );
    });

    await t.test("REAL auth tokens reach local HTTPS Functions callable and grant each device", async () => {
      const [g2,g3]=await Promise.all([
        requestGrant(second,install("b")),
        requestGrant(third,install("c")),
      ]);
      assert.equal(g2.data.approved,true);
      assert.equal(g3.data.approved,true);
      const limits=(await dbAdmin.doc(
          "deda_recovery_session_grant_limits/"+originalUid).get()).data();
      assert.equal(limits.ownerUid,originalUid);
      assert.equal(limits.count,2);
    });

    await t.test("both replacements obtain original UID session without changing Auth sign-ins", async () => {
      const [write2,write3]=await Promise.allSettled([
        setDoc(sessionDoc(second,originalUid),
            sessionData(originalUid,install("b"))),
        setDoc(sessionDoc(third,originalUid),
            sessionData(originalUid,install("c"))),
      ]);
      assert.equal(write2.status,"fulfilled");
      assert.equal(write3.status,"fulfilled");

      const saved=(await dbAdmin.doc("deda_sessions/"+originalUid).get()).data();
      assert.equal(saved.uid,originalUid);
      assert.equal(saved.accountKey,accountKey);
      // KNOWN DESIGN LIMIT: the shared legacy deda_sessions document retains
      // only ONE installId, even while 3 independent Auth tokens remain live.
      assert.ok([install("b"),install("c")].includes(saved.installId));
      console.log("QA_KNOWN_LIMIT_SINGLE_GLOBAL_INSTALL_ID");
    });

    await t.test("device A and B retain equal protected account READ/WRITE rights after installId changes", async () => {
      const profile = c => doc(c.db, "deda_account_profiles", accountKey);
      const [firstRead, secondRead] = await Promise.all([
        getDoc(profile(first)), getDoc(profile(second)),
      ]);
      assert.equal(firstRead.data().accountKey,accountKey);
      assert.equal(secondRead.data().accountKey,accountKey);
      const lastInstall=(await dbAdmin.doc("deda_sessions/"+originalUid).get()).data().installId;
      assert.ok([install("b"),install("c")].includes(lastInstall));
      // Both devices update ONLY their permitted non-financial lastSeenAt.
      await updateDoc(profile(first),{lastSeenAt: serverTimestamp()});
      await updateDoc(profile(second),{lastSeenAt: serverTimestamp()});
      const [afterA,afterB] = await Promise.all([
        getDoc(profile(first)),getDoc(profile(second)),
      ]);
      assert.equal(afterA.data().accountKey, accountKey);
      assert.equal(afterB.data().accountKey, accountKey);
      assert.ok(afterA.data().lastSeenAt);
      assert.ok(afterB.data().lastSeenAt);
    });

    await t.test("linked phone cannot delete shared UID session and interrupt other phones", async () => {
      await assert.rejects(deleteDoc(sessionDoc(second,originalUid)),
          /permission-denied/i);
      const row=await getDoc(sessionDoc(first,originalUid));
      assert.equal(row.exists(),true);
      assert.equal(row.data().uid,originalUid);
    });

    await t.test("original/second/third remain independently authenticated and can read own profile", async () => {
      for(const c of [first,second,third]){
        assert.equal(c.auth.currentUser.uid,originalUid);
        assert.equal(c.auth.currentUser.email,email);
        const token=await getIdToken(c.auth.currentUser,true);
        assert.ok(token.length>50);
        const profile=await ownUser(c,originalUid);
        assert.equal(profile.data().accountKey,accountKey);
        assert.equal(profile.data().sharePersonalId,originalId);
      }
    });

    await t.test("other anonymous user cannot borrow the original UID grant or session", async () => {
      const unrelated=client("another_unrelated_account");
      const different=await signInAnonymously(unrelated.auth);
      assert.notEqual(different.user.uid,originalUid);
      await assert.rejects(requestGrant(unrelated,install("d")));
      await assert.rejects(setDoc(sessionDoc(unrelated,originalUid),
          sessionData(originalUid,install("d"))));
      assert.equal(first.auth.currentUser.uid,originalUid);
      assert.equal(second.auth.currentUser.uid,originalUid);
      assert.equal(third.auth.currentUser.uid,originalUid);
    });

    await t.test("signing out phone 2 cannot sign out phone 1 or phone 3", async () => {
      await signOut(second.auth);
      assert.equal(second.auth.currentUser,null);
      assert.equal(first.auth.currentUser.uid,originalUid);
      assert.equal(third.auth.currentUser.uid,originalUid);
      await getIdToken(first.auth.currentUser,true);
      await getIdToken(third.auth.currentUser,true);
    });

    await t.test("issuer cannot bootstrap a principal once assigned admin role", async () => {
      await dbAdmin.doc("admins/"+originalUid).set({
        active:true,status:"active",role:"general_manager",
      });
      await assert.rejects(requestGrant(third,install("d")));
      assert.equal(third.auth.currentUser.uid,originalUid);
      await dbAdmin.doc("admins/"+originalUid).delete();
    });

    // Local emulator flow tests the remote Firebase SDKs; it does NOT run
    // the production Flutter main.dart or test dynamic on-device UID gates.
  } finally {
    for(const c of clients){
      try {if(c.auth.currentUser)await signOut(c.auth);}catch(_){}
    }
    for(const app of apps){try{await deleteApp(app);}catch(_){}}
    await adminDelete(admApp);
  }
});
