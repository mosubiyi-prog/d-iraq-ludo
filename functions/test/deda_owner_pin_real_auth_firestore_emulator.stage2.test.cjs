"use strict";
// Stage 2 PRIVATE CI ONLY: actual Firebase Auth + Firestore EMULATORS.
// Invoke the real pure onCall handler with synthetic request context.
// This validates real Admin SDK reads/transactions, NOT genuine AppCheck or
// HTTPS callable transport. No real project, no live rules, no deployment.
const test = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {createOwnerPinVerifyCallable} =
  require("../deda_owner_pin_verify_private_v1.js");

const PROJECT = "demo-deda-100436-stage2-pin-qa";
const account = "07712345678";
const originalUid = "stage2-original-uid-100436";
const originalId = "@DEDA-ABC123";
const email = account + "@deda-login.invalid";
const correctPin = "123456";
const oldRequestUid = "new-phone-anonymous-test-user";
const now = 1780000000000;
let app, db, auth;

class HttpsError extends Error {
  constructor(code, message) {super(message);this.code=code;}
}
const mockOnCall = (_options, handler) => handler;
const makeHandler = () => createOwnerPinVerifyCallable({
  onCall: mockOnCall, HttpsError, db, auth, now:()=>now, enabled:true,
});
const anonymousRequest=(data={})=>({
  app:{appId:"demo-app-attestation-not-real"},
  auth:{uid:oldRequestUid,token:{firebase:{sign_in_provider:"anonymous"}}},
  data:{phone:account,pin:correctPin,proofMode:"linked-password",...data},
});
const denied = async (handler, req) =>
  assert.rejects(handler(req),e=>e?.code==="permission-denied");

async function seed({pin=correctPin, stamp=true, lock=false,
  admin=false, active=true, ownerUid=originalUid, resetAttempts=true}={}) {
  const t = Timestamp.fromMillis(now);
  await Promise.all([
    db.doc("deda_account_directory/"+account).set({
      accountKey:account, createdUid:originalUid, active, authEmail:email,
    }),
    db.doc("deda_credentials/"+account).set({
      accountKey:account, createdUid:ownerUid, active, pin,
      pinSyncVersion:stamp?1:0, updatedAt:t,
      pinSyncedAt:stamp?t:Timestamp.fromMillis(now-1),
    }),
    db.doc("users/"+originalUid).set({
      accountKey:account, sharePersonalId:originalId,
      name:"QA Original Owner", accountType:"user",
    }),
    db.doc("deda_share_ids/"+originalId).set({
      publicId:originalId, ownerUid:originalUid,
      kind:"personal",active:true,
    }),
  ]);
  const optional=[
    ["deda_owner_pin_verify_limits/"+account,resetAttempts],
    ["deda_pin_recovery_locks/"+account,!lock],
    ["admins/"+originalUid,!admin],
  ];
  for(const [p,remove] of optional){
    const ref=db.doc(p);
    if(remove)await ref.delete();
    else if(p.includes("recovery_locks")) await ref.set({
      requestId:"pending-approved-qa",originalUid,accountKey:account,
    });
    else if(p.startsWith("admins/"))await ref.set({role:"admin",active:true});
  }
}
test.before(async()=>{
  assert.match(PROJECT,/^demo-/);
  assert.match(process.env.FIREBASE_AUTH_EMULATOR_HOST||"",/^127\.0\.0\.1:/);
  assert.match(process.env.FIRESTORE_EMULATOR_HOST||"",/^127\.0\.0\.1:/);
  app=initializeApp({projectId:PROJECT},"deda-stage2-owner-verifier-emulator");
  auth=getAuth(app);db=getFirestore(app);
  await auth.createUser({
    uid:originalUid,email,password:correctPin,disabled:false,
  });
});
test.after(async()=>{if(app) await deleteApp(app);});

test("real emulators: correct PIN returns original UID & ID, no custom token",async()=>{
  await seed();
  const h=makeHandler();
  const out=await h(anonymousRequest());
  assert.deepEqual(out,{accountKey:account,originalUid,originalId});
  const record=await auth.getUser(originalUid);
  assert.equal(record.uid,originalUid);
  const limit=await db.doc("deda_owner_pin_verify_limits/"+account).get();
  assert.equal(limit.data().windowAttempts,1);
  assert.equal(limit.data().dayAttempts,1);
});
test("real emulators: wrong PIN fails without modifying canonical owner",async()=>{
  await seed();
  await denied(makeHandler(),anonymousRequest({pin:"000000"}));
  const saved=await db.doc("users/"+originalUid).get();
  assert.equal(saved.data().sharePersonalId,originalId);
});
test("real emulators: missing sync marker fails closed even with correct PIN",async()=>{
  await seed({stamp:false});
  await denied(makeHandler(),anonymousRequest());
});
test("real emulators: in-flight PIN-rotation lock blocks recovery",async()=>{
  await seed({lock:true});
  await denied(makeHandler(),anonymousRequest());
});
test("real emulators: mismatched credential UID never grants owner proof",async()=>{
  await seed({ownerUid:"foreign-uid-qa"});
  await denied(makeHandler(),anonymousRequest());
});
test("real emulators: admin UID cannot use standard user restore",async()=>{
  await seed({admin:true});
  await denied(makeHandler(),anonymousRequest());
});
test("real emulators: anonymous Auth and AppCheck metadata are mandatory",async()=>{
  await seed();
  const h=makeHandler();
  await denied(h,{...anonymousRequest(),app:null});
  await denied(h,{...anonymousRequest(),auth:{uid:oldRequestUid,
    token:{firebase:{sign_in_provider:"password"}}}});
});
test("real emulators: cross-device per-account rate limit reaches five",async()=>{
  await seed();
  const h=makeHandler();
  for(let i=0;i<5;i++){
    const req=anonymousRequest();
    req.auth.uid="different-anon-device-"+i;
    assert.equal((await h(req)).originalUid,originalUid);
  }
  await denied(h,anonymousRequest());
  const limit=await db.doc("deda_owner_pin_verify_limits/"+account).get();
  assert.equal(limit.data().windowAttempts,5);
  assert.equal(limit.data().dayAttempts,5);
});
test("real emulators: PIN rotation rejects old and accepts synchronized new",async()=>{
  await seed({pin:"654321"});
  const h=makeHandler();
  await denied(h,anonymousRequest({pin:correctPin}));
  assert.equal((await h(anonymousRequest({pin:"654321"}))).originalUid,
    originalUid);
});
