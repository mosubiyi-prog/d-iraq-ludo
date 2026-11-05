"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase/app");
const {getAuth, connectAuthEmulator, signInAnonymously,
  linkWithCredential, EmailAuthProvider, signInWithEmailAndPassword} =
  require("firebase/auth");
const {getFirestore, connectFirestoreEmulator, doc, setDoc,
  getDocFromServer, getDocsFromServer, collection, query, orderBy, limit,
  updateDoc, deleteDoc, serverTimestamp} =
  require("firebase/firestore");
const {initializeApp: initializeAdmin, deleteApp: deleteAdmin} =
  require("firebase-admin/app");
const {getFirestore: adminFirestore} = require("firebase-admin/firestore");

// The OLD anonymous phone writes original bytes exactly once before linking.
// Two NEW phones authenticate to SAME UID, read those immutable artifacts.
// No Firebase Functions, no balances, grants or production deployment.
const project="demo-deda-100436-journal-qa";
const account="9647900123456";
const originalId="@DEDA-ARCH01";
const email=account+"@deda-login.invalid";
const pin="123456";
const install="a".repeat(48);
const capture="legacy_spark_archive_verified_20261105";
const apps=[];
function phone(s) {
  const app=initializeApp({
    apiKey:"demo-only",
    projectId:project,
    authDomain:project+".firebaseapp.com",
    appId:"1:1234567890:web:spark_prelink_"+s,
  },"stage2-spark-prelink-"+s);
  apps.push(app);
  const auth=getAuth(app);
  connectAuthEmulator(auth,"http://127.0.0.1:9099",{disableWarnings:true});
  const db=getFirestore(app);
  connectFirestoreEmulator(db,"127.0.0.1",8098);
  return {auth,db};
}
const progress="deda_progress_evidence/"+account+"/captures/"+capture;
const purchase="deda_purchase_evidence/"+account+"/captures/"+capture;
function fields(uid,kind,records,installId=install) {
  return {format:1,kind,accountKey:account,sourceUid:uid,
    installId,captureId:capture,records,createdAt:serverTimestamp()};
}
const progressRecords={
  taskPoints:'{"level":4,"points":150}',
  socialCoinsAndXp:'{"xp":150}',
  earnedDiamonds:'{"balance":200}',
};
const purchaseRecords={originalId,progressCaptureId:capture,
  localSnapshot:'{"format":1,"historical":"untrusted"}'};

test("Spark original-phone prelink archive — Auth + Firestore emulator, immutable and same UID",{
  timeout:120000,
},async t=>{
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,"127.0.0.1:9099");
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST,"127.0.0.1:8098");
  const admin=initializeAdmin({projectId:project},"spark-prelink-admin-unique");
  try{
    const old=phone("old");
    const owner=await signInAnonymously(old.auth);
    const uid=owner.user.uid;
    const a=adminFirestore(admin);
    await Promise.all([
      a.doc("deda_credentials/"+account).set({
        accountKey:account,createdUid:uid,active:true,pin}),
      a.doc("deda_account_directory/"+account).set({
        accountKey:account,createdUid:uid,active:true}),
      a.doc("users/"+uid).set({
        accountKey:account,sharePersonalId:originalId,accountType:"user"}),
      a.doc("deda_share_ids/"+originalId).set({
        publicId:originalId,kind:"personal",active:true,ownerUid:uid}),
      a.doc("deda_account_profiles/"+account).set({
        accountKey:account,accountType:"user",trustedInstallIds:[install]}),
    ]);
    await t.test("old phone proves legacy PIN, creates SAME UID session",async()=>{
      await setDoc(doc(old.db,"deda_auth_attempts",uid),{
        uid,accountKey:account,pin,createdAt:serverTimestamp(),
      });
      await setDoc(doc(old.db,"deda_sessions",uid),{
        uid,accountKey:account,installId:install,
        signedInAt:serverTimestamp(),lastSeenAt:serverTimestamp(),
      });
    });
    await t.test("new phone cannot use old phone account before original UID links",async()=>{
      const replacement=phone("unlinked");
      await assert.rejects(signInWithEmailAndPassword(replacement.auth,email,pin));
    });
    await t.test("mismatched installation, account and absent parent purchase cannot archive",async()=>{
      await assert.rejects(setDoc(doc(old.db,purchase),
        fields(uid,"legacy-purchase-evidence",purchaseRecords)),
        /permission-denied/i);
      await assert.rejects(setDoc(doc(old.db,progress),
        fields(uid,"legacy-local-evidence",progressRecords,"b".repeat(48))),
        /permission-denied/i);
      await assert.rejects(setDoc(doc(old.db,progress),
        {...fields(uid,"legacy-local-evidence",progressRecords),
          accountKey:"9647900000000"}),/permission-denied/i);
    });
    await t.test("original anonymous UID archives progress and purchase once",async()=>{
      await setDoc(doc(old.db,progress),
        fields(uid,"legacy-local-evidence",progressRecords));
      await setDoc(doc(old.db,purchase),
        fields(uid,"legacy-purchase-evidence",purchaseRecords));
      const p=await getDocFromServer(doc(old.db,progress));
      const q=await getDocFromServer(doc(old.db,purchase));
      assert.deepEqual(p.data().records,progressRecords);
      assert.deepEqual(q.data().records,purchaseRecords);
    });
    await t.test("original phone cannot overwrite, delete or forge other UID",async()=>{
      await assert.rejects(updateDoc(doc(old.db,progress),{
        records:{...progressRecords,earnedDiamonds:'{"balance":999999}'}
      }),/permission-denied/i);
      await assert.rejects(deleteDoc(doc(old.db,progress)),/permission-denied/i);
      await assert.rejects(setDoc(doc(old.db,progress),
        fields("forged-owner-uid","legacy-local-evidence",progressRecords)),
        /permission-denied/i);
    });
    await t.test("original phone links existing anonymous UID without changing canonical archives",async()=>{
      const linked=await linkWithCredential(old.auth.currentUser,
        EmailAuthProvider.credential(email,pin));
      assert.equal(linked.user.uid,uid);
      assert.equal(linked.user.isAnonymous,false);
    });
    await t.test("two replacement phones read BOTH immutable sources by same UID without Functions",async()=>{
      const second=phone("replacement2");
      const third=phone("replacement3");
      for(const device of [second,third]){
        const result=await signInWithEmailAndPassword(device.auth,email,pin);
        assert.equal(result.user.uid,uid);
        assert.deepEqual((await getDocFromServer(doc(device.db,progress)))
          .data().records,progressRecords);
        const history=await getDocsFromServer(query(
          collection(device.db,"deda_progress_evidence",account,"captures"),
          orderBy("createdAt","desc"),limit(26)));
        assert.equal(history.size,1);
        assert.deepEqual(history.docs[0].data().records,progressRecords);
        await assert.rejects(getDocsFromServer(query(
          collection(device.db,"deda_progress_evidence",account,"captures"),
          orderBy("createdAt","desc"),limit(27))),/permission-denied/i);
        assert.deepEqual((await getDocFromServer(doc(device.db,purchase)))
          .data().records,purchaseRecords);
        await assert.rejects(setDoc(doc(device.db,progress),
          fields(uid,"legacy-local-evidence",progressRecords)),
          /permission-denied/i);
      }
      const session=await a.doc("deda_sessions/"+uid).get();
      assert.equal(session.data().installId,install);
    });
    await t.test("unrelated anonymous UID cannot see either archive",async()=>{
      const outsider=phone("stranger");
      await signInAnonymously(outsider.auth);
      await assert.rejects(getDocFromServer(doc(outsider.db,progress)),
        /permission-denied/i);
      await assert.rejects(getDocsFromServer(query(
          collection(outsider.db,"deda_progress_evidence",account,"captures"),
          orderBy("createdAt","desc"),limit(26))),/permission-denied/i);
      await assert.rejects(getDocFromServer(doc(outsider.db,purchase)),
        /permission-denied/i);
    });
  }finally{
    await Promise.allSettled(apps.map(deleteApp));
    await deleteAdmin(admin);
  }
});