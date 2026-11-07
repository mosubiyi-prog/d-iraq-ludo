import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {before,after,test} from "node:test";
import {initializeTestEnvironment,assertSucceeds,assertFails}
  from "@firebase/rules-unit-testing";
import {doc,setDoc,getDoc,updateDoc,writeBatch,serverTimestamp}
  from "firebase/firestore";

const PROJECT="demo-deda-100439-gm-100m";
const FILE=process.env.DEDA_GM_RULES_CANDIDATE_PATH;
const WALLET="deda_admin_diamond_wallets";
const GIFTS="deda_diamond_gifts";
const PERSON="@DEDA-V3GIFT";
let env,manager,user,intruder;
const ref=(db,c,id)=>doc(db,c,id);
before(async()=>{
  assert.equal(process.env.GCLOUD_PROJECT,PROJECT);
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST);
  assert.ok(FILE && FILE.includes("deda-100439-gm-100m"));
  const policy=readFileSync(FILE,"utf8");
  assert.equal(policy.includes("DEDA_100439_GM_ADMIN_COMPENSATION_100M_CANDIDATE_NO_DEPLOY"),true);
  env=await initializeTestEnvironment({projectId:PROJECT,
    firestore:{rules:policy}});
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    await setDoc(ref(db,"admins","gm"),{role:"general_manager",
      active:true,status:"active"});
    await setDoc(ref(db,"admins","staff"),{role:"deputy_manager",
      active:true,status:"active"});
    await setDoc(ref(db,"users","beneficiary"),{
      accountKey:"07700000003",sharePersonalId:PERSON});
    await setDoc(ref(db,"deda_sessions","beneficiary"),{
      accountKey:"07700000003"});
    await setDoc(ref(db,"deda_share_ids",PERSON),{
      ownerUid:"beneficiary",publicId:PERSON,kind:"personal",
      active:true,displayName:"Test recipient"});
    // Trusted Admin SDK emulator seed: a review-approved, already-allocated
    // GM wallet. Client can ONLY debit it via one pending gift.
    await setDoc(ref(db,WALLET,"gm"),{adminUid:"gm",
      initialBalance:100000000,balance:100000000,
      createdAt:serverTimestamp(),updatedAt:serverTimestamp()});
  });
  manager=env.authenticatedContext("gm").firestore();
  user=env.authenticatedContext("beneficiary").firestore();
  intruder=env.authenticatedContext("staff").firestore();
});
after(async()=>{if(env)await env.cleanup();});

test("100m verified manager wallet readable only by manager",async()=>{
  assert.equal((await assertSucceeds(getDoc(ref(manager,WALLET,"gm"))))
    .data().balance,100000000);
  await assertFails(getDoc(ref(intruder,WALLET,"gm")));
  await assertFails(getDoc(ref(user,WALLET,"gm")));
});
test("no mint, no standalone 100m wallet replacement, no wallet decrease without gift",async()=>{
  await assertFails(updateDoc(ref(manager,WALLET,"gm"),{
    balance:100000001,updatedAt:serverTimestamp()}));
  await assertFails(updateDoc(ref(manager,WALLET,"gm"),{
    balance:99999900,updatedAt:serverTimestamp()}));
  await assertFails(setDoc(ref(intruder,WALLET,"staff"),{
    adminUid:"staff",initialBalance:100000000,balance:100000000,
    createdAt:serverTimestamp(),updatedAt:serverTimestamp()}));
  await assertFails(setDoc(ref(manager,WALLET,"new-gm"),{
    adminUid:"new-gm",initialBalance:100000000,balance:100000000,
    createdAt:serverTimestamp(),updatedAt:serverTimestamp()}));
});
test("one real pending gift can debit 100m manager wallet exactly",async()=>{
  const b=writeBatch(manager);
  b.update(ref(manager,WALLET,"gm"),{balance:99999750,
    lastGiftId:"one-gm100m-test",updatedAt:serverTimestamp()});
  b.set(ref(manager,GIFTS,"one-gm100m-test"),{
    giftId:"one-gm100m-test",sourceType:"admin",adminUid:"gm",
    adminName:"DEDA manager",senderLabel:"إدارة DEDA",
    targetPublicId:PERSON,targetName:"Test recipient",
    amount:250,reason:"تعويض ديدا",status:"pending",
    createdAt:serverTimestamp(),
  });
  await assertSucceeds(b.commit());
  assert.equal((await getDoc(ref(manager,WALLET,"gm"))).data().balance,99999750);
  assert.equal((await getDoc(ref(user,GIFTS,"one-gm100m-test"))).data().status,"pending");
  const again=writeBatch(manager);
  again.update(ref(manager,WALLET,"gm"),{balance:99999500,
    lastGiftId:"one-gm100m-test",updatedAt:serverTimestamp()});
  await assertFails(again.commit());
});
test("gift cannot be claimed by other role without ownership, even with 100m wallet",async()=>{
  await assertFails(updateDoc(ref(intruder,GIFTS,"one-gm100m-test"),
    {status:"received",claimedAt:serverTimestamp()}));
  const b=writeBatch(user);
  b.update(ref(user,GIFTS,"one-gm100m-test"),
    {status:"received",claimedAt:serverTimestamp()});
  b.set(ref(user,"deda_diamond_gift_balances",PERSON),{
    publicId:PERSON,balance:250,lastClaimGiftId:"one-gm100m-test",
    createdAt:serverTimestamp(),updatedAt:serverTimestamp()});
  await assertSucceeds(b.commit());
  assert.equal((await getDoc(ref(user,"deda_diamond_gift_balances",PERSON)))
    .data().balance,250);
});
