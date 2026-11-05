"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const fs=require("node:fs");
const {initializeTestEnvironment,assertSucceeds,assertFails}
  =require("@firebase/rules-unit-testing");
const {doc,collection,setDoc,updateDoc,deleteDoc,getDoc,getDocs,
  serverTimestamp} =require("firebase/firestore");
const account="07712345678",uid="same-original-uid",foreign="foreign-uid";
const original="@DEDA-ABC123",path="deda_step2_global_place_archives/"+account;
const captured="a".repeat(48);
let env;
function payload() {
  return {
    format:1,kind:"untrusted-device-global-display-evidence",
    accountKey:account,originalId:original,sourceUid:uid,captureId:captured,
    encoded:JSON.stringify({
      format:1,kind:"untrusted-device-global-display-evidence",
      accountKey:account,originalId:original,sourceUid:uid,captureId:captured,
      ownerConfirmedAtOriginalPhone:true,
      records:{deda_favorites_v1:['{"name":"original"}'],
        deda_recent_v1:null,deda_personal_places_v1:null,
        deda_language_v1:"ar",deda_voice_enabled_v1:null,
        deda_speech_rate_v1:null,deda_default_travel_mode_v1:null,
        deda_default_map_style_v1:null,
        ["deda_profile_frame_v1_"+account]:null}
    }),
    createdAt:serverTimestamp(),
  };
}
function owner() {
  return env.authenticatedContext(uid,{
    email:account+"@deda-login.invalid",
    firebase:{sign_in_provider:"password"}
  }).firestore();
}
function other() {
  return env.authenticatedContext(foreign,{
    email:"foreign@example.com",firebase:{sign_in_provider:"password"}
  }).firestore();
}
test.before(async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST||"",/127\.0\.0\.1:/);
  const candidate=fs.readFileSync(process.env.DEDA_EMULATOR_RULES_PATH,"utf8");
  assert.equal((candidate.match(/match \/deda_step2_global_place_archives\//g)||[]).length,1);
  env=await initializeTestEnvironment({
    projectId:"demo-deda-100436-global-rules",
    firestore:{rules:candidate}
  });
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    for(const [id,values] of Object.entries({
      ["deda_credentials/"+account]:{accountKey:account,createdUid:uid,pin:"000000",active:true},
      ["deda_account_directory/"+account]:{accountKey:account,createdUid:uid,active:true},
      ["users/"+uid]:{accountKey:account,sharePersonalId:original,accountType:"user"},
      ["deda_share_ids/"+original]:{publicId:original,kind:"personal",ownerUid:uid,active:true},
      ["deda_sessions/"+uid]:{uid,accountKey:account,installId:"a".repeat(48)},
      ["deda_account_profiles/"+account]:{accountKey:account,accountType:"user"},
    }))await setDoc(doc(db,id),values);
  });
});
test.after(async()=>{if(env)await env.cleanup();});
test("verified original account alone may create immutable archival data",async()=>{
  const db=owner();
  const prior=await assertSucceeds(getDoc(doc(db,path)));
  assert.equal(prior.exists(),false);
  await assertSucceeds(setDoc(doc(db,path),payload()));
  const row=await assertSucceeds(getDoc(doc(db,path)));
  assert.equal(row.data().accountKey,account);
  assert.equal(row.data().sourceUid,uid);
});
test("owner cannot enumerate, replace, delete or mint a different owner",async()=>{
  const db=owner();
  await assertFails(getDocs(collection(db,"deda_step2_global_place_archives")));
  await assertFails(updateDoc(doc(db,path),{encoded:"replacement"}));
  await assertFails(deleteDoc(doc(db,path)));
  await assertFails(setDoc(doc(db,path),payload()));
});
test("foreign UID has zero access to original owner's archive",async()=>{
  const db=other();
  await assertFails(getDoc(doc(db,path)));
  await assertFails(updateDoc(doc(db,path),{encoded:"foreign"}));
  await assertFails(setDoc(doc(db,path),payload()));
});
test("financial extras and owner spoofing rejected before first create",async()=>{
  const db=owner();
  await assertFails(setDoc(doc(db,
    "deda_step2_global_place_archives/"+account+"1"),{
      ...payload(),accountKey:account+"1",earnedDiamonds:1000000,
    }));
});
