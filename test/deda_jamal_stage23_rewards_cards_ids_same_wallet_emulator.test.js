"use strict";
// DEDA Jamal Stage23 reward -> 5k style / 10k approved public ID.
// Uses LOCAL FIRESTORE EMULATOR and OFFLINE GENERATED FAKE ECDSA PROVIDER ONLY.
// Synthetic signed "ad reward" is NOT actual Google AdMob SSV evidence.
const test=require("node:test"), assert=require("node:assert/strict");
const {createRequire}=require("node:module");
const {resolve}=require("node:path");
const {readFileSync}=require("node:fs");
const {createHash,generateKeyPairSync,sign}=require("node:crypto");
assert.match(process.env.FIRESTORE_EMULATOR_HOST||"",
  /^(127[.]0[.]0[.]1|localhost):[0-9]+$/,"EMULATOR REQUIRED");
assert.equal(process.env.GCLOUD_PROJECT,
  "demo-deda-stage22-ssv-fakeprovider","SAFE STOP exact demo project required");
const req=createRequire(resolve(__dirname,"../functions/package.json"));
const {initializeApp,deleteApp}=req("firebase-admin/app");
const {getFirestore}=req("firebase-admin/firestore");
const {initializeTestEnvironment,assertFails}=req("@firebase/rules-unit-testing");
const {doc,setDoc,getDoc}=req("firebase/firestore");
const {createApprovedSaleCatalog,checkoutVerifiedIdentifier}=
  require("../tools/deda_stage18_private_atomic_identifier_checkout_2026_10_19.js");
const {checkoutIdCard,readOwnedCards,accountHash}=
  require("../tools/deda_intakadha_point13_atomic_id_card_checkout_2026_10_19.js");
const {readVerifiedCardState,activateVerifiedCard}=
  require("../tools/deda_intakadha_point14_verified_card_activation_2026_10_19.js");
const {createPendingRewardChallenge,acceptProviderVerifiedReward}=
  require("../tools/deda_jamal_stage22_admob_ssv_ecdsa_staged_no_deploy_2026_10_19.js");
const SHA=s=>createHash("sha256").update(s).digest("hex");
const PROJECT="demo-deda-stage22-ssv-fakeprovider";
const A={uid:"stage23-current-user-A",old:"stage23-old-user-A",
  account:"stage23_person_A",original:"@DEDA-Q1W2E3"};
const B={uid:"stage23-current-user-B",old:"stage23-old-user-B",
  account:"stage23_person_B",original:"@DEDA-R4T5Y6"};
const PRODUCT="@DEDA-AAAAAA",CLOCK=Date.parse("2026-10-19T11:30:00Z");
const KEY_ID="123";
const keys=generateKeyPairSync("ec",{namedCurve:"prime256v1"});
const PINS={[KEY_ID]:keys.publicKey.export({type:"spki",format:"pem"}).toString()};
const policy=Object.freeze({
  verifiedForProduction:false,
  adUnitId:"ca-app-pub-2512641627784244/6037567292",
  expectedRewardItem:"diamonds",expectedRewardAmount:1,rewardDiamonds:3,
});
const catalog=createApprovedSaleCatalog({
  reservedSuffixes:Array.from({length:100},(_,i)=>
    String(i+1).padStart(6,"0")),
  approvedSuffixes:["AAAAAA"],
});
let app,db,env;
let sequence=0;
function signQuery(nonce){
  const transactionId="stage23_tx_"+String(++sequence).padStart(10,"0");
  const msg=[
    "ad_unit="+encodeURIComponent(policy.adUnitId),
    "custom_data="+encodeURIComponent(nonce),
    "reward_amount=1",
    "reward_item=diamonds",
    "timestamp="+CLOCK,
    "transaction_id="+transactionId,
  ].join("&");
  const sig=sign("sha256",Buffer.from(msg),keys.privateKey)
    .toString("base64url");
  return msg+"&signature="+sig+"&key_id="+KEY_ID;
}
async function reset(balance){
  await env.clearFirestore();
  const b=db.batch();
  for(const p of [A,B]){
    b.set(db.collection("users").doc(p.old),{
      accountKey:p.account,
    });
    b.set(db.collection("users").doc(p.uid),{
      accountKey:p.account,sharePersonalId:p.original,
      localDiamonds:999999,points:775,level:17,
    });
    b.set(db.collection("deda_sessions").doc(p.uid),{
      uid:p.uid,accountKey:p.account,
    });
    b.set(db.collection("deda_share_ids").doc(p.original),{
      publicId:p.original,kind:"personal",active:true,ownerUid:p.old,
    });
    b.set(db.collection("deda_diamond_gift_balances").doc(p.original),{
      publicId:p.original,balance:p===A?balance:100,
    });
  }
  b.set(db.collection("deda_verified_id_sale_catalog").doc(PRODUCT),{
    identifier:PRODUCT,group:"002",status:"verified_available",
    ownerApproved:true,priceDiamonds:10000,
  });
  await b.commit();
}
async function balance(person=A){
  return (await db.collection("deda_diamond_gift_balances")
    .doc(person.original).get()).data().balance;
}
async function fakeSignedServerReward(){
  const ch=await createPendingRewardChallenge(db,{
    authUid:A.uid,policy,trustedNowMs:CLOCK,
  });
  const query=signQuery(ch.customData);
  return {query,result:await acceptProviderVerifiedReward(db,{
    rawQuery:query,pinnedProviderKeys:PINS,
    policy,trustedNowMs:CLOCK,
  })};
}
function card(color="gold",requestId="stage23_card_req_0001",person=A){
  return checkoutIdCard(db,{uid:person.uid,color,requestId});
}
function idBuy(requestId="stage23_id_req_00001",person=A){
  return checkoutVerifiedIdentifier(db,{
    uid:person.uid,identifier:PRODUCT,requestId,approvedCatalog:catalog,
  });
}
test.before(async()=>{
  app=initializeApp({projectId:PROJECT},"deda-stage23-wallet-integration");
  db=getFirestore(app);
  env=await initializeTestEnvironment({projectId:PROJECT,firestore:{
    host:"127.0.0.1",
    port:Number(process.env.FIRESTORE_EMULATOR_HOST.split(":")[1]),
    rules:readFileSync(resolve(__dirname,"../firestore.rules"),"utf8"),
  }});
});
test.after(async()=>{
  if(env)await env.cleanup();
  if(app)await deleteApp(app);
});
test("fake signed +3 makes previously insufficient 4,998 balance eligible for ONE 5,000 style",async()=>{
  await reset(4998);
  await assert.rejects(card("gold","stage23_req_before_reward"),
    e=>e.code==="failed-precondition");
  const {result}=await fakeSignedServerReward();
  assert.equal(result.diamondsAwarded,3);
  assert.equal(await balance(),5001);
  const bought=await card("gold");
  assert.equal(bought.diamondsCharged,5000);
  assert.equal(await balance(),1);
  assert.deepEqual(await readOwnedCards(db,{uid:A.uid}),["gold"]);
  const chosen=await activateVerifiedCard(db,{uid:A.uid,color:"gold"});
  assert.equal(chosen.activeColor,"gold");
  assert.equal((await readVerifiedCardState(db,{uid:A.uid})).activeColor,"gold");
});
test("fake signed +3 makes 9,998 balance sufficient for ONE 10,000 Group002 ID",async()=>{
  await reset(9998);
  await assert.rejects(idBuy("stage23_before_reward"),
    e=>e.code==="failed-precondition");
  const {result}=await fakeSignedServerReward();
  assert.equal(result.diamondsAwarded,3);
  const buy=await idBuy();
  assert.equal(buy.diamondsCharged,10000);
  assert.equal(await balance(),1);
  const registry=(await db.collection("deda_owned_identifier_registry")
    .doc(PRODUCT).get()).data();
  assert.equal(registry.originalId,A.original);
  assert.equal(registry.acquisition,"diamond_purchase");
  const alias=(await db.collection("deda_owned_identifier_aliases")
    .doc(PRODUCT).get()).data();
  assert.equal(alias.originalId,A.original);
  const user=(await db.collection("users").doc(A.uid).get()).data();
  assert.equal(user.sharePersonalId,A.original);
  assert.equal(user.localDiamonds,999999);
});
test("one 3-diamond receipt plus concurrent 5k and 10k purchases shares SAME 15,000 wallet",async()=>{
  await reset(14997);
  const {query,result}=await fakeSignedServerReward();
  assert.equal(result.outcome,"awarded");
  assert.equal(await balance(),15000);
  const [a,b]=await Promise.all([
    card("pink","stage23_5k_spend_req_01"),
    idBuy("stage23_10k_spend_req_01"),
  ]);
  assert.equal(a.diamondsCharged+b.diamondsCharged,15000);
  assert.equal(await balance(),0);
  assert.equal((await db.collection("deda_verified_id_sale_catalog")
    .doc(PRODUCT).get()).data().status,"sold");
  const retry=await acceptProviderVerifiedReward(db,{
    rawQuery:query,pinnedProviderKeys:PINS,policy,trustedNowMs:CLOCK,
  });
  assert.equal(retry.outcome,"already-recorded");
  assert.equal(retry.diamondsAwarded,0);
  assert.equal((await card("pink","stage23_5k_spend_req_01")).diamondsCharged,5000);
  assert.equal((await idBuy("stage23_10k_spend_req_01")).diamondsCharged,10000);
  assert.equal(await balance(),0);
});
test("insufficient wallet for both after server reward: only ONE 5k/10k purchase wins",async()=>{
  await reset(14996);
  await fakeSignedServerReward();
  assert.equal(await balance(),14999);
  const results=await Promise.allSettled([
    card("royal","stage23_5k_race_req_02"),
    idBuy("stage23_10k_race_req_02"),
  ]);
  assert.equal(results.filter(x=>x.status==="fulfilled").length,1);
  assert.equal(results.filter(x=>x.status==="rejected").length,1);
  const spent=results.find(x=>x.status==="fulfilled").value.diamondsCharged;
  assert.ok([5000,10000].includes(spent));
  assert.equal(await balance(),14999-spent);
  const owned=await readOwnedCards(db,{uid:A.uid});
  const isSold=(await db.collection("deda_verified_id_sale_catalog")
    .doc(PRODUCT).get()).data().status==="sold";
  assert.equal((owned.includes("royal")?1:0)+(isSold?1:0),1);
});
test("old 999,999 locally displayed diamonds alone never authorize purchase",async()=>{
  await reset(0);
  await assert.rejects(card("diamond","stage23_local_5k_req"),
    e=>e.code==="failed-precondition");
  await assert.rejects(idBuy("stage23_local_10k_req"),
    e=>e.code==="failed-precondition");
  assert.equal(await balance(),0);
  assert.deepEqual(await readOwnedCards(db,{uid:A.uid}),[]);
});
test("revoked GM cannot spend GM personal wallet on 5k OR 10k despite stale access",async()=>{
  await reset(500);
  const batch=db.batch();
  batch.set(db.collection("deda_gm_personal_diamond_wallets").doc(A.account),{
    accountKey:A.account,balance:60000,initialBalance:1000000,
  });
  batch.set(db.collection("admin_entry_access").doc(A.account),{
    accountKey:A.account,active:true,status:"active",
    accessType:"general_manager_gateway",allowedRole:"general_manager",
  });
  batch.set(db.collection("admins").doc(A.uid),{
    role:"employee",active:true,status:"active",
  });
  await batch.commit();
  await assert.rejects(card("gold","stage23_revoked_5k_req"),
    e=>e.code==="failed-precondition");
  await assert.rejects(idBuy("stage23_revoked_10k_req"),
    e=>e.code==="failed-precondition");
  assert.equal(await balance(),500);
  assert.equal((await db.collection("deda_gm_personal_diamond_wallets")
    .doc(A.account).get()).data().balance,60000);
});
test("friend/legacy account identity and points remain after fake provider + two purchases",async()=>{
  await reset(14997);
  const before=(await db.collection("users").doc(A.uid).get()).data();
  await fakeSignedServerReward();
  await card("gold","stage23_profile_preserve_card");
  await idBuy("stage23_profile_preserve_id");
  assert.deepEqual((await db.collection("users").doc(A.uid).get()).data(),before);
  assert.equal((await db.collection("deda_sessions").doc(A.uid).get())
    .data().accountKey,A.account);
  assert.equal((await db.collection("deda_share_ids")
    .doc(A.original).get()).data().ownerUid,A.old);
  const ledger=(await db.collection("deda_owned_identifier_accounts")
    .doc(accountHash(A.account)).get()).data();
  assert.equal(ledger.activeId,A.original);
  assert.deepEqual(ledger.ownedIds,[A.original,PRODUCT]);
});
test("untrusted client cannot overwrite reward receipt, ownership or debit/credit wallet",async()=>{
  await reset(5000);
  const client=env.authenticatedContext(A.uid).firestore();
  await assertFails(setDoc(doc(client,"deda_stage22_ssv_receipts",
    SHA("stage23_forged_ssv")),{
    transactionId:"stage23_forged_ssv",diamondsAwarded:100000,
  }));
  await assertFails(setDoc(doc(client,"deda_id_card_entitlements",
    accountHash(A.account)),{colors:{gold:true}}));
  await assertFails(getDoc(doc(client,"deda_id_card_entitlements",
    accountHash(A.account))));
  assert.equal(await balance(),5000);
});
test("Stage22 offline ECDSA cannot access Firestore without exact fake demo project",async()=>{
  await reset(4998);
  const prev=process.env.GCLOUD_PROJECT;
  try{
    process.env.GCLOUD_PROJECT="real-production-project-is-blocked";
    await assert.rejects(createPendingRewardChallenge(db,{
      authUid:A.uid,policy,trustedNowMs:CLOCK,
    }),e=>e.code==="unavailable");
    assert.equal(await balance(),4998);
  } finally {
    if(prev===undefined)delete process.env.GCLOUD_PROJECT;
    else process.env.GCLOUD_PROJECT=prev;
  }
});
