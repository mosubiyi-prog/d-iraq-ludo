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
  signInAnonymously,signOut,EmailAuthProvider,linkWithCredential} = require("firebase/auth");
const {createOwnerPinVerifyCallable}
  = require("../deda_owner_pin_verify_private_v1.js");
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


test("same UID original anonymous prelink PIN approval and password link on two local devices",async()=>{
  // All fixtures are synthetic and run ONLY with Auth+Firestore emulators.
  // Callable is invoked in-process with injected Admin SDK; this is NOT an
  // externally deployed endpoint and AppCheck is simulated, not attested.
  const key="07222222222",id="@DEDA-EMUL99",pin="731946";
  const email2=key+"@deda-login.invalid";
  const oldApp=clientInit({projectId,apiKey:"demo-old-phone",authDomain:"localhost"},
    "deda-stage5-legacy-old-phone");
  const newApp=clientInit({projectId,apiKey:"demo-new-phone",authDomain:"localhost"},
    "deda-stage5-legacy-replacement-phone");
  const oldAuth=getAuth(oldApp),newAuth=getAuth(newApp);
  connectAuthEmulator(oldAuth,"http://127.0.0.1:9099",{disableWarnings:true});
  connectAuthEmulator(newAuth,"http://127.0.0.1:9099",{disableWarnings:true});
  try {
    const old=await signInAnonymously(oldAuth);
    const originalUid=old.user.uid;
    const docs={
      ["deda_account_directory/"+key]:{
        accountKey:key,createdUid:originalUid,active:true},
      ["deda_credentials/"+key]:{
        accountKey:key,createdUid:originalUid,pin,active:true},
      ["deda_share_ids/"+id]:{
        publicId:id,kind:"personal",ownerUid:originalUid,active:true},
      ["users/"+originalUid]:{accountKey:key,sharePersonalId:id},
      ["deda_social_profiles/"+id]:{
        publicId:id,ownerUid:originalUid},
      ["deda_sessions/"+originalUid]:{
        uid:originalUid,accountKey:key},
      ["deda_wallets/"+originalUid]:{diamonds:1234},
      ["deda_gifts/"+originalUid]:{giftCount:5},
    };
    const batch=db.batch();
    for(const [path,value] of Object.entries(docs))batch.set(db.doc(path),value);
    await batch.commit();

    class PrivateHttpsError extends Error {
      constructor(code,message){super(message);this.code=code;}
    }
    const proof=createOwnerPinVerifyCallable({
      onCall:(_options,handler)=>handler,HttpsError:PrivateHttpsError,
      db,auth:authAdmin,enabled:true,now:()=>1770000000000,
    });
    const request=(authUid,pinValue=pin,publicId=id)=>({
      auth:{uid:authUid,token:{firebase:{sign_in_provider:"anonymous"}}},
      app:{appId:"emulator-only-fake-appcheck-not-a-proof"},
      data:{phone:key,pin:pinValue,originalId:publicId,
        proofMode:"original-anonymous-prelink"},
    });
    // New anonymous device must NEVER claim the old UID by knowing PIN.
    const stranger=await signInAnonymously(newAuth);
    assert.notEqual(stranger.user.uid,originalUid);
    await assert.rejects(()=>proof(request(stranger.user.uid)),
      e=>e.code==="permission-denied");
    await assert.rejects(()=>proof(request(originalUid,"000000")),
      e=>e.code==="permission-denied");

    const verified=await proof(request(originalUid));
    assert.deepEqual(verified,{verified:true});
    assert.equal(oldAuth.currentUser.uid,originalUid);
    assert.equal(oldAuth.currentUser.isAnonymous,true);

    // Real local Firebase Auth emulator credential link on the ORIGINAL UID.
    const linked=await linkWithCredential(oldAuth.currentUser,
      EmailAuthProvider.credential(email2,pin));
    assert.equal(linked.user.uid,originalUid);
    assert.equal(oldAuth.currentUser.uid,originalUid);
    assert.equal(oldAuth.currentUser.isAnonymous,false);
    const same=await signInWithEmailAndPassword(newAuth,email2,pin);
    assert.equal(same.user.uid,originalUid);
    assert.equal(oldAuth.currentUser.uid,newAuth.currentUser.uid);
    // Do not treat sign-in as authorization to restore financial history.
    for(const [path,field,want] of [
      ["deda_account_directory/"+key,"createdUid",originalUid],
      ["deda_credentials/"+key,"createdUid",originalUid],
      ["deda_share_ids/"+id,"ownerUid",originalUid],
      ["deda_social_profiles/"+id,"ownerUid",originalUid],
      ["deda_wallets/"+originalUid,"diamonds",1234],
      ["deda_gifts/"+originalUid,"giftCount",5],
    ])assert.equal((await db.doc(path).get()).data()[field],want,path);

    // The prelink proof must no longer work after credential enrollment.
    await assert.rejects(()=>proof(request(originalUid)),
      e=>e.code==="permission-denied");
  } finally {
    if(oldAuth.currentUser)await signOut(oldAuth).catch(()=>{});
    if(newAuth.currentUser)await signOut(newAuth).catch(()=>{});
    await clientDelete(oldApp).catch(()=>{});
    await clientDelete(newApp).catch(()=>{});
  }
});
