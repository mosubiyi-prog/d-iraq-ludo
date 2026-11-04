"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  validPin, syncMarkerMatches, accountMatches,
  completeApprovedManualPinRecovery,
} = require("../deda_pin_manual_recovery_compat_private_v1.js");

const key = "07712345678";
const uid = "original-owner-uid-100436";
const requestId = "request-approved-100436";
const email = `${key}@deda-login.invalid`;
const oldPin = "123456";
const newPin = "654321";
const time = 1780000000000;
const Timestamp = {fromMillis: (ms) => ({toMillis: () => ms})};

class Db {
  constructor() {
    this.docs = new Map();
    this.writes = [];
    this.transactions = 0;
    this.failTransaction = 0;
    this.ackLossTransaction = 0;
  }
  put(path, data) {this.docs.set(path, {...data});}
  snap(path) {
    const d = this.docs.get(path);
    return {exists:!!d, data:() => d ? {...d} : undefined};
  }
  collection(name) {
    return {doc:id=>{
      const path=`${name}/${id}`;
      return {path,get:async()=>this.snap(path)};
    }};
  }
  async runTransaction(cb) {
    this.transactions++;
    const pending=[];
    const tx={
      get:async (ref)=>this.snap(ref.path),
      create:(ref, value)=>pending.push(["create",ref.path,value]),
      update:(ref, value)=>pending.push(["update",ref.path,value]),
      delete:(ref)=>pending.push(["delete",ref.path]),
    };
    const result=await cb(tx);
    if(this.failTransaction===this.transactions) throw Error("firestore-write-failed");
    for (const [kind,path,value] of pending) {
      if(kind==="create") {
        if(this.docs.has(path))throw Error("document-already-exists");
        this.put(path,value);
      } else if(kind==="update"){
        if(!this.docs.has(path))throw Error("missing-document");
        this.put(path,{...this.docs.get(path),...value});
      } else if(kind==="delete") this.docs.delete(path);
      this.writes.push({kind,path});
    }
    if(this.ackLossTransaction===this.transactions)throw Error("commit-ack-lost");
    return result;
  }
}

function fixture() {
  const db=new Db();
  const auth={
    password:oldPin, updates:[], fail:false,
    async getUserByEmail(e) {
      return {uid, email:e, disabled:false};
    },
    async updateUser(u, data){
      if(this.fail)throw Error("auth-update-unavailable");
      this.updates.push({u,password:data.password});
      this.password=data.password;
    },
  };
  db.put(`recovery_requests/${requestId}`, {
    status:"approved",accountKey:key,requesterUid:"replacement-requester-uid",
  });
  db.put(`deda_account_directory/${key}`,{
    accountKey:key,active:true,createdUid:uid,authEmail:email,
  });
  db.put(`deda_credentials/${key}`,{
    accountKey:key,active:true,createdUid:uid,pin:oldPin,
  });
  db.put(`users/${uid}`,{accountKey:key,sharePersonalId:"@DEDA-ABC123"});
  const params={db,auth,Timestamp,requestId,nowMs:time,generatePin:()=>newPin};
  return {db,auth,params};
}

test("canonical PIN and synchronization stamp validation",()=>{
  assert.equal(validPin("123456"),true);
  assert.equal(validPin("123"),false);
  assert.equal(validPin(123456),false);
  assert.equal(syncMarkerMatches({pinSyncVersion:1,
    updatedAt:Timestamp.fromMillis(time),pinSyncedAt:Timestamp.fromMillis(time)}),true);
  assert.equal(syncMarkerMatches({pinSyncVersion:1,
    updatedAt:Timestamp.fromMillis(time),pinSyncedAt:Timestamp.fromMillis(time-1)}),false);
  assert.equal(syncMarkerMatches({pinSyncVersion:0,
    updatedAt:Timestamp.fromMillis(time),pinSyncedAt:Timestamp.fromMillis(time)}),false);
});

test("approved manual recovery rotates BOTH sources, commits ready and clears lock",async()=>{
  const f=fixture();
  const result=await completeApprovedManualPinRecovery(f.params);
  assert.deepEqual(result,{outcome:"ready",originalUid:uid,recoveredAfterAckLoss:false});
  assert.equal(f.auth.password,newPin);
  const canonical=f.db.docs.get(`deda_credentials/${key}`);
  assert.equal(canonical.pin,newPin);
  assert.equal(syncMarkerMatches(canonical),true);
  const request=f.db.docs.get(`recovery_requests/${requestId}`);
  assert.equal(request.status,"ready");
  assert.equal(request.recoveryPin,newPin);
  assert.equal(request.recoveryPinExpiresAt.toMillis(),time+30*60*1000);
  assert.equal(f.db.docs.has(`deda_pin_recovery_locks/${key}`),false);
  assert.equal(f.auth.updates.length,1);
  assert.equal(f.db.docs.get(`users/${uid}`).sharePersonalId,"@DEDA-ABC123");
});

test("old PIN is absent after successful server rotation",async()=>{
  const f=fixture();
  await completeApprovedManualPinRecovery(f.params);
  assert.notEqual(f.db.docs.get(`deda_credentials/${key}`).pin,oldPin);
  assert.notEqual(f.auth.password,oldPin);
});

test("request not approved cannot change authentication",async()=>{
  const f=fixture();
  f.db.put(`recovery_requests/${requestId}`,{
    accountKey:key,status:"review",requesterUid:"replacement-requester-uid",
  });
  await assert.rejects(()=>completeApprovedManualPinRecovery(f.params),/not-approved/);
  assert.equal(f.auth.updates.length,0);
  assert.equal(f.db.writes.length,0);
});

test("foreign directory identity cannot change original user's PIN",async()=>{
  const f=fixture();
  f.db.put(`deda_credentials/${key}`,{
    accountKey:key,active:true,createdUid:"foreign-owner",pin:oldPin,
  });
  await assert.rejects(()=>completeApprovedManualPinRecovery(f.params),/owner-mismatch/);
  assert.equal(f.auth.updates.length,0);
});

test("admin account cannot use the ordinary user recovery",async()=>{
  const f=fixture();
  f.db.put(`admins/${uid}`,{role:"general_manager",active:true});
  await assert.rejects(()=>completeApprovedManualPinRecovery(f.params),/owner-mismatch/);
  assert.equal(f.auth.updates.length,0);
});

test("wrong Firebase Auth UID cannot be rotated",async()=>{
  const f=fixture();
  f.auth.getUserByEmail=async()=>({uid:"foreign-owner",email,disabled:false});
  await assert.rejects(()=>completeApprovedManualPinRecovery(f.params),/owner-mismatch/);
  assert.equal(f.auth.updates.length,0);
});

test("existing lock prevents a second recovery request taking ownership",async()=>{
  const f=fixture();
  f.db.put(`deda_pin_recovery_locks/${key}`,{requestId:"other-request"});
  await assert.rejects(()=>completeApprovedManualPinRecovery(f.params),/concurrent/);
  assert.equal(f.auth.updates.length,0);
});

test("failed Auth update keeps lock and does not switch canonical PIN",async()=>{
  const f=fixture();f.auth.fail=true;
  await assert.rejects(()=>completeApprovedManualPinRecovery(f.params),/auth-update/);
  assert.equal(f.db.docs.get(`deda_credentials/${key}`).pin,oldPin);
  assert.equal(f.db.docs.get(`recovery_requests/${requestId}`).status,"approved");
  assert.equal(f.db.docs.has(`deda_pin_recovery_locks/${key}`),true);
});

test("Firestore failed completion leaves a review lock; NO false ready",async()=>{
  const f=fixture();f.db.failTransaction=2;
  await assert.rejects(()=>completeApprovedManualPinRecovery(f.params),/pending-reconciliation/);
  assert.equal(f.auth.password,newPin);
  assert.equal(f.db.docs.get(`deda_credentials/${key}`).pin,oldPin);
  assert.equal(f.db.docs.get(`recovery_requests/${requestId}`).status,"approved");
  assert.equal(f.db.docs.has(`deda_pin_recovery_locks/${key}`),true);
});

test("lost Firestore acknowledgment after commit is resolved by trusted readback",async()=>{
  const f=fixture();f.db.ackLossTransaction=2;
  const result=await completeApprovedManualPinRecovery(f.params);
  assert.equal(result.recoveredAfterAckLoss,true);
  assert.equal(f.db.docs.get(`deda_credentials/${key}`).pin,newPin);
  assert.equal(syncMarkerMatches(f.db.docs.get(`deda_credentials/${key}`)),true);
  assert.equal(f.db.docs.has(`deda_pin_recovery_locks/${key}`),false);
});

test("replayed approved event cannot rotate PIN twice",async()=>{
  const f=fixture();
  await completeApprovedManualPinRecovery(f.params);
  await assert.rejects(()=>completeApprovedManualPinRecovery(f.params),/not-approved/);
  assert.equal(f.auth.updates.length,1);
});

test("same-old or invalid PIN generator fails without a lock",async()=>{
  const f=fixture();
  await assert.rejects(()=>completeApprovedManualPinRecovery({
    ...f.params,generatePin:()=>oldPin,
  }),/generator-invalid/);
  assert.equal(f.db.writes.length,0);
  await assert.rejects(()=>completeApprovedManualPinRecovery({
    ...f.params,generatePin:()=>"654",
  }),/generator-invalid/);
  assert.equal(f.db.writes.length,0);
});

test("invalid request identifier is rejected without database access",async()=>{
  const f=fixture();
  await assert.rejects(()=>completeApprovedManualPinRecovery({
    ...f.params,requestId:"../../admin",
  }),/invalid-server-arguments/);
  assert.equal(f.db.writes.length,0);
});

test("stale synchronisation marker rejects an automatic PIN-only rotation",()=>{
  const f=fixture();
  const credential=f.db.docs.get(`deda_credentials/${key}`);
  const t=Timestamp.fromMillis(time);
  credential.pinSyncVersion=1;
  credential.pinSyncedAt=t;
  credential.updatedAt=Timestamp.fromMillis(time+1);
  assert.equal(syncMarkerMatches(credential),false);
  credential.updatedAt=t;
  assert.equal(syncMarkerMatches(credential),true);
});

test("valid owner data is required before writing any password",()=>{
  const f=fixture();
  assert.equal(accountMatches({
    key,directory:f.db.docs.get(`deda_account_directory/${key}`),
    credential:f.db.docs.get(`deda_credentials/${key}`),
    profile:f.db.docs.get(`users/${uid}`),adminExists:false,
    authUser:{uid,email,disabled:false},
  }),true);
});
