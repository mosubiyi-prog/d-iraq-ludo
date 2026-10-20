"use strict";

// STAGE52: actual Rules Unit Testing against throwaway firestore emulator.
// Only reads /tmp/ generated candidate, never production rules/secrets/data.
const test=require("node:test"),assert=require("node:assert/strict");
const fs=require("node:fs");
const path=require("node:path");
const {createRequire}=require("node:module");
const req=createRequire(path.resolve(__dirname,"../functions/package.json"));
const {initializeTestEnvironment,assertFails,assertSucceeds}=
  req("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc, updateDoc, writeBatch, serverTimestamp}=
  req("firebase/firestore");
const host=process.env.FIRESTORE_EMULATOR_HOST||"";
const candidate=process.env.DEDA_STAGE52_RULES_CANDIDATE||"";
assert.match(host,/^(127\.0\.0\.1|localhost):[0-9]+$/,
  "SAFE_STOP: local Firestore emulator required");
assert.match(candidate,/^\/tmp\/[^/]+\.rules$/,
  "SAFE_STOP: only generated /tmp candidate rules allowed");
const rules=fs.readFileSync(candidate,"utf8");
assert.match(rules,/STAGE52_CANDIDATE_ONLY_NO_DEPLOY/);
const projectId="demo-deda-owner19-stage52-wallet-rules";
const person={
  uid:"stage52_person_001",account:"stage52_account_001",
  original:"@DEDA-A1B2C3",
};
const giftId="stage52_gift_0001";
let env,client,db;
const giftWallet="deda_diamond_gift_balances/"+person.original;
const gmWallet="deda_gm_personal_diamond_wallets/"+person.account;
function seedDocument(path,object) {
  return env.withSecurityRulesDisabled(async context=>
    setDoc(doc(context.firestore(),path),object));
}
test.before(async()=>{
  env=await initializeTestEnvironment({
    projectId,
    firestore:{
      host:"127.0.0.1",
      port:Number(host.split(":")[1]),
      rules,
    },
  });
  client=env.authenticatedContext(person.uid).firestore();
  db=env.unauthenticatedContext().firestore();
});
test.beforeEach(async()=>{
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async context=>{
    const admin=context.firestore();
    const originalData={accountKey:person.account,sharePersonalId:person.original};
    await Promise.all([
      setDoc(doc(admin,"users/"+person.uid),originalData),
      setDoc(doc(admin,"deda_sessions/"+person.uid),{
        uid:person.uid,accountKey:person.account,
      }),
      setDoc(doc(admin,"deda_share_ids/"+person.original),{
        publicId:person.original,ownerUid:person.uid,
        kind:"personal",active:true,
      }),
      setDoc(doc(admin,"admin_entry_access/"+person.account),{
        accountKey:person.account,active:true,status:"active",
        accessType:"general_manager_gateway",allowedRole:"general_manager",
      }),
      setDoc(doc(admin,"admins/"+person.uid),{
        role:"general_manager",active:true,status:"active",
      }),
      setDoc(doc(admin,giftWallet),{
        publicId:person.original,balance:1000,lastClaimGiftId:"previous_gift",
        createdAt:new Date(2026,8,1),updatedAt:new Date(2026,8,1),
      }),
      setDoc(doc(admin,gmWallet),{
        accountKey:person.account,balance:1000000,initialBalance:1000000,
        createdAt:new Date(2026,8,1),updatedAt:new Date(2026,8,1),
      }),
    ]);
  });
});
test.after(async()=>{if(env)await env.cleanup();});

test("legitimate owner CAN READ both historical wallet balances",async()=>{
  const gift=await assertSucceeds(getDoc(doc(client,giftWallet)));
  assert.equal(gift.data().balance,1000);
  const gm=await assertSucceeds(getDoc(doc(client,gmWallet)));
  assert.equal(gm.data().balance,1000000);
});
test("signed-in client cannot debit gifts without server receipt",async()=>{
  await assertFails(updateDoc(doc(client,giftWallet),{
    balance:995,updatedAt:serverTimestamp(),
  }));
  const current=await assertSucceeds(getDoc(doc(client,giftWallet)));
  assert.equal(current.data().balance,1000);
});
test("signed-in GM cannot debit personal test million itself",async()=>{
  await assertFails(updateDoc(doc(client,gmWallet),{
    balance:995000,updatedAt:serverTimestamp(),
  }));
  const current=await assertSucceeds(getDoc(doc(client,gmWallet)));
  assert.equal(current.data().balance,1000000);
});
test("GM cannot create another 1-million personal wallet from phone",async()=>{
  await env.withSecurityRulesDisabled(async context=>{
    const seeded=context.firestore();
    await setDoc(doc(seeded,"admin_entry_access/stage52_account_002"),{
      accountKey:"stage52_account_002",active:true,status:"active",
      accessType:"general_manager_gateway",allowedRole:"general_manager",
    });
    // sameAccount checks current auth account: original access must remain.
  });
  await assertFails(setDoc(doc(client,gmWallet),{
    accountKey:person.account,balance:1000000,initialBalance:1000000,
    createdAt:serverTimestamp(),updatedAt:serverTimestamp(),
  }));
});
test("original gift claim still credits wallet EXACTLY ONCE in atomic batch",async()=>{
  await seedDocument("deda_diamond_gifts/"+giftId,{
    giftId,targetPublicId:person.original,amount:100,status:"pending",
    sourceType:"admin",adminUid:"owner",createdAt:new Date(2026,8,1),
  });
  const batch=writeBatch(client);
  batch.update(doc(client,"deda_diamond_gifts/"+giftId),{
    status:"received",claimedAt:serverTimestamp(),
  });
  batch.update(doc(client,giftWallet),{
    balance:1100,lastClaimGiftId:giftId,
    updatedAt:serverTimestamp(),
  });
  await assertSucceeds(batch.commit());
  const after=await assertSucceeds(getDoc(doc(client,giftWallet)));
  assert.equal(after.data().balance,1100);
  await assertFails(batch.commit());
});
test("other unauthenticated visitor cannot read or debit gift balances",async()=>{
  await assertFails(getDoc(doc(db,giftWallet)));
  await assertFails(updateDoc(doc(db,giftWallet),{balance:0}));
});
