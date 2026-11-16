"use strict";
// Synthetic semantics probe against a COPY of current published rules,
// executed by a local Firestore emulator. No production Firestore data reads.
const fs = require("node:fs");
const assert = require("node:assert/strict");
const {test} = require("node:test");
const {initializeTestEnvironment} = require("@firebase/rules-unit-testing");
const A="QA_ORIGINAL_UID_A", B="QA_CREATION_UID_B", D="QA_UNKNOWN_UID_D";
const original="@DEDA-ABC123", account="9647712345678";
test("current live rules: synthetic cross-UID projection observation",async()=>{
  const env=await initializeTestEnvironment({
    projectId:"demo-deda-room-live-rules-readonly",
    firestore:{rules:fs.readFileSync("/tmp/deda-room-live-rules.rules","utf8"),
      host:"127.0.0.1",port:8088}
  });
  try {
    await env.withSecurityRulesDisabled(async c=>{
      const db=c.firestore();
      await Promise.all([
        db.doc("users/"+A).set({accountKey:account,sharePersonalId:original}),
        db.doc("users/"+B).set({accountKey:account}),
        db.doc("deda_sessions/"+A).set({accountKey:account,uid:A}),
        db.doc("deda_sessions/"+B).set({accountKey:account,uid:B}),
        db.doc("deda_share_ids/"+original).set(
          {publicId:original,ownerUid:A,kind:"personal",active:true})
      ]);
    });
    const db=uid=>env.authenticatedContext(uid).firestore();
    const receipt="deda_lab_frame_receipts/"+original+"/frames/FRAME_03";
    const can=async f=>{try{await f();return true}catch(_){return false}};
    const aOwn=await can(()=>db(A).doc("users/"+A).get());
    const bReadsA=await can(()=>db(B).doc("users/"+A).get());
    const dReceipt=await can(()=>db(D).doc(receipt).get());
    const bBefore=await can(()=>db(B).doc(receipt).get());
    const bSelfProject=await can(()=>db(B).doc("users/"+B).update(
      {sharePersonalId:original}));
    const bAfter=bSelfProject?
      await can(()=>db(B).doc(receipt).get()):false;
    console.log("LIVE_RULES_QA_A_OWN_DOCUMENT_ALLOWED",aOwn);
    console.log("LIVE_RULES_QA_B_READS_A_PRIVATE_DOCUMENT",bReadsA);
    console.log("LIVE_RULES_QA_UNKNOWN_D_READS_FRAME_RECEIPT",dReceipt);
    console.log("LIVE_RULES_QA_B_READS_FRAME_BEFORE_PROJECTION",bBefore);
    console.log("LIVE_RULES_QA_B_SELF_PROJECTS_ORIGINAL_ID",bSelfProject);
    console.log("LIVE_RULES_QA_B_READS_FRAME_AFTER_SELF_PROJECTION",bAfter);
    // These invariants must hold. A failure signals dangerous access.
    assert.equal(bReadsA,false,"B MUST NOT READ users/A");
    assert.equal(dReceipt,false,"UNKNOWN D MUST NOT READ FRAME RECEIPT");
    // The B-after result is an observation, not an authorization or a
    // credential. If true, it must be held for production-rule review.
    if(bAfter) console.log("LIVE_RULES_QA_REQUIRES_OWNER_SCOPE_HARDENING");
    else console.log("LIVE_RULES_QA_CROSS_UID_RECEIPT_ACCESS_BLOCKED");
  } finally {await env.cleanup()}
});
