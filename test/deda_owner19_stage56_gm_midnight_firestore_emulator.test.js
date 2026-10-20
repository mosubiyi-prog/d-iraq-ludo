"use strict";

// Stage56 real disposable Firestore emulator test: NO PRODUCTION / NO DEPLOY.
// Firestore transaction contention ensures two schedulers cannot double-top-up.
const test=require("node:test"),assert=require("node:assert/strict");
const {createRequire}=require("node:module");
const {resolve}=require("node:path");
const {createHash}=require("node:crypto");
const host=process.env.FIRESTORE_EMULATOR_HOST||"";
assert.match(host,/^(127\.0\.0\.1|localhost):[0-9]+$/);
assert.equal(process.env.GCLOUD_PROJECT,"demo-deda-owner19-stage56-midnight");
const r=createRequire(resolve(__dirname,"../functions/package.json"));
const {initializeApp,deleteApp}=r("firebase-admin/app");
const {getFirestore}=r("firebase-admin/firestore");
const {refillGMPersonalToMillion:refill,
  refillApprovedAtMidnight:sweep}=require(
  "../tools/deda_owner19_stage56_gm_personal_midnight_refill_PRIVATE_NO_DEPLOY_2026_10_20.js");
const sha=x=>createHash("sha256").update(x,"utf8").digest("hex");
const uid="stage56_gm_admin_001",accountKey="stage56_manager_identity",
  original="@DEDA-D5E6F7";
const walletPath="deda_gm_personal_diamond_wallets/"+accountKey;
const donationPath="deda_admin_diamond_wallets/"+accountKey;
const approvePath="deda_gm_personal_refill_approvals/"+sha(accountKey);
const before=new Date("2026-10-20T20:59:59.999Z");
const midnight=new Date("2026-10-20T21:00:00.000Z");
let app,db;

async function seed({amount=950000,approved=true}={}){
  const batch=db.batch();
  batch.set(db.collection("users").doc(uid),{
    accountKey,sharePersonalId:original});
  batch.set(db.collection("deda_sessions").doc(uid),{uid,accountKey});
  batch.set(db.collection("deda_share_ids").doc(original),{
    publicId:original,active:true,kind:"personal",ownerUid:uid});
  batch.set(db.collection("admin_entry_access").doc(accountKey),{
    accountKey,allowedRole:"general_manager",
    accessType:"general_manager_gateway",status:"active",active:true});
  batch.set(db.collection("admins").doc(uid),{
    role:"general_manager",active:true,status:"active"});
  batch.set(db.collection("deda_gm_personal_diamond_wallets").doc(accountKey),{
    accountKey,initialBalance:1000000,balance:amount});
  batch.set(db.collection("deda_admin_diamond_wallets").doc(accountKey),{
    accountKey,balance:1000000});
  batch.set(db.collection("deda_gm_personal_refill_approvals").doc(sha(accountKey)),{
    accountKey,originalId:original,approved,
    status:"active",walletType:"gm_personal_test",
    ownerApprovedMidnightRefill:true,serverAuditedMintProvenance:true,
    refillAnchorBaghdadDay:"2026-10-20",capDiamonds:1000000,
    lastVerifiedGmUid:uid});
  await batch.commit();
}
const read=path=>db.doc(path).get();
test.before(async()=>{
  app=initializeApp({projectId:"demo-deda-owner19-stage56-midnight"},
    "owner19_stage56_test");
  db=getFirestore(app);
});
test.after(async()=>{if(app)await deleteApp(app);});

test("exact midnight and two simultaneous calls restore 50k ONCE",async()=>{
  await seed();
  const first=await refill(db,{uid,now:before});
  assert.equal(first.diamondsRestored,0);
  assert.equal((await read(walletPath)).data().balance,950000);

  const out=await Promise.all([
    refill(db,{uid,now:midnight}),
    refill(db,{uid,now:midnight}),
  ]);
  assert.deepEqual(out.map(x=>x.diamondsRestored).sort((a,b)=>a-b),[0,50000]);
  const after=(await read(walletPath)).data();
  assert.equal(after.balance,1000000);
  assert.equal(after.lastDailyRefillAmount,50000);
  assert.equal(after.lastDailyRefillBaghdadDay,"2026-10-21");
  assert.equal((await read(donationPath)).data().balance,1000000);
});
test("spending later same day never triggers a second refill",async()=>{
  await db.doc(walletPath).update({balance:925000});
  const retry=await refill(db,{uid,now:new Date("2026-10-21T12:00:00Z")});
  assert.equal(retry.alreadyRefilledToday,true);
  assert.equal(retry.diamondsRestored,0);
  assert.equal((await read(walletPath)).data().balance,925000);
  const next=await refill(db,{uid,now:new Date("2026-10-21T21:00:00Z")});
  assert.equal(next.diamondsRestored,75000);
  assert.equal((await read(walletPath)).data().balance,1000000);
  assert.equal((await read(donationPath)).data().balance,1000000);
});
test("owner approval revocation prevents scheduler and direct refills",async()=>{
  await db.doc(approvePath).update({approved:false});
  const previous=(await read(walletPath)).data().balance;
  await assert.rejects(refill(db,{uid,now:new Date("2026-10-22T21:00:00Z")}),
    e=>e.code==="failed-precondition");
  const scheduled=await sweep(db,{
    now:new Date("2026-10-22T21:00:00Z"),
  });
  assert.equal(scheduled.length,0);
  assert.equal((await read(walletPath)).data().balance,previous);
});
