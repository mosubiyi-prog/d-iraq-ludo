"use strict";
/*
 * Offline real Auth + Firestore EMULATOR integration, fake records only.
 * Does not deploy or enable any recovery route. Directly invokes the
 * existing 100436 private canonical PIN worker, not a second PIN engine.
 */
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {
  completeApprovedManualPinRecovery, syncMarkerMatches,
} = require("../../functions/deda_pin_manual_recovery_compat_private_v1.js");

const project = "demo-deda-stage2-isolated-admin-anchor-qa";
const key = "07712345678";
const uid = "synthetic-original-user-pin-owner";
const requestId = "synthetic-pin-approval-qa";
const email = `${key}@deda-login.invalid`;
const oldPin = "123456";
const newPin = "654321";

async function login(pin) {
  const response = await fetch(
    "http://127.0.0.1:9097/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=emulator-only",
    {method:"POST",headers:{"Content-Type":"application/json"},
      body:JSON.stringify({email,password:pin,returnSecureToken:true})});
  const body = await response.json();
  return {ok:response.ok,body};
}

test("original UID keeps profile and wallets while AUTH and Firestore PIN rotate together",{
  timeout: 120000,
},async()=>{
  assert.equal(process.env.DEDA_EMULATOR_ONLY,"true");
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,"127.0.0.1:9097");
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST,"127.0.0.1:8097");
  assert.equal(process.env.GOOGLE_CLOUD_PROJECT,project);
  const app = initializeApp({projectId:project},"stage2-pin-dual-sync-synthetic");
  try {
    const auth = getAuth(app);
    const db = getFirestore(app);
    await auth.createUser({uid,email,password:oldPin,disabled:false});
    const person = {accountKey:key,sharePersonalId:"@DEDA-ABC123",
      level:13,points:347,diamonds:800,coins:2300,
      frameIds:["test-frame"],friends:["test-friend"]};
    await Promise.all([
      db.doc(`recovery_requests/${requestId}`).set({
        status:"approved",accountKey:key,requesterUid:uid,
      }),
      db.doc(`deda_account_directory/${key}`).set({
        accountKey:key,active:true,createdUid:uid,authEmail:email,
      }),
      db.doc(`deda_credentials/${key}`).set({
        accountKey:key,active:true,createdUid:uid,pin:oldPin,
      }),
      db.doc(`users/${uid}`).set(person),
    ]);
    const before = await login(oldPin);
    assert.equal(before.ok,true,"old PIN must authenticate the original synthetic UID");
    assert.equal(before.body.localId,uid);
    const nowMs=Date.now();
    const result=await completeApprovedManualPinRecovery({
      db,auth,Timestamp,requestId,nowMs,generatePin:()=>newPin,
    });
    assert.deepEqual(result,{
      outcome:"ready",originalUid:uid,recoveredAfterAckLoss:false,
    });
    const [credential,request,lock,unchanged] = await Promise.all([
      db.doc(`deda_credentials/${key}`).get(),
      db.doc(`recovery_requests/${requestId}`).get(),
      db.doc(`deda_pin_recovery_locks/${key}`).get(),
      db.doc(`users/${uid}`).get(),
    ]);
    assert.equal(credential.data().pin,newPin);
    assert.equal(syncMarkerMatches(credential.data()),true);
    assert.equal(credential.data().createdUid,uid);
    assert.equal(request.data().status,"ready");
    assert.equal(request.data().recoveryPin,newPin);
    assert.equal(lock.exists,false);
    assert.deepEqual(unchanged.data(),person,
      "level, diamonds, coins, original ID, frames, friends and points unchanged");
    assert.equal((await auth.getUser(uid)).uid,uid);
    const oldAfter=await login(oldPin);
    assert.equal(oldAfter.ok,false,"old PIN must no longer authenticate");
    const newAfter=await login(newPin);
    assert.equal(newAfter.ok,true,"new PIN must authenticate");
    assert.equal(newAfter.body.localId,uid,"no replacement Firebase UID");
    await assert.rejects(()=>completeApprovedManualPinRecovery({
      db,auth,Timestamp,requestId,nowMs,generatePin:()=>newPin,
    }),/manual-pin-not-approved/,"no replay of approved request");
    assert.equal((await db.doc(`users/${uid}`).get()).data().sharePersonalId,
      "@DEDA-ABC123");
  } finally {
    await deleteApp(app);
  }
});
