"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore,Timestamp}=require("firebase-admin/firestore");
const {inspectOriginalDedaPersonalLocationShare:inspectShare}=
  require("../deda_weekly_stage30_original_share_evidence_NOT_EXPORTED.js");
const {opaqueReceiptId}=
  require("../deda_weekly_owner_receipt_gate_NOT_EXPORTED.js");
const {simulateAtomicShadowTaskXp,ROOT}=
  require("../deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const {previewWeekFromAtomicShadowXp}=
  require("../deda_weekly_stage29_task_to_rank_emulator_NOT_EXPORTED.js");
const {PROJECT,ACTION_ROOT,SOURCE_ISSUER,SOURCES,
  simulateStage30ProofFromServerAction:verifyAction}=
  require("../deda_weekly_stage30_server_action_proof_emulator_NOT_EXPORTED.js");

if(process.env.GCLOUD_PROJECT!==PROJECT ||
   !process.env.FIRESTORE_EMULATOR_HOST){
  throw Error("STAGE30_DEDICATED_REAL_FIRESTORE_EMULATOR_ONLY");
}
const APP=initializeApp({projectId:PROJECT},"deda-stage30-real-emulator-only");
const db=getFirestore(APP);
const SECRET=Buffer.alloc(32,95);
const START=Date.UTC(2026,9,26,21);
const NOW=Date.UTC(2026,9,27,11);
const WEEK={weekId:"owner-test-week-20261026",
  startMs:START,endMs:START+7*86400000};
const NEXT={weekId:"owner-test-week-20261102",
  startMs:WEEK.endMs,endMs:WEEK.endMs+7*86400000};
const A="07701234567",B="07707654321";
const UIDS=[["user_a_phone1",A,"phone1"],
  ["user_a_phone2",A,"phone2"],["user_b",B,"phone_b"]];
const ORIGINALS={
  levelXp:1250,earnedDiamonds:999999,taskPoints:290,level:6,
};
function request(uid){
  return {auth:{uid},app:{appId:"firebase_app_check_fixture_only"},data:{}};
}
function actionRef(account,task,day="2026-10-27"){
  return opaqueReceiptId({accountKey:account,dayId:day,taskId:task});
}
async function installTrustedSource(account,task,
    {day="2026-10-27",week=WEEK,at=NOW-2000,changes={}}={}){
  const id=actionRef(account,task,day);
  await db.doc(ACTION_ROOT+"/"+id).set({
    issuer:SOURCE_ISSUER,source:SOURCES[task],
    status:"committed",emulatorOnly:true,
    accountKey:account,taskId:task,dayId:day,
    weekId:week.weekId,eventId:id,
    verifiedAtMs:at,taskPointsAwarded:true,
    levelXpApplied:true,levelXpAmount:20,...changes,
  });
  return id;
}
function verify(uid,task,now=NOW,week=WEEK){
  return verifyAction({
    db,request:request(uid),serverNowMs:now,
    serverTaskId:task,weekConfig:week,
  });
}
function issue(uid,task,now=NOW,week=WEEK){
  return simulateAtomicShadowTaskXp({
    db,request:request(uid),serverNowMs:now,
    serverTaskId:task,weekConfig:week,
  });
}
function ranks(uid="user_a_phone1",now=NOW,week=WEEK){
  return previewWeekFromAtomicShadowXp({
    db,request:request(uid),serverNowMs:now,
    weekConfig:week,backendSecret:SECRET,
  });
}
async function nextSession(now){
  const batch=db.batch();
  for(const [uid,account,install] of UIDS){
    batch.set(db.doc("deda_weekly_identity_attestations/"+uid),{
      issuer:"privileged_identity_verifier_v1",
      state:"verified",uid,accountKey:account,installId:install,
      issuedAtMs:now-1000,expiresAtMs:now+150000,
    });
  }
  await batch.commit();
}
test.before(async()=>{
  const batch=db.batch();
  for(const [uid,account,install] of UIDS){
    batch.set(db.doc("users/"+uid),{uid,accountKey:account,
      sharePersonalId:account===A?"@DEDA-A12345":"@DEDA-B12345"});
    batch.set(db.doc("deda_sessions/"+uid),{
      uid,accountKey:account,installId:install,
    });
  }
  batch.set(db.doc("deda_account_profiles/"+A),{
    accountKey:A,trustedInstallIds:["phone1","phone2"],
  });
  batch.set(db.doc("deda_account_profiles/"+B),{
    accountKey:B,trustedInstallIds:["phone_b"],
  });
  batch.set(db.doc("deda_share_ids/@DEDA-A12345"),{
    active:true,kind:"personal",ownerUid:"user_a_phone1",
  });
  batch.set(db.doc("deda_share_ids/@DEDA-B12345"),{
    active:true,kind:"personal",ownerUid:"user_b",
  });
  batch.set(db.doc("users/user_a_phone1/wallet/original"),ORIGINALS);
  batch.set(db.doc("deda_admin_diamond_wallets/manager"),{
    diamonds:1000000,
  });
  await batch.commit();
  await nextSession(NOW);
});
test.after(async()=>{await deleteApp(APP);});
test("untrusted app/UID and unsupported local-only task fail BEFORE creating a proof",async()=>{
  await assert.rejects(verifyAction({
    db,request:request("user_a_phone1"),
    serverNowMs:NOW,weekConfig:WEEK,
    serverTaskId:"open_map",
  }),/no_trusted_action_issuer_for_task/);
  await assert.rejects(verifyAction({
    db,request:{...request("user_a_phone1"),data:{xp:100000}},
    serverNowMs:NOW,weekConfig:WEEK,
    serverTaskId:"share_personal_location",
  }),/WEEKLY_READ_ONLY_BLOCK_/);
  await assert.rejects(verifyAction({
    db,request:{auth:{uid:"user_a_phone1"},data:{}},
    serverNowMs:NOW,weekConfig:WEEK,
    serverTaskId:"share_personal_location",
  }),/WEEKLY_READ_ONLY_BLOCK_/);
  const id=actionRef(A,"share_personal_location");
  assert.equal((await db.doc(ROOT.proof+"/"+id).get()).exists,false);
});
test("missing backend-confirmed event refuses +20, no mere UI click proof",async()=>{
  await assert.rejects(verify("user_a_phone1","share_personal_location"),
    /no_privileged_committed_action_evidence/);
  await assert.rejects(issue("user_a_phone1","share_personal_location"),
    /missing_privileged_task_proof/);
});
test("server action needs exact canonical owner, week, time and original level XP proof",async()=>{
  for(const change of [
    {levelXpApplied:false},{levelXpAmount:5},
    {taskPointsAwarded:false},{accountKey:B},{source:"client_button_clicked"},
    {issuer:"submitted_from_mobile"},{weekId:NEXT.weekId},
    {verifiedAtMs:NOW+100000},{emulatorOnly:false},
  ]){
    await installTrustedSource(A,"share_personal_location",{changes:change});
    await assert.rejects(verify("user_a_phone1","share_personal_location"),
      /no_privileged_committed_action_evidence/);
  }
  await db.doc(ACTION_ROOT+"/"+actionRef(A,"share_personal_location")).delete();
});
test("one trusted event -> proof -> +20 atomic shadow XP -> SAME player and GM preview",async()=>{
  await installTrustedSource(A,"share_personal_location");
  const original=(await db.doc("users/user_a_phone1/wallet/original").get()).data();
  const manager=(await db.doc("deda_admin_diamond_wallets/manager").get()).data();
  const before=await db.doc(ROOT.receipt+"/"+actionRef(A,"share_personal_location")).get();
  assert.equal(before.exists,false);
  const p=await verify("user_a_phone1","share_personal_location");
  assert.deepEqual({outcome:p.outcome,proofCreated:p.proofCreated},
    {outcome:"proof_recorded",proofCreated:true});
  const award=await issue("user_a_phone1","share_personal_location");
  assert.equal(award.outcome,"shadow_recorded");
  assert.equal(award.shadowXpAdded,20);
  const view=await ranks();
  assert.equal(view.rows.length,1);
  assert.equal(view.rows[0].weeklyXp,20);
  assert.equal(view.competitorView.myRank,1);
  assert.deepEqual(view.competitorView.rows,view.managerPreview.rows);
  assert.equal(view.managerPreview.approvalEnabled,false);
  assert.equal(view.payoutEnabled,false);
  assert.equal(view.verifiedRealXp,false);
  assert.deepEqual((await db.doc("users/user_a_phone1/wallet/original").get()).data(),original);
  assert.deepEqual((await db.doc("deda_admin_diamond_wallets/manager").get()).data(),manager);
});
test("two phones same canonical account: concurrent proof and claim cannot double award",async()=>{
  const two=await Promise.all([
    verify("user_a_phone1","share_personal_location"),
    verify("user_a_phone2","share_personal_location"),
  ]);
  assert.deepEqual(two.map(x=>x.outcome).sort(),
    ["already_proven","already_proven"]);
  const [a,b]=await Promise.all([
    issue("user_a_phone1","share_personal_location"),
    issue("user_a_phone2","share_personal_location"),
  ]);
  assert.equal(a.shadowXpAdded+b.shadowXpAdded,0);
  assert.equal((await ranks()).rows[0].weeklyXp,20);
});
test("second real-shaped account: 2 tasks vs 1 = 40/20 XP; same admin and both players",async()=>{
  await installTrustedSource(B,"share_personal_location");
  await installTrustedSource(A,"share_registered_place");
  assert.equal((await verify("user_b","share_personal_location")).outcome,"proof_recorded");
  assert.equal((await verify("user_a_phone2","share_registered_place")).outcome,"proof_recorded");
  await issue("user_b","share_personal_location");
  await issue("user_a_phone2","share_registered_place");
  const va=await ranks("user_a_phone1");
  const vb=await ranks("user_b");
  assert.deepEqual(va.rows.map(x=>x.weeklyXp),[40,20]);
  assert.deepEqual(va.rows.map(x=>x.plannedPrizeDiamonds),[150,100]);
  assert.equal(va.competitorView.myRank,1);
  assert.equal(vb.competitorView.myRank,2);
  assert.deepEqual(va.managerPreview.rows,vb.managerPreview.rows);
  assert.ok(!JSON.stringify(va).includes(A));
  assert.ok(!JSON.stringify(va).includes(B));
});
test("new week immediately resets weekly ranks, not original level or diamonds",async()=>{
  const time=NEXT.startMs+2000;
  await nextSession(time);
  const next=await ranks("user_a_phone1",time,NEXT);
  assert.equal(next.rows.length,0);
  assert.equal(next.state,"active");
  const old=await ranks("user_a_phone1",time,WEEK);
  assert.equal(old.state,"closed");
  assert.deepEqual(old.rows.map(x=>x.weeklyXp),[40,20]);
  assert.equal((await db.doc("users/user_a_phone1/wallet/original").get()).get("levelXp"),1250);
});
const SHARE_ID="abcdefghijklmnopqrst";
function realShare(overrides={}){
  const created=Timestamp.fromMillis(NOW-2500);
  return {
    senderUid:"user_a_phone1",
    senderPublicId:"@DEDA-A12345",
    recipientPublicId:"@DEDA-B12345",
    shareType:"current",status:"pending",
    senderName:"صاحب الحساب",placeId:"",placeName:"",
    latitude:35.1,longitude:44.2,durationMinutes:15,
    createdAt:created,updatedAt:created,
    expiresAt:Timestamp.fromMillis(NOW+14*60*1000),
    ...overrides,
  };
}
function inspectOriginalShare(){
  return inspectShare({
    db,shareId:SHARE_ID,weekConfig:WEEK,serverNowMs:NOW,
  });
}
test("inspect real-shaped original DEDA location share: server identity and ID only, NOT XP",async()=>{
  await db.doc("deda_location_shares/"+SHARE_ID).set(realShare());
  const candidate=await inspectOriginalShare();
  assert.equal(candidate.sourceCollection,"deda_location_shares");
  assert.equal(candidate.taskId,"share_personal_location");
  assert.equal(candidate.canonicalAccountKey,A);
  assert.equal(candidate.privateServerCandidateOnly,true);
  assert.equal(candidate.originalLevelXpApplied,false);
  assert.equal(candidate.verifiedTaskXpReceipt,false);
  assert.equal(candidate.allowedToPay,false);
  assert.equal((await db.doc(ROOT.proof+"/"+actionRef(A,"share_personal_location")).get())
    .exists,true);
  // No new duplicate Stage9 XP is caused by merely observing the source.
  const score=(await ranks()).rows.find(x=>x.weeklyXp===40);
  assert.ok(score);
});
test("wrong sender, premium alias, forged timestamp or place-share cannot prove original share",async()=>{
  for(const changes of [
    {senderUid:"user_b"},{senderPublicId:"@DEDA-IRAQI"},
    {senderPublicId:"@DEDA-B12345"},
    {shareType:"place"},{status:"accepted"},
    {placeId:"owned_place_fake"},{latitude:999},
    {updatedAt:Timestamp.fromMillis(NOW+300)},
  ]){
    await db.doc("deda_location_shares/"+SHARE_ID).set(realShare(changes));
    await assert.rejects(inspectOriginalShare(),
      /DEDA_ORIGINAL_SHARE_TASK_BLOCK_/);
  }
  await db.doc("deda_location_shares/"+SHARE_ID).set(realShare());
});

test("Firestore clients cannot directly forge staged action, proof or XP receipt",async()=>{
  const base="http://127.0.0.1:8080/v1/projects/"+
    PROJECT+"/databases/(default)/documents/";
  const paths=[
    ACTION_ROOT+"/external_attack",
    ROOT.proof+"/external_attack",
    ROOT.receipt+"/external_attack",
    "users/user_a_phone1/wallet/original",
  ];
  for(const path of paths){
    const url=base+path;
    const write=await fetch(url,{
      method:"PATCH",
      headers:{"Content-Type":"application/json"},
      body:JSON.stringify({fields:{xp:{integerValue:"9999999"}}}),
    });
    assert.ok([401,403].includes(write.status),
      "raw Firestore client write unexpectedly permitted: "+path+
      " status="+write.status+" body="+(await write.text()).slice(0,240));
    const read=await fetch(url);
    assert.ok([401,403].includes(read.status),
      "raw unauthenticated read unexpectedly permitted: "+path+
      " status="+read.status+" body="+(await read.text()).slice(0,240));
  }
});
