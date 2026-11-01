"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const fs=require("node:fs"),path=require("node:path");
const {createRequire}=require("node:module");
const req=createRequire(path.resolve(__dirname,"../functions/package.json"));
const {initializeTestEnvironment,assertSucceeds,assertFails}=
  req("@firebase/rules-unit-testing");
const {doc,setDoc,getDoc,getDocs,collection,deleteDoc,updateDoc,
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

const visualPath=(key=ACCOUNT)=>"deda_profile_ui_migration/"+key;
const visual=(overrides={})=>({
 format:1,kind:"free-profile-appearance-only",accountKey:ACCOUNT,
 originalId:ORIGINAL,uid:UID,avatarStyle:3,backgroundStyle:5,
 createdAt:serverTimestamp(),...overrides,
});
test("original phone stores immutable FREE visual preference snapshot, second device with SAME UID reads",async()=>{
 const original=db(UID);
 await assertSucceeds(setDoc(doc(original,visualPath()),visual()));
 const sameUidPhone2=db(UID);
 const snapshot=await assertSucceeds(getDoc(doc(sameUidPhone2,visualPath())));
 assert.equal(snapshot.data().avatarStyle,3);
 assert.equal(snapshot.data().backgroundStyle,5);
 await assertFails(setDoc(doc(original,visualPath()),visual({avatarStyle:4})));
 await assertFails(deleteDoc(doc(original,visualPath())));
});
test("other UID cannot read, enumerate or create visual preferences",async()=>{
 await assertSucceeds(setDoc(doc(db(UID),visualPath()),visual()));
 await assertFails(getDoc(doc(db(OTHER),visualPath())));
 await assertFails(getDocs(collection(db(OTHER),"deda_profile_ui_migration")));
 await assertFails(setDoc(doc(db(OTHER),visualPath()),visual()));
});
test("visual restore cannot smuggle paid frames, diamonds, roles, rewards or arbitrary amounts",async()=>{
 const owner=db(UID);
 for(const bad of [
  {paidFrames:["f13"]}, {diamondBalance:100000},
  {weeklyPrizes:150}, {accountType:"admin"}, {premiumId:"@DEDA-AAAAAA"},
  {avatarStyle:6}, {backgroundStyle:-1}, {avatarStyle:"5"},
  {uid:OTHER}, {accountKey:"07799999999"}, {originalId:"@DEDA-FFFFFF"},
 ]) {
  await assertFails(setDoc(doc(owner,visualPath()),visual(bad)));
 }
 // The malicious appearance writes have all been rejected; no valid
 // migration document has been written or paid entitlement issued.
 const rejected=await assertSucceeds(getDoc(doc(owner,visualPath())));
 assert.equal(rejected.exists(),false);
 // The separate pre-existing "archive cannot modify gift-wallet" regression
 // above continues to check financial isolation against the same rules.

});
test("visual archive requires active original route and session",async()=>{
 const owner=db(UID);
 await env.withSecurityRulesDisabled(async c=>{
  await deleteDoc(doc(c.firestore(),"deda_sessions",UID));
 });
 await assertFails(setDoc(doc(owner,visualPath()),visual()));
 await assertFails(getDoc(doc(owner,visualPath())));
});

const publishedPlacePath="published_places/DEDA-ORIGINAL-APPROVED-PLACE-434";
async function seedPublishedOwnerPlace(){
  await env.withSecurityRulesDisabled(async c=>{
    await setDoc(doc(c.firestore(),publishedPlacePath),{
      placeName:"Synthetic Approved Owner Place",
      accountKey:ACCOUNT,ownerUid:UID,published:true,
      approvalNumber:"ORIGINAL-DEDA-APPROVAL-434",
      isAvailableNow:false,likes:17,followers:9,
      updatedAt:serverTimestamp(),
    });
  });
}
test("same original UID on replacement phone can manage original approved place availability",async()=>{
  await seedPublishedOwnerPlace();
  const newPhoneSameUid=db(UID);
  const ref=doc(newPhoneSameUid,publishedPlacePath);
  const before=await assertSucceeds(getDoc(ref));
  assert.equal(before.data().ownerUid,UID);
  assert.equal(before.data().approvalNumber,"ORIGINAL-DEDA-APPROVAL-434");
  await assertSucceeds(updateDoc(ref,{
    isAvailableNow:true,updatedAt:serverTimestamp(),
  }));
  const after=await assertSucceeds(getDoc(ref));
  assert.equal(after.data().isAvailableNow,true);
  assert.equal(after.data().ownerUid,UID);
  assert.equal(after.data().approvalNumber,before.data().approvalNumber);
  assert.equal(after.data().likes,17);
  assert.equal(after.data().followers,9);
});
test("foreign UID cannot manage or take over another account's published place",async()=>{
  await seedPublishedOwnerPlace();
  const foreign=db(OTHER);
  const ref=doc(foreign,publishedPlacePath);
  // The map place itself is public; management is never public.
  const visible=await assertSucceeds(getDoc(ref));
  assert.equal(visible.data().published,true);
  await assertFails(updateDoc(ref,{
    isAvailableNow:true,updatedAt:serverTimestamp(),
  }));
  const owner=db(UID);
  await assertFails(updateDoc(doc(owner,publishedPlacePath),{
    ownerUid:OTHER,approvalNumber:"FORGED",updatedAt:serverTimestamp(),
  }));
  const unchanged=await assertSucceeds(getDoc(doc(owner,publishedPlacePath)));
  assert.equal(unchanged.data().ownerUid,UID);
  assert.equal(unchanged.data().approvalNumber,"ORIGINAL-DEDA-APPROVAL-434");
  assert.equal(unchanged.data().isAvailableNow,false);
});
