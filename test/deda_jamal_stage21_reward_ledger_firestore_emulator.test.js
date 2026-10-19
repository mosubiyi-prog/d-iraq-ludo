"use strict";
// DEDA Stage21: REAL Firestore Emulator only; all rewards synthetic.
const test=require("node:test");
const assert=require("node:assert/strict");
const {createRequire}=require("node:module");
const {resolve}=require("node:path");
const {readFileSync}=require("node:fs");
const {createHmac,createHash}=require("node:crypto");
assert.match(process.env.FIRESTORE_EMULATOR_HOST||"",
  /^(127\.0\.0\.1|localhost):[0-9]+$/,"FIRESTORE EMULATOR REQUIRED");
const req=createRequire(resolve(__dirname,"../functions/package.json"));
const {initializeApp,deleteApp}=req("firebase-admin/app");
const {getFirestore}=req("firebase-admin/firestore");
const {initializeTestEnvironment,assertFails}=req("@firebase/rules-unit-testing");
const {doc,getDoc,setDoc,updateDoc}=req("firebase/firestore");
const {simulateAttestedRewardOnEmulator:claim,dayBaghdad,payloadString,PROJECT}=
  require("../tools/deda_jamal_stage21_reward_attestation_emulator_only_2026_10_19.js");

const demoKey=Buffer.from("stage21-test-secret-NO-PRODUCTION_"+ "1".repeat(32));
const CLOCK=Date.parse("2026-10-19T09:20:00Z");
const A={uid:"new_UID_A",older:"original_UID_A",
  key:"account_AAAA",original:"@DEDA-A1B2C3"};
const B={uid:"new_UID_B",older:"original_UID_B",
  key:"account_BBBB",original:"@DEDA-D4E5F6"};
const sha=s=>createHash("sha256").update(s).digest("hex");
let app,db,env;
let serial=0;
function ticket(user=A,source="ad_demo",id=null,time=CLOCK-1000) {
  const eventId=id||("s21_event_"+String(++serial).padStart(8,"0"));
  const p={
    source,eventId,accountKey:user.key,issuedForOriginalId:user.original,
    verifiedAtMs:time,dayId:dayBaghdad(time),
    amount:source==="ad_demo"?3:5,
  };
  return {...p,signatureHex:createHmac("sha256",demoKey)
    .update(payloadString(p),"utf8").digest("hex")};
}
async function init() {
  await env.clearFirestore();
  const b=db.batch();
  for(const u of [A,B]){
    b.set(db.collection("users").doc(u.uid),{
      accountKey:u.key,sharePersonalId:u.original,
      points:1000,level:11,localDiamonds:999999,
    });
    b.set(db.collection("users").doc(u.older),{accountKey:u.key});
    b.set(db.collection("deda_sessions").doc(u.uid),{
      uid:u.uid,accountKey:u.key,
    });
    b.set(db.collection("deda_share_ids").doc(u.original),{
      publicId:u.original,kind:"personal",active:true,
      ownerUid:u.older,
    });
    b.set(db.collection("deda_diamond_gift_balances").doc(u.original),{
      publicId:u.original,balance:u===A?70:20,
    });
  }
  b.set(db.collection("admins").doc(A.uid),{
    active:true,status:"active",role:"general_manager",
  });
  b.set(db.collection("deda_admin_diamond_wallets").doc(A.uid),{
    balance:900000,initialBalance:1000000,adminUid:A.uid,
  });
  b.set(db.collection("deda_gm_personal_diamond_wallets").doc(A.key),{
    accountKey:A.key,balance:43000,initialBalance:1000000,
  });
  b.set(db.collection("deda_telegram_account_claims").doc(A.key),{
    accountKey:A.key,telegramUserId:"123123123",
  });
  await b.commit();
}
function attempt(u,p,clock=CLOCK) {
  return claim(db,{authUid:u.uid,ticket:p,
    testOnlyHmacSecret:demoKey,trustedNowMs:clock});
}
async function balance(u=A) {
  return (await db.collection("deda_diamond_gift_balances")
    .doc(u.original).get()).data().balance;
}
async function ledgerEvent(id) {
  return db.collection("deda_stage21_emulator_reward_claims")
    .doc(sha(id)).get();
}
test.before(async()=>{
  app=initializeApp({projectId:PROJECT},"stage21-reward-emulator-only");
  db=getFirestore(app);
  env=await initializeTestEnvironment({
    projectId:PROJECT,
    firestore:{
      host:"127.0.0.1",
      port:Number(process.env.FIRESTORE_EMULATOR_HOST.split(":")[1]),
      rules:readFileSync(resolve(__dirname,"../firestore.rules"),"utf8"),
    },
  });
});
test.after(async()=>{
  if(env)await env.cleanup();
  if(app)await deleteApp(app);
});

test("genuine atomic synthetic claim: +3 to existing gift/TG wallet, original ID and manager funds untouched",async()=>{
  await init();
  const p=ticket();
  const beforeAdmin=(await db.collection("deda_admin_diamond_wallets")
    .doc(A.uid).get()).data();
  const beforeGM=(await db.collection("deda_gm_personal_diamond_wallets")
    .doc(A.key).get()).data();
  const out=await attempt(A,p);
  assert.equal(out.outcome,"awarded");
  assert.equal(out.awarded,3);
  assert.equal(out.balanceAfter,73);
  assert.equal(await balance(A),73);
  assert.equal((await ledgerEvent(p.eventId)).exists,true);
  const r=(await ledgerEvent(p.eventId)).data();
  assert.equal(r.provenance,"emulator_fake_HMAC_DO_NOT_PAY_PRODUCTION");
  assert.equal(r.accountKey,A.key);
  assert.deepEqual((await db.collection("users").doc(A.uid).get()).data(),{
    accountKey:A.key,sharePersonalId:A.original,
    points:1000,level:11,localDiamonds:999999,
  });
  assert.deepEqual((await db.collection("deda_admin_diamond_wallets")
    .doc(A.uid).get()).data(),beforeAdmin);
  assert.deepEqual((await db.collection("deda_gm_personal_diamond_wallets")
    .doc(A.key).get()).data(),beforeGM);
});
test("lost-response replay same synthetic event cannot pay twice",async()=>{
  await init();
  const p=ticket();
  const first=await attempt(A,p);
  const second=await attempt(A,p);
  assert.equal(first.outcome,"awarded");
  assert.equal(second.outcome,"already-recorded");
  assert.equal(second.awarded,0);
  assert.equal(await balance(A),73);
});
test("ten simultaneous retries of one event -> one +3, global receipt exactly once",async()=>{
  await init();
  const p=ticket();
  const results=await Promise.allSettled(
    Array.from({length:10},()=>attempt(A,p)));
  const awarded=results.filter(x=>x.status==="fulfilled"&&
    x.value.outcome==="awarded");
  const replay=results.filter(x=>x.status==="fulfilled"&&
    x.value.outcome==="already-recorded");
  assert.equal(awarded.length,1);
  assert.equal(awarded.length+replay.length,10);
  assert.equal(await balance(A),73);
});
test("two different concurrent signed events atomically add exact 3+5 without lost update",async()=>{
  await init();
  const p=ticket(A,"ad_demo"),q=ticket(A,"task_demo");
  const results=await Promise.all([attempt(A,p),attempt(A,q)]);
  assert.deepEqual(results.map(x=>x.awarded).sort(),[3,5]);
  assert.equal(await balance(A),78);
  const daily=(await db.collection("deda_stage21_emulator_reward_daily")
    .doc(sha(A.key+"|"+dayBaghdad(CLOCK))).get()).data();
  assert.equal(daily.count,2);
  assert.equal(daily.amount,8);
});
test("cross-account event theft and tampering amount/source/user/sig are rejected without credit",async()=>{
  await init();
  const p=ticket(A);
  await assert.rejects(attempt(B,p),e=>e.code==="permission-denied");
  for(const tamper of [
    {...p,amount:9999},
    {...p,source:"task_demo"},
    {...p,accountKey:B.key},
    {...p,issuedForOriginalId:B.original},
    {...p,signatureHex:"0".repeat(64)},
    {...p,admin:true},
  ])await assert.rejects(attempt(A,tamper),e=>e.code==="permission-denied");
  assert.equal(await balance(A),70);
  assert.equal(await balance(B),20);
});
test("unverified ad tap/unsigned client callback can't mint, even with local 999999 diamonds",async()=>{
  await init();
  const p=ticket(A);
  const {signatureHex,...unsigned}=p;
  await assert.rejects(attempt(A,unsigned),e=>e.code==="permission-denied");
  assert.equal(await balance(A),70);
});
test("expired/clock-skew/different Baghdad day signed proof rejected",async()=>{
  await init();
  await assert.rejects(attempt(A,ticket(A,"ad_demo",null,CLOCK-20*60*1000)),
    e=>e.code==="permission-denied");
  await assert.rejects(attempt(A,ticket(A,"ad_demo",null,CLOCK+4*60*1000)),
    e=>e.code==="permission-denied");
  assert.equal(await balance(A),70);
});
test("five ads/day capped, sixth cannot mint even with a distinct valid signed event",async()=>{
  await init();
  for(let i=0;i<5;i++){
    assert.equal((await attempt(A,ticket())).awarded,3);
  }
  const overflow=ticket();
  await assert.rejects(attempt(A,overflow),e=>e.code==="resource-exhausted");
  assert.equal(await balance(A),85);
  assert.equal((await ledgerEvent(overflow.eventId)).exists,false);
});
test("six demo tasks/day capped, points/levels separate; no repeated issuance",async()=>{
  await init();
  for(let i=0;i<6;i++){
    assert.equal((await attempt(A,ticket(A,"task_demo"))).awarded,5);
  }
  await assert.rejects(attempt(A,ticket(A,"task_demo")),
    e=>e.code==="resource-exhausted");
  assert.equal(await balance(A),100);
  assert.equal((await db.collection("users").doc(A.uid).get())
    .data().points,1000);
});
test("tampered wallet publicId and negative balance do not mint",async()=>{
  await init();
  const wallet=db.collection("deda_diamond_gift_balances").doc(A.original);
  await wallet.update({publicId:B.original});
  await assert.rejects(attempt(A,ticket()),e=>e.code==="failed-precondition");
  await wallet.update({publicId:A.original,balance:-2});
  await assert.rejects(attempt(A,ticket()),e=>e.code==="failed-precondition");
});
test("rotated session mismatch denies even previously signed event",async()=>{
  await init();
  await db.collection("deda_sessions").doc(A.uid)
    .update({accountKey:B.key});
  const p=ticket(A);
  await assert.rejects(attempt(A,p),e=>e.code==="permission-denied");
  assert.equal(await balance(A),70);
});
test("no client Firestore write can forge internal demo receipts or increase diamond wallet",async()=>{
  await init();
  const client=env.authenticatedContext(A.uid).firestore();
  await assertFails(setDoc(doc(client,"deda_stage21_emulator_reward_claims",
    sha("client_fake_1001")),{source:"ad_demo",amount:99999}));
  await assertFails(updateDoc(doc(client,"deda_diamond_gift_balances",
    A.original),{balance:987654321}));
  assert.equal(await balance(A),70);
});
