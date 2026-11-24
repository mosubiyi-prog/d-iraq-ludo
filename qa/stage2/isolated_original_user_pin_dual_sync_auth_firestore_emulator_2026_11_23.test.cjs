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

/* Local candidate only: same canonical UID on two independent clients,
 * expired proof denied, existing trusted installations retained.
 * No real account or deployed rules; do not confuse with Flutter integration. */
test("candidate session admission binds canonical UID and fresh PIN across devices",{
  timeout: 120000,
},async()=>{
  assert.equal(process.env.DEDA_EMULATOR_ONLY,"true");
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST,"127.0.0.1:8097");
  assert.equal(process.env.GOOGLE_CLOUD_PROJECT,project);
  const fs=require("node:fs");
  const os=require("node:os");
  const path=require("node:path");
  const {execFileSync}=require("node:child_process");
  const firebase=require("firebase/compat/app");
  require("firebase/compat/firestore");
  const {initializeTestEnvironment,assertSucceeds,assertFails}=require("@firebase/rules-unit-testing");
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,"127.0.0.1:9097");
  const clientApp=require("firebase/app");
  const clientAuth=require("firebase/auth");
  const clientStore=require("firebase/firestore");
  const apps=[];
  let adminApp;
  function makeClient(label) {
    const app=clientApp.initializeApp({
      projectId:project,apiKey:"local-synthetic-demo-key",
      authDomain:project+".firebaseapp.com",
      appId:"1:1234567890:web:stage01_owner_"+label,
    },"stage01-owner-device-"+label);
    apps.push(app);
    const auth=clientAuth.getAuth(app);
    clientAuth.connectAuthEmulator(auth,"http://127.0.0.1:9097",{disableWarnings:true});
    const db=clientStore.getFirestore(app);
    clientStore.connectFirestoreEmulator(db,"127.0.0.1",8097);
    return {auth,db};
  }
  const temp=fs.mkdtempSync(path.join(os.tmpdir(),"deda-owner-session-qa-"));
  let env;
  try {
    const output=path.join(temp,"owner-session.rules");
    execFileSync("python3",[
      "qa/stage2/build_isolated_admin_gateway_anchor_candidate_2026_11_23.py",
      "--owner-session-only","--output",output,
    ],{stdio:"inherit"});
    env=await initializeTestEnvironment({projectId:project,firestore:{
      host:"127.0.0.1",port:8097,rules:fs.readFileSync(output,"utf8"),
    }});
    const account="07712345987", owner="qa-stage01-canonical-owner", other="qa-stage01-other";
    const deviceA="qa-install-A",deviceB="qa-install-B";
    const pin="246810";
    const sent=()=>firebase.firestore.FieldValue.serverTimestamp();
    const stale=firebase.firestore.Timestamp.fromMillis(Date.now()-600000);
    const a=env.authenticatedContext(owner).firestore();
    const b=env.authenticatedContext(owner).firestore();
    const outsider=env.authenticatedContext(other).firestore();
    const session=(id,installId)=>({uid:id,accountKey:account,installId,
      signedInAt:sent(),lastSeenAt:sent()});
    await env.withSecurityRulesDisabled(async ctx=>{
      const db=ctx.firestore();
      await db.doc("deda_account_directory/"+account).set({accountKey:account,createdUid:owner,active:true});
      await db.doc("deda_credentials/"+account).set({accountKey:account,createdUid:owner,active:true,pin});
      await db.doc("deda_account_profiles/"+account).set({accountKey:account,name:"QA owner",trustedInstallIds:[]});
      await db.doc("deda_auth_attempts/"+owner).set({uid:owner,accountKey:account,pin,createdAt:stale});
    });
    await assertFails(a.doc("deda_sessions/"+owner).set(session(owner,deviceA)));
    await assertSucceeds(a.doc("deda_auth_attempts/"+owner).set({uid:owner,accountKey:account,pin,createdAt:sent()}));
    await assertSucceeds(a.doc("deda_sessions/"+owner).set(session(owner,deviceA)));
    await assertSucceeds(b.doc("deda_sessions/"+owner).set(session(owner,deviceB)));
    await assertSucceeds(a.doc("deda_account_profiles/"+account).get());
    await assertSucceeds(b.doc("deda_account_profiles/"+account).get());
    await assertSucceeds(outsider.doc("deda_auth_attempts/"+other).set({uid:other,accountKey:account,pin,createdAt:sent()}));
    await assertFails(outsider.doc("deda_sessions/"+other).set(session(other,deviceA)));
    await assertFails(outsider.doc("deda_account_profiles/"+account).get());
    await env.withSecurityRulesDisabled(async ctx=>{
      const db=ctx.firestore();
      await db.doc("deda_account_profiles/"+account).update({trustedInstallIds:[deviceA,deviceB]});
      await db.doc("deda_auth_attempts/"+owner).update({createdAt:stale});
    });
    await assertSucceeds(a.doc("deda_sessions/"+owner).set(session(owner,deviceA)));
    await assertSucceeds(b.doc("deda_sessions/"+owner).set(session(owner,deviceB)));
    await assertFails(a.doc("deda_sessions/"+owner).set(session(owner,"untrusted-device")));
    await assertFails(outsider.doc("deda_sessions/"+other).set(session(other,deviceA)));
    await assertSucceeds(a.doc("deda_account_profiles/"+account).get());
    await assertSucceeds(b.doc("deda_account_profiles/"+account).get());

    // Authenticated test contexts alone cannot prove real SDK sign-out
    // independence. Reuse the same synthetic canonical account and rules,
    // but obtain separate actual Auth emulator tokens on two Firebase apps.
    adminApp=initializeApp({projectId:project},"stage01-owner-sdk-fixture");
    const adminAuth=getAuth(adminApp);
    const ownerEmail=account+"@deda-login.invalid";
    await adminAuth.createUser({uid:owner,email:ownerEmail,password:pin});
    const property={accountKey:account,name:"QA owner",
      sharePersonalId:"@DEDA-QA1234",level:13,points:347,diamonds:800,
      coins:2300,frameIds:["synthetic-frame"]};
    await env.withSecurityRulesDisabled(async ctx=>{
      await ctx.firestore().doc("users/"+owner).set(property);
    });
    const first=makeClient("A"), second=makeClient("B");
    const signIn=client=>clientAuth.signInWithEmailAndPassword(client.auth,ownerEmail,pin);
    const profile=client=>clientStore.getDocFromServer(
      clientStore.doc(client.db,"deda_account_profiles",account));
    const wallet=client=>clientStore.getDocFromServer(
      clientStore.doc(client.db,"users",owner));
    const sessionRef=client=>clientStore.doc(client.db,"deda_sessions",owner);
    const open=(client,installId)=>clientStore.setDoc(sessionRef(client),{
      uid:owner,accountKey:account,installId,
      signedInAt:clientStore.serverTimestamp(),lastSeenAt:clientStore.serverTimestamp(),
    });
    const [loginA,loginB]=await Promise.all([signIn(first),signIn(second)]);
    assert.equal(loginA.user.uid,owner);
    assert.equal(loginB.user.uid,owner);
    await open(first,deviceA);
    await open(second,deviceB);
    assert.equal((await profile(first)).data().accountKey,account);
    assert.deepEqual((await wallet(second)).data(),property);
    await clientAuth.signOut(first.auth);
    assert.equal(first.auth.currentUser,null);
    assert.equal(second.auth.currentUser.uid,owner);
    await assert.rejects(profile(first),/permission.denied|insufficient permissions/i);
    assert.equal((await profile(second)).data().accountKey,account);
    assert.deepEqual((await wallet(second)).data(),property);
    assert.equal((await clientStore.getDocFromServer(sessionRef(second))).data().uid,owner);
    assert.equal((await signIn(first)).user.uid,owner);
    await open(first,deviceA);
    assert.deepEqual((await wallet(first)).data(),property);
    assert.equal(second.auth.currentUser.uid,owner);
    assert.deepEqual((await wallet(second)).data(),property);
    const users=await adminAuth.listUsers();
    assert.equal(users.users.filter(u=>u.email===ownerEmail).length,1);
    console.log("PASS_STAGE01_TWO_REAL_AUTH_EMULATOR_CLIENTS_SAME_UID_LOCAL_SIGNOUT_PRESERVED");
  } finally {
    await Promise.allSettled(apps.map(app=>clientApp.deleteApp(app)));
    if(adminApp) await deleteApp(adminApp);
    if(env) await env.cleanup();
    fs.rmSync(temp,{recursive:true,force:true});
  }
});
