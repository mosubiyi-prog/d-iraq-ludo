"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const fs=require("node:fs"),path=require("node:path");
const {createRequire}=require("node:module");
const req=createRequire(path.resolve(__dirname,"../functions/package.json"));
const {initializeTestEnvironment,assertSucceeds,assertFails}=
  req("@firebase/rules-unit-testing");
const {doc,setDoc,getDoc,getDocs,collection,deleteDoc,serverTimestamp}=
  req("firebase/firestore");
const PROJECT="demo-deda-100432-quiz-ui-qa";
const RULE=process.env.DEDA_100432_RULES_PATH;
if(process.env.GCLOUD_PROJECT!==PROJECT||
  process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
  process.env.GOOGLE_APPLICATION_CREDENTIALS!==undefined||
  !RULE||!RULE.endsWith("/deda-100432-live-quiz-qa.rules")) {
  throw Error("REFUSE_NON_LOCAL_FIRESTORE_QA");
}
const UID="original_uid_432",OTHER="new_anon_uid_432";
const ACCOUNT="07712345678",ORIGINAL="@DEDA-ABC123",DAY="2026-11-01";
const encoded=JSON.stringify({
  format:1,kind:"untrusted-local-task-quiz-ui-evidence",
  accountKey:ACCOUNT,originalId:ORIGINAL,iraqDay:DAY,taskPointsRaw:null,
  quizSeen:["sign_stop","sign_yield_v2","sign_school_v3","sign_speed_60_v4","sign_no_entry_v5"],
  quizSelected:["sign_stop","sign_yield_v2","sign_school_v3","sign_speed_60_v4","sign_no_entry_v5"],
  quizProgressRaw:'{"index":4,"answers":{"sign_stop":3},"correct":["sign_stop"]}',
  quizCompletedRaw:false,
});
let env;
const db=uid=>env.authenticatedContext(uid).firestore();
const addr=(uid=UID,day=DAY)=>"deda_quiz_ui_snapshots/"+uid+"/days/"+day;
const payload=(override={})=>({
  format:1,kind:"display-only-untrusted-quiz-v1",
  uid:UID,accountKey:ACCOUNT,originalId:ORIGINAL,day:DAY,
  encoded,createdAt:serverTimestamp(),...override,
});
test.before(async()=>{
 env=await initializeTestEnvironment({projectId:PROJECT,
  firestore:{host:"127.0.0.1",port:8080,rules:fs.readFileSync(RULE,"utf8")}});
});
test.after(async()=>{if(env)await env.cleanup()});
test.beforeEach(async()=>{
 await env.clearFirestore();
 await env.withSecurityRulesDisabled(async c=>{
  const d=c.firestore();
  await Promise.all([
   setDoc(doc(d,"deda_sessions",UID),{uid:UID,accountKey:ACCOUNT,installId:"old-phone"}),
   setDoc(doc(d,"users",UID),{accountKey:ACCOUNT,sharePersonalId:ORIGINAL}),
   setDoc(doc(d,"deda_account_directory",ACCOUNT),{
      accountKey:ACCOUNT,createdUid:UID,active:true}),
   setDoc(doc(d,"deda_share_ids",ORIGINAL),{
      publicId:ORIGINAL,kind:"personal",active:true,ownerUid:UID}),
   setDoc(doc(d,"deda_diamond_gift_balances",ORIGINAL),{
      publicId:ORIGINAL,balance:9876}),
  ]);
 });
});
test("original Firebase UID can create ONE immutable UI-only cloud quiz archive",async()=>{
 const owner=db(UID);
 await assertSucceeds(setDoc(doc(owner,addr()),payload()));
 const snap=await assertSucceeds(getDoc(doc(owner,addr())));
 assert.equal(snap.data().encoded,encoded);
 assert.equal(snap.data().kind,"display-only-untrusted-quiz-v1");
});
test("second device signed into SAME Firebase UID reads original quiz archive",async()=>{
 const owner=db(UID);
 await assertSucceeds(setDoc(doc(owner,addr()),payload()));
 const nextSameUid=db(UID);
 assert.equal((await assertSucceeds(getDoc(doc(nextSameUid,addr())))).data().encoded,encoded);
});
test("different anonymous UID cannot get or create other owner's UI document",async()=>{
 const thief=db(OTHER);
 await assertFails(getDoc(doc(thief,addr())));
 await assertFails(setDoc(doc(thief,addr()),payload()));
 await assertFails(setDoc(doc(thief,addr(OTHER)),payload({uid:OTHER})));
});
test("cannot add any task points / financial credits to UI archive schema",async()=>{
 const originalWallet=await env.withSecurityRulesDisabled(async c=>{
   const x=await getDoc(doc(c.firestore(),"deda_diamond_gift_balances",ORIGINAL));
   return x.data();
 });
 const owner=db(UID);
 await assertFails(setDoc(doc(owner,addr()),payload({diamonds:999999})));
 await assertFails(setDoc(doc(owner,addr()),payload({taskAwards:["already-paid"]})));
 await assertFails(setDoc(doc(owner,addr()),payload({kind:"verified-wallet"})));
 const after=await env.withSecurityRulesDisabled(async c=>{
   const x=await getDoc(doc(c.firestore(),"deda_diamond_gift_balances",ORIGINAL));
   return x.data();
 });
 assert.deepEqual(after,originalWallet);
});
test("no missing/forged original route or UID ownership can upload",async()=>{
 await env.withSecurityRulesDisabled(async c=>{
   await setDoc(doc(c.firestore(),"deda_share_ids",ORIGINAL),
     {publicId:ORIGINAL,kind:"personal",active:true,ownerUid:OTHER});
 });
 await assertFails(setDoc(doc(db(UID),addr()),payload()));
});
test("client cannot revise, delete or list any saved quiz history",async()=>{
 const owner=db(UID);
 await assertSucceeds(setDoc(doc(owner,addr()),payload()));
 await assertFails(setDoc(doc(owner,addr()),payload()));
 await assertFails(deleteDoc(doc(owner,addr())));
 await assertFails(getDocs(collection(owner,"deda_quiz_ui_snapshots",UID,"days")));
});
test("wrong accountKey, original, day and oversized payload fail closed",async()=>{
 const owner=db(UID);
 await assertFails(setDoc(doc(owner,addr()),payload({accountKey:"07799999999"})));
 await assertFails(setDoc(doc(owner,addr()),payload({originalId:"@DEDA-FFFF99"})));
 await assertFails(setDoc(doc(owner,addr()),payload({day:"2026-11-02"})));
 await assertFails(setDoc(doc(owner,addr()),payload({encoded:"X".repeat(61000)})));
});
test("revoked session does not allow upload or reading old snapshot",async()=>{
 const owner=db(UID);
 await assertSucceeds(setDoc(doc(owner,addr()),payload()));
 await env.withSecurityRulesDisabled(async c=>{
  await deleteDoc(doc(c.firestore(),"deda_sessions",UID));
 });
 await assertFails(getDoc(doc(owner,addr())));
 await assertFails(setDoc(doc(owner,addr(UID,"2026-11-02")),
   payload({day:"2026-11-02"})));
});
