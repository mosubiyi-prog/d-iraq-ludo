"use strict";

// Stage 5: TWO INDEPENDENT Firebase Auth client app instances (representing
// two phones) with the SAME independently verified Firebase account.
// Artificial emails/passwords ONLY; password login here demonstrates UID
// continuity, NOT sufficient ownership evidence in production with PIN.
// Both Auth and Firestore emulators must run on localhost in a demo project.
const test = require("node:test");
const assert = require("node:assert/strict");
const {generateKeyPairSync,sign} = require("node:crypto");
const {initializeApp:adminInit,deleteApp:adminDelete}
  = require("firebase-admin/app");
const {getAuth:adminGetAuth} = require("firebase-admin/auth");
const {getFirestore,Timestamp} = require("firebase-admin/firestore");
const {initializeApp:clientInit,deleteApp:clientDelete}
  = require("firebase/app");
const {getAuth,connectAuthEmulator,signInWithEmailAndPassword,
  signInAnonymously,signOut,EmailAuthProvider,GoogleAuthProvider,
  linkWithCredential,signInWithCredential} = require("firebase/auth");
const {createOwnerPinVerifyCallable}
  = require("../deda_owner_pin_verify_private_v1.js");
const {reviewExistingGoogleWithStoredNonce,
  createTrustedGoogleNonceStore}
  = require("../deda_100441_legacy_google_oidc_verifier_PRIVATE_NOT_EXPORTED.js");
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
    const week="2026-11-07";
    const giftId="deda-weekly-"+week+"-"+id.substring(1);
    const friendOtherUid="synthetic-other-friend-owner-uid";
    // These are the ACTUAL Firestore account-domain collection paths used
    // by deda_step2_account_domains_recovery_readback.dart, not generic
    // fictional deda_wallets/deda_gifts paths.
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
      ["deda_account_profiles/"+key]:{
        accountKey:key,accountType:"user"},
      ["deda_diamond_gift_balances/"+id]:{
        publicId:id,balance:1234},
      ["deda_stage71_active_identifier/"+id]:{
        originalId:id,activeId:"@DEDA-VIP999"},
      ["deda_weekly_direct_accounts/"+id]:{
        publicId:id,accountKey:key},
      ["deda_weekly_direct_control/active"]:{weekId:week},
      ["deda_weekly_direct_weeks/"+week+"/scores/"+id]:{
        weekId:week,publicId:id,weeklyXp:85},
      ["deda_diamond_gifts/"+giftId]:{
        giftId,sourceType:"weekly_league",targetPublicId:id,
        amount:150,status:"pending",
        createdAt:Timestamp.fromDate(new Date("2026-11-07T06:00:00Z"))},
      ["deda_friendships/synthetic-safe-friend-relation"]:{
        requesterUid:originalUid,recipientUid:friendOtherUid,
        members:[originalUid,friendOtherUid],status:"accepted"},
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

    // Firebase Auth EMULATOR ONLY: a fabricated third-party Google identity.
    // No live Google token, consent, OAuth endpoint, or user data is involved.
    // This checks whether attaching the second provider preserves the original
    // UID and that an independent client can subsequently use that provider.
    const fakeGoogle=JSON.stringify({
      sub:"101010101010101010101",
      email:"deda-emulator-google@example.test",
      email_verified:true,
    });
    const mockGoogleCredential=GoogleAuthProvider.credential(fakeGoogle);
    const withGoogle=await linkWithCredential(oldAuth.currentUser,
      mockGoogleCredential);
    assert.equal(withGoogle.user.uid,originalUid);
    assert.equal(oldAuth.currentUser.uid,originalUid);
    assert(oldAuth.currentUser.providerData.some(
      p=>p.providerId==="google.com"));
    // The replacement client insists on BOTH original password and Google
    // providers. The emulator integration must prove that this condition is
    // actually satisfied, not merely that the same UID survived linking.
    assert(oldAuth.currentUser.providerData.some(
      p=>p.providerId==="password" && p.email===email2),
      "Original password provider must survive the Google link");
    const adminPrincipalAfterLink=await authAdmin.getUser(originalUid);
    assert.equal(adminPrincipalAfterLink.uid,originalUid);

    // Admin Auth provider lookup is READ-ONLY: no client IdP sign-in request.
    // The caller must separately authenticate the Google subject (e.g. by
    // verified OIDC ID token). A submitted subject string is not proof.
    const knownByProvider=await authAdmin.getUserByProviderUid(
      "google.com","101010101010101010101");
    assert.equal(knownByProvider.uid,originalUid);
    await assert.rejects(
      ()=>authAdmin.getUserByProviderUid(
        "google.com","different-never-linked-google-subject"),
      err=>err.code==="auth/user-not-found");
    assert.equal(oldAuth.currentUser.uid,originalUid);

    // Exercise the NON-CREATING server OIDC + linked-provider + canonical
    // Firestore read with genuine local Admin Auth/Firestore emulators.
    // This token is signed by a DISPOSABLE synthetic key for test only,
    // not by Google and not valid for production authentication.
    const t=1800000000000;
    const audience="123456789012-productionrecovery.apps.googleusercontent.com";
    const prodConfig={projectId:"deda-25b88",
      source:"trusted_server_configuration",serverApproved:true,
      productionOAuthAudience:audience};
    // Firebase Admin verifies an actual Auth Emulator ID token. AppCheck
    // verification remains a MOCK because the local AppCheck service is
    // NOT running; physical AppCheck proof is still required before launch.
    const deviceToken=await oldAuth.currentUser.getIdToken(true);
    const requester={firebaseIdToken:deviceToken,
      appCheckToken:"local-emulator-synthetic-appcheck-not-attested"};
    let serverNow=t-10000,appCheckChecks=0;
    const appCheckVerifier={verifyToken:async v=>{
      assert.equal(v,requester.appCheckToken);
      appCheckChecks++;
      return {appId:"1:123456789:android:emulator-test-only"};
    }};
    const challengeStore=createTrustedGoogleNonceStore({
      db,auth:authAdmin,productionConfig:prodConfig,clock:()=>serverNow,
      appCheckVerifier,
    });
    const issued=await challengeStore.issue(requester);
    const nonce=issued.nonce;
    serverNow=t;
    const stored=await challengeStore.read({...requester,nonce});
    assert.equal(stored.source,"trusted_server_nonce_store");
    assert.equal(stored.createdAtMs,t-10000);
    assert(appCheckChecks>=2);
    await assert.rejects(()=>challengeStore.issue(requester),
      e=>e.message==="GOOGLE_CHALLENGE_REQUESTER_RATE_LIMITED");
    const {privateKey,publicKey}=generateKeyPairSync("rsa",{modulusLength:2048});
    const pub=publicKey.export({format:"jwk"});
    const jkeys={keys:[{...pub,kid:"local-demo-google-key",alg:"RS256",use:"sig"}]};
    const enc=x=>Buffer.from(JSON.stringify(x)).toString("base64url");
    const header=enc({alg:"RS256",kid:"local-demo-google-key",typ:"JWT"});
    const payload=enc({iss:"https://accounts.google.com",aud:audience,
      sub:"101010101010101010101",nonce,
      iat:Math.floor(t/1000)-5,exp:Math.floor(t/1000)+300});
    const oidc=header+"."+payload+"."+
      sign("RSA-SHA256",Buffer.from(header+"."+payload),privateKey)
        .toString("base64url");
    const inputs={
      idToken:oidc,nonce,...requester,clock:()=>serverNow,
      productionConfig:prodConfig,appCheckVerifier,
      loadTrustedGoogleJwks:async()=>jkeys,
      auth:authAdmin,db,accountKey:key,originalId:id,
    };
    const query=(overrides={})=>reviewExistingGoogleWithStoredNonce({
      ...inputs,...overrides,
    });
    // A mismatched App Check / Firebase requester is refused BEFORE the
    // one-use challenge can be consumed by a valid original requester.
    const badApp=await query({appCheckToken:"other-appcheck-token"});
    assert.equal(badApp.status,"DENY");
    const badToken=await query({firebaseIdToken:"other-firebase-id-token"});
    assert.equal(badToken.status,"DENY");
    const badNonce=await query({nonce:"differentServerNonceabcdefghijkl1234"});
    assert.equal(badNonce.status,"DENY");
    const badGoogle=await query({idToken:"invalid.google.assertion"});
    assert.equal(badGoogle.status,"DENY");
    const reviewed=await query();
    assert.equal(reviewed.status,
      "EXISTING_GOOGLE_PROVIDER_CANONICAL_REVIEW_ONLY");
    assert.equal(reviewed.mayLogin,false);
    assert.equal(reviewed.mayCreateUid,false);
    assert.equal(reviewed.mayWriteFirestore,false);
    assert(!JSON.stringify(reviewed).includes(originalUid));
    const replay=await query();
    assert.equal(replay.status,"DENY");
    assert.equal(replay.reason,"NO_TRUSTED_SERVER_GOOGLE_CHALLENGE");
    assert.equal(await challengeStore.read({...requester,nonce}),null);

    // Retain historical negative evidence: the Auth emulator does not
    // guarantee that REST autoCreate:false avoids account creation.
    // This REST request is not performed by the DEDA replacement client.
    // Mirror the existing Flutter signInWithIdp(autoCreate:false) preflight
    // against local Identity Toolkit emulator BEFORE FirebaseAuth signs in.
    // An unrelated Google identity must never be created by this check.
    const existingIdp=async (token) => {
      const reply=await fetch(
        "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=demo-local-key",
        {
          method:"POST",headers:{"content-type":"application/json"},
          body:JSON.stringify({
            requestUri:"http://localhost",
            postBody:new URLSearchParams({
              id_token:token,providerId:"google.com",
            }).toString(),
            returnSecureToken:true,autoCreate:false,
          }),
        });
      const json=await reply.json();
      return {status:reply.status,result:json};
    };
    const existingGoogle=await existingIdp(fakeGoogle);
    assert.equal(existingGoogle.status,200,
      "Emulator existing Google IDP preflight must resolve an already-linked UID");
    assert.equal(existingGoogle.result.localId,originalUid);
    assert.notEqual(existingGoogle.result.isNewUser,true);
    const unrelatedGoogle=await existingIdp(JSON.stringify({
      sub:"different-never-linked-google-subject",
      email:"unlinked-deda-emulator@example.test",
      email_verified:true,
    }));
    // Current Auth Emulator may IGNORE autoCreate:false and return success.
    // Treat this explicitly as an UNSAFE PRE-FLIGHT, never as proof that
    // calling the REST endpoint cannot create a new Auth UID in production.
    // A 200 response for an unlinked provider must be classified as NEW or
    // UNKNOWN (both DENY), not admitted into DEDA's original account.
    if(unrelatedGoogle.status===200) {
      assert.notEqual(unrelatedGoogle.result.localId,originalUid);
      assert.notEqual(unrelatedGoogle.result.isNewUser,false,
        "Emulator falsely marked an unlinked Google identity as existing");
      assert.equal((await db.doc(
        "deda_account_directory/"+key).get()).data().createdUid,originalUid);
      console.log("EMULATOR_NO_CREATE_NOT_GUARANTEED__NEW_UID_HOLD_ONLY");
    }
    await signOut(newAuth);
    const googleOtherPhone=await signInWithCredential(newAuth,
      mockGoogleCredential);
    assert.equal(googleOtherPhone.user.uid,originalUid);
    assert.equal(oldAuth.currentUser.uid,newAuth.currentUser.uid);
    // The replacement device uses both the original password provider and
    // Google on the SAME principal; this is what the Flutter recovery gate
    // requires. Never treat Google email equality as old-account ownership.
    assert(newAuth.currentUser.providerData.some(
      p=>p.providerId==="password" && p.email===email2));
    assert(newAuth.currentUser.providerData.some(
      p=>p.providerId==="google.com"));
    // Do not treat sign-in as authorization to restore financial history.
    for(const [path,field,want] of [
      ["deda_account_directory/"+key,"createdUid",originalUid],
      ["deda_credentials/"+key,"createdUid",originalUid],
      ["deda_share_ids/"+id,"ownerUid",originalUid],
      ["deda_social_profiles/"+id,"ownerUid",originalUid],
      ["deda_account_profiles/"+key,"accountType","user"],
      ["deda_diamond_gift_balances/"+id,"balance",1234],
      ["deda_diamond_gift_balances/"+id,"publicId",id],
      ["deda_stage71_active_identifier/"+id,"activeId","@DEDA-VIP999"],
      ["deda_weekly_direct_accounts/"+id,"publicId",id],
      ["deda_weekly_direct_weeks/"+week+"/scores/"+id,"weeklyXp",85],
      ["deda_diamond_gifts/"+giftId,"amount",150],
      ["deda_diamond_gifts/"+giftId,"status","pending"],
      ["deda_friendships/synthetic-safe-friend-relation","requesterUid",originalUid],
    ])assert.equal((await db.doc(path).get()).data()[field],want,path);
    const actualGift=(await db.collection("deda_diamond_gifts")
      .where("targetPublicId","==",id).get()).docs;
    assert.equal(actualGift.length,1);
    assert.equal(actualGift[0].id,giftId);
    assert(actualGift[0].data().createdAt instanceof Timestamp);
    const relations=(await db.collection("deda_friendships")
      .where("members","array-contains",originalUid).get()).docs;
    assert.equal(relations.length,1);
    assert.equal(relations[0].data().status,"accepted");
    assert.deepEqual(relations[0].data().members,
      [originalUid,friendOtherUid]);

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
