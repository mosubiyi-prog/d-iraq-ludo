"use strict";
// Stage18 marketplace: REAL Firestore Emulator transactions only.
// NO PRODUCTION catalog, no users, wallet writes or sale activation.
const test=require("node:test"),assert=require("node:assert/strict");
const {createRequire}=require("node:module");
const {resolve}=require("node:path");
const {readFileSync}=require("node:fs");
const {createHash}=require("node:crypto");
assert.match(process.env.FIRESTORE_EMULATOR_HOST||"",
  /^(127\.0\.0\.1|localhost):[0-9]+$/, "EMULATOR REQUIRED");
const req=createRequire(resolve(__dirname,"../functions/package.json"));
const {initializeApp,deleteApp}=req("firebase-admin/app");
const {getFirestore}=req("firebase-admin/firestore");
const {initializeTestEnvironment,assertFails}=req("@firebase/rules-unit-testing");
const {doc,setDoc,getDoc}=req("firebase/firestore");
const {createApprovedSaleCatalog,checkoutVerifiedIdentifier,
  PRICE_DIAMONDS}=require(
  "../tools/deda_stage18_private_atomic_identifier_checkout_2026_10_19.js");
const PROJECT="demo-deda-stage18-purchase-real-races";
const idA="@DEDA-AAAAAA",idB="@DEDA-BBBBBB";
const approved=createApprovedSaleCatalog({
  reservedSuffixes:Array.from({length:100},(_,i)=>
    String(i+1).padStart(6,"0")),
  approvedSuffixes:["AAAAAA","BBBBBB"],
});
const hash=x=>createHash("sha256").update(x).digest("hex");
let app, db,env;
function buyer(id,uid,original,key,balance=14000) {
  return {uid,original,key,balance};
}
const a=buyer("A","buyer_UID_A","@DEDA-Z9X8Y7","account_buyer_A",14000);
const b=buyer("B","buyer_UID_B","@DEDA-Y7X8Z9","account_buyer_B",14000);
async function init() {
  await env.clearFirestore();
  const batch=db.batch();
  for(const person of [a,b]){
    batch.set(db.collection("users").doc(person.uid),{
      accountKey:person.key,sharePersonalId:person.original,
      localDiamonds:999999,points:155,level:6,
    });
    batch.set(db.collection("deda_sessions").doc(person.uid),{
      uid:person.uid,accountKey:person.key,
    });
    batch.set(db.collection("deda_share_ids").doc(person.original),{
      kind:"personal",active:true,publicId:person.original,
      ownerUid:person.uid,
    });
    batch.set(db.collection("deda_diamond_gift_balances").doc(person.original),{
      publicId:person.original,balance:person.balance,
    });
  }
  for(const id of [idA,idB]){
    batch.set(db.collection("deda_verified_id_sale_catalog").doc(id),{
      identifier:id,group:"002",status:"verified_available",
      ownerApproved:true,priceDiamonds:10000,
    });
  }
  await batch.commit();
}
function buy(person,identifier=idA,requestId="order_000001") {
  return checkoutVerifiedIdentifier(db,{
    uid:person.uid,identifier,requestId,approvedCatalog:approved,
  });
}
async function giftBalance(person){
  const s=await db.collection("deda_diamond_gift_balances")
    .doc(person.original).get();return s.data().balance;
}
test.before(async()=>{
  app=initializeApp({projectId:PROJECT},"deda-stage18-checkout-races-emulator");
  db=getFirestore(app);
  env=await initializeTestEnvironment({projectId:PROJECT,
    firestore:{
      host:"127.0.0.1",port:Number(
        process.env.FIRESTORE_EMULATOR_HOST.split(":")[1]),
      rules:readFileSync(resolve(__dirname,"../firestore.rules"),"utf8"),
    }});
});
test.after(async()=>{
  if(env)await env.cleanup();
  if(app)await deleteApp(app);
});
test("10k verified purchase is one atomic deduction, receipt, stock, owner + permanent alias",async()=>{
  await init();
  assert.equal(PRICE_DIAMONDS,10000);
  const result=await buy(a);
  assert.equal(result.serverConfirmed,true);
  assert.equal(result.diamondsCharged,10000);
  assert.equal(await giftBalance(a),4000);
  assert.equal((await db.collection("users").doc(a.uid).get()).data()
    .sharePersonalId,a.original);
  const reg=(await db.collection("deda_owned_identifier_registry")
    .doc(idA).get()).data();
  assert.equal(reg.identifier,idA);
  assert.equal(reg.originalId,a.original);
  assert.equal(reg.acquisition,"diamond_purchase");
  assert.equal((await db.collection("deda_verified_id_sale_catalog")
    .doc(idA).get()).data().status,"sold");
  const ledger=(await db.collection("deda_owned_identifier_accounts")
    .doc(hash(a.key)).get()).data();
  assert.deepEqual(ledger.ownedIds,[a.original,idA]);
  assert.equal(ledger.activeId,a.original);
  assert.equal((await db.collection("deda_owned_identifier_aliases")
    .doc(idA).get()).data().kind,"permanent_alias");
  const receipt=(await db.collection("deda_id_purchase_requests")
    .doc(hash(a.key)).collection("requests").doc("order_000001").get()).data();
  assert.equal(receipt.diamondsCharged,10000);
  assert.equal(receipt.giftCharged,10000);
});
test("same buyer retry with identical request ID is idempotent, never double-debits",async()=>{
  await init();
  const first=await buy(a);
  const second=await buy(a);
  assert.deepEqual(first,second);
  assert.equal(await giftBalance(a),4000);
});
test("two competing buyers race for ONE 10k ID, only one wins and spends diamonds",async()=>{
  await init();
  const results=await Promise.allSettled([
    buy(a,idA,"buyer_a_req_1"),
    buy(b,idA,"buyer_b_req_2"),
  ]);
  assert.equal(results.filter(x=>x.status==="fulfilled").length,1);
  assert.equal(results.filter(x=>x.status==="rejected").length,1);
  const reg=(await db.collection("deda_owned_identifier_registry")
    .doc(idA).get()).data();
  assert.ok([a.key,b.key].includes(reg.accountKey));
  const first=await giftBalance(a),second=await giftBalance(b);
  assert.deepEqual([first,second].sort((x,y)=>x-y),[4000,14000]);
  assert.equal((await db.collection("deda_verified_id_sale_catalog")
    .doc(idA).get()).data().status,"sold");
});
test("same buyer concurrent distinct 10k IDs with 14k verified balance cannot spend 20k",async()=>{
  await init();
  const results=await Promise.allSettled([
    buy(a,idA,"two_ids_req_001"),
    buy(a,idB,"two_ids_req_002"),
  ]);
  assert.equal(results.filter(x=>x.status==="fulfilled").length,1);
  assert.equal(await giftBalance(a),4000);
  let sold=0;
  for(const id of [idA,idB]){
    const snap=await db.collection("deda_verified_id_sale_catalog")
      .doc(id).get();
    if(snap.data().status==="sold")sold++;
  }
  assert.equal(sold,1);
});
test("stock must be verified, ownerApproved, correct group and exact server price",async()=>{
  await init();
  await db.collection("deda_verified_id_sale_catalog").doc(idA)
    .update({ownerApproved:false});
  await assert.rejects(buy(a),e=>e.code==="failed-precondition");
  assert.equal(await giftBalance(a),14000);
  await db.collection("deda_verified_id_sale_catalog").doc(idA)
    .update({ownerApproved:true,priceDiamonds:9000});
  await assert.rejects(buy(a),e=>e.code==="failed-precondition");
  assert.equal(await giftBalance(a),14000);
});
test("local 999999 diamonds cannot buy if VERIFIED backend balance is zero",async()=>{
  await init();
  await db.collection("deda_diamond_gift_balances").doc(a.original)
    .update({balance:0});
  await assert.rejects(buy(a),e=>e.code==="failed-precondition");
  assert.equal((await db.collection("users").doc(a.uid).get()).data()
    .localDiamonds,999999);
  assert.equal((await db.collection("deda_owned_identifier_registry")
    .doc(idA).get()).exists,false);
});
test("globally existing personal/share ID blocks purchase, no diamond debit",async()=>{
  await init();
  await db.collection("deda_share_ids").doc(idA).set({
    publicId:idA,kind:"personal",active:true,ownerUid:b.uid,
  });
  await assert.rejects(buy(a),e=>e.code==="already-exists");
  assert.equal(await giftBalance(a),14000);
});
test("GM personal verified diamonds combine with gift balance, exact 10k receipt",async()=>{
  await init();
  await db.collection("deda_diamond_gift_balances").doc(a.original)
    .update({balance:3000});
  await db.collection("admin_entry_access").doc(a.key).set({
    accountKey:a.key,status:"active",active:true,
    allowedRole:"general_manager",accessType:"general_manager_gateway",
  });
  await db.collection("admins").doc(a.uid).set({
    status:"active",active:true,role:"general_manager",
  });
  await db.collection("deda_gm_personal_diamond_wallets").doc(a.key).set({
    accountKey:a.key,balance:8000,
  });
  const bought=await buy(a,idA,"verified_gm_purchase_1");
  assert.equal(bought.diamondsCharged,10000);
  assert.equal(await giftBalance(a),0);
  assert.equal((await db.collection("deda_gm_personal_diamond_wallets")
    .doc(a.key).get()).data().balance,1000);
  const receipt=(await db.collection("deda_id_purchase_requests")
    .doc(hash(a.key)).collection("requests")
    .doc("verified_gm_purchase_1").get()).data();
  assert.equal(receipt.giftCharged,3000);
  assert.equal(receipt.gmPersonalCharged,7000);
});

test("revoked GM with stale old admin access CANNOT debit personal GM wallet",async()=>{
  await init();
  await db.collection("deda_diamond_gift_balances").doc(a.original)
    .update({balance:3000});
  await db.collection("admin_entry_access").doc(a.key).set({
    accountKey:a.key,status:"active",active:true,
    allowedRole:"general_manager",accessType:"general_manager_gateway",
  });
  await db.collection("admins").doc(a.uid).set({
    status:"active",active:true,role:"employee",
  });
  await db.collection("deda_gm_personal_diamond_wallets").doc(a.key).set({
    accountKey:a.key,balance:9000,
  });
  await assert.rejects(buy(a,idA,"revoked_gm_purchase_1"),
    e=>e.code==="failed-precondition");
  assert.equal(await giftBalance(a),3000);
  assert.equal((await db.collection("deda_gm_personal_diamond_wallets")
    .doc(a.key).get()).data().balance,9000);
  assert.equal((await db.collection("deda_verified_id_sale_catalog")
    .doc(idA).get()).data().status,"verified_available");
  assert.equal((await db.collection("deda_owned_identifier_registry")
    .doc(idA).get()).exists,false);
});

test("client Firestore rules cannot forge purchases, own registry, sales or balance",async()=>{
  await init();
  const client=env.authenticatedContext(a.uid).firestore();
  await assertFails(setDoc(doc(client,"deda_owned_identifier_registry",idA),{
    identifier:idA,status:"owned",
  }));
  await assertFails(setDoc(doc(client,"deda_verified_id_sale_catalog",idA),{
    ownerApproved:true,status:"sold",
  }));
  await assertFails(setDoc(doc(client,"deda_id_purchase_requests",
    hash(a.key),"requests","forged_req_0001"),{
      diamondsCharged:0,
  }));
});


test("Stage53 mixed exclusive 4-character GM gift and new 6-character sale coexist in ONE account",async()=>{
  await init();
  const exclusive="@DEDA-ABCD";
  await db.collection("deda_owned_identifier_accounts")
    .doc(hash(a.key)).set({
      accountKey:a.key,originalId:a.original,
      activeId:exclusive,ownedIds:[a.original,exclusive],
    });
  await db.collection("deda_owned_identifier_registry").doc(exclusive).set({
    identifier:exclusive,accountKey:a.key,originalId:a.original,
    status:"owned",acquisition:"general_manager_gift",assignedColor:"diamond",
  });
  await db.collection("deda_owned_identifier_aliases").doc(exclusive).set({
    identifier:exclusive,accountKey:a.key,originalId:a.original,
    kind:"permanent_alias",
  });
  await db.collection("deda_admin_identifier_grants")
    .doc(hash(a.key+":"+exclusive)).set({
      identifier:exclusive,accountKey:a.key,originalId:a.original,
      color:"diamond",
    });
  const sale=await buy(a,idA,"stage53_exclusive_sale_001");
  assert.equal(sale.serverConfirmed,true);
  assert.equal(sale.diamondsCharged,10000);
  assert.equal(await giftBalance(a),4000);
  const after=(await db.collection("deda_owned_identifier_accounts")
    .doc(hash(a.key)).get()).data();
  assert.deepEqual(after.ownedIds,[a.original,exclusive,idA]);
  assert.equal(after.activeId,exclusive);
  assert.equal((await db.collection("deda_admin_identifier_grants")
    .doc(hash(a.key+":"+exclusive)).get()).data().color,"diamond");
  const retry=await buy(a,idA,"stage53_exclusive_sale_001");
  assert.deepEqual(retry,sale);
  assert.equal(await giftBalance(a),4000);
  const secondReq=await buy(a,idB,"stage53_exclusive_sale_002")
    .then(v=>v,e=>e);
  assert.equal(secondReq.code,"failed-precondition");
  assert.equal(await giftBalance(a),4000);
});

test("Stage53 cannot buy Group001 short name, even if present in client-selected style",async()=>{
  await init();
  await assert.rejects(buy(a,"@DEDA-ABCD","stage53_fake_sale_001"),
    e=>e.code==="permission-denied");
  assert.equal(await giftBalance(a),14000);
});

test("Stage53 cannot charge wallet for forged short ID ownership or oversized ID",async()=>{
  for(const badId of ["@DEDA-A","@DEDA-ABCDEFGHIJKLM"]){
    await init();
    await db.collection("deda_owned_identifier_accounts")
      .doc(hash(a.key)).set({
        accountKey:a.key,originalId:a.original,
        activeId:badId,ownedIds:[a.original,badId],
      });
    const current=await buy(a,idA,"stage53_bad_owner_req_001")
      .then(v=>v,e=>e);
    assert.equal(current.code,"failed-precondition");
    assert.equal(await giftBalance(a),14000);
    assert.equal((await db.collection("deda_owned_identifier_registry")
      .doc(idA).get()).exists,false);
  }
});
