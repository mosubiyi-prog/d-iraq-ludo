"use strict";
// Stage20 source reconciliation READ ONLY / real Firestore Emulator.
// This NEVER calls any live Firebase Cloud Function or touches a live wallet.
const test=require("node:test"),assert=require("node:assert/strict");
const {createRequire}=require("node:module"),{resolve}=require("node:path");
const {readFileSync}=require("node:fs");
assert.match(process.env.FIRESTORE_EMULATOR_HOST||"",
  /^(127\.0\.0\.1|localhost):[0-9]+$/, "EMULATOR REQUIRED");
const req=createRequire(resolve(__dirname,"../functions/package.json"));
const {initializeApp,deleteApp}=req("firebase-admin/app");
const {getFirestore}=req("firebase-admin/firestore");
const {initializeTestEnvironment,assertFails}=req("@firebase/rules-unit-testing");
const {doc,setDoc,getDoc}=req("firebase/firestore");
const {auditDiamondSourcesForAuthenticatedAccount:audit}=
  require("../tools/deda_jamal_stage20_diamond_source_audit_readonly_2026_10_19.js");

const PROJECT="demo-deda-stage20-diamonds-source-audit";
let db,app,env;
const A={uid:"diamond_a_uid",key:"diamond_account_A",orig:"@DEDA-A1B2C3"},
      B={uid:"diamond_b_uid",key:"diamond_account_B",orig:"@DEDA-D4E5F6"};
async function seed(){
  await env.clearFirestore();
  const b=db.batch();
  for(const user of [A,B]){
    b.set(db.collection("users").doc(user.uid),{
      accountKey:user.key,sharePersonalId:user.orig,
      diamonds:987654321,level:9,points:800,
    });
    b.set(db.collection("deda_sessions").doc(user.uid),{
      uid:user.uid,accountKey:user.key,
    });
    b.set(db.collection("deda_share_ids").doc(user.orig),{
      kind:"personal",publicId:user.orig,
      ownerUid:user.uid,active:true,
    });
  }
  b.set(db.collection("deda_diamond_gift_balances").doc(A.orig),{
    publicId:A.orig,balance:75,
  });
  b.set(db.collection("deda_diamond_gift_balances").doc(B.orig),{
    publicId:B.orig,balance:180,
  });
  b.set(db.collection("deda_gm_personal_diamond_wallets").doc(A.key),{
    accountKey:A.key,initialBalance:1000000,balance:999999,
  });
  b.set(db.collection("admin_entry_access").doc(A.key),{
    accountKey:A.key,allowedRole:"general_manager",
    accessType:"general_manager_gateway",active:true,status:"active",
  });
  b.set(db.collection("admins").doc(A.uid),{
    active:true,status:"active",role:"general_manager",
  });
  b.set(db.collection("deda_admin_diamond_wallets").doc(A.uid),{
    adminUid:A.uid,initialBalance:1000000,balance:900000,
  });
  await b.commit();
}
async function snapshot(ref){return (await ref.get()).data();}
test.before(async()=>{
  app=initializeApp({projectId:PROJECT},"stage20-diamond-reads-only");
  db=getFirestore(app);
  env=await initializeTestEnvironment({
    projectId:PROJECT,
    firestore:{
      host:"127.0.0.1",port:Number(
        process.env.FIRESTORE_EMULATOR_HOST.split(":")[1]),
      rules:readFileSync(resolve(__dirname,"../firestore.rules"),"utf8"),
    },
  });
});
test.after(async()=>{if(env)await env.cleanup();if(app)await deleteApp(app);});

test("manager audit reads separate gift and personal wallets, never spends gift pool",async()=>{
  await seed();
  const gifted=db.collection("deda_diamond_gift_balances").doc(A.orig);
  const personal=db.collection("deda_gm_personal_diamond_wallets").doc(A.key);
  const pool=db.collection("deda_admin_diamond_wallets").doc(A.uid);
  const [oldGift,oldPersonal,oldPool]=await Promise.all([
    snapshot(gifted),snapshot(personal),snapshot(pool),
  ]);
  const x=await audit(db,{uid:A.uid});
  assert.equal(x.serverConfirmed,true);
  assert.equal(x.giftAndServerVerifiedRewardWallet.recordedBalance,75);
  assert.equal(x.managerPersonalTestWallet.recordedBalance,999999);
  assert.equal(x.managerPersonalTestWallet.currentlyAuthorizedGM,true);
  assert.equal(x.managerPersonalTestWallet.approvedForAutomaticMigration,false);
  assert.equal(x.purchaseActivationApproved,false);
  assert.deepEqual(await Promise.all([
    snapshot(gifted),snapshot(personal),snapshot(pool),
  ]),[oldGift,oldPersonal,oldPool]);
});
test("ordinary account sees only own verified gift wallet; no cross-wallet leak",async()=>{
  await seed();
  const x=await audit(db,{uid:B.uid});
  assert.equal(x.originalId,B.orig);
  assert.equal(x.giftAndServerVerifiedRewardWallet.recordedBalance,180);
  assert.equal(x.managerPersonalTestWallet.recordedBalance,0);
  assert.equal(x.managerPersonalTestWallet.currentlyAuthorizedGM,false);
  assert.equal(x.purchaseActivationApproved,false);
});
test("revoke canonical manager role: old gateway entry cannot approve personal test balance",async()=>{
  await seed();
  await db.collection("admins").doc(A.uid).update({role:"employee"});
  const x=await audit(db,{uid:A.uid});
  assert.equal(x.managerPersonalTestWallet.currentlyAuthorizedGM,false);
  assert.equal(x.managerPersonalTestWallet.recordedBalance,999999);
  assert.equal(x.managerPersonalTestWallet.approvedForAutomaticMigration,false);
});
test("stale or spoofed session denies source reconciliation",async()=>{
  await seed();
  await db.collection("deda_sessions").doc(A.uid)
    .update({accountKey:"wrong_account"});
  await assert.rejects(audit(db,{uid:A.uid}),
    e=>e.code==="permission-denied");
});
test("wrong wallet publicId or broken value rejects rather than minting funds",async()=>{
  await seed();
  await db.collection("deda_diamond_gift_balances").doc(A.orig)
    .update({balance:-1});
  await assert.rejects(audit(db,{uid:A.uid}),
    e=>e.code==="failed-precondition");
});
test("existing real rules deny clients writing a synthetic spendable migration ledger",async()=>{
  await seed();
  const client=env.authenticatedContext(B.uid).firestore();
  await assertFails(setDoc(doc(client,
    "deda_diamond_migration_server_ledger","forged_earned_1"),{
    uid:B.uid,diamonds:987654321,serverVerified:true,
  }));
  await assertFails(getDoc(doc(client,
    "deda_diamond_migration_server_ledger","forged_earned_1")));
});
