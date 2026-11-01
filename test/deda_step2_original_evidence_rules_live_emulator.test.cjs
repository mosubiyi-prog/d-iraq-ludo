"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const fs=require("node:fs"),path=require("node:path");
const {createRequire}=require("node:module");
const req=createRequire(path.resolve(__dirname,"../functions/package.json"));
const {initializeTestEnvironment,assertSucceeds,assertFails}=
  req("@firebase/rules-unit-testing");
const {doc,setDoc,getDoc,getDocs,collection,deleteDoc,
  serverTimestamp,query,orderBy,limit}=req("firebase/firestore");
const PROJECT="demo-deda-100434-original-evidence";
const RULE=process.env.DEDA_100434_RULES_PATH;
if(process.env.GCLOUD_PROJECT!==PROJECT ||
  process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080" ||
  process.env.GOOGLE_APPLICATION_CREDENTIALS!==undefined ||
  !RULE || !RULE.endsWith("/deda-100434-live-evidence-qa.rules")) {
  throw Error("REFUSE_NON_LOCAL_FIRESTORE_QA");
}
const UID="original_uid_434",OTHER="foreign_uid_434";
const ACCOUNT="07712345678",ORIGINAL="@DEDA-ABC123";
const CAPTURE="ABCDEFGHIJKLMNOPQRSTUVWX123456";
let env;
const db=uid=>env.authenticatedContext(uid).firestore();
const addr=(key=ACCOUNT,id=CAPTURE)=>`deda_progress_evidence/${key}/captures/${id}`;
const payload=(overrides={})=>({
  format:1,kind:"legacy-local-evidence",accountKey:ACCOUNT,
  sourceUid:UID,installId:"original-device",captureId:CAPTURE,
  records:{
    taskPoints:'{"claims":{"daily":5}}',
    socialCoinsAndXp:'{"xp":100}',
    earnedDiamonds:'{"source":"legacy","earned":1000}',
  },createdAt:serverTimestamp(),...overrides,
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
    setDoc(doc(d,"deda_sessions",UID),{uid:UID,accountKey:ACCOUNT,installId:"original-device"}),
    setDoc(doc(d,"users",UID),{accountKey:ACCOUNT,sharePersonalId:ORIGINAL}),
    setDoc(doc(d,"deda_account_directory",ACCOUNT),{accountKey:ACCOUNT,createdUid:UID,active:true}),
    setDoc(doc(d,"deda_share_ids",ORIGINAL),{publicId:ORIGINAL,kind:"personal",active:true,ownerUid:UID}),
    setDoc(doc(d,"deda_diamond_gift_balances",ORIGINAL),{publicId:ORIGINAL,balance:8765}),
  ]);
 });
});
test("original signed UID uploads one evidence-only immutable source",async()=>{
 const original=db(UID);
 await assertSucceeds(setDoc(doc(original,addr()),payload()));
 const snap=await assertSucceeds(getDoc(doc(original,addr())));
 assert.equal(snap.data().records.earnedDiamonds,payload().records.earnedDiamonds);
 await assertFails(setDoc(doc(original,addr()),payload()));
 await assertFails(deleteDoc(doc(original,addr())));
});
test("replacement phone with SAME UID reads immutable old-device capture",async()=>{
 await assertSucceeds(setDoc(doc(db(UID),addr()),payload()));
 const sameOriginalUidOnPhone2=db(UID);
 const read=await assertSucceeds(getDoc(doc(sameOriginalUidOnPhone2,addr())));
 assert.equal(read.data().sourceUid,UID);
 const list=await assertSucceeds(getDocs(query(
  collection(sameOriginalUidOnPhone2,"deda_progress_evidence",ACCOUNT,"captures"),
  orderBy("createdAt","desc"),limit(26))));
 assert.equal(list.size,1);
});
test("other Firebase UID cannot read/list/create original archives",async()=>{
 await assertSucceeds(setDoc(doc(db(UID),addr()),payload()));
 const other=db(OTHER);
 await assertFails(getDoc(doc(other,addr())));
 await assertFails(getDocs(query(collection(other,"deda_progress_evidence",ACCOUNT,"captures"),limit(26))));
 await assertFails(setDoc(doc(other,addr()),payload()));
});
test("wrong account or fake fields cannot be uploaded",async()=>{
 const original=db(UID);
 await assertFails(setDoc(doc(original,addr()),payload({accountKey:"07799999999"})));
 await assertFails(setDoc(doc(original,addr()),payload({sourceUid:OTHER})));
 await assertFails(setDoc(doc(original,addr()),payload({balanceCredit:9000000})));
 await assertFails(setDoc(doc(original,addr()),payload({kind:"verified-spendable-money"})));
 await assertFails(setDoc(doc(original,addr()),payload({records:{earnedDiamonds:"500000"}})));
 await assertFails(setDoc(doc(original,addr()),payload({captureId:"a-wrong-id"})));
});
test("original directory and personal route cannot be bypassed",async()=>{
 await env.withSecurityRulesDisabled(async c=>{
  await setDoc(doc(c.firestore(),"deda_share_ids",ORIGINAL),
   {publicId:ORIGINAL,kind:"personal",active:false,ownerUid:OTHER});
 });
 await assertFails(setDoc(doc(db(UID),addr()),payload()));
});
test("no session or revoked directory: no read or new upload",async()=>{
 await assertSucceeds(setDoc(doc(db(UID),addr()),payload()));
 await env.withSecurityRulesDisabled(async c=>{
  await deleteDoc(doc(c.firestore(),"deda_sessions",UID));
 });
 await assertFails(getDoc(doc(db(UID),addr())));
 await assertFails(setDoc(doc(db(UID),addr(ACCOUNT,"ABCDEFGHIJKLMNOPQRSTUVWX234567")),payload({
  captureId:"ABCDEFGHIJKLMNOPQRSTUVWX234567"
 })));
});
test("archive cannot modify gift-wallet financial state",async()=>{
 const originalWallet=await env.withSecurityRulesDisabled(async c=>
  (await getDoc(doc(c.firestore(),"deda_diamond_gift_balances",ORIGINAL))).data());
 await assertSucceeds(setDoc(doc(db(UID),addr()),payload()));
 const walletAfter=await env.withSecurityRulesDisabled(async c=>
  (await getDoc(doc(c.firestore(),"deda_diamond_gift_balances",ORIGINAL))).data());
 assert.deepEqual(walletAfter,originalWallet);
});
test("bounded list is required, never scan a user's entire account history",async()=>{
 await assertSucceeds(setDoc(doc(db(UID),addr()),payload()));
 await assertFails(getDocs(collection(db(UID),"deda_progress_evidence",ACCOUNT,"captures")));
});
