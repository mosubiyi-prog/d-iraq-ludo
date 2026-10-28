import {readFileSync} from "node:fs";
import {before,after,test} from "node:test";
import {strict as assert} from "node:assert";
import {assertFails,assertSucceeds,initializeTestEnvironment}
  from "@firebase/rules-unit-testing";
import {doc,getDoc,setDoc,updateDoc,deleteDoc} from "firebase/firestore";

/*
 * Entire REAL deployed Firestore rules (read-only fetched by CI) PLUS
 * isolated Stage41/48 deny-only patch, tested on the local emulator.
 * Expected security property: NO client can alter server-owned XP,
 * proof, old-app cutover audit, private gifts or second-phone ledger.
 * This is a candidate. Does NOT protect real users until reviewed
 * and separately deployed by authorized owner.
 */
const RULES_FILE=process.env.DEDA_STAGE49_CANDIDATE_RULES_TMPFILE;
const PROJECT="demo-deda-stage49-server-uid-binding";
if(!RULES_FILE||!RULES_FILE.endsWith(".rules")||
   !process.env.FIRESTORE_EMULATOR_HOST)
  throw Error("STAGE49_REQUIRES_REAL_LIVE_DERIVED_TEMP_RULES_AND_EMULATOR");
const rules=readFileSync(RULES_FILE,"utf8");
if(!rules.includes("stage41DistinctCanonicalRecipient")||
   !rules.includes("STAGE48 PRIVATE FULL-LIVE RULESET CANDIDATE")||
   !rules.includes("match /deda_weekly_stage46_private_server_signed_task_claims/{document=**}"))
  throw Error("STAGE49_MISSING_REVIEWED_CANDIDATE");
const ACCOUNT="07701234567";
const A="stage48_account_original_phone";
const SAME="stage48_same_canonical_second_phone";
const OTHER="stage48_unrelated_account";
const GM="stage48_general_manager";
const ID="stage49_sender_personal_id";
const roots=[
  "deda_weekly_identity_attestations",
  "deda_weekly_stage42_server_verified_share_actions_private",
  "deda_weekly_stage42_private_league_receipts",
  "deda_weekly_stage42_private_writer_fences",
  "deda_weekly_stage43_private_reviewed_cutover_epochs",
  "deda_weekly_stage43_private_enrolled_server_installs",
  "deda_weekly_stage44_private_public_profile_fixtures",
  "deda_weekly_stage45_private_sealed_top10",
  "deda_weekly_stage45_private_gift_settlements",
  "deda_weekly_stage45_private_gift_inbox",
  "deda_weekly_stage45_private_shadow_earned_diamonds",
  "deda_weekly_stage46_private_server_signed_task_claims",
  "deda_weekly_stage47_private_two_device_legacy_audit_HOLD_ONLY"
];
const extraPaths=[
  "deda_progress_migrations/"+ACCOUNT+"/task_authorizations/receipt_01",
  "deda_progress_migrations/"+ACCOUNT+"/settlements/settlement_01",
  "deda_verified_progress/"+ACCOUNT+"/events/receipt_01",
  "deda_progress_receipts/"+ACCOUNT+"/events/receipt_01",
  "deda_progress_evidence/"+ACCOUNT+"/captures/old_phone",
  "deda_weekly_stage47_private_two_device_legacy_audit_HOLD_ONLY/audit_01/illegal/child",
];
const allPaths=[
  ...roots.map(root=>root+"/stage48_private_fixture01"),
  ...extraPaths,
  "deda_weekly_stage49_private_server_uid_bindings/"+A,
  "deda_weekly_stage49_private_server_uid_bindings/"+SAME,
  "deda_weekly_stage49_private_server_uid_bindings/server_saved_uid_01",
];
let env,owner,second,other,manager,unauth;
before(async()=>{
 env=await initializeTestEnvironment({projectId:PROJECT,firestore:{rules}});
 owner=env.authenticatedContext(A).firestore();
 second=env.authenticatedContext(SAME).firestore();
 other=env.authenticatedContext(OTHER).firestore();
 manager=env.authenticatedContext(GM).firestore();
 unauth=env.unauthenticatedContext().firestore();
 await env.withSecurityRulesDisabled(async context=>{
   const db=context.firestore();
   await setDoc(doc(db,"admins",GM),{
     active:true,status:"active",role:"general_manager"
   });
   for(const [uid,accountKey] of [
     [A,ACCOUNT],[SAME,ACCOUNT],[OTHER,"07707654321"]
   ]){
     await setDoc(doc(db,"users",uid),{
       uid,accountKey,sharePersonalId:"@DEDA-"+uid.slice(0,6).toUpperCase(),
       name:"Stage49 client"
     });
     await setDoc(doc(db,"deda_sessions",uid),{
       uid,accountKey,installId:"existing_install",
       signedInAt:0,lastSeenAt:0
     });
   }
   await setDoc(doc(db,"deda_account_profiles",ACCOUNT),{
     accountKey:ACCOUNT,name:"Stage48",
     trustedInstallIds:["existing_install"]
   });
   for(const path of allPaths)
     await setDoc(doc(db,path),{
       issuer:"privileged_backend_fixture_only",
       emulatorOnly:true,canAuthorizeProduction:false,
       accountKey:ACCOUNT,source:"stage48",xp:20,
       coins:10,earnedDiamonds:150
     });
 });
});
after(async()=>{if(env)await env.cleanup();});

test("new server UID binding denied for CLIENT writes despite mutable original installs",()=>{
 assert.ok(rules.includes("match /deda_weekly_stage49_private_server_uid_bindings/{uid}"));
 // Existing Stage48 protects 13 other private namespaces too.
 assert.ok(rules.includes("STAGE48 PRIVATE FULL-LIVE RULESET CANDIDATE"));
});
test("full current deployed rules provenance and EXACT 13 server-only namespaces",()=>{
 assert.equal(roots.length,13);
 for(const root of roots){
   const match="match /"+root+"/{document=**} {";
   assert.ok(rules.includes(match),"missing explicit deny match "+root);
 }
 assert.ok(rules.includes("match /deda_progress_migrations/{document=**}"));
 assert.ok(rules.includes("stage41DistinctCanonicalRecipient"));
});
test("CURRENT legacy session install and trustedInstallIds are CLIENT WRITABLE, not trusted claims",async()=>{
 const profile=doc(owner,"deda_account_profiles",ACCOUNT);
 await assertSucceeds(updateDoc(profile,{
   trustedInstallIds:["existing_install","client_added_install"]
 }));
 const session=doc(owner,"deda_sessions",A);
 await assertSucceeds(updateDoc(session,{installId:"client_added_install"}));
 const saved=await assertSucceeds(getDoc(session));
 assert.equal(saved.data().installId,"client_added_install");
 // No API-authenticated server proof is established by this operation.
});
for(const [role,client] of [
 ["original account owner",()=>owner],
 ["second phone on same canonical account",()=>second],
 ["unrelated signed-in account",()=>other],
 ["general-manager Flutter client",()=>manager],
 ["anonymous / unauthenticated client",()=>unauth],
]){
 test(role+" denied GET / CREATE / UPDATE / DELETE on every private XP, gift and claim root",async()=>{
   let tried=0;
   for(const path of allPaths){
     const ref=doc(client(),path);
     await assertFails(getDoc(ref));tried++;
     await assertFails(updateDoc(ref,{xp:900000,earnedDiamonds:900000}));tried++;
     await assertFails(deleteDoc(ref));tried++;
     await assertFails(setDoc(doc(client(),path+"__forged"),{
       issuer:"privileged_server",accountKey:ACCOUNT,
       canAuthorizeProduction:true,source:"old_apk_replay",
       lifetimeXp:900000,socialCoins:900000,earnedDiamonds:900000
     }));tried++;
   }
   assert.equal(tried,allPaths.length*4);
 });
}
test("owner cannot read or forge a fake Stage46 signed original +20 task receipt",async()=>{
 const proof="deda_weekly_stage46_private_server_signed_task_claims/"+
    "a".repeat(64);
 await assertFails(setDoc(doc(owner,proof),{
   record:{accountKey:ACCOUNT,points:5,lifetimeXp:20,
     socialCoins:10,weeklyXpWhenActive:20},
   signature:"f".repeat(64),issuer:"stage46_backend_private_signed_claim_TEST_ONLY",
   emulatorOnly:true
 }));
 await assertFails(getDoc(doc(manager,proof)));
});
test("old APK cannot forge a top-ten diamonds inbox gift even if session install is writable",async()=>{
 const r=doc(owner,"deda_weekly_stage45_private_gift_inbox/stage48_client_forgery");
 await assertFails(setDoc(r,{
   place:1,amount:150,status:"received",
   recipientToken:ACCOUNT,emulatorOnly:false,
   issuer:"stage45_backend_fixture_only_NOT_LIVE"
 }));
 await assertFails(getDoc(doc(owner,"deda_weekly_stage45_private_gift_inbox/stage48_private_fixture01")));
});
