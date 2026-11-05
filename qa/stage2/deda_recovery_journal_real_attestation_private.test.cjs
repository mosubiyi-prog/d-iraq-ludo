"use strict";

const test=require("node:test");
const assert=require("node:assert/strict");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore,Timestamp}=require("firebase-admin/firestore");
const {getAuth}=require("firebase-admin/auth");
const {__privateVerifiedCompletionForQaOnly:complete}=require(
  "../../functions/deda_recovery_journal_completion_private_v1.js");

const project="demo-deda-100436-journal-qa";
const account="9647712345702";
const uid="stage2-journal-original-uid";
const originalId="@DEDA-QA2345";
const captureId="qa_stage2_original_capture_20261105";
const install="b".repeat(48);
const intentId="stage2_original_guardian_intent_01";
const placeId="published_stage2_001";
const levelRaw='{"version":1,"completions":{},"awards":{},"ledger":[]}';
const frames=["FRAME_03","FRAME_05","FRAME_06","FRAME_07","FRAME_08",
  "FRAME_09","FRAME_10","FRAME_11","FRAME_12","FRAME_13",
  "FRAME_14","FRAME_15","FRAME_16"];
function label(prefix,parts){
  let a=0x811c9dc5,b=0x9e3779b9;
  for(const byte of Buffer.from(parts,"utf8")){
    a=Math.imul(a^byte,16777619)>>>0;
    b=Math.imul(b^byte,2246822519)>>>0;
  }
  return prefix+"_"+a.toString(16).padStart(8,"0")+
    b.toString(16).padStart(8,"0");
}
function request(code,receiptId,asUid=uid){
  const op="deda_guardian_v1/"+uid+"/"+intentId+"/"+code;
  return {
    app:{appId:"synthetic-emulator-appcheck"},
    auth:{uid:asUid,token:{email:account+"@deda-login.invalid",
      firebase:{sign_in_provider:"password"}}},
    data:{accountKey:account,originalUid:uid,originalId,intentId,code,
      operationKey:op,receiptId},
  };
}
function validReceipt(code){
  switch(code){
    case "originalBackupReadback":
      return label("progress",captureId+"|"+install);
    case "purchaseBackupReadback":
      return label("purchases",captureId+"|"+install);
    case "levelPointsRestore":
      return label("level",captureId+"|0");
    case "publishedPlaceRecovery":
      return label("published_place",placeId);
  }
  throw Error("unreviewed-code");
}
const codes=["originalBackupReadback","purchaseBackupReadback",
  "levelPointsRestore","publishedPlaceRecovery"];

test("real Firestore emulator: four server-domain attestations, same UID, idempotency and denied forgery",{
  timeout:120000,
},async()=>{
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST,"127.0.0.1:8098");
  assert.equal(process.env.FUNCTIONS_EMULATOR,"true");
  assert.equal(process.env.DEDA_RECOVERY_JOURNAL_SERVER_ENABLED,"true");
  const app=initializeApp({projectId:project},"stage2-journal-real-emulator");
  try {
    const db=getFirestore(app),auth=getAuth(app),stamp=Timestamp.now();
    await auth.createUser({uid,email:account+"@deda-login.invalid",
      password:"123456"});
    await Promise.all([
      db.doc("deda_account_directory/"+account).set({
        accountKey:account,createdUid:uid,active:true,
      }),
      db.doc("users/"+uid).set({
        accountKey:account,sharePersonalId:originalId,
      }),
      db.doc("deda_share_ids/"+originalId).set({
        publicId:originalId,kind:"personal",ownerUid:uid,active:true,
      }),
      db.doc("deda_sessions/"+uid).set({
        uid,accountKey:account,installId:install,
        signedInAt:stamp,lastSeenAt:stamp,
      }),
      db.doc("deda_progress_evidence/"+account+
          "/captures/"+captureId).set({
        format:1,kind:"legacy-local-evidence",accountKey:account,
        sourceUid:uid,installId:install,captureId,
        records:{taskPoints:levelRaw,socialCoinsAndXp:null,
          earnedDiamonds:null},
        createdAt:stamp,
      }),
      db.doc("deda_purchase_evidence/"+account+
          "/captures/"+captureId).set({
        format:1,kind:"legacy-purchase-evidence",accountKey:account,
        sourceUid:uid,installId:install,captureId,
        records:{
          originalId,progressCaptureId:captureId,
          localSnapshot:JSON.stringify({
            format:1,accountKey:account,originalId,inventory:null,
            frameJournals:Object.fromEntries(frames.map(f=>[f,null])),
          }),
        },createdAt:stamp,
      }),
      db.doc("published_places/"+placeId).set({
        accountKey:account,ownerUid:uid,published:true,
        approvalNumber:"APPROVED-STAGE2-001",
      }),
    ]);
    for(const code of codes){
      const path="deda_recovery_journals/"+uid+
        "/steps/"+intentId+"_"+code;
      await db.doc(path).set({
        ownerUid:uid,accountKey:account,originalId,intentId,code,
        operationKey:"deda_guardian_v1/"+uid+"/"+intentId+"/"+code,
        state:"reserved",createdAt:stamp,
      });
      const correct=validReceipt(code);
      assert.match(correct,/^[A-Za-z0-9_-]{12,128}$/);
      const result=await complete(request(code,correct),db);
      assert.deepEqual(result,{verified:true,receiptId:correct});
      const saved=(await db.doc(path).get()).data();
      assert.equal(saved.state,"verified");
      assert.equal(saved.receiptId,correct);
      const proof=(await db.doc("deda_recovery_server_attestations/"+
        uid+"/receipts/"+intentId+"_"+code).get()).data();
      assert.equal(proof.serverVerified,true);
      assert.equal(proof.receiptId,correct);
      assert.equal(proof.issuedBy,"deda-approved-domain-verifier-v1");
      assert.match(proof.sourceRevision,/^[0-9a-f]{64}$/);
      assert.deepEqual(await complete(request(code,correct),db),result);
    }

    const badIntent="stage2_malicious_receipt_intent001";
    const badCode="originalBackupReadback";
    await db.doc("deda_recovery_journals/"+uid+
      "/steps/"+badIntent+"_"+badCode).set({
      ownerUid:uid,accountKey:account,originalId,intentId:badIntent,
      code:badCode,operationKey:"deda_guardian_v1/"+uid+
        "/"+badIntent+"/"+badCode,
      state:"reserved",createdAt:stamp,
    });
    const malicious=request(badCode,"progress_deadbeefdeadbeef");
    malicious.data.intentId=badIntent;
    malicious.data.operationKey="deda_guardian_v1/"+uid+
      "/"+badIntent+"/"+badCode;
    await assert.rejects(complete(malicious,db),
      e=>e.code==="failed-precondition");
    const still=(await db.doc("deda_recovery_journals/"+uid+
      "/steps/"+badIntent+"_"+badCode).get()).data();
    assert.equal(still.state,"reserved");
    assert.equal((await db.doc("deda_recovery_server_attestations/"+
      uid+"/receipts/"+badIntent+"_"+badCode).get()).exists,false);
    await assert.rejects(complete(request(
        "originalBackupReadback",validReceipt("originalBackupReadback"),
        "other-auth-uid"),db),
      e=>e.code==="permission-denied");
  }finally{await deleteApp(app);}
});
