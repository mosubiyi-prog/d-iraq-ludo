"use strict";
const test=require("node:test"), assert=require("node:assert/strict");
const fs=require("node:fs");
const crypto=require("node:crypto");
const {auditDiamondSourcesForAuthenticatedAccount:check}=
  require("../tools/deda_jamal_stage20_diamond_source_audit_readonly_2026_10_19.js");

class Ref{
  constructor(path){this.path=path;}
  doc(id){return new Ref(this.path+"/"+id);}
}
class MemoryDb{
  constructor(){this.docs=new Map();this.writes=0;this.reads=0;}
  collection(n){return new Ref(n);}
  put(path,data){this.docs.set(path,structuredClone(data));}
  async runTransaction(f){
    const tx={
      get:async ref=>{
        this.reads++;
        const row=this.docs.get(ref.path);
        return {exists:!!row,data:()=>structuredClone(row)};
      },
      set:()=>{this.writes++;throw Error("write-is-forbidden");},
      update:()=>{this.writes++;throw Error("write-is-forbidden");},
      create:()=>{this.writes++;throw Error("write-is-forbidden");},
      delete:()=>{this.writes++;throw Error("write-is-forbidden");},
    };
    return f(tx);
  }
}
const uid="account_rotated_002",oldUid="account_original_001";
const key="account_fixed_person_01",orig="@DEDA-A1B2C3";
function fixture({gift=1200,gm=150000,role="general_manager",adminActive=true}={}){
  const db=new MemoryDb();
  db.put("users/"+uid,{accountKey:key,sharePersonalId:orig,
    localDiamonds:999999,points:300,level:12});
  db.put("deda_sessions/"+uid,{uid,accountKey:key});
  db.put("users/"+oldUid,{accountKey:key});
  db.put("deda_share_ids/"+orig,{
    kind:"personal",publicId:orig,active:true,ownerUid:oldUid,
  });
  db.put("deda_diamond_gift_balances/"+orig,{publicId:orig,balance:gift});
  db.put("deda_gm_personal_diamond_wallets/"+key,{
    accountKey:key,balance:gm,initialBalance:1000000});
  db.put("admin_entry_access/"+key,{
    accountKey:key,active:true,status:"active",
    allowedRole:"general_manager",accessType:"general_manager_gateway",
  });
  db.put("admins/"+uid,{active:adminActive,status:adminActive?"active":"disabled",role});
  return db;
}
test("rotated uid maps only to permanent original DEDA account",async()=>{
  const db=fixture();
  const result=await check(db,{uid});
  assert.equal(result.serverConfirmed,true);
  assert.equal(result.originalId,orig);
  assert.equal(db.writes,0);
  assert.ok(db.reads>0);
});
test("Telegram reward already shares gift wallet, not summed again",async()=>{
  const got=await check(fixture(),{uid});
  assert.equal(got.giftAndServerVerifiedRewardWallet.recordedBalance,1200);
  assert.equal(got.giftAndServerVerifiedRewardWallet.separateTelegramAmountToAdd,0);
  assert.equal(got.managerPersonalTestWallet.recordedBalance,150000);
  assert.equal(got.purchaseActivationApproved,false);
});
test("local ad/task values never become purchasable by audit",async()=>{
  const db=fixture();
  db.put("users/"+uid,{accountKey:key,sharePersonalId:orig,localDiamonds:999999999});
  const got=await check(db,{uid,localDiamonds:999999999});
  assert.equal(got.localAdsWallet.clientBalanceAccepted,false);
  assert.equal(got.localAdsWallet.automaticallyImportedDiamonds,0);
  assert.equal(got.taskAndSurveyWallet.automaticallyImportedDiamonds,0);
  assert.equal(got.administrativeGiftPool.includedInPersonalSpending,false);
  assert.equal(db.writes,0);
});
test("revoked current manager never treated as authorized despite stale old entry access",async()=>{
  const got=await check(fixture({role:"employee"}),{uid});
  assert.equal(got.managerPersonalTestWallet.currentlyAuthorizedGM,false);
  assert.equal(got.managerPersonalTestWallet.approvedForAutomaticMigration,false);
  assert.equal(got.managerPersonalTestWallet.requiresOwnerProvenanceReview,true);
});
test("enabled GM still has personal TEST balance, no automatic migration approved",async()=>{
  const got=await check(fixture(),{uid});
  assert.equal(got.managerPersonalTestWallet.currentlyAuthorizedGM,true);
  assert.equal(got.managerPersonalTestWallet.approvedForAutomaticMigration,false);
  assert.equal(got.purchaseActivationApproved,false);
});
test("missing wallets are zero recorded, not credits invented by client",async()=>{
  const db=fixture();
  db.docs.delete("deda_diamond_gift_balances/"+orig);
  db.docs.delete("deda_gm_personal_diamond_wallets/"+key);
  const got=await check(db,{uid});
  assert.equal(got.giftAndServerVerifiedRewardWallet.recordedBalance,0);
  assert.equal(got.managerPersonalTestWallet.recordedBalance,0);
  assert.equal(got.managerPersonalTestWallet.requiresOwnerProvenanceReview,false);
});
test("negative or non-integer balance fails closed without modifying anything",async()=>{
  for(const field of ["deda_diamond_gift_balances/"+orig,
    "deda_gm_personal_diamond_wallets/"+key]){
    const db=fixture();
    db.put(field,field.includes("gift")?{publicId:orig,balance:-1}:
      {accountKey:key,balance:5.5});
    await assert.rejects(check(db,{uid}),e=>e.code==="failed-precondition");
    assert.equal(db.writes,0);
  }
});
test("tampered wallet identity fails closed",async()=>{
  const db=fixture();
  db.put("deda_diamond_gift_balances/"+orig,{publicId:"@DEDA-FAKE00",balance:20});
  await assert.rejects(check(db,{uid}),e=>e.code==="failed-precondition");
});
test("cross-account session spoof prevented with no wallet access",async()=>{
  const db=fixture();db.put("deda_sessions/"+uid,{uid,accountKey:"other_key"});
  await assert.rejects(check(db,{uid}),e=>e.code==="permission-denied");
  assert.equal(db.writes,0);
});
test("revoked, missing original ID owner proof fails closed",async()=>{
  const db=fixture();
  db.put("users/"+oldUid,{accountKey:"wrong_account_key"});
  await assert.rejects(check(db,{uid}),e=>e.code==="permission-denied");
});
test("anonymous caller and missing backend denied",async()=>{
  await assert.rejects(check(fixture(),{uid:""}),e=>e.code==="unauthenticated");
  await assert.rejects(check(null,{uid}),e=>e.code==="unavailable");
});
test("audit source evidence: rewarded ad wallet remains phone-local SharedPreferences",()=>{
  const src=fs.readFileSync("tools/add_diamonds_reward_100259_2026_10_04.py","utf8");
  assert.match(src,/deda_diamonds_wallet_v1_/);
  assert.match(src,/SharedPreferences\.getInstance\(\)/);
  assert.match(src,/static Future<DedaDiamondsClaimResult> claimReward/);
});
test("audit source evidence: telegram server reward credits same gift balance document",()=>{
  const src=fs.readFileSync("functions/deda_telegram_verified_claim.js","utf8");
  assert.match(src,/collection\("deda_diamond_gift_balances"\)/);
  assert.match(src,/balance: balance \+ REWARD/);
});
test("audit source evidence: shadow test ledger is emulator only and cannot be spent",()=>{
  const src=fs.readFileSync("functions/deda_daily_reward_shadow_ledger.js","utf8");
  assert.match(src,/STAGE9_EMULATOR_ONLY_DO_NOT_PAY/);
  assert.match(src,/deda_stage9_shadow_balances/);
});
test("audit source evidence: personal GM test million has client create under existing Firestore rules",()=>{
  const src=fs.readFileSync("firestore.rules","utf8");
  assert.match(src,/match \/deda_gm_personal_diamond_wallets\/\{accountKey\}/);
  assert.match(src,/allow create: if isGeneralManagerPersonalAccount/);
  assert.match(src,/initialBalance == 1000000/);
});
test("no current production wallet or functions file imported Stage20 audit",()=>{
  const source=fs.readFileSync("functions/index.js","utf8");
  assert.doesNotMatch(source,/deda_jamal_stage20_diamond_source_audit/);
  assert.doesNotMatch(source,/checkoutVerifiedIdentifier/);
});
