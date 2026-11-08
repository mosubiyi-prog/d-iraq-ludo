"use strict";
// Test Google root using local Admin Firestore transactions, and real Auth
// Emulator-issued PASSWORD/ANONYMOUS tokens for negative controls.
// Positive "google.com" provider is a controlled server mock; Google OAuth
// cannot be claimed tested end-to-end by a local Auth Emulator fixture.
// Never run against non-demo project or without both local emulators.
const test=require("node:test"),assert=require("node:assert/strict");
const {initializeApp:adminAppInit,deleteApp:adminDelete}=require("firebase-admin/app");
const {getFirestore}=require("firebase-admin/firestore");
const {getAuth:adminGetAuth}=require("firebase-admin/auth");
const {initializeApp:clientInit,deleteApp:clientDelete}=require("firebase/app");
const {getAuth:clientGetAuth,connectAuthEmulator,
  signInAnonymously,signInWithEmailAndPassword,signOut}=require("firebase/auth");
const {reserveNewGoogleRoot}=require(
  "../deda_100441_stage7_google_uid_root_reservation_PRIVATE_NOT_EXPORTED.js");
const P="demo-deda-stage7-google-root-no-phone-claim";
if(process.env.GCLOUD_PROJECT!==P ||
  process.env.FIREBASE_AUTH_EMULATOR_HOST!=="127.0.0.1:9099" ||
  process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080")
  throw Error("BOTH_LOCAL_EMULATORS_REQUIRED");
const UID_A="stage7-google-only-synthetic-owner-A";
const UID_B="stage7-google-only-synthetic-owner-B";
const SUB="stage7-google-subject-123456";
const KEY=Buffer.alloc(40,22);
const NOW=Date.UTC(2026,10,8,12);
let adminApp,db,auth,clientApp,clientAuth,passwordToken,anonToken;
const fakeGoogleAuth=(uid=UID_A,subject=SUB)=>({
  async verifyIdToken(_,revoked) {
    assert.equal(revoked,true);
    return {uid,firebase:{sign_in_provider:"google.com"}};
  },
  async getUser(requested) {
    assert.equal(requested,uid);
    return {uid,disabled:false,customClaims:{},
      providerData:[{providerId:"google.com",uid:subject}]};
  },
});
function request(idToken) {return {idToken};}
const params=(authPort,enabled=true)=>({
  enabled,auth:authPort,db,subjectIndexKey:KEY,now:()=>NOW});
async function count(){
  return {
    a:(await db.collection("deda_google_uid_reservations_private_v1").get()).size,
    b:(await db.collection("deda_google_subject_index_private_v1").get()).size,
    directory:(await db.collection("deda_account_directory").get()).size,
    users:(await db.collection("users").get()).size,
  };
}
test.before(async()=>{
  adminApp=adminAppInit({projectId:P},"stage7-admin");
  db=getFirestore(adminApp);
  auth=adminGetAuth(adminApp);
  await auth.createUser({uid:"stage7-password-user",
    email:"stage7-only@invalid.test",password:"LocalOnly-Password12345!"});
  clientApp=clientInit({projectId:P,apiKey:"demo-api-only",
    authDomain:"localhost"},"stage7-client");
  clientAuth=clientGetAuth(clientApp);
  connectAuthEmulator(clientAuth,"http://127.0.0.1:9099",{disableWarnings:true});
  passwordToken=(await signInWithEmailAndPassword(
    clientAuth,"stage7-only@invalid.test","LocalOnly-Password12345!")).user;
  passwordToken=await passwordToken.getIdToken(true);
  await signOut(clientAuth);
  anonToken=(await signInAnonymously(clientAuth)).user;
  anonToken=await anonToken.getIdToken(true);
});
test.after(async()=>{
  if(clientAuth?.currentUser)await signOut(clientAuth).catch(()=>{});
  if(clientApp)await clientDelete(clientApp).catch(()=>{});
  if(adminApp)await adminDelete(adminApp).catch(()=>{});
});
test("genuine local password bearer cannot act as Google first owner",async()=>{
  const out=await reserveNewGoogleRoot(request(passwordToken),params(auth));
  assert.equal(out.classification,"UNVERIFIED_GOOGLE_PROVIDER");
  assert.deepEqual(await count(),{a:0,b:0,directory:0,users:0});
});
test("genuine local anonymous bearer never reserves Google ownership",async()=>{
  const out=await reserveNewGoogleRoot(request(anonToken),params(auth));
  assert.equal(out.classification,"UNVERIFIED_GOOGLE_PROVIDER");
  assert.deepEqual(await count(),{a:0,b:0,directory:0,users:0});
});
test("synthetic Google provider proof with REAL Firestore transaction reserves only UID",async()=>{
  const out=await reserveNewGoogleRoot(
    request("fake-google-issuer-idtoken-not-live-123456"),params(fakeGoogleAuth()));
  assert.equal(out.classification,"GOOGLE_UID_RESERVED_PHONE_UNVERIFIED");
  assert.equal(out.phoneOwnershipProved,false);
  assert.deepEqual(await count(),{a:1,b:1,directory:0,users:0});
  const row=await db.doc("deda_google_uid_reservations_private_v1/"+UID_A).get();
  assert.equal(row.data().uid,UID_A);
  assert.equal(row.data().phoneClaimed,false);
});
test("second transaction for same Google UID is idempotent on REAL Firestore",async()=>{
  const out=await reserveNewGoogleRoot(request("fake-google-issuer-idtoken-not-live-123456"),
    params(fakeGoogleAuth()));
  assert.equal(out.classification,"SAME_UID_PENDING_REVIEW_NO_DUPLICATE");
  assert.deepEqual(await count(),{a:1,b:1,directory:0,users:0});
});
test("different UID with same verified Google subject cannot steal index",async()=>{
  const out=await reserveNewGoogleRoot(request("fake-google-issuer-idtoken-not-live-123456"),
    params(fakeGoogleAuth(UID_B,SUB)));
  assert.equal(out.classification,"PRIOR_RESERVATION_CONFLICT_OR_EXPIRED");
  assert.equal((await db.doc(
    "deda_google_uid_reservations_private_v1/"+UID_A).get()).data().uid,UID_A);
  assert.deepEqual(await count(),{a:1,b:1,directory:0,users:0});
});
test("existing user UID cannot register new Google owner or affect profile",async()=>{
  await db.doc("users/"+UID_B).set({accountKey:"07111111111",
    immutableOriginalId:"@DEDA-ABC123"});
  const out=await reserveNewGoogleRoot(request("fake-google-issuer-idtoken-not-live-123456"),
    params(fakeGoogleAuth(UID_B,"fresh-google-subject-98765")));
  assert.equal(out.classification,"EXISTING_ACCOUNT_OR_ADMIN_REQUIRES_SEPARATE_REVIEW");
  assert.equal((await db.doc("users/"+UID_B).get()).data().accountKey,"07111111111");
  assert.equal((await db.collection("deda_google_uid_reservations_private_v1").get()).size,1);
});
