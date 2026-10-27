"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {
  resolveFutureVerifiedAccount,inspectFutureServerXpReceipt,opaqueReceiptId,
}=require("../deda_weekly_owner_receipt_gate_NOT_EXPORTED.js");

const START=Date.UTC(2026,9,27,0);
const NOW=START+3600*1000;
const week={weekId:"week-2026-test",startMs:START,endMs:START+7*86400000};
const ACCOUNT="07701234567";
const UID1="anonymous_phone_A",UID2="anonymous_phone_B";
const INSTALL1="install_A",INSTALL2="install_B";
const DAY="2026-10-27";
const TASK="open_map";
function store(docs) {
  const requested=[];
  return {
    requested,
    doc(path) {
      requested.push(path);
      return {async get() {
        const value=docs.get(path);
        if(!value)return {exists:false};
        return {exists:true,data:()=>structuredClone(value)};
      }};
    },
  };
}
function fixtures(uid=UID1,install=INSTALL1,now=NOW) {
  return new Map([
    ["users/"+uid,{accountKey:ACCOUNT,uid}],
    ["deda_sessions/"+uid,{uid,accountKey:ACCOUNT,installId:install}],
    ["deda_account_profiles/"+ACCOUNT,{
      accountKey:ACCOUNT,trustedInstallIds:[INSTALL1,INSTALL2]}],
    ["deda_weekly_identity_attestations/"+uid,{
      uid,accountKey:ACCOUNT,installId:install,
      state:"verified",issuer:"privileged_identity_verifier_v1",
      issuedAtMs:now-30000,expiresAtMs:now+30000,
    }],
  ]);
}
function request(uid=UID1) {
  return {auth:{uid},app:{appId:"deda_app_check_test_fixture"},data:{}};
}
function receipt(accountKey=ACCOUNT) {
  const receiptId=opaqueReceiptId({accountKey,dayId:DAY,taskId:TASK});
  return {
    issuer:"privileged_server_only_task_xp_issuer_v1",
    status:"final_award_committed",
    accountKey,dayId:DAY,taskId:TASK,weekId:week.weekId,receiptId,
    taskPointsAwarded:true,levelXpApplied:true,levelXpAmount:20,
    verifiedAtMs:NOW-1000,
  };
}
const path="deda_weekly_xp_receipts/"+week.weekId+"/events/"+
    opaqueReceiptId({accountKey:ACCOUNT,dayId:DAY,taskId:TASK});

test("server-only future attestation is required: current backend fails CLOSED",async()=>{
  const docs=fixtures();
  docs.delete("deda_weekly_identity_attestations/"+UID1);
  await assert.rejects(
    resolveFutureVerifiedAccount({
      db:store(docs),request:request(),serverNowMs:NOW,
    }),/verified_document_missing/);
});

test("future server proof resolves same account after a second phone and UID",async()=>{
  const a=await resolveFutureVerifiedAccount({
    db:store(fixtures(UID1,INSTALL1)),request:request(UID1),serverNowMs:NOW,
  });
  const b=await resolveFutureVerifiedAccount({
    db:store(fixtures(UID2,INSTALL2)),request:request(UID2),serverNowMs:NOW,
  });
  assert.equal(a.canonicalAccountKey,ACCOUNT);
  assert.equal(b.canonicalAccountKey,a.canonicalAccountKey);
  assert.notEqual(a.authenticatedUid,b.authenticatedUid);
  assert.equal(a.readOnly,true);
});

test("app check, Firebase caller identity and arbitrary client totals fail CLOSED",async()=>{
  const base={db:store(fixtures()),request:request(),serverNowMs:NOW};
  for (const altered of [
    {request:{auth:{uid:UID1},data:{}}},
    {request:{app:{appId:"deda_app_check_test_fixture"},data:{}}},
    {request:{...request(),data:{accountKey:ACCOUNT}}},
    {request:{...request(),data:{uid:UID1}}},
    {request:{...request(),data:{xp:1000000}}},
    {request:{...request(),data:{weekId:week.weekId}}},
  ]) {
    await assert.rejects(
      resolveFutureVerifiedAccount({...base,...altered}),
      /WEEKLY_READ_ONLY_BLOCK_/);
  }
});

test("mismatched session owner, forged second install or stale attestation blocked",async()=>{
  const base=fixtures();
  const differentAccount=fixtures();
  differentAccount.set("deda_sessions/"+UID1,{
    uid:UID1,accountKey:"07799999999",installId:INSTALL1,
  });
  const untrustedInstall=fixtures();
  untrustedInstall.set("deda_sessions/"+UID1,{
    uid:UID1,accountKey:ACCOUNT,installId:"new_untrusted_device",
  });
  const outdated=fixtures();
  outdated.get("deda_weekly_identity_attestations/"+UID1).expiresAtMs=NOW-1;
  const oldIssued=fixtures();
  const proof=oldIssued.get("deda_weekly_identity_attestations/"+UID1);
  proof.issuedAtMs=NOW-(6*3600*1000);
  proof.expiresAtMs=NOW+30000;
  for(const dbData of [differentAccount,untrustedInstall,outdated,oldIssued]){
    await assert.rejects(resolveFutureVerifiedAccount({
      db:store(dbData),request:request(),serverNowMs:NOW,
    }),/WEEKLY_READ_ONLY_BLOCK_/);
  }
  assert.equal(base.get("deda_sessions/"+UID1).accountKey,ACCOUNT);
});

test("future trusted server task XP receipt is accepted read-only; no account write",async()=>{
  const docs=fixtures();
  docs.set(path,receipt());
  const db=store(docs);
  const identity=await resolveFutureVerifiedAccount({
    db,request:request(),serverNowMs:NOW,
  });
  const inspected=await inspectFutureServerXpReceipt({
    db,identity,weekConfig:week,dayId:DAY,taskId:TASK,serverNowMs:NOW,
  });
  assert.equal(inspected.levelXpEarned,20);
  assert.equal(inspected.accountKey,ACCOUNT);
  assert.equal(inspected.readOnly,true);
  assert.equal(inspected.receiptId,receipt().receiptId);
  assert.ok(db.requested.includes(path));
  assert.equal(typeof db.set, "undefined");
});

test("absent future privileged XP issuance never becomes a weekly rank",async()=>{
  const db=store(fixtures());
  const identity=await resolveFutureVerifiedAccount({
    db,request:request(),serverNowMs:NOW,
  });
  await assert.rejects(inspectFutureServerXpReceipt({
    db,identity,weekConfig:week,taskId:TASK,dayId:DAY,serverNowMs:NOW,
  }),/verified_document_missing/);
});

test("ordinary task point alone is NOT proof of 20 XP being applied",async()=>{
  const base=fixtures();
  const missingXp=receipt();
  missingXp.levelXpApplied=false;
  const wrongXp=receipt();
  wrongXp.levelXpAmount=5;
  const clientMinted=receipt();
  clientMinted.issuer="client_forged_issuer";
  const wrongAccount=receipt();
  wrongAccount.accountKey="07722222222";
  for(const bad of [missingXp,wrongXp,clientMinted,wrongAccount]){
    const docs=new Map(base);
    docs.set(path,bad);
    const db=store(docs);
    const identity=await resolveFutureVerifiedAccount({
      db,request:request(),serverNowMs:NOW,
    });
    await assert.rejects(inspectFutureServerXpReceipt({
      db,identity,weekConfig:week,taskId:TASK,dayId:DAY,serverNowMs:NOW,
    }),/invalid_xp_receipt/);
  }
});

test("device time cannot spoof Iraq day or server weekly boundaries",async()=>{
  const base=fixtures();
  const wrongDay=receipt();
  wrongDay.dayId="2026-10-28";
  const weekEnd=receipt();
  weekEnd.verifiedAtMs=week.endMs;
  const future=receipt();
  future.verifiedAtMs=NOW+1000;
  for(const bad of [wrongDay,weekEnd,future]){
    const docs=new Map(base);
    docs.set(path,bad);
    const db=store(docs);
    const identity=await resolveFutureVerifiedAccount({
      db,request:request(),serverNowMs:NOW,
    });
    await assert.rejects(inspectFutureServerXpReceipt({
      db,identity,weekConfig:week,taskId:TASK,dayId:DAY,serverNowMs:NOW,
    }),/invalid_xp_receipt/);
  }
});

test("fresh account identity expires after account/session switching",async()=>{
  const docs=fixtures();
  docs.set(path,receipt());
  const db=store(docs);
  const identity=await resolveFutureVerifiedAccount({
    db,request:request(),serverNowMs:NOW,
  });
  await assert.rejects(inspectFutureServerXpReceipt({
    db,identity,weekConfig:week,taskId:TASK,dayId:DAY,serverNowMs:NOW+1,
  }),/identity_expired/);
});

test("new phone cannot collect older phone's unverifiable local XP",async()=>{
  const docs=fixtures(UID2,INSTALL2);
  const db=store(docs);
  const identity=await resolveFutureVerifiedAccount({
    db,request:request(UID2),serverNowMs:NOW,
  });
  await assert.rejects(inspectFutureServerXpReceipt({
    db,identity,weekConfig:week,taskId:TASK,dayId:DAY,serverNowMs:NOW,
  }),/verified_document_missing/);
});
