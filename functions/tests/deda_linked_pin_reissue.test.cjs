"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {FieldValue} = require("firebase-admin/firestore");
const {approveForgottenPin,finishStagedReset} =
  require("../deda_linked_pin_reissue.js");

const key = "9647712345678";
const uid = "original_owner_uid_001";
const requester = "recovery_requester_uid";
const actor = {uid:"manager_uid_001",role:"general_manager",name:"Manager"};
const requestId="specific_request_00001";
const oldPin="123456",newPin="789123";

function memoryDb(overrides={}) {
  const initial={
    ["recovery_requests/"+requestId]:{
      status:"new",accountKey:key,requesterUid:requester,
      requesterInstallId:"a".repeat(48),fullName:"صاحب الحساب",
    },
    ["deda_account_directory/"+key]:{
      active:true,accountKey:key,createdUid:uid,
    },
    ["deda_credentials/"+key]:{
      accountKey:key,createdUid:uid,pin:oldPin,active:true,
    },
    ["deda_account_profiles/"+key]:{
      accountKey:key,name:"صاحب الحساب",accountType:"user",
    },
    ["users/"+uid]:{
      accountKey:key,name:"صاحب الحساب",sharePersonalId:"@DEDA-ABC123",
    },
  };
  const docs=new Map(Object.entries(initial));
  for(const [p,val] of Object.entries(overrides)) {
    if(val===null) docs.delete(p);
    else docs.set(p,{...(docs.get(p)||{}),...val});
  }
  let failFinalize=false;
  let transactionCount=0;
  const read = (p) => ({exists:docs.has(p),data:()=>docs.get(p)});
  function ref(p){
    return {path:p,async get(){return read(p);}};
  }
  const db={
    docs,
    get transactionCount(){return transactionCount;},
    setFailFinalOnce(){failFinalize=true;},
    collection(c) {return {doc(id){return ref(c+"/"+id);}};},
    async runTransaction(fn) {
      transactionCount++;
      const changes=[];
      const tx={
        async get(r){return read(r.path);},
        update(r,value){changes.push({op:"update",p:r.path,value});},
        set(r,value){changes.push({op:"set",p:r.path,value});},
      };
      const result=await fn(tx);
      if(failFinalize && changes.some(c=>c.p==="recovery_requests/"+requestId &&
          c.value.status==="ready")) {
        failFinalize=false;
        throw Error("simulated-final-Firestore-commit-failure");
      }
      for(const change of changes){
        const data={...(docs.get(change.p)||{})};
        for(const [k,v] of Object.entries(change.value)) {
          if(v && typeof v.isEqual==="function" &&
              v.isEqual(FieldValue.delete())) delete data[k];
          else data[k]=v;
        }
        docs.set(change.p,data);
      }
      return result;
    },
  };
  return db;
}
function authFor(email=key+"@deda-login.invalid"){
  let failUpdate=false;
  const updates=[];
  return {
    updates,
    failNext(){failUpdate=true;},
    async getUser(requestedUid){
      assert.equal(requestedUid,uid);
      return {uid,email,disabled:false};
    },
    async updateUser(requestedUid,change){
      assert.equal(requestedUid,uid);
      assert.deepEqual(change,{password:newPin});
      if(failUpdate){failUpdate=false;throw Error("simulated-auth-timeout");}
      updates.push({uid:requestedUid,...change});
      return {uid:requestedUid,email};
    },
  };
}
const approve=(db,auth,options={})=>approveForgottenPin(db,auth,{
  requestId,actor,generatePin:()=>newPin,...options,
});

test("manager issues one synchronized PIN: original UID and all profile/point fields untouched",async()=>{
  const db=memoryDb(),auth=authFor();
  const oldUser={...db.docs.get("users/"+uid)};
  const answer=await approve(db,auth);
  assert.equal(answer.status,"ready");
  assert.equal(answer.linkedUidPreserved,true);
  assert.deepEqual(auth.updates,[{uid,password:newPin}]);
  assert.equal(db.docs.get("deda_credentials/"+key).pin,newPin);
  assert.equal(db.docs.get("deda_credentials/"+key).createdUid,uid);
  assert.equal(db.docs.get("deda_credentials/"+key).pendingRecovery,undefined);
  assert.equal(db.docs.get("recovery_requests/"+requestId).recoveryPin,newPin);
  assert.deepEqual(db.docs.get("users/"+uid),oldUser);
  assert.equal(db.docs.get("admin_audit/pin_reissue_"+requestId)
    .targetUid,uid);
  assert.equal(JSON.stringify(db.docs.get("admin_audit/pin_reissue_"+requestId))
    .includes(newPin),false);
  assert.equal((await finishStagedReset(db,auth,requestId)).status,"ready");
  assert.equal(auth.updates.length,1);
});

test("Auth password failure never announces a usable PIN; retries same persisted code",async()=>{
  const db=memoryDb(),auth=authFor();
  auth.failNext();
  await assert.rejects(approve(db,auth),/simulated-auth-timeout/);
  assert.equal(db.docs.get("deda_credentials/"+key).pin,oldPin);
  assert.equal(db.docs.get("recovery_requests/"+requestId).status,"issuing");
  assert.equal(db.docs.get("recovery_requests/"+requestId).recoveryPin,undefined);
  assert.equal(db.docs.get("deda_credentials/"+key).pendingRecovery.pin,newPin);
  await approve(db,auth,{generatePin:()=>{throw Error("must reuse old pending PIN");}});
  assert.equal(db.docs.get("recovery_requests/"+requestId).status,"ready");
  assert.deepEqual(auth.updates,[{uid,password:newPin}]);
});

test("Firestore final commit failure retains protected pending PIN, retry finishes same UID",async()=>{
  const db=memoryDb(),auth=authFor();
  db.setFailFinalOnce();
  await assert.rejects(approve(db,auth),/simulated-final/);
  assert.equal(db.docs.get("deda_credentials/"+key).pin,oldPin);
  assert.equal(db.docs.get("recovery_requests/"+requestId).status,"issuing");
  const before=db.docs.get("deda_credentials/"+key).pendingRecovery.pin;
  await finishStagedReset(db,auth,requestId);
  assert.equal(db.docs.get("deda_credentials/"+key).pin,before);
  assert.equal(db.docs.get("recovery_requests/"+requestId).recoveryPin,before);
  assert.equal(db.docs.get("deda_credentials/"+key).pendingRecovery,undefined);
  assert.equal(auth.updates.every(x=>x.uid===uid),true);
});

test("legacy anonymous original uses same UID and Firestore credential, no new Auth password",async()=>{
  const db=memoryDb(),auth=authFor(null);
  await approve(db,auth);
  assert.equal(auth.updates.length,0);
  assert.equal(db.docs.get("deda_credentials/"+key).pin,newPin);
  assert.equal(db.docs.get("deda_account_directory/"+key).createdUid,uid);
});

test("non-manager, unrelated Auth email and tampered profile are rejected",async()=>{
  const noManager=memoryDb();
  await assert.rejects(approve(noManager,authFor(),{
    actor:{uid:"employee",role:"employee"}}),/general-manager/);
  assert.equal(noManager.transactionCount,0);
  const foreignAuth=memoryDb();
  await assert.rejects(approve(foreignAuth,authFor("other@example.org")),
    /original-auth-email-conflict/);
  assert.equal(foreignAuth.docs.get("recovery_requests/"+requestId).status,"issuing");
  assert.equal(foreignAuth.docs.get("recovery_requests/"+requestId).recoveryPin,undefined);
  const badProfile=memoryDb({["users/"+uid]:{accountKey:"wrong-account"}});
  await assert.rejects(approve(badProfile,authFor()),/not-verified/);
  assert.equal(badProfile.docs.get("deda_credentials/"+key).pin,oldPin);
});

test("different recovery request or actor never seizes an in-flight original identity",async()=>{
  const db=memoryDb(),auth=authFor();auth.failNext();
  await assert.rejects(approve(db,auth));
  await assert.rejects(approve(db,auth,{
    actor:{uid:"other_manager",role:"general_manager"}}),/another-or-unverified/);
  assert.equal(db.docs.get("recovery_requests/"+requestId).recoveryPin,undefined);
});

test("Dart manager button cannot write legacy pin directly or generate alternative UID",()=>{
  const file=fs.readFileSync(path.resolve(__dirname,
    "../../lib/deda_recovery_admin.dart"),"utf8");
  assert.match(file,/httpsCallable\('dedaApproveLinkedPinRecovery'\)/);
  assert.doesNotMatch(file,/collection\('deda_credentials'\)/);
  assert.doesNotMatch(file,/Random\.secure\(\)/);
});
