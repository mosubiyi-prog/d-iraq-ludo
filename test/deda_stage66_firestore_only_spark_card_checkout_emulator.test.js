"use strict";
// Spark Stage66: real local Firestore Rules Emulator. SYNTHETIC spendable
// gift diamonds only. No released wallet, real user, manager secret, APK,
// active in-app products or live checkout. Never turn on actual shop with this.
const test=require("node:test");
const assert=require("node:assert/strict");
const {readFileSync}=require("node:fs");
const {resolve}=require("node:path");
const {createRequire}=require("node:module");
const req=createRequire(resolve(__dirname,"../functions/package.json"));
const {initializeTestEnvironment,assertFails,assertSucceeds}=
  req("@firebase/rules-unit-testing");
const {doc,setDoc,getDoc,writeBatch,serverTimestamp}=
  req("firebase/firestore");
const PROJECT="demo-deda-stage66-spark-card-only";
assert.equal(process.env.GCLOUD_PROJECT,PROJECT);
assert.match(process.env.FIRESTORE_EMULATOR_HOST||"",/^(127\.0\.0\.1|localhost):[0-9]{2,5}$/);
const rules=readFileSync("/tmp/deda-stage66-candidate.rules","utf8");
assert.match(rules,/STAGE66_FIRESTORE_ONLY_CANDIDATE_NO_DEPLOY/);
const user={uid:"stage66_owner_phone",key:"9647700001111",id:"@DEDA-AX7H9P"};
const stranger={uid:"stage66_stranger",key:"9647800002222",id:"@DEDA-BY8J3Q"};
let env;
function wallet(db,id=user.id){return doc(db,"deda_diamond_gift_balances",id);}
function receipt(db,id=user.id,style="gold"){return doc(db,"deda_stage66_card_receipts",id+"_"+style);}
function card(db,id=user.id,style="gold"){return doc(db,"deda_stage66_owned_cards",id+"_"+style);}
async function reset(balance=15000){
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    for(const a of [user,stranger]){
      await setDoc(doc(db,"deda_sessions",a.uid),{uid:a.uid,accountKey:a.key});
      await setDoc(doc(db,"users",a.uid),{accountKey:a.key,sharePersonalId:a.id});
      await setDoc(doc(db,"deda_share_ids",a.id),{ownerUid:a.uid,kind:"personal",active:true,publicId:a.id});
    }
    await setDoc(wallet(db),{publicId:user.id,balance,updatedAt:new Date(),createdAt:new Date(),lastClaimGiftId:"synthetic_original"});
  });
}
test.before(async()=>{
  env=await initializeTestEnvironment({projectId:PROJECT,
    firestore:{host:"127.0.0.1",port:8080,rules}});
});
test.after(async()=>{if(env)await env.cleanup()});
function client(uid=user.uid){return env.authenticatedContext(uid).firestore();}
function checkout(db,style,id=user.id,price=5000){
  const batch=writeBatch(db), rid=id+"_"+style;
  batch.update(wallet(db,id),{
    balance:price===5000?10000:10500,
    lastPurchaseStyle:style,lastPurchaseReceiptId:rid,updatedAt:serverTimestamp(),
  });
  batch.set(receipt(db,id,style),{
    publicId:id,style,kind:"card",cost:price,createdAt:serverTimestamp(),
  });
  batch.set(card(db,id,style),{
    publicId:id,style,receiptId:rid,createdAt:serverTimestamp(),
  });
  return batch.commit();
}
test("verified gift-wallet 5k checkout creates immutable receipt+ownership and exactly 1 debit",async()=>{
  await reset();
  const db=client();
  await assertSucceeds(checkout(db,"gold"));
  assert.equal((await getDoc(wallet(db))).data().balance,10000);
  const paid=await assertSucceeds(getDoc(receipt(db)));
  assert.equal(paid.data().cost,5000);
  const owned=await assertSucceeds(getDoc(card(db)));
  assert.equal(owned.data().receiptId,user.id+"_gold");
  await assertFails(checkout(db,"gold"));
  assert.equal((await getDoc(wallet(db))).data().balance,10000);
  assert.equal((await getDoc(receipt(db))).data().cost,5000);
});
test("single wallet-only debit and receipt-free entitlement are rejected",async()=>{
  await reset();
  const db=client();
  await assertFails((async()=>{
    const b=writeBatch(db);
    b.update(wallet(db),{balance:10000,updatedAt:serverTimestamp()});
    return b.commit();
  })());
  await assertFails(setDoc(card(db),{publicId:user.id,style:"gold",
    receiptId:user.id+"_gold",createdAt:serverTimestamp()}));
  assert.equal((await getDoc(wallet(db))).data().balance,15000);
});
test("wrong price cannot pass server fixed 5000, no phantom card",async()=>{
  await reset();
  const db=client();
  await assertFails(checkout(db,"gold",user.id,4500));
  assert.equal((await getDoc(wallet(db))).data().balance,15000);
});
test("stranger cannot debit the wallet, invent a receipt, or claim another user's card",async()=>{
  await reset();
  const db=client(stranger.uid);
  await assertFails(checkout(db,"royal"));
  assert.equal((await env.withSecurityRulesDisabled(ctx=>getDoc(wallet(ctx.firestore())))).data().balance,15000);
});
test("insufficient funds do not create ownership",async()=>{
  await reset(4000);
  const db=client();
  await assertFails(checkout(db,"pink"));
  assert.equal((await getDoc(wallet(db))).data().balance,4000);
});
test("unauthenticated cannot mint a receipt or buy an ID card",async()=>{
  await reset();
  const db=env.unauthenticatedContext().firestore();
  await assertFails(setDoc(receipt(db),{
    publicId:user.id,style:"gold",kind:"card",cost:5000,
    createdAt:serverTimestamp(),
  }));
  await assertFails(checkout(db,"gold"));
});
