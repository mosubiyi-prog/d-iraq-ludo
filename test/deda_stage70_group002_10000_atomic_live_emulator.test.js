"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const {readFileSync}=require("node:fs"),{resolve}=require("node:path");
const {createRequire}=require("node:module"),req=createRequire(resolve(__dirname,"../functions/package.json"));
const {initializeTestEnvironment,assertFails,assertSucceeds}=req("@firebase/rules-unit-testing");
const {doc,setDoc,getDoc,writeBatch,serverTimestamp}=req("firebase/firestore");
const PROJECT="demo-deda-stage70-group002-spark";
assert.equal(process.env.GCLOUD_PROJECT,PROJECT);
const rules=readFileSync("/tmp/deda-stage70-candidate.rules","utf8");
assert.match(rules,/STAGE70_GROUP002_FIXED_10000_SPARK_NO_DEPLOY/);
const people=[{uid:"person_a",key:"account_a",original:"@DEDA-AAA111"},{uid:"person_b",key:"account_b",original:"@DEDA-BBB222"}];
const sale="@DEDA-Q7W8E9";let env;
const wallet=(db,p)=>doc(db,"deda_diamond_gift_balances",p.original);
const stock=db=>doc(db,"deda_stage70_group002_stock",sale);
const registry=db=>doc(db,"deda_stage70_group002_registry",sale);
const receipt=(db,p)=>doc(db,"deda_stage70_group002_receipts",p.original+"__"+sale);
const user=i=>env.authenticatedContext(people[i]).firestore();
async function seed(){
 await env.clearFirestore();
 await env.withSecurityRulesDisabled(async ctx=>{
  const db=ctx.firestore();
  for(const p of people){
   await setDoc(doc(db,"users",p.uid),{accountKey:p.key,sharePersonalId:p.original});
   await setDoc(doc(db,"deda_sessions",p.uid),{uid:p.uid,accountKey:p.key});
   await setDoc(doc(db,"deda_share_ids",p.original),{publicId:p.original,ownerUid:p.uid,kind:"personal",active:true});
   await setDoc(wallet(db,p),{publicId:p.original,balance:30000,lastClaimGiftId:"verified",
     createdAt:new Date(),updatedAt:new Date()});
  }
  await setDoc(stock(db),{identifier:sale,group:"002",approved:true,
    priceDiamonds:10000,status:"available",approvedBy:"trusted",createdAt:new Date()});
 });
}
function purchase(db,p,charge=10000){
 const id=p.original+"__"+sale,b=writeBatch(db);
 b.update(wallet(db,p),{balance:20000,lastPurchaseIdentifier:sale,
   lastPurchaseReceiptId:id,updatedAt:serverTimestamp()});
 b.update(stock(db),{status:"sold",soldToOriginalId:p.original,
   soldAt:serverTimestamp(),receiptId:id});
 b.set(registry(db),{identifier:sale,publicId:p.original,
   kind:"group002",receiptId:id,createdAt:serverTimestamp()});
 b.set(receipt(db,p),{publicId:p.original,identifier:sale,
   kind:"group002",cost:charge,createdAt:serverTimestamp()});
 return b.commit();
}
test.before(async()=>{env=await initializeTestEnvironment({
 projectId:PROJECT,firestore:{host:"127.0.0.1",port:8080,rules}});});
test.after(async()=>{if(env)await env.cleanup();});
test.beforeEach(seed);
test("fixed 10000 checkout creates ownership, receipt, sold stock and debit",async()=>{
 const db=user(0),p=people[0];
 await assertSucceeds(purchase(db,p));
 assert.equal((await getDoc(wallet(db,p))).data().balance,20000);
 assert.equal((await getDoc(stock(db))).data().status,"sold");
 assert.equal((await getDoc(registry(db))).data().publicId,p.original);
 assert.equal((await getDoc(receipt(db,p))).data().cost,10000);
});
test("receipt and global stock cannot be purchased twice",async()=>{
 const a=user(0),b=user(1);
 await assertSucceeds(purchase(a,people[0]));
 await assertFails(purchase(a,people[0]));
 await assertFails(purchase(b,people[1]));
 assert.equal((await getDoc(wallet(b,people[1]))).data().balance,30000);
});
test("wrong charge and standalone debit do not grant a premium ID",async()=>{
 const db=user(0),p=people[0];
 await assertFails(purchase(db,p,5000));
 const batch=writeBatch(db);
 batch.update(wallet(db,p),{balance:20000,updatedAt:serverTimestamp()});
 await assertFails(batch.commit());
 assert.equal((await getDoc(wallet(db,p))).data().balance,30000);
 assert.equal((await getDoc(registry(db))).exists(),false);
});
