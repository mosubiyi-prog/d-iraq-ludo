"use strict";
/*
 * DEDA Stage2: synthetic secondary Firebase Auth + Firestore SDK integration,
 * against LOCAL candidate rules. Does not run Flutter or access any real
 * Firebase project, secret, production account or device.
 */
const fs = require("node:fs");
const assert = require("node:assert/strict");
const {test} = require("node:test");
const {initializeApp, deleteApp} = require("firebase/app");
const {getAuth, connectAuthEmulator, signInAnonymously,
  createUserWithEmailAndPassword, signOut} = require("firebase/auth");
const {getFirestore, connectFirestoreEmulator, doc,
  getDocFromServer, updateDoc, setDoc, runTransaction, serverTimestamp,
  deleteField} = require("firebase/firestore");
const {initializeTestEnvironment} = require("@firebase/rules-unit-testing");

const project = "demo-deda-stage2-isolated-admin-anchor-qa";
const account = "9647712345690";
const userEmail = "qa.stage2.invited.staff@example.invalid";
const invitationId = "qa_stage2_auth_sdk_invitation";
const code = "12345678";
const invitedAdminId = "DEDA-ADM-QA-AUTH";
const guestUid = "qa_stage2_private_guest";

test("secondary Auth signup, claimed invitation, bound gate; public UID unchanged",{
  timeout: 160000,
},async(t)=>{
  assert.equal(process.env.DEDA_EMULATOR_ONLY,"true");
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST,"127.0.0.1:8097");
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,"127.0.0.1:9097");
  const rulesPath=process.env.DEDA_ADMIN_CANDIDATE_RULES_PATH;
  assert.ok(rulesPath && fs.existsSync(rulesPath));
  const apps=[];
  function makeApp(label){
    const app=initializeApp({
      projectId:project, apiKey:"local-synthetic-demo-key",
      authDomain:project+".firebaseapp.com",
      appId:"1:1234567890:web:isolated_admin_"+label,
    },"qa-stage2-integration-"+label);
    apps.push(app);
    const auth=getAuth(app);
    connectAuthEmulator(auth,"http://127.0.0.1:9097",{
      disableWarnings:true,
    });
    const db=getFirestore(app);
    connectFirestoreEmulator(db,"127.0.0.1",8097);
    return {auth,db};
  }
  const env=await initializeTestEnvironment({
    projectId:project,
    firestore:{
      rules:fs.readFileSync(rulesPath,"utf8"),
      host:"127.0.0.1",port:8097,
    },
  });
  try{
    const publicApp=makeApp("public-deda");
    const isolatedAdminApp=makeApp("secondary-admin");
    const oldUser=await signInAnonymously(publicApp.auth);
    const publicUid=oldUser.user.uid;
    assert.ok(publicUid);
    assert.equal(isolatedAdminApp.auth.currentUser,null);
    // Seed ONLY synthetic records via local disabled-rules test context.
    await env.withSecurityRulesDisabled(async ctx=>{
      const db=ctx.firestore();
      const ts=require("firebase/compat/app");
      require("firebase/compat/firestore");
      const T=ts.firestore.Timestamp;
      const now=T.now();
      const future=T.fromDate(new Date(Date.now()+3600000));
      await Promise.all([
        db.doc("deda_sessions/"+publicUid).set({
          accountKey:account,uid:publicUid,
        }),
        db.doc("deda_account_directory/"+account).set({
          accountKey:account,active:true,createdUid:publicUid,
        }),
        db.doc("admin_entry_access/"+account).set({
          accountKey:account,phone:account,
          accessType:"member",allowedRole:"employee",
          allowedAdminEmail:userEmail,inviteId:invitationId,
          adminUid:"",adminId:invitedAdminId,
          status:"invited",active:true,
        }),
        db.doc("admin_invites/"+invitationId).set({
          adminId:invitedAdminId,displayName:"Synthetic Staff Member",
          email:userEmail,phone:account,department:"Support",
          role:"employee",governorate:"",
          permissions:{viewUsers:true},
          status:"pending",activationCode:code,
          createdByUid:"qa_gm_actor",createdByName:"Synthetic GM",
          createdAt:now,updatedAt:now,expiresAt:future,
        }),
        db.doc("users/"+guestUid).set({
          accountKey:"9647712345997",name:"Synthetic private user",
        }),
      ]);
    });
    const publicBefore=await getDocFromServer(
      doc(publicApp.db,"deda_sessions",publicUid));
    assert.equal(publicBefore.data().accountKey,account);
    const gatewayBefore=await getDocFromServer(
      doc(publicApp.db,"admin_entry_access",account));
    assert.equal(gatewayBefore.data().status,"invited");

    const activated=await createUserWithEmailAndPassword(
      isolatedAdminApp.auth,userEmail,"SafeEmulatorOnly9876!");
    const adminUid=activated.user.uid;
    assert.notEqual(adminUid,publicUid);
    assert.equal(publicApp.auth.currentUser.uid,publicUid);
    assert.equal(isolatedAdminApp.auth.currentUser.uid,adminUid);

    const inviteRef=doc(isolatedAdminApp.db,"admin_invites",invitationId);
    const gateRef=doc(isolatedAdminApp.db,"admin_entry_access",account);
    const adminRef=doc(isolatedAdminApp.db,"admins",adminUid);
    await t.test("wrong invitation code is denied by rules, no public signout",async()=>{
      await assert.rejects(updateDoc(inviteRef,{
        status:"claimed",claimedUid:adminUid,claimCode:"00000000",
        claimedAt:serverTimestamp(),updatedAt:serverTimestamp(),
      }),/permission-denied/i);
      assert.equal(publicApp.auth.currentUser.uid,publicUid);
    });
    await t.test("valid invited admin UID claims invitation and creates exact profile",async()=>{
      await updateDoc(inviteRef,{
        status:"claimed",claimedUid:adminUid,claimCode:code,
        claimedAt:serverTimestamp(),updatedAt:serverTimestamp(),
      });
      const claimed=await getDocFromServer(inviteRef);
      assert.equal(claimed.data().claimedUid,adminUid);
      assert.equal(claimed.data().status,"claimed");
      await setDoc(adminRef,{
        adminId:invitedAdminId,displayName:"Synthetic Staff Member",
        email:userEmail,phone:account,department:"Support",
        role:"employee",governorate:"",
        status:"active",active:true,permissions:{viewUsers:true},
        mustChangePassword:false,inviteId:invitationId,
        createdAt:serverTimestamp(),updatedAt:serverTimestamp(),
        createdByUid:"qa_gm_actor",createdByName:"Synthetic GM",
        permissionsUpdatedAt:serverTimestamp(),
        permissionsUpdatedByUid:"qa_gm_actor",
        permissionsUpdatedByName:"Synthetic GM",
        lastSeenAt:serverTimestamp(),lastLoginAt:serverTimestamp(),
        firstLoginCompletedAt:serverTimestamp(),
      });
      assert.equal((await getDocFromServer(adminRef)).data().inviteId,invitationId);
      // Before gateway completion, the *candidate server rules*, not merely
      // Flutter, must deny all newly granted staff read permissions.
      await assert.rejects(getDocFromServer(
        doc(isolatedAdminApp.db,"users",guestUid)),/permission-denied/i);
    });
    await t.test("link invitation+gateway+audit in one real client transaction",async()=>{
      const auditRef=doc(isolatedAdminApp.db,"admin_audit",
        "qa_stage2_auth_sdk_accepted");
      await runTransaction(isolatedAdminApp.db,async tx=>{
        const liveInvite=await tx.get(inviteRef);
        const liveGate=await tx.get(gateRef);
        assert.equal(liveInvite.data().claimedUid,adminUid);
        assert.equal(liveInvite.data().status,"claimed");
        assert.equal(liveGate.data().status,"invited");
        tx.update(gateRef,{
          adminUid,adminId:invitedAdminId,status:"active",
          active:true,updatedAt:serverTimestamp(),
        });
        tx.update(inviteRef,{
          status:"completed",acceptedAt:serverTimestamp(),
          updatedAt:serverTimestamp(),
          activationCode:deleteField(),claimCode:deleteField(),
        });
        tx.set(auditRef,{
          action:"admin_invite_accepted",
          adminUid,adminName:"Synthetic Staff Member",
          adminRole:"employee",inviteId:invitationId,
          targetAdminId:invitedAdminId,targetAdminRole:"employee",
          createdAt:serverTimestamp(),
        });
      });
      assert.equal((await getDocFromServer(inviteRef)).data().status,"completed");
      assert.equal((await getDocFromServer(gateRef)).data().adminUid,adminUid);
      assert.equal((await getDocFromServer(auditRef)).data().adminUid,adminUid);
      assert.equal((await getDocFromServer(
        doc(isolatedAdminApp.db,"users",guestUid))).data().name,
        "Synthetic private user");
      assert.equal(publicApp.auth.currentUser.uid,publicUid);
    });
    await t.test("separate admin sign-out cannot sign out public DEDA UID",async()=>{
      await signOut(isolatedAdminApp.auth);
      assert.equal(isolatedAdminApp.auth.currentUser,null);
      assert.equal(publicApp.auth.currentUser.uid,publicUid);
      const session=await getDocFromServer(
        doc(publicApp.db,"deda_sessions",publicUid));
      assert.equal(session.data().uid,publicUid);
      await assert.rejects(getDocFromServer(
        doc(publicApp.db,"users",guestUid)),/permission-denied/i);
    });
    console.log("PASS_SECONDARY_AUTH_REAL_EMULATOR_PUBLIC_UID_UNCHANGED");
    console.log("PASS_INVITATION_CLAIM_GATEWAY_AUDIT_REAL_SDK_TRANSACTION");
  }finally{
    await Promise.allSettled(apps.map(deleteApp));
    await env.cleanup();
  }
});
