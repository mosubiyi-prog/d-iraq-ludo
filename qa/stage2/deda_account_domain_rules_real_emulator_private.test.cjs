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
  assert.doesNotMatch(originalRules,/match \/deda_stage66_card_receipts\//);
  assert.match(stage2Rules,/match \/deda_stage66_card_receipts\//);
  assert.match(stage2Rules,/match \/deda_stage71_granted_registry\//);
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

test("missing PRIVATE archives: original UID reads unknown, foreign UID denied",
  async()=>{
    await seed();
    const missing=[
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

test("public friend lookup remains readable but only for active personal IDs",
  async()=>{
    await seed();
    const mine=owner(),other=stranger();
    const existing=await assertSucceeds(getDoc(
      doc(other,"deda_social_profiles",original)));
    assert.equal(existing.data().displayName,"Original Owner");
    await candidate.withSecurityRulesDisabled(async ctx=>{
      const {deleteDoc}=require("firebase/firestore");
      await deleteDoc(doc(ctx.firestore(),"deda_social_profiles",original));
    });
    const missing=await assertSucceeds(getDoc(
      doc(other,"deda_social_profiles",original)));
    assert.equal(missing.exists(),false,
      "optional public friend display missing is not an account reset");
    await assertFails(getDoc(doc(other,"deda_social_profiles",otherId)));
    await assertSucceeds(getDoc(doc(mine,"deda_social_profiles",original)));
});

test("public friend profile with secret fields is blocked for every client",
  async()=>{
    await seed();
    await candidate.withSecurityRulesDisabled(async ctx=>{
      await setDoc(doc(ctx.firestore(),"deda_social_profiles",original),{
        publicId:original, ownerUid:uid, displayName:"Original Owner",
        phone:"07700000000", privateGiftBalance:999999,
      });
    });
    await assertFails(getDoc(doc(stranger(),"deda_social_profiles",original)));
    await assertFails(getDoc(doc(owner(),"deda_social_profiles",original)));
    await seed();
    const publicOnly=await assertSucceeds(getDoc(
      doc(stranger(),"deda_social_profiles",original)));
    assert.equal(publicOnly.data().displayName,"Original Owner");
});

// Stage2 asset provenance: strictly existing server receipts and grants.
// This test proves neither old AdMob local diamonds nor any automatic credit.
async function seedAssetEvidence() {
  await seed();
  await candidate.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore(), now=Timestamp.now();
    const paidId=original+"_gold";
    await setDoc(doc(db,"deda_stage66_card_receipts",paidId),{
      publicId:original,kind:"card",style:"gold",cost:5000,createdAt:now,
    });
    await setDoc(doc(db,"deda_stage66_owned_cards",paidId),{
      publicId:original,style:"gold",receiptId:paidId,createdAt:now,
    });
    await setDoc(doc(db,"deda_stage71_granted_registry","@DEDA-AB1234"),{
      identifier:"@DEDA-AB1234",recipientOriginalId:original,group:"001",
      baseColor:"gold",kind:"self_used",grantedByUid:"manager",grantedAt:now,
    });
    await setDoc(doc(db,"deda_stage71_granted_registry","@DEDA-AC1234"),{
      identifier:"@DEDA-AC1234",recipientOriginalId:original,group:"001",
      baseColor:"royal",kind:"gifted",grantedByUid:"manager",grantedAt:now,
    });
    await setDoc(doc(db,"deda_stage74_id_gift_receipts","@DEDA-AC1234"),{
      identifier:"@DEDA-AC1234",originalId:original,group:"001",
      receivedAt:now,
    });
  });
}

test("original UID can read paired paid card and accepted premium grants only",
  async()=>{
    await seedAssetEvidence();
    const db=owner(), paidId=original+"_gold";
    const receipt=await assertSucceeds(getDoc(
      doc(db,"deda_stage66_card_receipts",paidId)));
    const owned=await assertSucceeds(getDoc(
      doc(db,"deda_stage66_owned_cards",paidId)));
    assert.equal(receipt.data().cost,5000);
    assert.equal(owned.data().receiptId,paidId);
    const grants=await assertSucceeds(getDocs(query(
      collection(db,"deda_stage71_granted_registry"),
      where("recipientOriginalId","==",original))));
    assert.equal(grants.size,2);
    const accepted=await assertSucceeds(getDoc(
      doc(db,"deda_stage74_id_gift_receipts","@DEDA-AC1234")));
    assert.equal(accepted.data().originalId,original);
    // Absence remains UNKNOWN, never an empty inventory proof for all history.
    const missing=await assertSucceeds(getDoc(
      doc(db,"deda_stage66_card_receipts",original+"_pink")));
    assert.equal(missing.exists(),false);
  });

test("foreign owner and unscoped registry cannot read another person's paid items",
  async()=>{
    await seedAssetEvidence();
    const other=stranger();
    await assertFails(getDoc(doc(other,
      "deda_stage66_card_receipts",original+"_gold")));
    await assertFails(getDoc(doc(other,
      "deda_stage66_owned_cards",original+"_gold")));
    await assertFails(getDoc(doc(other,
      "deda_stage74_id_gift_receipts","@DEDA-AC1234")));
    await assertFails(getDocs(query(
      collection(other,"deda_stage71_granted_registry"),
      where("recipientOriginalId","==",original))));
    await assertFails(getDocs(collection(owner(),
      "deda_stage71_granted_registry")));
  });

test("owner recovery readback cannot grant, claim, debit or rewrite receipts",
  async()=>{
    await seedAssetEvidence();
    const db=owner(),paidId=original+"_gold";
    await assertFails(updateDoc(doc(db,
      "deda_stage66_card_receipts",paidId),{cost:1}));
    await assertFails(setDoc(doc(db,
      "deda_stage66_owned_cards",original+"_pink"),{
        publicId:original,style:"pink",receiptId:original+"_pink",
      }));
    await assertFails(updateDoc(doc(db,
      "deda_stage71_granted_registry","@DEDA-AC1234"),{
        recipientOriginalId:otherId,
      }));
    await assertFails(setDoc(doc(db,
      "deda_stage74_id_gift_receipts","@DEDA-AC1234"),{
        identifier:"@DEDA-AC1234",originalId:original,group:"001",
        receivedAt:serverTimestamp(),
      }));
    await assertFails(updateDoc(doc(db,
      "deda_diamond_gift_balances",original),{balance:8000000}));
  });

test("corrupted paid receipt is denied and not silently treated as ownership",
  async()=>{
    await seedAssetEvidence();
    await candidate.withSecurityRulesDisabled(async ctx=>{
      await updateDoc(doc(ctx.firestore(),
        "deda_stage66_card_receipts",original+"_gold"),{cost:5});
    });
    await assertFails(getDoc(doc(owner(),
      "deda_stage66_card_receipts",original+"_gold")));
  });
