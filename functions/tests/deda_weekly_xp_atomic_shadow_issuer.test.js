"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {PROJECT,ROOT,simulateAtomicShadowTaskXp}=
  require("../deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const {opaqueReceiptId}=
  require("../deda_weekly_owner_receipt_gate_NOT_EXPORTED.js");
const NOW=Date.UTC(2026,9,27,11);
const START=Date.UTC(2026,9,26,21);
const WEEK={weekId:"week-config-from-server",startMs:START,
  endMs:START+7*86400000};
const DAY="2026-10-27",ACCOUNT="07701234567",UID_A="uid_phone_A",
  UID_B="uid_phone_B",TASK="traffic_skills";
const INSTALL_A="trusted_install_A", INSTALL_B="trusted_install_B";
const SAVED_ENV={
  FIRESTORE_EMULATOR_HOST:process.env.FIRESTORE_EMULATOR_HOST,
  GCLOUD_PROJECT:process.env.GCLOUD_PROJECT,
};
function env() {
  process.env.FIRESTORE_EMULATOR_HOST="127.0.0.1:8765";
  process.env.GCLOUD_PROJECT=PROJECT;
}
function restoreEnv() {
  for(const [k,v] of Object.entries(SAVED_ENV)) {
    if(v===undefined)delete process.env[k];else process.env[k]=v;
  }
}
test.after(restoreEnv);
function request(uid=UID_A) {
  return {auth:{uid},app:{appId:"verified_test_firebase_appcheck"},data:{}};
}
function props(taskId=TASK,serverNowMs=NOW,uid=UID_A) {
  return {db:null,request:request(uid),weekConfig:WEEK,serverNowMs,
    serverTaskId:taskId};
}
function setupMap() {
  const m=new Map();
  for(const [uid,install] of [[UID_A,INSTALL_A],[UID_B,INSTALL_B]]) {
    m.set("users/"+uid,{uid,accountKey:ACCOUNT});
    m.set("deda_sessions/"+uid,{uid,accountKey:ACCOUNT,installId:install});
    m.set("deda_weekly_identity_attestations/"+uid,{
      issuer:"privileged_identity_verifier_v1",state:"verified",
      uid,accountKey:ACCOUNT,installId:install,
      issuedAtMs:NOW-6000,expiresAtMs:NOW+6000,
    });
  }
  m.set("deda_account_profiles/"+ACCOUNT,{accountKey:ACCOUNT,
    trustedInstallIds:[INSTALL_A,INSTALL_B]});
  m.set("users/"+UID_A+"/original_account_wallet",{
    diamonds:999,xp:4567,taskPoints:888,
  });
  return m;
}
function fixtureProof(m,{taskId=TASK,at=NOW-3000,dayId=DAY,
  accountKey=ACCOUNT,issuer="emulator_fixture_only_verified_task_v1",
  xpApplied=true,pointsAwarded=true,amount=20,weekId=WEEK.weekId}={}) {
  const eventId=opaqueReceiptId({accountKey,dayId,taskId});
  m.set(ROOT.proof+"/"+eventId,{
    issuer,status:"emulator_task_and_xp_confirmed",accountKey,dayId,
    taskId,eventId,weekId,
    taskPointsAwarded:pointsAwarded,levelXpApplied:xpApplied,
    levelXpAmount:amount,verifiedAtMs:at,
  });
  return eventId;
}
function memoryDb(records) {
  let critical=Promise.resolve();
  const written=[];
  const db={
    written,
    doc(path) {
      return {
        path,
        async get() {
          const d=records.get(path);
          return d===undefined?{exists:false}:{
            exists:true,data:()=>structuredClone(d),
          };
        },
      };
    },
    async runTransaction(callback) {
      let release;
      const predecessor=critical;
      critical=new Promise(r=>{release=r;});
      await predecessor;
      try {
        const pending=[];
        const tx={
          get:(ref)=>db.doc(ref.path).get(),
          create:(ref,value)=>pending.push(["create",ref.path,
            structuredClone(value)]),
          set:(ref,value)=>pending.push(["set",ref.path,
            structuredClone(value)]),
        };
        const result=await callback(tx);
        for(const [type,path,value] of pending) {
          if(type==="create"&&records.has(path))throw Error("conflict");
          if(!path.startsWith("deda_weekly_stage9_shadow_"))
            throw Error("real_user_balance_write_denied");
          records.set(path,value);written.push({type,path});
        }
        return result;
      } finally {release();}
    },
  };
  return db;
}
test("fail closed unless exact emulator host AND project; no native Firebase/wallet",async()=>{
  const m=setupMap();fixtureProof(m);
  const db=memoryDb(m);
  const base={...props(),db};
  delete process.env.FIRESTORE_EMULATOR_HOST;
  await assert.rejects(simulateAtomicShadowTaskXp(base),/emulator_only_do_not_pay/);
  env();process.env.GCLOUD_PROJECT="deda-25b88";
  await assert.rejects(simulateAtomicShadowTaskXp(base),/emulator_only_do_not_pay/);
  env();
  const valid=await simulateAtomicShadowTaskXp(base);
  assert.equal(valid.outcome,"shadow_recorded");
  assert.equal(valid.shadowOnly,true);
  assert.equal(db.written.length,3);
});
test("one verified daily task creates exactly +20 isolated shadow XP and no real balances",async()=>{
  env();
  const m=setupMap(),id=fixtureProof(m),initialWallet=
    structuredClone(m.get("users/"+UID_A+"/original_account_wallet"));
  const db=memoryDb(m);
  const result=await simulateAtomicShadowTaskXp({...props(),db});
  assert.deepEqual({
    outcome:result.outcome,amount:result.shadowXpAdded,shadowOnly:result.shadowOnly,
  },{outcome:"shadow_recorded",amount:20,shadowOnly:true});
  assert.equal(result.receiptId,id);
  assert.deepEqual(m.get("users/"+UID_A+"/original_account_wallet"),initialWallet);
  assert.deepEqual(db.written.map(x=>x.type),["create","set","set"]);
  assert.ok(db.written.every(x=>x.path.startsWith("deda_weekly_stage9_shadow_")));
  assert.equal(m.get(ROOT.receipt+"/"+id).issuer,
    "emulator_only_weekly_xp_shadow_v1");
  assert.equal(m.get(ROOT.receipt+"/"+id).shadowOnly,true);
});
test("same canonical user switching UID/phone cannot double credit a task",async()=>{
  env();const m=setupMap();fixtureProof(m);
  const db=memoryDb(m);
  const [first,second]=await Promise.all([
    simulateAtomicShadowTaskXp({...props(),db}),
    simulateAtomicShadowTaskXp({...props(TASK,NOW,UID_B),db}),
  ]);
  assert.deepEqual([first.outcome,second.outcome].sort(),
    ["already_recorded","shadow_recorded"]);
  const records=[...m.entries()].filter(([key])=>key.startsWith(ROOT.receipt+"/"));
  assert.equal(records.length,1);
});
test("same task cannot be counted via device time, missing XP, or ordinary 5 points",async()=>{
  env();
  for(const change of [{xpApplied:false},{pointsAwarded:false},
    {amount:5},{issuer:"client_said_completed"},{dayId:"2026-10-26"},
    {at:NOW+1},{weekId:"different_week"}]) {
    const m=setupMap();fixtureProof(m,change);const db=memoryDb(m);
    await assert.rejects(simulateAtomicShadowTaskXp({...props(),db}),
      /missing_privileged_task_proof/);
    assert.equal(db.written.length,0);
  }
});
test("task proof must be server-owned; no XP from traffic answers or device totals",async()=>{
  env();const db=memoryDb(setupMap());
  for(const data of [{xp:99999},{taskPoints:5},{score:50},{taskId:TASK},
    {accountKey:ACCOUNT},{wallet:123},{weekId:WEEK.weekId}]) {
    await assert.rejects(simulateAtomicShadowTaskXp({
      ...props(),db,request:{...request(),data},
    }),/client_input_forbidden/);
  }
  assert.equal(db.written.length,0);
});
test("two distinct daily tasks count 40 XP in isolated shadow weekly totals",async()=>{
  env();const m=setupMap();fixtureProof(m);
  fixtureProof(m,{taskId:"open_map"});
  const db=memoryDb(m);
  await simulateAtomicShadowTaskXp({...props(),db});
  const result=await simulateAtomicShadowTaskXp({
    ...props("open_map"),db,
  });
  assert.equal(result.shadowXpAdded,20);
  const totals=[...m.entries()].filter(([key])=>key.startsWith(ROOT.week+"/"));
  assert.equal(totals.length,1);
  assert.deepEqual({xp:totals[0][1].xp,count:totals[0][1].count},
    {xp:40,count:2});
});
test("no 9th eligible daily task: refuses exceeding signed task count",async()=>{
  env();const m=setupMap();
  const db=memoryDb(m);
  for(let i=1;i<=8;i++){
    fixtureProof(m,{taskId:"test_task_"+i});
    assert.equal((await simulateAtomicShadowTaskXp({...props("test_task_"+i),db}))
      .shadowXpAdded,20);
  }
  fixtureProof(m,{taskId:"test_task_9"});
  await assert.rejects(simulateAtomicShadowTaskXp({
    ...props("test_task_9"),db}),/daily_claim_limit/);
  assert.equal([...m.keys()].filter(x=>x.startsWith(ROOT.receipt+"/")).length,8);
});
test("bad authenticated session, expired attestation and app check never award",async()=>{
  env();
  for(const forged of [
    request("different_anonymous_uid"),
    {auth:{uid:UID_A},data:{}},
    {app:{appId:"verified_test_firebase_appcheck"},data:{}},
  ]) {
    const m=setupMap();fixtureProof(m);const db=memoryDb(m);
    await assert.rejects(simulateAtomicShadowTaskXp({
      ...props(),db,request:forged,
    }),/WEEKLY_READ_ONLY_BLOCK_/);
    assert.equal(db.written.length,0);
  }
});
test("owner must configure seven-day week on server; no unapproved day boundary",async()=>{
  env();const m=setupMap();fixtureProof(m);const db=memoryDb(m);
  await assert.rejects(simulateAtomicShadowTaskXp({
    ...props(),db,weekConfig:{...WEEK,endMs:WEEK.endMs-1000},
  }),/week_duration/);
  await assert.rejects(simulateAtomicShadowTaskXp({
    ...props(),db,serverNowMs:WEEK.endMs,
  }),/not_active_week|fresh_privileged_attestation_required/);
});
test("no XP credited from a missing proof even when task id is eligible",async()=>{
  env();const db=memoryDb(setupMap());
  await assert.rejects(simulateAtomicShadowTaskXp({...props(),db}),
    /missing_privileged_task_proof/);
  assert.equal(db.written.length,0);
});
