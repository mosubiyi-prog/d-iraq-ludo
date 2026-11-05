"use strict";
// Only local Firebase Emulator test. This reads candidate rules from the
// temporary CI file, NEVER the deployed Firestore rules.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require("@firebase/rules-unit-testing");
const {
  doc, collection, query, where, getDoc, getDocs,
  setDoc, updateDoc, serverTimestamp, Timestamp,
} = require("firebase/firestore");

const uid="owner-uid-stage2-domains";
const foreign="foreign-owner-stage2-domains";
const account="07712345678";
const original="@DEDA-ABC123";
const otherId="@DEDA-QQQ999";
const day="2026-11-05";
let baseline, candidate;
const owner=()=>candidate.authenticatedContext(uid, {
  email:account+"@deda-login.invalid",
  firebase:{sign_in_provider:"password"},
}).firestore();
const stranger=()=>candidate.authenticatedContext(foreign, {
  email:"foreign@example.com",firebase:{sign_in_provider:"password"},
}).firestore();

async function seed() {
  await candidate.clearFirestore();
  await candidate.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    for(const [path,data] of Object.entries({
      ["users/"+uid]:{
        accountKey:account,sharePersonalId:original,
      },
      ["deda_sessions/"+uid]:{
        uid,accountKey:account,installId:"existing-owner-install",
        signedInAt:Timestamp.now(),lastSeenAt:Timestamp.now(),
      },
      ["deda_share_ids/"+original]:{
        publicId:original,kind:"personal",ownerUid:uid,active:true,
      },
      ["deda_social_profiles/"+original]:{
        publicId:original,ownerUid:uid,displayName:"Original Owner",
      },
      ["deda_friendships/"+uid+"__friend-uid"]:{
        members:[uid,"friend-uid"],requesterUid:uid,
        recipientUid:"friend-uid",status:"accepted",
      },
      ["deda_diamond_gift_balances/"+original]:{
        publicId:original,balance:300,lastClaimGiftId:"gift-readback",
      },
      ["deda_diamond_gifts/gift-readback"]:{
        giftId:"gift-readback",targetPublicId:original,
        sourceType:"admin",amount:100,status:"claimed",
      },
      ["deda_stage71_active_identifier/"+original]:{
        originalId:original,activeId:"@DEDA-QA1234",
      },
      ["deda_profile_ui_migration/"+account]:{
        format:1,kind:"free-profile-appearance-only",
        accountKey:account,originalId:original,uid,
        avatarStyle:1,backgroundStyle:2,createdAt:Timestamp.now(),
      },
      ["deda_quiz_ui_snapshots/"+uid+"/days/"+day]:{
        format:1,kind:"display-only-untrusted-quiz-v1",
        uid,accountKey:account,originalId:original,day,
        encoded:"ui-only-nonfinancial",createdAt:Timestamp.now(),
      },
    })){
      await setDoc(doc(db,path),data);
    }
  });
}

test.before(async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST||"",/127\.0\.0\.1:/);
  const originalRules=fs.readFileSync("firestore.rules","utf8");
  const stage2Rules=fs.readFileSync(
    process.env.DEDA_JOURNAL_EMULATOR_RULES,"utf8");
  assert.doesNotMatch(originalRules,/match \/deda_friendships\//);
  assert.match(stage2Rules,/match \/deda_friendships\//);
  assert.match(stage2Rules,/match \/deda_quiz_ui_snapshots\//);
  baseline=await initializeTestEnvironment({
    projectId:"demo-deda-stage2-domain-base",
    firestore:{rules:originalRules},
  });
  candidate=await initializeTestEnvironment({
    projectId:"demo-deda-stage2-domain-candidate",
    firestore:{rules:stage2Rules},
  });
  await seed();
});
test.after(async()=>{
  if(baseline)await baseline.cleanup();
  if(candidate)await candidate.cleanup();
});

test("baseline source has no friend/profile/quiz rules; candidate owner can read",
  async()=>{
    const base=baseline.authenticatedContext(uid).firestore();
    await assertFails(getDoc(doc(base,"deda_social_profiles",original)));
    const db=owner();
    const profile=await assertSucceeds(getDoc(
      doc(db,"deda_social_profiles",original)));
    assert.equal(profile.data().ownerUid,uid);
    const relations=await assertSucceeds(getDocs(query(
      collection(db,"deda_friendships"),
      where("members","array-contains",uid))));
    assert.equal(relations.size,1);
    assert.equal(relations.docs[0].data().status,"accepted");
    const prefs=await assertSucceeds(getDoc(
      doc(db,"deda_profile_ui_migration",account)));
    assert.equal(prefs.data().originalId,original);
    const selection=await assertSucceeds(getDoc(
      doc(db,"deda_stage71_active_identifier",original)));
    assert.equal(selection.data().activeId,"@DEDA-QA1234");
    const quiz=await assertSucceeds(getDoc(
      doc(db,"deda_quiz_ui_snapshots",uid,"days",day)));
    assert.equal(quiz.data().uid,uid);
});

test("same UID reads historical gift wallet/inbox without writing a second award",
  async()=>{
    const db=owner();
    const wallet=await assertSucceeds(getDoc(
      doc(db,"deda_diamond_gift_balances",original)));
    assert.equal(wallet.data().balance,300);
    const inbox=await assertSucceeds(getDocs(query(
      collection(db,"deda_diamond_gifts"),
      where("targetPublicId","==",original))));
    assert.equal(inbox.size,1);
    assert.equal(inbox.docs[0].data().amount,100);
    await assertFails(updateDoc(
      doc(db,"deda_diamond_gift_balances",original),{balance:999999}));
    await assertFails(setDoc(
      doc(db,"deda_gm_personal_diamond_wallets",account),
      {accountKey:account,balance:1000000}));
});

test("foreign UID cannot read private friends, quiz, free appearance or gifts",
  async()=>{
    const db=stranger();
    await assertFails(getDocs(query(
      collection(db,"deda_friendships"),
      where("members","array-contains",uid))));
    await assertFails(getDoc(doc(db,"deda_profile_ui_migration",account)));
    await assertFails(getDoc(
      doc(db,"deda_stage71_active_identifier",original)));
    await assertFails(getDoc(
      doc(db,"deda_quiz_ui_snapshots",uid,"days",day)));
    await assertFails(getDocs(query(
      collection(db,"deda_diamond_gifts"),
      where("targetPublicId","==",original))));
    await assertFails(getDoc(
      doc(db,"deda_diamond_gift_balances",original)));
});

test("owner cannot enumerate all friendships or mutate another relationship",
  async()=>{
    const db=owner();
    await assertFails(getDocs(collection(db,"deda_friendships")));
    await assertFails(setDoc(doc(db,"deda_friendships","forged-relation"),{
      members:[uid,foreign],status:"accepted",
    }));
    await assertFails(updateDoc(doc(db,
      "deda_friendships",uid+"__friend-uid"),{status:"accepted"}));
});

test("old phone may create immutable free settings and quiz backup only for itself",
  async()=>{
    await seed();
    await candidate.withSecurityRulesDisabled(async ctx=>{
      const db=ctx.firestore();
      const {deleteDoc}=require("firebase/firestore");
      await deleteDoc(doc(db,"deda_profile_ui_migration",account));
      await deleteDoc(doc(db,"deda_quiz_ui_snapshots",uid,"days",day));
    });
    const db=owner();
    const settings=doc(db,"deda_profile_ui_migration",account);
    await assertSucceeds(setDoc(settings,{
      format:1,kind:"free-profile-appearance-only",
      accountKey:account,originalId:original,uid,
      avatarStyle:1,backgroundStyle:4,createdAt:serverTimestamp(),
    }));
    await assertFails(updateDoc(settings,{avatarStyle:5}));
    const quiz=doc(db,"deda_quiz_ui_snapshots",uid,"days",day);
    await assertSucceeds(setDoc(quiz,{
      format:1,kind:"display-only-untrusted-quiz-v1",
      uid,accountKey:account,originalId:original,day,
      encoded:"display-only",createdAt:serverTimestamp(),
    }));
    await assertFails(updateDoc(quiz,{encoded:"give-me-diamonds"}));
    await assertFails(setDoc(doc(db,
      "deda_quiz_ui_snapshots",foreign,"days",day),{
      format:1,kind:"display-only-untrusted-quiz-v1",
      uid:foreign,accountKey:account,originalId:original,day,
      encoded:"forged",createdAt:serverTimestamp(),
    }));
});

test("owner private archive cannot be deleted or overwritten by third party",
  async()=>{
    const db=stranger();
    await assertFails(setDoc(doc(db,"deda_profile_ui_migration",account),{
      format:1,kind:"free-profile-appearance-only",
      accountKey:account,originalId:otherId,uid:foreign,
      avatarStyle:0,backgroundStyle:0,createdAt:serverTimestamp(),
    }));
    await assertFails(setDoc(doc(db,
      "deda_quiz_ui_snapshots",uid,"days",day),{
      format:1,kind:"display-only-untrusted-quiz-v1",
      uid,accountKey:account,originalId:original,day,
      encoded:"forged",createdAt:serverTimestamp(),
    }));
});

test("optional legacy cloud archives: original UID can read MISSING, foreign UID cannot",
  async()=>{
    await seed();
    const missing=[
      ["deda_social_profiles",original],
      ["deda_stage71_active_identifier",original],
      ["deda_profile_ui_migration",account],
      ["deda_quiz_ui_snapshots",uid,"days",day],
    ];
    await candidate.withSecurityRulesDisabled(async ctx=>{
      const {deleteDoc}=require("firebase/firestore");
      const db=ctx.firestore();
      for(const parts of missing) await deleteDoc(doc(db,...parts));
    });
    const mine=owner(),other=stranger();
    for(const parts of missing) {
      const absent=await assertSucceeds(getDoc(doc(mine,...parts)));
      assert.equal(absent.exists(),false,
        "no backup must mean UNKNOWN, never account reset");
      await assertFails(getDoc(doc(other,...parts)));
    }
});
