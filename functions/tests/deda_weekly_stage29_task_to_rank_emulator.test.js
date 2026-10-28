"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {simulateAtomicShadowTaskXp,ROOT,PROJECT}=
  require("../deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const {opaqueReceiptId}=
  require("../deda_weekly_owner_receipt_gate_NOT_EXPORTED.js");
const {ISSUER,previewWeekFromAtomicShadowXp}=
  require("../deda_weekly_stage29_task_to_rank_emulator_NOT_EXPORTED.js");

const START=Date.UTC(2026,9,26,21),NOW=Date.UTC(2026,9,27,11);
const WEEK={weekId:"owner-calendar-week-test-1",
  startMs:START,endMs:START+7*86400000};
const NEXT={weekId:"owner-calendar-week-test-2",
  startMs:WEEK.endMs,endMs:WEEK.endMs+7*86400000};
const A="07701234567", B="07707654321";
const SECRET=Buffer.alloc(32,73);
const UIDS=[["uid_a1",A,"install_a1"],["uid_a2",A,"install_a2"],
  ["uid_b",B,"install_b"]];
const ORIGINAL_ENV={
  GCLOUD_PROJECT:process.env.GCLOUD_PROJECT,
  FIRESTORE_EMULATOR_HOST:process.env.FIRESTORE_EMULATOR_HOST,
};
function emulator(){
  process.env.GCLOUD_PROJECT=PROJECT;
  process.env.FIRESTORE_EMULATOR_HOST="127.0.0.1:8080";
}
test.after(()=>{
  for(const [k,v] of Object.entries(ORIGINAL_ENV)){
    if(v===undefined)delete process.env[k];else process.env[k]=v;
  }
});
function request(uid){
  return {auth:{uid},app:{appId:"stage29_test_verified_appcheck"},data:{}};
}
function memoryDb(m){
  let lane=Promise.resolve();
  const written=[];
  const db={
    written,
    doc(path){
      return {
        path,async get(){
          const d=m.get(path);
          return d===undefined?{exists:false}:{exists:true,
            data:()=>structuredClone(d)};
        },
      };
    },
    collection(path){
      assert.equal(path,ROOT.receipt);
      return {async get(){
        return {docs:[...m.entries()]
          .filter(([k])=>k.startsWith(path+"/"))
          .map(([k,v])=>({id:k.slice(path.length+1),
            data:()=>structuredClone(v)}))};
      }};
    },
    async runTransaction(fn){
      let release;
      const prior=lane;
      lane=new Promise(resolve=>{release=resolve;});
      await prior;
      try{
        const writes=[];
        const tx={
          get:ref=>db.doc(ref.path).get(),
          create:(ref,data)=>writes.push(["create",ref.path,
            structuredClone(data)]),
          set:(ref,data)=>writes.push(["set",ref.path,
            structuredClone(data)]),
        };
        const value=await fn(tx);
        for(const [op,path,data] of writes){
          if(!path.startsWith("deda_weekly_stage9_shadow_"))
            throw Error("unsafe_non_shadow_write");
          if(op==="create"&&m.has(path))throw Error("duplicate_create");
          m.set(path,data);written.push({op,path});
        }
        return value;
      }finally{release();}
    },
  };
  return db;
}
function freshDatabase(){
  const m=new Map();
  for(const [uid,account,install] of UIDS){
    m.set("users/"+uid,{uid,accountKey:account});
    m.set("deda_sessions/"+uid,{uid,accountKey:account,installId:install});
    m.set("deda_weekly_identity_attestations/"+uid,{
      issuer:"privileged_identity_verifier_v1",state:"verified",
      uid,accountKey:account,installId:install,
      issuedAtMs:NOW-10000,expiresAtMs:NOW+100000,
    });
  }
  m.set("deda_account_profiles/"+A,{accountKey:A,
    trustedInstallIds:["install_a1","install_a2"]});
  m.set("deda_account_profiles/"+B,{accountKey:B,
    trustedInstallIds:["install_b"]});
  m.set("users/uid_a1/original_wallet",{
    diamonds:999999,levelXp:1000,taskPoints:500,
  });
  m.set("users/uid_b/original_wallet",{
    diamonds:123,levelXp:250,taskPoints:60,
  });
  return {m,db:memoryDb(m)};
}
function proof(m,account,task,at=NOW-3000,week=WEEK){
  const day="2026-10-27";
  const id=opaqueReceiptId({accountKey:account,dayId:day,taskId:task});
  m.set(ROOT.proof+"/"+id,{
    issuer:"emulator_fixture_only_verified_task_v1",
    status:"emulator_task_and_xp_confirmed",
    accountKey:account,dayId:day,taskId:task,eventId:id,
    weekId:week.weekId,taskPointsAwarded:true,
    levelXpApplied:true,levelXpAmount:20,verifiedAtMs:at,
  });
  return id;
}
async function claim(db,uid,task,now=NOW,week=WEEK){
  return simulateAtomicShadowTaskXp({
    db,request:request(uid),weekConfig:week,
    serverNowMs:now,serverTaskId:task,
  });
}
function projection(db,uid="uid_a1",now=NOW,week=WEEK){
  return previewWeekFromAtomicShadowXp({
    db,weekConfig:week,serverNowMs:now,
    backendSecret:SECRET,request:request(uid),
  });
}

test("two real-shaped account identities: receipts -> ONE sorted competitor/manager preview",async()=>{
  emulator();
  const {m,db}=freshDatabase();
  const before=[structuredClone(m.get("users/uid_a1/original_wallet")),
    structuredClone(m.get("users/uid_b/original_wallet"))];
  proof(m,A,"open_map");
  proof(m,A,"traffic_skills",NOW-2000);
  proof(m,B,"share_personal_location",NOW-1000);
  assert.equal((await claim(db,"uid_a1","open_map")).shadowXpAdded,20);
  assert.equal((await claim(db,"uid_a2","traffic_skills")).shadowXpAdded,20);
  assert.equal((await claim(db,"uid_b","share_personal_location")).shadowXpAdded,20);
  const first=await projection(db,"uid_a1");
  const second=await projection(db,"uid_b");
  assert.equal(first.issuer,ISSUER);
  assert.equal(first.previewOnly,true);
  assert.equal(first.verifiedRealXp,false);
  assert.equal(first.payoutEnabled,false);
  assert.equal(first.adminAuthorizationVerified,false);
  assert.equal(first.competitorView.myRank,1);
  assert.equal(second.competitorView.myRank,2);
  assert.deepEqual(first.managerPreview.rows,first.rows);
  assert.deepEqual(first.managerPreview.rows,second.rows);
  assert.equal(first.rows.length,2);
  assert.deepEqual(first.rows.map(r=>r.weeklyXp),[40,20]);
  assert.deepEqual(first.rows.map(r=>r.plannedPrizeDiamonds),[150,100]);
  assert.equal(first.managerPreview.approvalEnabled,false);
  assert.deepEqual(m.get("users/uid_a1/original_wallet"),before[0]);
  assert.deepEqual(m.get("users/uid_b/original_wallet"),before[1]);
  assert.ok(db.written.every(x=>x.path.startsWith("deda_weekly_stage9_shadow_")));
  const json=JSON.stringify(first);
  for(const privateData of [A,B,"uid_a1","uid_b","install_a1","@DEDA-IRAQI"]){
    assert.ok(!json.includes(privateData),"private identity leaked");
  }
});
test("same canonical account on two devices cannot create duplicate receipt/rank",async()=>{
  emulator();
  const {m,db}=freshDatabase();proof(m,A,"open_map");
  const two=await Promise.all([
    claim(db,"uid_a1","open_map"),
    claim(db,"uid_a2","open_map"),
  ]);
  assert.deepEqual(two.map(x=>x.outcome).sort(),[
    "already_recorded","shadow_recorded"]);
  const view=await projection(db,"uid_a2");
  assert.equal(view.rows.length,1);
  assert.equal(view.rows[0].weeklyXp,20);
});
test("local +5 points, forged proof, changed premium alias NEVER count",async()=>{
  emulator();
  const {m,db}=freshDatabase();
  m.set("users/uid_a1/local_task_award",{points:5,
    fakeDailyXp:100000,activeId:"@DEDA-IRAQI"});
  await assert.rejects(claim(db,"uid_a1","open_map"),
    /missing_privileged_task_proof/);
  assert.equal((await projection(db)).rows.length,0);
  proof(m,A,"open_map");
  await claim(db,"uid_a1","open_map");
  const view=await projection(db);
  assert.equal(view.rows[0].weeklyXp,20);
  const bad={...m.get(ROOT.receipt+"/"+opaqueReceiptId({
    accountKey:A,dayId:"2026-10-27",taskId:"open_map",
  })),amount:5};
  m.set(ROOT.receipt+"/"+bad.eventId,bad);
  await assert.rejects(projection(db),/untrusted_shadow_receipt/);
});
test("untrusted identity, forged scores, and production credentials fail before reads",async()=>{
  emulator();const {m,db}=freshDatabase();
  const normal={db,serverNowMs:NOW,weekConfig:WEEK,backendSecret:SECRET};
  for(const bad of [
    {...normal,request:{...request("uid_a1"),data:{xp:999}}},
    {...normal,request:{...request("uid_a1"),data:{weekId:WEEK.weekId}}},
    {...normal,request:{...request("uid_a1"),data:{premiumId:"@DEDA-IRAQI"}}},
    {...normal,request:{auth:{uid:"uid_a1"},data:{}}},
    {...normal,request:request("unknown_uid")},
  ])await assert.rejects(previewWeekFromAtomicShadowXp(bad),
    /WEEKLY_READ_ONLY_BLOCK_/);
  const before=m.size;
  delete process.env.FIRESTORE_EMULATOR_HOST;
  await assert.rejects(projection(db),/emulator_only/);
  emulator();process.env.GCLOUD_PROJECT="deda-25b88";
  await assert.rejects(projection(db),/emulator_only/);
  assert.equal(m.size,before);
});
test("second week begins immediately, rankings reset without resetting original XP",async()=>{
  emulator();const {m,db}=freshDatabase();
  proof(m,A,"open_map");await claim(db,"uid_a1","open_map");
  const time=NEXT.startMs+500;
  for(const [uid,account,install] of UIDS){
    m.set("deda_weekly_identity_attestations/"+uid,{
      issuer:"privileged_identity_verifier_v1",state:"verified",
      uid,accountKey:account,installId:install,
      issuedAtMs:time-100,expiresAtMs:time+60000,
    });
  }
  const next=await projection(db,"uid_a1",time,NEXT);
  assert.equal(next.state,"active");
  assert.equal(next.rows.length,0);
  const old=await projection(db,"uid_a1",time,WEEK);
  assert.equal(old.state,"closed");
  assert.equal(old.rows[0].weeklyXp,20);
  assert.equal(m.get("users/uid_a1/original_wallet").levelXp,1000);
});
test("malformed fake shadow receipt blocks all rows; no partial winners",async()=>{
  emulator();const {m,db}=freshDatabase();
  proof(m,A,"open_map");await claim(db,"uid_a1","open_map");
  m.set(ROOT.receipt+"/fake",{
    eventId:"fake",issuer:"emulator_only_weekly_xp_shadow_v1",
    shadowOnly:true,weekId:WEEK.weekId,accountKey:B,amount:20,
    taskId:"open_map",dayId:"2026-10-27",
    verifiedAtMs:NOW-1,createdAtMs:NOW,
  });
  await assert.rejects(projection(db),/untrusted_shadow_receipt/);
});
test("no backend-only HMAC secret means no preview; no diamond credit",async()=>{
  emulator();
  const {db}=freshDatabase();
  await assert.rejects(previewWeekFromAtomicShadowXp({
    db,weekConfig:WEEK,serverNowMs:NOW,
    backendSecret:Buffer.alloc(10,1),request:request("uid_a1"),
  }),/backend_secret_missing/);
  assert.equal(db.written.length,0);
});
