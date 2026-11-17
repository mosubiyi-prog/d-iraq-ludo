"use strict";
// Emulator only: compare unchanged legacy behavior with additive private room views.
const fs=require("node:fs");
const assert=require("node:assert/strict");
const {test}=require("node:test");
const {initializeTestEnvironment}=require("@firebase/rules-unit-testing");
const firebase=require("firebase/compat/app");
require("firebase/compat/firestore");
const A="QA_ORIGINAL_UID_A",B="QA_CREATION_UID_B",C="QA_SOCIAL_UID_C",D="QA_UNKNOWN_UID_D";
const account="9647712345678",original="@DEDA-ABC123",now=Date.now();
const domains=["profile","original_id","premium_id","friends","league","gifts","wallet","places"];
const sessionNonce="QA_ROOM_B_REVISION_NINE_2026";
const doc=(u,d)=>"deda_unified_room_private_views/"+u+"/domains/"+d;
const grant=(u,d)=>"deda_unified_room_read_grants/"+u+"/domains/"+d;
const frame="deda_lab_frame_receipts/"+original+"/frames/FRAME_03";
const stamp=ms=>firebase.firestore.Timestamp.fromDate(new Date(ms));
const viewer=(u,d)=>({readerUid:u,domain:d,canonicalAccountId:"DEDA_QA_CANONICAL_1",
  originalId:original,sourceUid:A,scopeVersion:1,
  sessionRevision:9,sessionNonce,
  payload:{display:"safe-synthetic-projection",containsMoney:false}});
const permit=(u,d)=>({readerUid:u,domain:d,canonicalAccountId:"DEDA_QA_CANONICAL_1",
  originalId:original,sourceUid:A,scopeVersion:1,
  sessionRevision:9,sessionNonce,
  status:"active",proofKind:"independent_verified",
  issuedAt:stamp(now-20_000),expiresAt:stamp(now+250_000)});
const can=async fn=>{try{await fn();return true}catch(_){return false}};
const signed=(env,u,provider="google.com")=>env.authenticatedContext(u,{
  firebase:{sign_in_provider:provider}
}).firestore();
async function seed(env) {
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    await Promise.all([
      db.doc("users/"+A).set({accountKey:account,sharePersonalId:original}),
      db.doc("users/"+B).set({accountKey:account}),
      db.doc("deda_sessions/"+A).set({uid:A,accountKey:account}),
      db.doc("deda_sessions/"+B).set({uid:B,accountKey:account,
        active:true,revision:9,sessionNonce}),
      db.doc("deda_share_ids/"+original).set({publicId:original,ownerUid:A,
        kind:"personal",active:true}),
      db.doc(doc(B,"original_id")).set(viewer(B,"original_id")),
      db.doc(grant(B,"original_id")).set(permit(B,"original_id")),
      db.doc(doc(B,"friends")).set(viewer(B,"friends"))
    ]);
  });
}
async function oldPlay(env) {
  const a=signed(env,A),b=signed(env,B),d=signed(env,D);
  const row={
    ownUserA:await can(()=>a.doc("users/"+A).get()),
    crossUidPrivateRead:await can(()=>b.doc("users/"+A).get()),
    publicOriginalIdRead:await can(()=>b.doc("deda_share_ids/"+original).get()),
    unknownFrameRead:await can(()=>d.doc(frame).get()),
    frameBeforeSelfProjection:await can(()=>b.doc(frame).get()),
    selfProjectOriginalId:await can(()=>b.doc("users/"+B).update({sharePersonalId:original}))
  };
  row.frameAfterSelfProjection=await can(()=>b.doc(frame).get());
  return row;
}
async function newEnv(rulesFile) {
  const env=await initializeTestEnvironment({
    projectId:"demo-deda-room-live-additive-compare",
    firestore:{rules:fs.readFileSync(rulesFile,"utf8"),host:"127.0.0.1",port:8088}
  });
  await env.clearFirestore();
  await seed(env);
  return env;
}
test("scoped room candidate, revoked grants, and old Play paths",async()=>{
  let base,updated;
  try{
    base=await newEnv("/tmp/deda-room-live-rules.rules");
    const old=await oldPlay(base);
    assert.equal(await can(()=>signed(base,B).doc(doc(B,"original_id")).get()),false);
    assert.deepEqual(old,{
      ownUserA:true,crossUidPrivateRead:false,publicOriginalIdRead:true,
      unknownFrameRead:false,frameBeforeSelfProjection:false,
      selfProjectOriginalId:true,frameAfterSelfProjection:true
    },"baseline source behavior changed: safe stop");
    await base.cleanup();base=null;
    updated=await newEnv("/tmp/deda-room-candidate-rules.rules");
    const legacy=await oldPlay(updated);
    assert.deepEqual(legacy,old,"legacy Play compatibility changed");
    console.log("PASS_LEGACY_PLAY_BEHAVIOR_UNCHANGED",JSON.stringify(legacy));
    const b=signed(updated,B),a=signed(updated,A),d=signed(updated,D);
    const anon=signed(updated,B,"anonymous");
    assert.equal(await can(()=>b.doc(doc(B,"original_id")).get()),true);
    assert.equal(await can(()=>a.doc(doc(B,"original_id")).get()),false);
    assert.equal(await can(()=>d.doc(doc(B,"original_id")).get()),false);
    assert.equal(await can(()=>anon.doc(doc(B,"original_id")).get()),false);
    assert.equal(await can(()=>b.doc(doc(B,"friends")).get()),false);
    assert.equal(await can(()=>b.doc(grant(B,"original_id")).get()),false);
    assert.equal(await can(()=>b.doc(grant(B,"original_id")).update({status:"active"})),false);
    assert.equal(await can(()=>b.doc(grant(B,"gifts")).set(permit(B,"gifts"))),false);
    assert.equal(await can(()=>b.doc(doc(B,"original_id")).update({sourceUid:B})),false);
    assert.equal(await can(()=>b.collection(
      "deda_unified_room_private_views/"+B+"/domains").get()),false);
    assert.equal(await can(()=>b.doc("users/"+A).get()),false);
    const adminSet=async (path,value)=>updated.withSecurityRulesDisabled(
      async ctx=>ctx.firestore().doc(path).set(value));
    for(const domain of domains) {
      await adminSet(doc(B,domain),viewer(B,domain));
      await adminSet(grant(B,domain),permit(B,domain));
      assert.equal(await can(()=>b.doc(doc(B,domain)).get()),true,
        domain+" must permit only its scoped server view");
    }
    console.log("PASS_EIGHT_INDEPENDENT_DOMAIN_GRANTS");
    // A new login epoch with the same UID must invalidate every old raw view.
    await adminSet("deda_sessions/"+B,{uid:B,accountKey:account,
      active:true,revision:10,sessionNonce:"QA_REPLACED_B_SESSION_2026"});
    assert.equal(await can(()=>b.doc(doc(B,"friends")).get()),false);
    assert.equal(await can(()=>b.doc(doc(B,"original_id")).get()),false);
    await adminSet("deda_sessions/"+B,{uid:B,accountKey:account,
      active:true,revision:9,sessionNonce});
    assert.equal(await can(()=>b.doc(doc(B,"friends")).get()),true);
    await adminSet(grant(B,"friends"),{...permit(B,"friends"),status:"revoked"});
    assert.equal(await can(()=>b.doc(doc(B,"friends")).get()),false);
    await adminSet(grant(B,"wallet"),{...permit(B,"wallet"),expiresAt:stamp(now-5000)});
    assert.equal(await can(()=>b.doc(doc(B,"wallet")).get()),false);
    await adminSet(grant(B,"gifts"),{...permit(B,"gifts"),expiresAt:stamp(now+900000)});
    assert.equal(await can(()=>b.doc(doc(B,"gifts")).get()),false);
    await adminSet(doc(B,"premium_id"),{...viewer(B,"premium_id"),sourceUid:C});
    assert.equal(await can(()=>b.doc(doc(B,"premium_id")).get()),false);
    await adminSet(doc(B,"league"),{...viewer(B,"league"),originalId:"@DEDA-XYZ999"});
    assert.equal(await can(()=>b.doc(doc(B,"league")).get()),false);
    await adminSet(grant(B,"places"),{...permit(B,"places"),proofKind:"pin-only"});
    assert.equal(await can(()=>b.doc(doc(B,"places")).get()),false);
    await adminSet(grant(B,"profile"),{
      ...permit(B,"profile"),issuedAt:stamp(now+20000),
      expiresAt:stamp(now+250000)});
    assert.equal(await can(()=>b.doc(doc(B,"profile")).get()),false,
      "future-dated grant beyond 5s skew must remain denied");
    console.log("PASS_REVOKE_EXPIRY_MISMATCH_AND_FORGED_GRANT_DENIAL");
  }finally{
    if(base) await base.cleanup();
    if(updated) await updated.cleanup();
  }
});
