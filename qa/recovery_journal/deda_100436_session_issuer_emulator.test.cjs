"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {initializeTestEnvironment, assertFails, assertSucceeds}
    = require("@firebase/rules-unit-testing");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {doc, getDoc, setDoc, serverTimestamp, Timestamp} = require("firebase/firestore");
const {__privateIssueLinkedOwnerGrantForQaOnly: issue}
    = require("./deda_linked_owner_session_grant_issuer_CANDIDATE_NOT_EXPORTED.js");

// Uses LOCAL Firestore Emulator Admin SDK. Request.auth/AppCheck are mock
// authenticated call context; it does NOT test Firebase Auth password strength
// nor a deployed Cloud Function. No service account or real Firebase project.
const PROJECT = "demo-deda-100436-session-issuer";
const uid = "original-account-owner-uid";
const account = "9647712345678";
const originalId = "@DEDA-ABC123";
const installation = hex => hex.repeat(48);
const accountEmail = account + "@deda-login.invalid";
const sessionPath = "deda_sessions/" + uid;
const grantPath = device => "deda_recovery_session_bootstrap_grants/" +
    uid + "/installs/" + device;
const limitPath = "deda_recovery_session_grant_limits/" + uid;
const makeRequest = (device = installation("a")) => ({
  data: {accountKey: account, originalId, installId: device},
  auth: {uid, token: {
    email: accountEmail, firebase: {sign_in_provider: "password"},
  }},
  app: {appId: "demo-app-check-only-not-a-real-attestation"},
});
let env, app, admin;
const ownerDb = () => env.authenticatedContext(uid, {
  email: accountEmail, firebase: {sign_in_provider: "password"},
}).firestore();
const path = (db,p) => doc(db,p);
async function seed({adminRole = false, priorSession = false,
    credentials = true, ownerRoute = true, ledger = true} = {}) {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async context => {
    const db=context.firestore();
    await setDoc(path(db,"deda_account_directory/"+account),{
      accountKey:account,createdUid:uid,active:true,
    });
    if (credentials) await setDoc(path(db,"deda_credentials/"+account),{
      accountKey:account,createdUid:uid,active:true,pin:"123456",
    });
    await setDoc(path(db,"users/"+uid),{
      accountKey:account,sharePersonalId:originalId,
    });
    if (ownerRoute) await setDoc(path(db,"deda_share_ids/"+originalId),{
      publicId:originalId,kind:"personal",active:true,ownerUid:uid,
    });
    if (adminRole) await setDoc(path(db,"admins/"+uid),{
      active:true,role:"general_manager",status:"active",
    });
    if (ledger) await setDoc(path(db,limitPath),{
      ownerUid:uid, count:0,
      windowStartedAt: Timestamp.fromMillis(Date.now()-1000),
      updatedAt: Timestamp.fromMillis(Date.now()-1000),
    });
    if (priorSession) await setDoc(path(db,sessionPath),{
      uid,accountKey:account,installId:installation("b"),
    });
  });
}
test.before(async () => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST||"",/^127\.0\.0\.1:/);
  assert.equal(process.env.DEDA_LINKED_OWNER_GRANT_ISSUER_ENABLED,"true");
  const rules=fs.readFileSync(process.env.DEDA_JOURNAL_EMULATOR_RULES,"utf8");
  assert.match(rules,/dedaLinkedOriginalOwnerSessionBootstrap/);
  env=await initializeTestEnvironment({
    projectId:PROJECT,firestore:{rules},
  });
  app=initializeApp({projectId:PROJECT},"deda-100436-qa-issuer");
  admin=getFirestore(app);
});
test.after(async () => {
  if(app)await deleteApp(app);
  if(env)await env.cleanup();
});

test("without pre-provisioned server-only rate ledger, issuer fails closed", async () => {
  await seed({ledger:false});
  await assert.rejects(issue(makeRequest(),admin),
      /server-rate-limit-ledger-not-provisioned/);
  assert.equal((await admin.doc(limitPath).get()).exists,false);
});

test("simultaneous requests for DIFFERENT devices consume two rate allowances", async () => {
  await seed();
  const answers = await Promise.all([
    issue(makeRequest(installation("a")),admin),
    issue(makeRequest(installation("b")),admin),
  ]);
  assert.ok(answers.every(x=>x.approved===true));
  assert.equal((await admin.doc(limitPath).get()).data().count,2);
  for(const device of ["a","b"]) {
    assert.equal((await admin.doc(grantPath(installation(device))).get()).exists,true);
  }
});

test("real emulator: server-issued UID grant permits new-device session, not client grant write", async () => {
  await seed();
  const request=makeRequest();
  const result=await issue(request,admin);
  assert.equal(result.approved,true);
  assert.equal(result.reused,false);
  const db=ownerDb();
  await assertFails(getDoc(path(db,grantPath(request.data.installId))));
  await assertFails(setDoc(path(db,grantPath(request.data.installId)),{state:"approved"}));
  await assertSucceeds(setDoc(path(db,sessionPath),{
    uid,accountKey:account,installId:request.data.installId,
    signedInAt:serverTimestamp(),lastSeenAt:serverTimestamp(),
  }));
  assert.equal((await getDoc(path(db,sessionPath))).data().uid,uid);
});
test("reusing same unexpired issuer grant is idempotent and rate count unchanged", async () => {
  await seed();
  const request=makeRequest();
  const first=await issue(request,admin);
  const second=await issue(request,admin);
  assert.equal(first.reused,false);
  assert.equal(second.reused,true);
  const limit=(await admin.doc(limitPath).get()).data();
  assert.equal(limit.count,1);
});
test("issue count is limited to 3 different devices per owner per hour", async () => {
  await seed();
  for (const device of ["a","b","c"]) {
    const result=await issue(makeRequest(installation(device)),admin);
    assert.equal(result.approved,true);
  }
  await assert.rejects(issue(makeRequest(installation("d")),admin),
      /linked-owner-grant-hourly-limit/);
  assert.equal((await admin.doc(limitPath).get()).data().count,3);
  assert.equal((await admin.doc(grantPath(installation("d"))).get()).exists,false);
});
test("simultaneous requests for SAME device cannot double-count grants", async () => {
  await seed();
  const results=await Promise.all([
    issue(makeRequest(),admin),issue(makeRequest(),admin),
  ]);
  assert.ok(results.every(x => x.approved === true));
  // In a concurrent completion two clients can see "new" before retry
  // acknowledgement; the authoritative ledger/documents—not the response
  // hints—must prove there was only ONE grant consumed for this device.
  assert.equal((await admin.doc(limitPath).get()).data().count,1);
  const saved = await admin.doc(grantPath(installation("a"))).get();
  assert.equal(saved.exists,true);
  assert.equal(saved.data().installId,installation("a"));
});
test("wrong Auth UID, email, provider or missing AppCheck context fail without write", async () => {
  await seed();
  const scenarios=[
    {...makeRequest(),auth:{uid:"other-uid",token:makeRequest().auth.token}},
    {...makeRequest(),auth:{uid,token:{
      email:"someone@example.com",
      firebase:{sign_in_provider:"password"},
    }}},
    {...makeRequest(),auth:{uid,token:{
      email:accountEmail,firebase:{sign_in_provider:"anonymous"},
    }}},
    {...makeRequest(),app:null},
  ];
  for (const request of scenarios) {
    await assert.rejects(issue(request,admin));
  }
  assert.equal((await admin.doc(limitPath).get()).data().count,0);
});
test("administrative Firebase principal is never silently owner-bootstrapped", async () => {
  await seed({adminRole:true});
  await assert.rejects(issue(makeRequest(),admin),
      /immutable-original-uid-evidence-missing/);
  assert.equal((await admin.doc(limitPath).get()).data().count,0);
});
test("missing immutable credentials or original ID route never issues grant", async () => {
  for(const opts of [{credentials:false},{ownerRoute:false}]){
    await seed(opts);
    await assert.rejects(issue(makeRequest(),admin),
        /immutable-original-uid-evidence-missing/);
    assert.equal((await admin.doc(limitPath).get()).data().count,0);
  }
});
test("issuer rejects attempt to replace a different account's active session", async () => {
  await seed({priorSession:true});
  await admin.doc(sessionPath).set({
    uid,accountKey:"9647700000011",installId:installation("b"),
  });
  await assert.rejects(issue(makeRequest(),admin),
      /immutable-original-uid-evidence-missing/);
  assert.equal((await admin.doc(limitPath).get()).data().count,0);
});
test("rate limit is independent of client-controlled install ID string", async () => {
  await seed();
  const request=makeRequest("untrusted-install-id");
  await assert.rejects(issue(request,admin),
      /original-uid-owner-auth-required/);
  assert.equal((await admin.doc(limitPath).get()).data().count,0);
});
