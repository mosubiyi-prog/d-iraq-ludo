"use strict";
// Integration of the private offline grant lifecycle with a LOCAL Firestore
// emulator containing a COPY of the published Rules. Synthetic UIDs only.
// The "trusted store" is simulated via withSecurityRulesDisabled; it is not
// a production auth or admin interface and MUST NOT be deployed.
const fs=require("node:fs");
const assert=require("node:assert/strict");
const {test}=require("node:test");
const {initializeTestEnvironment}=require("@firebase/rules-unit-testing");
const firebase=require("firebase/compat/app");
require("firebase/compat/firestore");
const {issueFixture,revokeFixture}=
  require("./room_grant_lifecycle_PRIVATE_OFFLINE_QA.cjs");
const A="QA_ORIGINAL_UID_A",B="QA_CREATION_UID_B",C="QA_SOCIAL_UID_C",
      D="QA_UNKNOWN_UID_D";
const key="9647712345678",original="@DEDA-ABC123",
      canonical="DEDA_CANONICAL_ROOM_QA_12345";
const token="OFFLINE_VERIFIED_FAKE_TOKEN_001";
const view=(u,d)=>"deda_unified_room_private_views/"+u+"/domains/"+d;
const grant=(u,d)=>"deda_unified_room_read_grants/"+u+"/domains/"+d;
const session=(u)=>"qa_room_emulator_sessions/"+u;
const stamp=ms=>firebase.firestore.Timestamp.fromMillis(ms);
const can=async f=>{try{await f();return true}catch(_){return false;}};
test("real Firestore emulator: issue/revoke fake server scopes, fail closed, zero UID creations",async()=>{
 const env=await initializeTestEnvironment({
  projectId:"demo-deda-room-live-additive-compare",
  firestore:{rules:fs.readFileSync("/tmp/deda-room-candidate-rules.rules","utf8"),
    host:"127.0.0.1",port:8088}
 });
 let current={uid:B,canonicalAccountId:canonical,active:true,
   revision:12,sessionNonce:"QA_SERVER_SESSION_001"};
 const now=Date.now(),issuedAudits=[];
 const fakeRoom={canonicalAccountId:canonical,accountKey:key,originalId:original,
   historicalUids:[A,B,C]};
 const fakeReview={source:"independent_server_review",independentlyVerified:true,
   ownerApproved:true,accountKey:key,originalId:original,
   canonicalAccountId:canonical,authUid:B,backupVerified:true,
   rollbackDocumented:true,reviewId:"QA_SIGNED_REVIEW_001",verifiedAtMs:now-1000};
 const fakeProof={
   trustedSource:"independently_reviewed_domain",status:"approved",
   reviewId:fakeReview.reviewId,canonicalAccountId:canonical,readerUid:B,
   sourceUid:A,originalId:original,mayReadSanitizedProjection:true,
   mayMutate:false,verifiedAtMs:now-1000
 };
 const auth={uid:B,provider:"google.com",anonymous:false};
 const server=async fn=>env.withSecurityRulesDisabled(async ctx=>fn(ctx.firestore()));
 const deps={
   qaMode:"isolated-fake-only",clockMs:()=>now,
   verifyIdToken:async (t,checkRevoked)=>{
     if(t!==token || checkRevoked!==true)throw Error("invalid_token");
     return {...auth};
   },
   readRoomForUid:async uid=>uid===B?structuredClone(fakeRoom):null,
   readOwnerReview:async()=>structuredClone(fakeReview),
   readDomainProof:async(_,d)=>({...structuredClone(fakeProof),domain:d}),
   readSession:async()=>structuredClone(current),
   buildProjection:async plan=>plan.domain==="original_id"?
     {publicId:original}:plan.domain==="friends"?{friendCount:2}:null,
   store:{
     environment:"isolated-fake-only",
     issueAtomic:async ({plan,session:expected,view:v,grant:g,expectedOwnerReview})=>{
       let committed=false;
       await server(async db=>{committed=await db.runTransaction(async tx=>{
         const sr=db.doc(session(B));
         const prev=await tx.get(sr);
         const s=prev.data();
         if(!s||s.revision!==expected.revision ||
           s.sessionNonce!==expected.sessionNonce ||
           s.uid!==plan.readerUid||s.active!==true||
           expectedOwnerReview!==fakeReview.reviewId) {
           console.log('QA_TRANSACTION_GUARD',JSON.stringify({
             exists:!!s,revisionMatches:s?.revision===expected.revision,
             nonceMatches:s?.sessionNonce===expected.sessionNonce,
             uidMatches:s?.uid===plan.readerUid,active:s?.active===true,
             ownerReviewMatches:expectedOwnerReview===fakeReview.reviewId}));
           return false;
         }
         const rr=db.doc(grant(B,plan.domain)),vr=db.doc(view(B,plan.domain));
         const prior=await tx.get(rr);
         if(prior.exists){console.log('QA_TRANSACTION_ALREADY_GRANTED');return false;}
         tx.set(vr,v);
         tx.set(rr,{...g,issuedAt:stamp(g.issuedAtMs),
           expiresAt:stamp(g.expiresAtMs)});
         return true;
       });});
       return committed;
     },
     revokeAtomic:async ({readerUid,domain,session:expected})=>{
       let revoked=false;
       await server(async db=>{revoked=await db.runTransaction(async tx=>{
         const sr=db.doc(session(readerUid));
         const gr=db.doc(grant(readerUid,domain));
         const s=(await tx.get(sr)).data();
         if(!s||s.revision!==expected.revision ||
            s.sessionNonce!==expected.sessionNonce ||!s.active)return false;
         const g=await tx.get(gr);
         if(!g.exists)return false;
         tx.update(gr,{status:"revoked"});
         return true;
       });});
       return revoked;
     }
   }
 };
 try {
   await env.clearFirestore();
   await server(async db=>db.doc(session(B)).set({...current}));
   const b=env.authenticatedContext(B,{
     firebase:{sign_in_provider:"google.com"}}).firestore();
   const a=env.authenticatedContext(A,{
     firebase:{sign_in_provider:"google.com"}}).firestore();
   const d=env.authenticatedContext(D,{
     firebase:{sign_in_provider:"google.com"}}).firestore();
   const anonymous=env.authenticatedContext(B,{
     firebase:{sign_in_provider:"anonymous"}}).firestore();
   assert.equal(await can(()=>b.doc(view(B,"original_id")).get()),false);
   const issued=await issueFixture({idToken:token,domain:"original_id"},deps);
   assert.equal(issued.status,"QA_FIXTURE_ISSUED",issued.reason||"");
   assert.equal(issued.productionAccess,false);
   assert.equal(await can(()=>b.doc(view(B,"original_id")).get()),true);
   assert.equal(await can(()=>a.doc(view(B,"original_id")).get()),false);
   assert.equal(await can(()=>d.doc(view(B,"original_id")).get()),false);
   assert.equal(await can(()=>anonymous.doc(view(B,"original_id")).get()),false);
   assert.equal(await can(()=>b.doc(view(B,"friends")).get()),false);
   assert.equal(await can(()=>b.doc(grant(B,"original_id")).get()),false);
   assert.equal(await can(()=>b.doc(grant(B,"original_id")).update({status:"active"})),false);
   assert.equal(await can(()=>b.doc("users/"+A).get()),false);
   assert.equal(await can(()=>b.doc(view(B,"original_id")).update({
     originalId:"@DEDA-XYZ999"})),false);
   // Issue another domain, then revoke original_id without touching friends.
   assert.equal((await issueFixture({idToken:token,domain:"friends"},deps)).status,
     "QA_FIXTURE_ISSUED");
   assert.equal(await can(()=>b.doc(view(B,"friends")).get()),true);
   const revoked=await revokeFixture({idToken:token,domain:"original_id"},deps);
   assert.equal(revoked.status,"QA_FIXTURE_REVOKED");
   assert.equal(await can(()=>b.doc(view(B,"original_id")).get()),false);
   assert.equal(await can(()=>b.doc(view(B,"friends")).get()),true);
   console.log("PASS_REAL_EMULATOR_ISSUE_REVOKE_PER_DOMAIN_NO_CROSS_UID");
   // Rotated session may not issue another grant, and no session write
   // touches production.
   current={...current,revision:13};
   const blocked=await issueFixture({idToken:token,domain:"wallet"},deps);
   assert.notEqual(blocked.status,"QA_FIXTURE_ISSUED");
   assert.equal(await can(()=>b.doc(view(B,"wallet")).get()),false);
   assert.deepEqual(fakeRoom.historicalUids,[A,B,C]);
   console.log("PASS_NO_NEW_UID_NO_RAW_HISTORIC_READ_NO_ASSET_MUTATION");
 }finally{await env.cleanup();}
});
