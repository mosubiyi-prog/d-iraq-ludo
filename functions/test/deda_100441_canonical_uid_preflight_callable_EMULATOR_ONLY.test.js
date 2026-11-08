"use strict";

// Tests the private Callable HANDLER against genuine local Firebase Auth
// ID tokens and Firebase Admin Firestore transactions; no HTTP publication.
// Only demo-* localhost emulators, no real Firebase project or credentials.
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  initializeApp: adminInitialize, deleteApp: adminDelete,
} = require("firebase-admin/app");
const {getAuth: adminGetAuth} = require("firebase-admin/auth");
const {getFirestore} = require("firebase-admin/firestore");
const {
  initializeApp: clientInitialize, deleteApp: clientDelete,
} = require("firebase/app");
const {
  getAuth: clientGetAuth, connectAuthEmulator,
  signInWithEmailAndPassword, signInAnonymously, signOut,
} = require("firebase/auth");
const {
  createPrivateCanonicalUidPreflightCallable,
} = require("../deda_100441_canonical_uid_preflight_callable_PRIVATE_NOT_EXPORTED.js");

const projectId = "demo-deda-100441-canonical-callable-qa";
if (process.env.FIREBASE_AUTH_EMULATOR_HOST !== "127.0.0.1:9099" ||
    process.env.FIRESTORE_EMULATOR_HOST !== "127.0.0.1:8080" ||
    process.env.GCLOUD_PROJECT !== projectId) {
  throw Error("AUTH_AND_FIRESTORE_LOCAL_EMULATORS_ONLY");
}
const ACCOUNT = "07111111111"; // invented
const ORIGINAL = "@DEDA-T3ST99";
const UID = "deda-emulator-original-uid";
const PIN = "715826";  // synthetic for Firestore fixture only
const password = "EmulatorOnlyStrongPassword456#";
const limiterKey = "synthetic-internal-hmac-key-qa-32-characters-minimum";
const email = ACCOUNT + "@deda-login.invalid";
let adminApp, adminAuth, db, clientApp, clientAuth, token;
let handler, handlerDisabled, options;

class HttpsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}
function makeHandler(enabled) {
  return createPrivateCanonicalUidPreflightCallable({
    onCall: (o, fn) => {options = o; return fn;},
    HttpsError, auth:adminAuth, db, limiterKey, enabled,
  });
}
function requestWith(tokenValue, uidValue = UID) {
  return {
    app:{appId:"local-app-check-context"},
    auth:{uid:uidValue,token:{firebase:{sign_in_provider:"password"}}},
    data:{accountKey:ACCOUNT,originalId:ORIGINAL},
    rawRequest:{headers:{authorization:"Bearer "+tokenValue}},
  };
}
async function denial(action) {
  await assert.rejects(action, error=>
    error instanceof HttpsError && error.code === "permission-denied" &&
    error.message === "owner-review-unavailable"
  );
}

test.before(async()=>{
  adminApp = adminInitialize({projectId}, "deda-100441-callable-admin");
  adminAuth = adminGetAuth(adminApp);
  db = getFirestore(adminApp);
  clientApp = clientInitialize({
    projectId, apiKey:"demo-key", authDomain:"localhost",
  },"deda-100441-callable-client");
  clientAuth = clientGetAuth(clientApp);
  connectAuthEmulator(clientAuth,"http://127.0.0.1:9099",{
    disableWarnings:true,
  });
  await adminAuth.createUser({
    uid:UID,email,emailVerified:true,password,
  });
  const batch = db.batch();
  for (const [path, data] of Object.entries({
    ["deda_account_directory/"+ACCOUNT]:{
      accountKey:ACCOUNT,createdUid:UID,active:true,
    },
    ["deda_credentials/"+ACCOUNT]:{
      accountKey:ACCOUNT,createdUid:UID,active:true,pin:PIN,
    },
    ["deda_share_ids/"+ORIGINAL]:{
      publicId:ORIGINAL,kind:"personal",active:true,ownerUid:UID,
    },
    ["users/"+UID]:{accountKey:ACCOUNT,sharePersonalId:ORIGINAL},
    ["deda_social_profiles/"+ORIGINAL]:{
      publicId:ORIGINAL,ownerUid:UID,
    },
    ["deda_sessions/"+UID]:{uid:UID,accountKey:ACCOUNT},
  })) batch.set(db.doc(path),data);
  await batch.commit();
  const credential=await signInWithEmailAndPassword(
    clientAuth,email,password);
  assert.equal(credential.user.uid,UID);
  token=await credential.user.getIdToken(true);
  handler=makeHandler(true);
  handlerDisabled=makeHandler(false);
});
test.after(async()=>{
  if (clientAuth?.currentUser) await signOut(clientAuth).catch(()=>{});
  if (clientApp) await clientDelete(clientApp).catch(()=>{});
  if (adminApp) await adminDelete(adminApp).catch(()=>{});
});

test("real emulator Auth token remains blocked by default-OFF Callable", async()=>{
  await denial(()=>handlerDisabled(requestWith(token)));
  assert.equal(options.enforceAppCheck,true);
});

test("enabled private handler performs real server Auth checks and returns only generic review", async()=>{
  const response=await handler(requestWith(token));
  assert.deepEqual(response,{status:"review_required"});
  const redacted=JSON.stringify(response);
  for(const s of [UID,ACCOUNT,ORIGINAL,PIN,token,password]){
    assert(!redacted.includes(s));
  }
  const original=(await db.doc("deda_share_ids/"+ORIGINAL).get()).data();
  const cred=(await db.doc("deda_credentials/"+ACCOUNT).get()).data();
  assert.equal(original.ownerUid,UID);
  assert.equal(cred.createdUid,UID);
  assert.equal(cred.pin,PIN);
});

test("real Firestore split is detected, never moved and public response remains uniform", async()=>{
  const row=db.doc("deda_social_profiles/"+ORIGINAL);
  await row.update({ownerUid:"deda-unrelated-social-uid"});
  try {
    assert.deepEqual(await handler(requestWith(token)),
      {status:"review_required"});
    assert.equal((await row.get()).data().ownerUid,
      "deda-unrelated-social-uid");
    assert.equal((await db.doc("deda_share_ids/"+ORIGINAL).get()).data().ownerUid,UID);
  } finally {
    await row.update({ownerUid:UID});
  }
});

test("fake caller UID, missing AppCheck and invalid Auth bearer all deny", async()=>{
  await denial(()=>handler(requestWith(token,"deda-other-uid")));
  const noApp=requestWith(token);
  delete noApp.app;
  await denial(()=>handler(noApp));
  await denial(()=>handler(requestWith("invalid-nonfirebase-bearer-token")));
});

test("real Firebase anonymous session cannot adopt canonical account", async()=>{
  await signOut(clientAuth);
  const anon=await signInAnonymously(clientAuth);
  assert.notEqual(anon.user.uid,UID);
  const anonToken=await anon.user.getIdToken(true);
  const request=requestWith(anonToken,anon.user.uid);
  request.auth.token.firebase.sign_in_provider="anonymous";
  await denial(()=>handler(request));
});

test("actual account-scoped Firestore transaction enforces five attempts per hour",async()=>{
  // First two accepted tests used 2 attempts. Failed auth and anonymous did
  // not consume a limit. Three more accepted then another must be denied.
  const t=await signInWithEmailAndPassword(clientAuth,email,password);
  const goodToken=await t.user.getIdToken(true);
  for(let i=0;i<3;i++) {
    assert.deepEqual(await handler(requestWith(goodToken)),
      {status:"review_required"});
  }
  await denial(()=>handler(requestWith(goodToken)));
  const limits=await db.collection("deda_100441_uid_preflight_rate_limits").get();
  assert.equal(limits.size,1);
  const one=limits.docs[0];
  assert(/^[a-f0-9]{64}$/.test(one.id));
  assert.equal(one.data().windowCount,5);
  const txt=JSON.stringify({id:one.id,...one.data()});
  for(const s of [UID,ACCOUNT,ORIGINAL,PIN,goodToken,password]){
    assert(!txt.includes(s));
  }
});

test("after limits, records for profile and owner ID remain untouched",async()=>{
  assert.equal((await db.doc("users/"+UID).get()).data().sharePersonalId,ORIGINAL);
  assert.equal((await db.doc("deda_sessions/"+UID).get()).data().uid,UID);
  assert.equal((await db.doc("deda_account_directory/"+ACCOUNT).get()).data().createdUid,UID);
});
