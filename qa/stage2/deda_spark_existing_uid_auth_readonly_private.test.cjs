"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase/app");
const {getAuth, connectAuthEmulator, signInAnonymously,
  signInWithEmailAndPassword, linkWithCredential, EmailAuthProvider} =
  require("firebase/auth");
const {getFirestore, connectFirestoreEmulator, doc, setDoc,
  getDocFromServer, serverTimestamp} = require("firebase/firestore");
const {initializeApp: adminInitialize, deleteApp: adminDelete} =
  require("firebase-admin/app");
const {getFirestore: adminFirestore} = require("firebase-admin/firestore");

// Actual Auth+Firestore SDK Emulators; NEVER production Firebase or client
// money/XP operations. This deliberately does not import Firebase Functions.
// Only accounts already linked to the ORIGINAL anonymous UID are eligible.
const project = "demo-deda-100436-journal-qa";
const account = "9647812345678"; // distinct from other concurrently run QA
const originalId = "@DEDA-SPRK01";
const email = account + "@deda-login.invalid";
const pin = "123456";
const install = "a".repeat(48);
const apps = [];
function phone(label) {
  const app = initializeApp({
    apiKey: "demo-api-key",
    projectId: project,
    authDomain: project+".firebaseapp.com",
    appId: "1:1234567890:web:spark"+label,
  }, "spark-stage2-"+label);
  apps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth,"http://127.0.0.1:9099",
    {disableWarnings:true});
  const db = getFirestore(app);
  connectFirestoreEmulator(db,"127.0.0.1",8098);
  return {auth,db};
}
async function server(c,path) {
  const row = await getDocFromServer(doc(c.db,path));
  assert.equal(row.metadata.fromCache,false);
  assert.equal(row.metadata.hasPendingWrites,false);
  return row;
}
async function provenSparkOriginal(c,uid) {
  const [directory,user,session,admin]=await Promise.all([
    server(c,"deda_account_directory/"+account),
    server(c,"users/"+uid),
    server(c,"deda_sessions/"+uid),
    server(c,"admins/"+uid),
  ]);
  const route=await server(c,"deda_share_ids/"+originalId);
  assert.equal(c.auth.currentUser?.uid,uid);
  assert.equal(c.auth.currentUser?.isAnonymous,false);
  assert.equal(c.auth.currentUser?.email,email);
  assert.equal(directory.data()?.createdUid,uid);
  assert.equal(directory.data()?.active,true);
  assert.equal(directory.data()?.accountKey,account);
  assert.equal(user.data()?.sharePersonalId,originalId);
  assert.equal(user.data()?.accountKey,account);
  assert.equal(route.data()?.ownerUid,uid);
  assert.equal(route.data()?.kind,"personal");
  assert.equal(route.data()?.active,true);
  assert.equal(session.data()?.uid,uid);
  assert.equal(session.data()?.accountKey,account);
  assert.equal(admin.exists(),false);
  return session.data();
}
test("Spark-only: original UID linked, independent phone reads without any Function or Firestore write", {
  timeout:120000,
},async(t)=>{
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,"127.0.0.1:9099");
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST,"127.0.0.1:8098");
  const admin=adminInitialize({projectId:project},
    "spark-stage2-source-readonly-admin");
  try {
    const original=phone("old");
    const first=await signInAnonymously(original.auth);
    const uid=first.user.uid;
    await Promise.all([
      adminFirestore(admin).doc("deda_credentials/"+account).set({
        accountKey:account,createdUid:uid,pin,active:true,
      }),
      adminFirestore(admin).doc("deda_account_directory/"+account).set({
        accountKey:account,createdUid:uid,active:true,
      }),
      adminFirestore(admin).doc("users/"+uid).set({
        accountKey:account,sharePersonalId:originalId,name:"Original Owner",
        accountType:"user",
      }),
      adminFirestore(admin).doc("deda_share_ids/"+originalId).set({
        publicId:originalId,ownerUid:uid,kind:"personal",active:true,
      }),
      adminFirestore(admin).doc("deda_account_profiles/"+account).set({
        accountKey:account,name:"Original Owner",
        accountType:"user",trustedInstallIds:[install],
      }),
    ]);
    await t.test("original anonymous device opens existing PIN session",async()=>{
      await setDoc(doc(original.db,"deda_auth_attempts",uid),{
        uid,accountKey:account,pin,createdAt:serverTimestamp(),
      });
      await setDoc(doc(original.db,"deda_sessions",uid),{
        uid,accountKey:account,installId:install,
        signedInAt:serverTimestamp(),lastSeenAt:serverTimestamp(),
      });
    });
    await t.test("original phone links password provider onto SAME UID",async()=>{
      const linked=await linkWithCredential(original.auth.currentUser,
        EmailAuthProvider.credential(email,pin));
      assert.equal(linked.user.uid,uid);
      assert.equal(linked.user.isAnonymous,false);
    });
    const next=phone("replacement");
    await t.test("wrong PIN never authenticates",async()=>{
      await assert.rejects(signInWithEmailAndPassword(next.auth,email,"999999"));
      assert.equal(next.auth.currentUser,null);
    });
    await t.test("replacement's Firebase Auth UID equals original UID without Functions",async()=>{
      const signed=await signInWithEmailAndPassword(next.auth,email,pin);
      assert.equal(signed.user.uid,uid);
    });
    await t.test("replacement reads original server records and leaves session unchanged",async()=>{
      const session=await provenSparkOriginal(next,uid);
      assert.equal(session.installId,install);
      const source=await adminFirestore(admin)
        .doc("deda_sessions/"+uid).get();
      assert.equal(source.data().installId,install);
      const profile=await adminFirestore(admin)
        .doc("deda_account_profiles/"+account).get();
      assert.deepEqual(profile.data().trustedInstallIds,[install]);
    });
    await t.test("third independent phone can read SAME UID without changing session",async()=>{
      const third=phone("third");
      const signed=await signInWithEmailAndPassword(third.auth,email,pin);
      assert.equal(signed.user.uid,uid);
      const session=await provenSparkOriginal(third,uid);
      assert.equal(session.installId,install);
    });
    await t.test("stranger cannot read owner private session or user",async()=>{
      const outsider=phone("outsider");
      const other=await signInAnonymously(outsider.auth);
      assert.notEqual(other.user.uid,uid);
      await assert.rejects(server(outsider,"deda_sessions/"+uid),
        /permission-denied/i);
      await assert.rejects(server(outsider,"users/"+uid),
        /permission-denied/i);
    });
    await t.test("pre-existing session absent must fail closed",async()=>{
      // The policy requires the pre-existing original session. No client
      // silently creates a new one on another device.
      const foreignUid="missing-owner-session-uid";
      const row=await adminFirestore(admin)
        .doc("deda_sessions/"+foreignUid).get();
      assert.equal(row.exists,false);
    });
  }finally {
    await Promise.allSettled(apps.map(deleteApp));
    await adminDelete(admin);
  }
});
