"use strict";

// Stage 5: TWO INDEPENDENT Firebase Auth client app instances (representing
// two phones) with the SAME independently verified Firebase account.
// Artificial emails/passwords ONLY; password login here demonstrates UID
// continuity, NOT sufficient ownership evidence in production with PIN.
// Both Auth and Firestore emulators must run on localhost in a demo project.
const test = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp:adminInit,deleteApp:adminDelete}
  = require("firebase-admin/app");
const {getAuth:adminGetAuth} = require("firebase-admin/auth");
const {getFirestore} = require("firebase-admin/firestore");
const {initializeApp:clientInit,deleteApp:clientDelete}
  = require("firebase/app");
const {getAuth,connectAuthEmulator,signInWithEmailAndPassword,
  signInAnonymously,signOut} = require("firebase/auth");
const {assessSameUidRecovery}
  = require("../deda_100441_same_uid_recovery_readiness_PRIVATE_NOT_EXPORTED.js");

const projectId="demo-deda-100441-two-device-continuity";
if(process.env.GCLOUD_PROJECT!==projectId ||
  process.env.FIREBASE_AUTH_EMULATOR_HOST!=="127.0.0.1:9099" ||
  process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080")
  throw Error("DEDA_LOCAL_TWO_DEVICE_EMULATORS_REQUIRED");

const ACCOUNT="07111111111",ORIGINAL="@DEDA-ABC123",
  UID="deda-same-uid-test-account",UNRELATED="deda-unrelated-account";
const email=ACCOUNT+"@deda-login.invalid";
const password="EmulatorOnlyStrongSecret-2026-do-not-use";
const PIN="617283"; // never a real user PIN

let adminApp, authAdmin, db, app1,app2,auth1,auth2,token1,token2;
function nonAuthorized(out) {
  assert.equal(out.decision,"HOLD_INDEPENDENT_OWNER_PROOF_AND_SERVER_REVIEW");
  for(const k of ["canSignIn","canCreateUid","canMintToken",
      "canBootstrapSession","canWriteFirestore","canTransferOwnership",
      "canModifyAdmin","canModifyWallet","canModifyGifts","canModifyLeague"]){
    assert.equal(out[k],false);
  }
}
test.before(async()=>{
  adminApp=adminInit({projectId},"deda-stage5-admin");
  authAdmin=adminGetAuth(adminApp);
  db=getFirestore(adminApp);
  await authAdmin.createUser({uid:UID,email,password,emailVerified:true});
  await authAdmin.createUser({
    uid:UNRELATED,email:"other-test@invalid.example",
    password:"OtherStrongEmulatorOnlySecret123!",
  });
  const docs={
    ["deda_account_directory/"+ACCOUNT]:{
      accountKey:ACCOUNT,createdUid:UID,active:true},
    ["deda_credentials/"+ACCOUNT]:{
      accountKey:ACCOUNT,createdUid:UID,pin:PIN,active:true},
    ["deda_share_ids/"+ORIGINAL]:{
      publicId:ORIGINAL,kind:"personal",ownerUid:UID,active:true},
    ["users/"+UID]:{accountKey:ACCOUNT,sharePersonalId:ORIGINAL},
    ["deda_social_profiles/"+ORIGINAL]:{
      publicId:ORIGINAL,ownerUid:UID},
    ["deda_sessions/"+UID]:{uid:UID,accountKey:ACCOUNT},
    ["deda_wallets/"+UID]:{diamonds:1234},
    ["deda_gifts/"+UID]:{giftCount:5},
  };
  const batch=db.batch();
  for(const [p,v] of Object.entries(docs))batch.set(db.doc(p),v);
  await batch.commit();
  app1=clientInit({projectId,apiKey:"demo-key-1",authDomain:"localhost"},
    "deda-stage5-device-1");
  app2=clientInit({projectId,apiKey:"demo-key-2",authDomain:"localhost"},
    "deda-stage5-device-2");
  auth1=getAuth(app1);
  auth2=getAuth(app2);
  connectAuthEmulator(auth1,"http://127.0.0.1:9099",{disableWarnings:true});
  connectAuthEmulator(auth2,"http://127.0.0.1:9099",{disableWarnings:true});
  const a=await signInWithEmailAndPassword(auth1,email,password);
  const b=await signInWithEmailAndPassword(auth2,email,password);
  assert.equal(a.user.uid,UID);
  assert.equal(b.user.uid,UID);
  token1=await a.user.getIdToken(true);
  token2=await b.user.getIdToken(true);
});
test.after(async()=>{
  for(const a of [auth1,auth2]){
    if(a?.currentUser)await signOut(a).catch(()=>{});
  }
  for(const a of [app1,app2]){
    if(a)await clientDelete(a).catch(()=>{});
  }
  if(adminApp)await adminDelete(adminApp).catch(()=>{});
});
function req(idToken){
  return {idToken,accountKey:ACCOUNT,originalId:ORIGINAL};
}
test("device 1 and device 2 have same stable Firebase Auth UID, different client app sessions",async()=>{
  assert.equal(auth1.currentUser.uid,UID);
  assert.equal(auth2.currentUser.uid,UID);
  assert.notEqual(auth1,auth2);
  // Firebase may legitimately issue byte-identical tokens in one second.
  assert.equal((await authAdmin.verifyIdToken(token1)).uid,UID);
  assert.equal((await authAdmin.verifyIdToken(token2)).uid,UID);
});
test("legacy 6-digit PIN is never considered an independent provider even for same UID",async()=>{
  for(const token of [token1,token2]){
    const out=await assessSameUidRecovery(req(token),{auth:authAdmin,db});
    assert.equal(out.classification,"NO_PRELINKED_INDEPENDENT_PROVIDER");
    nonAuthorized(out);
  }
});
test("no new account directory, wallet, ID or gift row created by second device sign-in",async()=>{
  assert.equal((await db.doc("deda_account_directory/"+ACCOUNT).get()).data().createdUid,UID);
  assert.equal((await db.doc("deda_share_ids/"+ORIGINAL).get()).data().ownerUid,UID);
  assert.equal((await db.doc("deda_wallets/"+UID).get()).data().diamonds,1234);
  assert.equal((await db.doc("deda_gifts/"+UID).get()).data().giftCount,5);
  assert.equal((await db.doc("deda_sessions/"+UID).get()).data().uid,UID);
});
test("signing out TEST device 2 does not invalidate TEST device 1 UID",async()=>{
  await signOut(auth2);
  assert.equal(auth1.currentUser?.uid,UID);
  assert.equal(auth2.currentUser,null);
  const d2=await signInWithEmailAndPassword(auth2,email,password);
  assert.equal(d2.user.uid,UID);
  assert.equal(auth1.currentUser?.uid,UID);
});
test("anonymous test device 2 creates DIFFERENT UID, forbidden as original owner",async()=>{
  await signOut(auth2);
  const anon=await signInAnonymously(auth2);
  assert.notEqual(anon.user.uid,UID);
  const token=await anon.user.getIdToken(true);
  const result=await assessSameUidRecovery(req(token),{auth:authAdmin,db});
  assert.equal(result.classification,"NO_PRELINKED_INDEPENDENT_PROVIDER");
  nonAuthorized(result);
  assert.equal(auth1.currentUser.uid,UID);
  assert.equal((await db.doc("deda_share_ids/"+ORIGINAL).get()).data().ownerUid,UID);
});
test("Firestore account and finances are unaffected by anonymous blocked review",async()=>{
  const docs=[
    ["deda_account_directory/"+ACCOUNT,"createdUid",UID],
    ["deda_credentials/"+ACCOUNT,"createdUid",UID],
    ["deda_wallets/"+UID,"diamonds",1234],
    ["deda_gifts/"+UID,"giftCount",5],
    ["deda_share_ids/"+ORIGINAL,"ownerUid",UID],
  ];
  for(const [path,key,want] of docs) {
    assert.equal((await db.doc(path).get()).data()[key],want);
  }
});
