import {readFileSync} from "node:fs";
import {before,after,test} from "node:test";
import {assertFails,assertSucceeds,initializeTestEnvironment}
  from "@firebase/rules-unit-testing";
import {doc,getDoc,setDoc,updateDoc,deleteDoc,
  serverTimestamp,Timestamp} from "firebase/firestore";

const PROJECT="demo-deda-stage41-canonical-progress";
const FILE=process.env.DEDA_STAGE41_CANDIDATE_RULES_TMPFILE;
if(!FILE||!FILE.endsWith(".rules")||
   !process.env.FIRESTORE_EMULATOR_HOST)
  throw Error("STAGE41_TESTS_LOCAL_PRIVATE_RULES_EMULATOR_ONLY");
const RULES=readFileSync(FILE,"utf8");
if(!RULES.includes("stage41DistinctCanonicalRecipient")||
   !RULES.includes("match /deda_verified_progress/{document=**}"))
  throw Error("STAGE41_NO_REVIEWED_CANDIDATE_RULES");

let env,authA,authB,authAlias,manager,outsider,anon;
const A="stage41_original_sender",B="stage41_actual_recipient";
const ALIAS="stage41_other_phone_same_account";
const MANAGER="stage41_general_manager";
const FORGER="stage41_other_user";
const ACCOUNT_A="07701234567",ACCOUNT_B="07707654321";
const ID_A="@DEDA-A12345", ID_B="@DEDA-B12345";
const ID_ALIAS="@DEDA-C12345",ID_SAME_UID="@DEDA-D12345";
function share(changes={}){
  const t=Date.now();
  return {
    senderUid:A,senderPublicId:ID_A,
    senderName:"Stage41 sender",recipientPublicId:ID_B,
    shareType:"current",placeName:"",placeId:"",
    latitude:35.4,longitude:44.1,durationMinutes:15,
    status:"pending",
    createdAt:serverTimestamp(),updatedAt:serverTimestamp(),
    expiresAt:Timestamp.fromMillis(t+15*60*1000),
    ...changes
  };
}
before(async()=>{
  env=await initializeTestEnvironment({
    projectId:PROJECT,firestore:{rules:RULES},
  });
  authA=env.authenticatedContext(A).firestore();
  authB=env.authenticatedContext(B).firestore();
  authAlias=env.authenticatedContext(ALIAS).firestore();
  manager=env.authenticatedContext(MANAGER,{role:"general_manager"}).firestore();
  outsider=env.authenticatedContext(FORGER).firestore();
  anon=env.unauthenticatedContext().firestore();
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    for(const [uid,key,id,name] of [
      [A,ACCOUNT_A,ID_A,"Stage41 sender"],
      [B,ACCOUNT_B,ID_B,"Stage41 recipient"],
      [ALIAS,ACCOUNT_A,ID_ALIAS,"Another device same DEDA account"],
      [FORGER,"07701110000","@DEDA-E12345","Outsider"],
    ])await setDoc(doc(db,"users",uid),{
      uid,accountKey:key,sharePersonalId:id,name,
    });
    for(const [id,uid] of [[ID_A,A],[ID_B,B],
      [ID_ALIAS,ALIAS],[ID_SAME_UID,A]]){
      await setDoc(doc(db,"deda_share_ids",id),{
        active:true,kind:"personal",ownerUid:uid,publicId:id,
      });
    }
    await setDoc(doc(db,"admins",MANAGER),{
      active:true,status:"active",role:"general_manager",
    });
    const coreIds=[
      "deda_progress_migrations/"+ACCOUNT_A,
      "deda_progress_migrations/"+ACCOUNT_A+"/reviews/review_01",
      "deda_progress_migrations/"+ACCOUNT_A+"/classifications/receipt_01",
      "deda_progress_migrations/"+ACCOUNT_A+"/settlements/settlement_01",
      "deda_progress_evidence/"+ACCOUNT_A+"/captures/capture_01",
      "deda_progress_receipts/"+ACCOUNT_A+"/events/receipt_01",
      "deda_verified_progress/"+ACCOUNT_A,
      "deda_verified_progress/"+ACCOUNT_A+"/events/receipt_01",
      "deda_weekly_stage38_private_task_proofs/receipt_01",
      "deda_weekly_stage38_private_writer_fences/"+ACCOUNT_A,
      "deda_weekly_stage38_private_league_receipts/receipt_01",
    ];
    for(const path of coreIds){
      await setDoc(doc(db,path),{accountKey:ACCOUNT_A,
        testFixtureOnly:true,points:105,coins:40,xp:1250,
        earnedDiamonds:800,receiptId:"fixture_01"});
    }
  });
});
after(async()=>{if(env)await env.cleanup();});

test("original legitimate two-distinct-account share still works",async()=>{
  await assertSucceeds(setDoc(doc(authA,"deda_location_shares","s41_valid"),
    share()));
  await assertSucceeds(getDoc(doc(authA,"deda_location_shares","s41_valid")));
  await assertSucceeds(getDoc(doc(authB,"deda_location_shares","s41_valid")));
  await assertFails(getDoc(doc(outsider,"deda_location_shares","s41_valid")));
});
test("original valid sender cannot share with OWN public ID",async()=>{
  await assertFails(setDoc(doc(authA,"deda_location_shares","s41_selfid"),
    share({recipientPublicId:ID_A})));
});
test("different public ID registered under SAME authenticated UID blocked",async()=>{
  await assertFails(setDoc(doc(authA,"deda_location_shares","s41_secondid"),
    share({recipientPublicId:ID_SAME_UID})));
});
test("different UID and personal ID but SAME canonical account blocked",async()=>{
  await assertFails(setDoc(doc(authA,"deda_location_shares","s41_alias"),
    share({recipientPublicId:ID_ALIAS})));
});
test("third-party recipient cannot submit forged sender to earn points",async()=>{
  await assertFails(setDoc(doc(authAlias,"deda_location_shares","s41_forged"),
    share({recipientPublicId:ID_B})));
  await assertFails(setDoc(doc(manager,"deda_location_shares","s41_manager_forged"),
    share()));
});
test("original legitimate share cannot be mutated/deleted even as manager",async()=>{
  await assertFails(updateDoc(doc(authA,"deda_location_shares","s41_valid"),
    {latitude:91}));
  await assertFails(deleteDoc(doc(manager,"deda_location_shares","s41_valid")));
});

const paths=[
  "deda_progress_migrations/"+ACCOUNT_A,
  "deda_progress_migrations/"+ACCOUNT_A+"/reviews/review_01",
  "deda_progress_migrations/"+ACCOUNT_A+"/classifications/receipt_01",
  "deda_progress_migrations/"+ACCOUNT_A+"/settlements/settlement_01",
  "deda_progress_evidence/"+ACCOUNT_A+"/captures/capture_01",
  "deda_progress_receipts/"+ACCOUNT_A+"/events/receipt_01",
  "deda_verified_progress/"+ACCOUNT_A,
  "deda_verified_progress/"+ACCOUNT_A+"/events/receipt_01",
  "deda_weekly_stage38_private_task_proofs/receipt_01",
  "deda_weekly_stage38_private_writer_fences/"+ACCOUNT_A,
  "deda_weekly_stage38_private_league_receipts/receipt_01",
];
for(const [role,source] of [
  ["account owner",()=>authA],
  ["another phone same account",()=>authAlias],
  ["general manager client",()=>manager],
  ["unrelated signed account",()=>outsider],
  ["unauthenticated",()=>anon],
]){
  test(role+" CANNOT read or write privileged migrated balances, receipts and writer fences",async()=>{
    for(const path of paths){
      const ref=doc(source(),path);
      await assertFails(getDoc(ref));
      await assertFails(setDoc(ref,{accountKey:ACCOUNT_A,
        points:900000,xp:900000,earnedDiamonds:900000}));
      await assertFails(updateDoc(ref,{xp:900000}));
      await assertFails(deleteDoc(ref));
    }
  });
}
test("client direct new server claim issuer document cannot be forged",async()=>{
  const ref=doc(authA,"deda_weekly_stage38_private_task_proofs","new_forgery");
  await assertFails(setDoc(ref,{issuer:"server",emulatorOnly:true,
    ordinaryTaskPointsAwardedPreviously:false,
    originalLevelXpAwardedPreviously:false}));
});
