"use strict";

// Genuine Firebase Auth + Firestore EMULATOR negative tests for stage 6.
// Google OAuth provider is NOT emulated here: positive Google-first enrollment
// is tested only with injected Auth-provider fixtures. No false claim of
// successful end-to-end Google sign-in or verified phone challenge.
const test=require("node:test");
const assert=require("node:assert/strict");
const {initializeApp:adminInit,deleteApp:adminDelete}=
  require("firebase-admin/app");
const {getAuth:getAdminAuth}=require("firebase-admin/auth");
const {getFirestore}=require("firebase-admin/firestore");
const {initializeApp:clientInit,deleteApp:clientDelete}=
  require("firebase/app");
const {getAuth:getClientAuth,connectAuthEmulator,
  signInWithEmailAndPassword,signInAnonymously,signOut}=
  require("firebase/auth");
const {enrollNewGoogleOwner}=require(
  "../deda_100441_new_owner_google_enrollment_PRIVATE_NOT_EXPORTED.js"
);

const PROJECT="demo-deda-stage6-google-enroll-negative";
if(process.env.GCLOUD_PROJECT!==PROJECT ||
   process.env.FIREBASE_AUTH_EMULATOR_HOST!=="127.0.0.1:9099" ||
   process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080")
  throw Error("DEDA_STAGE6_LOCAL_EMULATORS_REQUIRED");
const ACCOUNT="07111111111",ORIGINAL="@DEDA-ABC123";
const UID="stage6-verified-password-test";
const PASS="EmulatorOnlyNeverUserPassword123!";
let adminApp,adminAuth,db,clientApp,clientAuth,token;
const KEYS=Buffer.alloc(40,11); // synthetic; never production
function input(t=token){return {idToken:t,accountKey:ACCOUNT,originalId:ORIGINAL};}
const deps=()=>({
  auth:adminAuth,db,intentMacKey:KEYS,enabled:true,now:()=>Date.UTC(2026,10,8,14),
});
async function noEnrollment(){
  const x=await db.collection("deda_owner_provider_enrollments").get();
  assert.equal(x.size,0);
  const y=await db.collection("deda_owner_registration_verified_intents").get();
  assert.equal(y.size,0);
}
test.before(async()=>{
  adminApp=adminInit({projectId:PROJECT},"stage6-negative-admin");
  adminAuth=getAdminAuth(adminApp);
  db=getFirestore(adminApp);
  await adminAuth.createUser({
    uid:UID,email:ACCOUNT+"@deda-login.invalid",
    password:PASS,emailVerified:true,
  });
  clientApp=clientInit({
    projectId:PROJECT,apiKey:"demo-only-key",
    authDomain:"localhost",
  },"stage6-negative-client");
  clientAuth=getClientAuth(clientApp);
  connectAuthEmulator(clientAuth,"http://127.0.0.1:9099",{
    disableWarnings:true,
  });
  const signed=await signInWithEmailAndPassword(
    clientAuth,ACCOUNT+"@deda-login.invalid",PASS);
  assert.equal(signed.user.uid,UID);
  token=await signed.user.getIdToken(true);
});
test.after(async()=>{
  if(clientAuth?.currentUser)await signOut(clientAuth).catch(()=>{});
  if(clientApp)await clientDelete(clientApp).catch(()=>{});
  if(adminApp)await adminDelete(adminApp).catch(()=>{});
});
test("genuine Firebase password user cannot enroll as independently verified Google owner",async()=>{
  const x=await enrollNewGoogleOwner(input(),deps());
  assert.equal(x.status,"NO_VERIFIED_GOOGLE_FIRST_IDENTITY");
  assert.equal(x.mayCreateUid,false);
  await noEnrollment();
});
test("genuine Auth ID token with stage6 disabled causes no owner or rate-limit writes",async()=>{
  const x=await enrollNewGoogleOwner(input(),{...deps(),enabled:false});
  assert.equal(x.status,"NOT_ENABLED_OR_INVALID_REQUEST");
  await noEnrollment();
});
test("anonymous Firebase Auth UID does not adopt a registered accountKey",async()=>{
  await signOut(clientAuth);
  const anon=await signInAnonymously(clientAuth);
  assert.notEqual(anon.user.uid,UID);
  const x=await enrollNewGoogleOwner(input(await anon.user.getIdToken(true)),deps());
  assert.equal(x.status,"NO_VERIFIED_GOOGLE_FIRST_IDENTITY");
  await noEnrollment();
});
test("invalid bearer never leads to Firestore enrollment",async()=>{
  const x=await enrollNewGoogleOwner(input("invalid-id-token-that-must-fail"),deps());
  assert.equal(x.status,"UNVERIFIED_AUTH_TOKEN");
  await noEnrollment();
});
