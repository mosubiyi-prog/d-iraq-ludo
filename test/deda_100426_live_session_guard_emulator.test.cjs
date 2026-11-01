"use strict";
/* 100426: EXACT live Firestore Rules with a narrow session guard applied.
 * The only required behavior change: a COPIED install string on a fresh UID
 * can no longer bypass PIN. All old PIN entry works without Cloud Functions.
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {createRequire} = require("node:module");
const req = createRequire(path.resolve(__dirname,"../functions/package.json"));
const {initializeTestEnvironment,assertSucceeds,assertFails} =
  req("@firebase/rules-unit-testing");
const {doc,setDoc,getDoc,serverTimestamp,deleteDoc} = req("firebase/firestore");
const PROJECT="demo-deda-100426-no-billing-qa";
const RULES=process.env.DEDA_100426_CANDIDATE_PATH;
if(process.env.GCLOUD_PROJECT!==PROJECT ||
   process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080" ||
   process.env.GOOGLE_APPLICATION_CREDENTIALS!==undefined ||
   !RULES || !RULES.endsWith("/deda-100426-live-session-candidate.rules")) {
  throw Error("REFUSE_NON_LOCAL_100426_SECURITY_TEST");
}
const P="07701234567",PIN="758492",OLD="original_legacy_UID",NEW="new_legacy_UID",
      ACCOUNT2="07701234568",ORIGINAL="@DEDA-AB3C5D",INSTALL="reusable-install-token";
let env;
const db=uid=>env.authenticatedContext(uid).firestore();
const attempt=(uid,key=P,pin=PIN)=>({uid,accountKey:key,pin,createdAt:serverTimestamp()});
const session=(uid,key=P,installId=INSTALL)=>({
  uid,accountKey:key,installId,signedInAt:serverTimestamp(),
  lastSeenAt:serverTimestamp()
});
test.before(async()=>{
  env=await initializeTestEnvironment({projectId:PROJECT,
    firestore:{host:"127.0.0.1",port:8080,
      rules:fs.readFileSync(RULES,"utf8")}});
});
test.after(async()=>{if(env)await env.cleanup()});
test.beforeEach(async()=>{
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async ctx=>{
    const d=ctx.firestore();
    await setDoc(doc(d,"deda_credentials",P),
      {accountKey:P,pin:PIN,active:true,createdUid:OLD});
    await setDoc(doc(d,"deda_account_directory",P),
      {accountKey:P,active:true,createdUid:OLD});
    await setDoc(doc(d,"deda_account_profiles",P),
      {accountKey:P,name:"Synthetic account",accountType:"user",
       trustedInstallIds:[INSTALL]});
    await setDoc(doc(d,"deda_credentials",ACCOUNT2),
      {accountKey:ACCOUNT2,pin:"333333",active:true,createdUid:"other_user"});
    await setDoc(doc(d,"deda_account_profiles",ACCOUNT2),
      {accountKey:ACCOUNT2,name:"Other synthetic",trustedInstallIds:[INSTALL]});
    await setDoc(doc(d,"users",OLD),
      {accountKey:P,name:"Synthetic",sharePersonalId:ORIGINAL});
    await setDoc(doc(d,"deda_share_ids",ORIGINAL),
      {publicId:ORIGINAL,ownerUid:OLD,kind:"personal",active:true});
  });
});
test("copied trusted install ID cannot CREATE session without PIN on another Firebase UID",async()=>{
  const c=db(NEW);
  await assertFails(setDoc(doc(c,"deda_sessions",NEW),session(NEW)));
  await assertFails(getDoc(doc(c,"deda_account_profiles",P)));
});
test("100340 correct six-digit PIN still CREATES session on new phone",async()=>{
  const c=db(NEW);
  await assertSucceeds(setDoc(doc(c,"deda_auth_attempts",NEW),attempt(NEW)));
  await assertSucceeds(setDoc(doc(c,"deda_sessions",NEW),session(NEW)));
  const profile=await assertSucceeds(getDoc(doc(c,"deda_account_profiles",P)));
  assert.equal(profile.data().accountKey,P);
});
test("existing trusted UID session can refresh without reentering PIN",async()=>{
  const c=db(OLD);
  await assertSucceeds(setDoc(doc(c,"deda_auth_attempts",OLD),attempt(OLD)));
  await assertSucceeds(setDoc(doc(c,"deda_sessions",OLD),session(OLD)));
  await assertSucceeds(deleteDoc(doc(c,"deda_auth_attempts",OLD)));
  await assertSucceeds(setDoc(doc(c,"deda_sessions",OLD),session(OLD)));
});
test("reusing old UID session cannot silently switch account via copied install",async()=>{
  const c=db(OLD);
  await assertSucceeds(setDoc(doc(c,"deda_auth_attempts",OLD),attempt(OLD)));
  await assertSucceeds(setDoc(doc(c,"deda_sessions",OLD),session(OLD)));
  await assertSucceeds(deleteDoc(doc(c,"deda_auth_attempts",OLD)));
  await assertFails(setDoc(doc(c,"deda_sessions",OLD),session(OLD,ACCOUNT2)));
});
test("wrong PIN still cannot create any session",async()=>{
  const c=db(NEW);
  await assertFails(setDoc(doc(c,"deda_auth_attempts",NEW),attempt(NEW,P,"000000")));
  await assertFails(setDoc(doc(c,"deda_sessions",NEW),session(NEW)));
});
test("old account data and original ID cannot be read or overwritten by outsider",async()=>{
  const c=db(NEW);
  await assertFails(getDoc(doc(c,"users",OLD)));
  await assertFails(setDoc(doc(c,"deda_share_ids",ORIGINAL),
    {publicId:ORIGINAL,kind:"personal",ownerUid:NEW,active:true}));
});
test("new server-only identity ledgers remain unreadable and unwritable",async()=>{
  const c=db(NEW);
  for(const namespace of ["deda_secure_canonical_accounts","deda_secure_original_id_owners",
    "deda_secure_account_bindings","deda_secure_pin_account_limits"]){
    await assertFails(getDoc(doc(c,namespace,"synthetic")));
    await assertFails(setDoc(doc(c,namespace,"synthetic"),{fake:true}));
  }
});
