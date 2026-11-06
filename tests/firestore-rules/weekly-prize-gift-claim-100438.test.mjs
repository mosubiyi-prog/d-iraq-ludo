import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {before,after,test} from "node:test";
import {
  initializeTestEnvironment,assertSucceeds,assertFails
} from "@firebase/rules-unit-testing";
import {
  doc,getDoc,getDocs,writeBatch,collection,query,where,serverTimestamp,
  setDoc,updateDoc
} from "firebase/firestore";

const PROJECT="demo-deda-weekly-claim-100438";
const FIRST="@DEDA-WEEK01",OTHER="@DEDA-WEEK02";
const GIFT_ID="deda-weekly-2026-10-31-DEDA-WEEK01";
const amount=250;
let env,first,other,anonymous;
const path=(db,c,id)=>doc(db,c,id);
const gift=(db)=>path(db,"deda_diamond_gifts",GIFT_ID);
const balance=(db)=>path(db,"deda_diamond_gift_balances",FIRST);

before(async()=>{
  assert.equal(process.env.GCLOUD_PROJECT,PROJECT);
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST,"NO_EMULATOR_PRODUCTION_FORBIDDEN");
  env=await initializeTestEnvironment({
    projectId:PROJECT,
    firestore:{rules:readFileSync("firestore.rules","utf8")}
  });
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    await setDoc(path(db,"users","firstUid"),{
      accountKey:"07700000001",sharePersonalId:FIRST
    });
    await setDoc(path(db,"deda_sessions","firstUid"),{
      accountKey:"07700000001"
    });
    await setDoc(path(db,"deda_share_ids",FIRST),{
      ownerUid:"firstUid",kind:"personal",active:true,publicId:FIRST,
      displayName:"First"
    });
    await setDoc(path(db,"users","otherUid"),{
      accountKey:"07700000002",sharePersonalId:OTHER
    });
    await setDoc(path(db,"deda_sessions","otherUid"),{
      accountKey:"07700000002"
    });
    await setDoc(path(db,"deda_share_ids",OTHER),{
      ownerUid:"otherUid",kind:"personal",active:true,publicId:OTHER,
      displayName:"Other"
    });
    // Mimics server-side gift creation using privileged Admin SDK.
    // The client does NOT create a prize, even in the emulator.
    await setDoc(gift(db),{
      giftId:GIFT_ID,sourceType:"weekly_league",
      adminUid:"deda-weekly-league-system",
      adminName:"دوري DEDA",senderLabel:"إدارة DEDA",
      targetPublicId:FIRST,targetName:"First",
      amount,reason:"جائزة دوري DEDA — الأسبوع 2026-10-31 — المركز 1",
      status:"pending",createdAt:serverTimestamp()
    });
  });
  first=env.authenticatedContext("firstUid").firestore();
  other=env.authenticatedContext("otherUid").firestore();
  anonymous=env.unauthenticatedContext().firestore();
});
after(async()=>{if(env)await env.cleanup();});

function claim(db,requestedAmount=amount){
  const batch=writeBatch(db);
  batch.update(gift(db),{status:"received",claimedAt:serverTimestamp()});
  batch.set(balance(db),{
    publicId:FIRST,balance:requestedAmount,lastClaimGiftId:GIFT_ID,
    createdAt:serverTimestamp(),updatedAt:serverTimestamp()
  });
  return batch.commit();
}

test("weekly pending gift appears in owner's هداياي query, not other accounts",async()=>{
  const own=query(collection(first,"deda_diamond_gifts"),
    where("targetPublicId","==",FIRST));
  const mine=await assertSucceeds(getDocs(own));
  assert.equal(mine.docs.length,1);
  assert.equal(mine.docs[0].data().sourceType,"weekly_league");
  assert.equal(mine.docs[0].data().status,"pending");
  await assertFails(getDoc(gift(other)));
  await assertFails(getDoc(gift(anonymous)));
  await assertFails(getDocs(collection(first,"deda_diamond_gifts")));
});

test("weekly gift cannot be created by recipient or another account",async()=>{
  await assertFails(setDoc(path(first,"deda_diamond_gifts","fake-week"),{
    giftId:"fake-week",sourceType:"weekly_league",
    targetPublicId:FIRST,amount:250,status:"pending",
    createdAt:serverTimestamp()
  }));
});

test("wrong user, forged larger value and unpaired status change all denied",async()=>{
  await assertFails(claim(other));
  await assertFails(claim(first,250000));
  await assertFails(updateDoc(gift(first),{
    status:"received",claimedAt:serverTimestamp()
  }));
  assert.equal((await getDoc(gift(first))).data().status,"pending");
});

test("real weekly owner claims exactly once; diamond balance credited atomically",async()=>{
  await assertSucceeds(claim(first));
  assert.equal((await getDoc(gift(first))).data().status,"received");
  assert.equal((await getDoc(balance(first))).data().balance,250);
  await assertFails(claim(first));
  await assertFails(updateDoc(balance(first),{
    balance:500,updatedAt:serverTimestamp()
  }));
  assert.equal((await getDoc(balance(first))).data().balance,250);
});
