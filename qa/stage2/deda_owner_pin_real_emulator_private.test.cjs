"use strict";

const test=require("node:test");
const assert=require("node:assert/strict");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore,Timestamp}=require("firebase-admin/firestore");
const {getAuth}=require("firebase-admin/auth");
const {createOwnerPinVerifyCallable}=require(
  "../../functions/deda_owner_pin_verify_private_v1.js");

const project="demo-deda-100436-journal-qa";
const account="9647712345701";
const uid="stage2-original-linked-uid";
const originalId="@DEDA-QA1234";
const pin="123456";
const now=1780000000000;
class HttpsError extends Error {
  constructor(code,message){super(message);this.code=code;}
}
function request(phonePin,device="replacement-a") {
  return {
    app:{appId:"synthetic-qa-appcheck-not-a-device-attestation"},
    auth:{uid:device,token:{firebase:{sign_in_provider:"anonymous"}}},
    data:{phone:account,pin:phonePin,proofMode:"linked-password"},
  };
}
const denied=e=>e instanceof HttpsError &&
  e.code==="permission-denied" &&
  e.message==="owner-verification-unavailable";

test("actual Auth+Firestore Emulator validates original UID, sync, route, PIN and shared rate limits",{
  timeout:90000,
},async()=>{
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,"127.0.0.1:9099");
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST,"127.0.0.1:8098");
  const app=initializeApp({projectId:project},"stage2-pin-proof-real-emulator");
  try{
    const db=getFirestore(app),auth=getAuth(app);
    await auth.createUser({uid,email:account+"@deda-login.invalid",password:pin});
    const moment=Timestamp.fromMillis(1770000000000);
    await Promise.all([
      db.doc("deda_account_directory/"+account).set({
        accountKey:account,active:true,createdUid:uid,
        authEmail:account+"@deda-login.invalid",
      }),
      db.doc("deda_credentials/"+account).set({
        accountKey:account,active:true,createdUid:uid,pin,
        pinSyncVersion:1,updatedAt:moment,pinSyncedAt:moment,
      }),
      db.doc("users/"+uid).set({
        accountKey:account,sharePersonalId:originalId,
      }),
      db.doc("deda_share_ids/"+originalId).set({
        publicId:originalId,kind:"personal",active:true,ownerUid:uid,
      }),
    ]);
    const onCall=(opts,action)=>{
      assert.equal(opts.enforceAppCheck,true);
      return action;
    };
    const endpoint=createOwnerPinVerifyCallable({
      onCall,HttpsError,db,auth,now:()=>now,enabled:true,
    });
    let proof=await endpoint(request(pin));
    assert.deepEqual(proof,{originalUid:uid,originalId,accountKey:account});
    assert.equal("customToken" in proof,false);
    assert.equal((await auth.getUser(uid)).uid,uid);

    await assert.rejects(endpoint(request("000000","replacement-b")),denied);
    const marker=await db.doc("deda_credentials/"+account).get();
    await db.doc("deda_credentials/"+account).update({pinSyncVersion:0});
    await assert.rejects(endpoint(request(pin,"replacement-b")),denied);
    await db.doc("deda_credentials/"+account)
      .update({pinSyncVersion:1});
    await db.doc("deda_share_ids/"+originalId).update({ownerUid:"wrong-uid"});
    await assert.rejects(endpoint(request(pin,"replacement-c")),denied);
    await db.doc("deda_share_ids/"+originalId).update({ownerUid:uid});

    proof=await endpoint(request(pin,"replacement-c"));
    assert.equal(proof.originalUid,uid);
    assert.equal(proof.originalId,originalId);
    // Cross-device invalid PIN attempts use the SAME atomic account ledger.
    await assert.rejects(endpoint(request(pin,"replacement-d")),denied);
    const ledger=(await db.doc(
      "deda_owner_pin_verify_limits/"+account).get()).data();
    assert.equal(ledger.windowAttempts,5);
    assert.equal(ledger.dayAttempts,5);
    assert.equal((await auth.getUser(uid)).uid,uid);
    assert.equal(marker.data().createdUid,uid);
  }finally{await deleteApp(app);}
});
