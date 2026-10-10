import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {before, after, test} from "node:test";
import {initializeTestEnvironment, assertSucceeds, assertFails}
  from "@firebase/rules-unit-testing";
import {doc, getDoc, getDocs, setDoc, updateDoc, writeBatch,
  collection, query, where, serverTimestamp, Timestamp}
  from "firebase/firestore";

const PROJECT="demo-deda-admin-gift-manual-claim";
const A="@DEDA-T7GIFT", B="@DEDA-X8GIFT";
let env,gm,staff,member,other,guest;
const d=(db,c,id)=>doc(db,c,id);
const wallet=(db,uid="gm")=>d(db,"deda_admin_diamond_wallets",uid);
const gift=(db,id)=>d(db,"deda_diamond_gifts",id);
const balance=(db,id=A)=>d(db,"deda_diamond_gift_balances",id);

function giftData(id,recipient=A,amount=250) {
  return {
    giftId:id,sourceType:"admin",adminUid:"gm",
    adminName:"DEDA manager",senderLabel:"إدارة DEDA",
    targetPublicId:recipient,targetName:"Verified user",
    amount,reason:"مكافأة من إدارة DEDA",
    status:"pending",createdAt:serverTimestamp(),
  };
}
async function sendGift(id,recipient=A,amount=250) {
  const b=writeBatch(gm);
  const prior=(await getDoc(wallet(gm))).data().balance;
  b.update(wallet(gm),{
    balance:prior-amount,lastGiftId:id,
    updatedAt:serverTimestamp(),
  });
  b.set(gift(gm,id),giftData(id,recipient,amount));
  return b.commit();
}
function claimGift(db,id,recipient=A,amount=250,previousBalance=null) {
  const b=writeBatch(db);
  b.update(gift(db,id),{status:"received",claimedAt:serverTimestamp()});
  if(previousBalance===null) {
    b.set(balance(db,recipient), {
      publicId:recipient,balance:amount,lastClaimGiftId:id,
      createdAt:serverTimestamp(),updatedAt:serverTimestamp(),
    });
  } else {
    b.update(balance(db,recipient),{
      balance:previousBalance+amount,lastClaimGiftId:id,
      updatedAt:serverTimestamp(),
    });
  }
  return b.commit();
}

before(async()=>{
  assert.equal(process.env.GCLOUD_PROJECT,PROJECT);
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST,
    "ABORT: local Firestore emulator must be running. NEVER use production.");
  env=await initializeTestEnvironment({
    projectId:PROJECT,
    firestore:{rules:readFileSync("firestore.rules","utf8")},
  });
  await env.withSecurityRulesDisabled(async(ctx)=>{
    const db=ctx.firestore();
    for(const [uid,role,active] of [
      ["gm","general_manager",true],
      ["deputy","deputy_manager",true],
      ["paused","general_manager",false],
    ]) {
      await setDoc(d(db,"admins",uid),{
        role,active,status:active?"active":"disabled",
      });
    }
    for(const [uid,id,key] of [
      ["member",A,"07700000001"],["other",B,"07700000002"],
    ]) {
      await setDoc(d(db,"users",uid),{
        accountKey:key,sharePersonalId:id,
      });
      await setDoc(d(db,"deda_sessions",uid),{
        accountKey:key,
      });
      await setDoc(d(db,"deda_share_ids",id),{
        ownerUid:uid,kind:"personal",active:true,publicId:id,
        displayName:uid,
      });
    }
  });
  gm=env.authenticatedContext("gm").firestore();
  staff=env.authenticatedContext("deputy").firestore();
  member=env.authenticatedContext("member").firestore();
  other=env.authenticatedContext("other").firestore();
  guest=env.unauthenticatedContext().firestore();
});
after(async()=>{if(env)await env.cleanup();});

test("only active true GM can create one-million administrative wallet",async()=>{
  for(const c of [staff,member,other,guest,
    env.authenticatedContext("paused").firestore()]) {
    await assertFails(setDoc(wallet(c),{
      adminUid:"gm",initialBalance:1000000,balance:1000000,
      createdAt:serverTimestamp(),updatedAt:serverTimestamp(),
    }));
  }
  await assertSucceeds(setDoc(wallet(gm),{
    adminUid:"gm",initialBalance:1000000,balance:1000000,
    createdAt:serverTimestamp(),updatedAt:serverTimestamp(),
  }));
  assert.equal((await getDoc(wallet(gm))).data().balance,1000000);
  await assertFails(getDoc(wallet(member)));
  await assertFails(getDoc(wallet(staff)));
});

test("no manager mint, no refill, no standalone fake gift or unilateral debit",async()=>{
  await assertFails(updateDoc(wallet(gm),{
    balance:1000001,updatedAt:serverTimestamp(),
  }));
  await assertFails(updateDoc(wallet(gm),{
    balance:999800,lastGiftId:"forged",
    updatedAt:serverTimestamp(),
  }));
  await assertFails(setDoc(gift(gm,"forged-standalone"),
    giftData("forged-standalone")));
  await assertFails(setDoc(gift(staff,"staff-fake"),
    giftData("staff-fake")));
  await assertFails(setDoc(gift(member,"user-fake"),
    giftData("user-fake")));
  await assertFails(setDoc(gift(gm,"wrong-user"),
    giftData("wrong-user","@DEDA-NOTREGISTERED")));
});

test("manager send debits pool atomically and leaves recipient uncredited",async()=>{
  await assertSucceeds(sendGift("gift-a",A,250));
  assert.equal((await getDoc(wallet(gm))).data().balance,999750);
  assert.equal((await getDoc(gift(gm,"gift-a"))).data().status,"pending");
  assert.equal((await getDoc(gift(member,"gift-a"))).data().amount,250);
  assert.equal((await getDoc(balance(member))).exists(),false);
  await assertFails(getDoc(gift(other,"gift-a")));
  await assertFails(getDoc(gift(guest,"gift-a")));
  await assertFails(getDoc(gift(staff,"gift-a")));
});

test("inbox equality query sees user's own pending gifts and no others",async()=>{
  const mine=query(collection(member,"deda_diamond_gifts"),
    where("targetPublicId","==",A));
  const res=await assertSucceeds(getDocs(mine));
  assert.equal(res.docs.length,1);
  assert.equal(res.docs[0].id,"gift-a");
  const all=query(collection(member,"deda_diamond_gifts"));
  await assertFails(getDocs(all));
  const notMine=query(collection(other,"deda_diamond_gifts"),
    where("targetPublicId","==",A));
  await assertFails(getDocs(notMine));
});

test("claim without wallet credit, or with forged larger amount fails",async()=>{
  await assertFails(updateDoc(gift(member,"gift-a"),{
    status:"received",claimedAt:serverTimestamp(),
  }));
  await assertFails(setDoc(balance(member),{
    publicId:A,balance:10000,lastClaimGiftId:"gift-a",
    createdAt:serverTimestamp(),updatedAt:serverTimestamp(),
  }));
  await assertFails(claimGift(member,"gift-a",A,9999));
  await assertFails(claimGift(other,"gift-a",A,250));
  await assertFails(setDoc(balance(other),{
    publicId:A,balance:250,lastClaimGiftId:"gift-a",
    createdAt:serverTimestamp(),updatedAt:serverTimestamp(),
  }));
});

test("one explicit recipient claim atomically credits real balance once",async()=>{
  await assertSucceeds(claimGift(member,"gift-a",A,250));
  assert.equal((await getDoc(balance(member))).data().balance,250);
  assert.equal((await getDoc(gift(member,"gift-a"))).data().status,"received");
  await assertFails(claimGift(member,"gift-a",A,250));
  await assertFails(updateDoc(balance(member),{
    balance:500,updatedAt:serverTimestamp(),
  }));
  assert.equal((await getDoc(balance(member))).data().balance,250);
});

test("second gift augments same wallet; 3rd party may not claim",async()=>{
  await assertSucceeds(sendGift("gift-b",A,60));
  await assertFails(claimGift(other,"gift-b",A,60,250));
  await assertSucceeds(claimGift(member,"gift-b",A,60,250));
  assert.equal((await getDoc(balance(member))).data().balance,310);
  assert.equal((await getDoc(wallet(gm))).data().balance,999690);
  await assertFails(claimGift(member,"gift-b",A,60,310));
});

test("spending owned credit may decrease, but may never increase",async()=>{
  await assertSucceeds(updateDoc(balance(member),{
    balance:300,updatedAt:serverTimestamp(),
  }));
  await assertFails(updateDoc(balance(other),{
    balance:9900,updatedAt:serverTimestamp(),
  }));
  await assertFails(updateDoc(balance(member),{
    balance:301,updatedAt:serverTimestamp(),
  }));
  assert.equal((await getDoc(balance(member))).data().balance,300);
});

test("no 24-hour admin pool refill before trusted server is available",async()=>{
  await assertFails(updateDoc(wallet(gm),{
    balance:1000000,updatedAt:serverTimestamp(),
  }));
  assert.equal((await getDoc(wallet(gm))).data().balance,999690);
});
