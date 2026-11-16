"use strict";
// Fake server + fake atomic store. NO Firebase SDK or production connection.
const {test}=require("node:test");
const assert=require("node:assert/strict");
const {issueFixture,revokeFixture,trustedPayload,DOMAINS} =
  require("./room_grant_lifecycle_PRIVATE_OFFLINE_QA.cjs");
const A="QA_HISTORICAL_UID_A", B="QA_HISTORICAL_UID_B", C="QA_HISTORICAL_UID_C",
      D="QA_UNKNOWN_UID_D";
const key="9647712345678",original="@DEDA-ABC123",
      canonical="DEDA_CANONICAL_ROOM_QA_12345", now=1800000000000,
      token="SYNTHETIC_VERIFIED_TOKEN_2026";
const validValues={
  profile:{displayName:"QA Owner",level:14},
  original_id:{publicId:original},
  premium_id:{displayId:"@DEDA-ABCD",color:"gold"},
  friends:{friendCount:3},
  league:{weeklyPoints:45},
  gifts:{giftCount:2},
  wallet:{balanceDisplay:1000},
  places:{publishedPlaceCount:1}
};
function fixture() {
  const state={session:{uid:B,canonicalAccountId:canonical,revision:7,
      sessionNonce:"SERVER_SESSION_NONCE_1",active:true},
    auth:{uid:B,provider:"google.com",anonymous:false},
    room:{canonicalAccountId:canonical,accountKey:key,originalId:original,
      historicalUids:[A,B,C]},
    review:{source:"independent_server_review",independentlyVerified:true,
      ownerApproved:true,accountKey:key,originalId:original,canonicalAccountId:canonical,
      authUid:B,backupVerified:true,rollbackDocumented:true,verifiedAtMs:now-1000,
      reviewId:"SERVER_REVIEW_QA_001"},
    proofs:Object.fromEntries(Object.keys(validValues).map(domain=>[domain,{
      trustedSource:"independently_reviewed_domain",status:"approved",domain,
      reviewId:"SERVER_REVIEW_QA_001",canonicalAccountId:canonical,
      readerUid:B,sourceUid:domain==="friends"?C:A,originalId:original,
      mayReadSanitizedProjection:true,mayMutate:false,verifiedAtMs:now-1000
    }])),
    projects:structuredClone(validValues), writes:new Map(), audit:[], revoked:new Set(),
    issuedCount:0, revokeCount:0,
    failIssue:false, failRevoke:false, rotateBeforeCommit:false};
  const store={
    environment:"isolated-fake-only",
    issueAtomic:async ({plan,session,view,grant,expectedOwnerReview})=>{
      if(state.failIssue) throw Error("atomic write unavailable");
      if(state.rotateBeforeCommit) state.session.revision++;
      if(state.session.uid!==session.uid ||
         state.session.revision!==session.revision ||
         state.session.sessionNonce!==session.sessionNonce ||
         state.session.active!==true ||
         expectedOwnerReview!==state.review.reviewId ||
         grant.readerUid!==state.session.uid ||
         grant.domain!==view.domain ||
         grant.sourceUid!==view.sourceUid ||
         grant.originalId!==view.originalId ||
         grant.canonicalAccountId!==view.canonicalAccountId) return false;
      const k=plan.readerUid+"|"+plan.domain;
      if(state.revoked.has(k)) return false;
      if(state.writes.has(k)) {  // idempotent retry: do not extend expiry
        const old=state.writes.get(k);
        return old.view.originalId===view.originalId &&
          old.grant.sourceUid===grant.sourceUid;
      }
      // Fake transaction commits view+grant+audit as one operation.
      state.writes.set(k,{view,grant});
      state.audit.push({op:"issue",key:k,proof:expectedOwnerReview});
      state.issuedCount++;
      return true;
    },
    revokeAtomic:async ({readerUid,domain,session})=>{
      if(state.failRevoke) throw Error("atomic revoke unavailable");
      if(state.session.uid!==readerUid ||
         state.session.revision!==session.revision ||
         state.session.sessionNonce!==session.sessionNonce ||
         !state.session.active) return false;
      const k=readerUid+"|"+domain;
      if(!state.revoked.has(k)) {
        state.revoked.add(k);
        if(state.writes.has(k)){
          const current=state.writes.get(k);
          state.writes.set(k,{...current,grant:{...current.grant,status:"revoked"}});
        }
        state.audit.push({op:"revoke",key:k});
        state.revokeCount++;
      }
      return true;
    }
  };
  const deps={
    qaMode:"isolated-fake-only",store,clockMs:()=>now,
    verifyIdToken:async (received,checkRevoked)=>{
      assert.equal(checkRevoked,true);
      if(received!==token||state.tokenRevoked)throw Error("revoked or invalid");
      return {...state.auth};
    },
    readRoomForUid:async uid=>uid===state.auth.uid?structuredClone(state.room):null,
    readOwnerReview:async()=>structuredClone(state.review),
    readDomainProof:async(_,domain)=>structuredClone(state.proofs[domain]||null),
    readSession:async()=>structuredClone(state.session),
    buildProjection:async plan=>structuredClone(state.projects[plan.domain])
  };
  return {state,deps};
}
const issue=(f,domain="original_id")=>issueFixture({idToken:token,domain},f.deps);
const revoke=(f,domain="original_id")=>revokeFixture({idToken:token,domain},f.deps);
const expectHold=async (p,code)=>{
  const r=await p; assert.equal(r.status,"HOLD");if(code)assert.equal(r.reason,code);
  assert.equal(r.productionAccess,false);assert.equal(r.authTokenIssued,false);
  assert.equal(r.accountUidChanged,false);
};
test("01 issue one original_id scope with exact minimal server-side payload",async()=>{
 const f=fixture(),r=await issue(f);assert.equal(r.status,"QA_FIXTURE_ISSUED");
 const v=f.state.writes.get(B+"|original_id");
 assert.deepEqual(v.view.payload,validValues.original_id);
 assert.equal(v.grant.sourceUid,A);assert.equal(v.grant.status,"active");
 assert.equal(v.grant.expiresAtMs-v.grant.issuedAtMs,300000);
 assert.equal(f.state.audit.length,1);
 assert.equal(r.productionAccess,false);
});
test("02 all 8 room domains independently issued with no wildcard",async()=>{
 const f=fixture();
 assert.equal(Object.keys(DOMAINS).length,8);
 for(const d of Object.keys(DOMAINS))assert.equal((await issue(f,d)).status,"QA_FIXTURE_ISSUED");
 assert.equal(f.state.issuedCount,8);assert.equal(f.state.writes.size,8);
 assert.equal(f.state.writes.get(B+"|friends").grant.sourceUid,C);
});
test("03 repeated request idempotent without expiry extension",async()=>{
 const f=fixture();await issue(f);const at=f.state.writes.get(B+"|original_id").grant.expiresAtMs;
 assert.equal((await issue(f)).status,"QA_FIXTURE_ISSUED");
 assert.equal(f.state.issuedCount,1);assert.equal(f.state.writes.get(B+"|original_id").grant.expiresAtMs,at);
});
test("04 single scope revocation leaves other domains unchanged",async()=>{
 const f=fixture();await issue(f);await issue(f,"friends");
 assert.equal((await revoke(f)).status,"QA_FIXTURE_REVOKED");
 assert.equal(f.state.writes.get(B+"|original_id").grant.status,"revoked");
 assert.equal(f.state.writes.get(B+"|friends").grant.status,"active");
});
test("05 revoke twice safe and audit once",async()=>{
 const f=fixture();await issue(f);await revoke(f);await revoke(f);
 assert.equal(f.state.revokeCount,1);assert.equal(f.state.audit.length,2);
});
test("06 revoked review cannot be silently re-used for grant",async()=>{
 const f=fixture();await issue(f);await revoke(f);
 await expectHold(issue(f),"ATOMIC_ISSUE_REJECTED");
});
test("07 missing trusted QA mode fail closed",async()=>{
 const f=fixture();f.deps.qaMode="production";
 await expectHold(issue(f),"NO_ISOLATED_TRUSTED_BACKEND");
 assert.equal(f.state.writes.size,0);
});
test("08 wrong storage environment fails without issuing",async()=>{
 const f=fixture();f.deps.store.environment="live-firebase";
 await expectHold(issue(f),"NO_ISOLATED_TRUSTED_BACKEND");
});
test("09 cannot issue with anonymous Firebase UID",async()=>{
 const f=fixture();f.state.auth.anonymous=true;
 await expectHold(issue(f),"OWNER_OR_DOMAIN_PROOF_REJECTED:NO_DURABLE_AUTH");
});
test("10 PIN-only identity cannot issue",async()=>{
 const f=fixture();f.state.auth.provider="pin-only";
 await expectHold(issue(f),"OWNER_OR_DOMAIN_PROOF_REJECTED:NO_DURABLE_AUTH");
});
test("11 unknown D not an historical identity",async()=>{
 const f=fixture();f.state.auth.uid=D;
 await expectHold(issue(f),"OWNER_OR_DOMAIN_PROOF_REJECTED:NO_VERIFIED_HISTORIC_ROOM");
});
test("12 cannot create new Firebase UID for any room",async()=>{
 const f=fixture();await issue(f);
 assert.deepEqual(f.state.room.historicalUids,[A,B,C]);
 assert.equal(f.state.session.uid,B);
 assert.equal(f.state.writes.size,1);
});
test("13 deny when current session UID differs",async()=>{
 const f=fixture();f.state.session.uid=A;
 await expectHold(issue(f),"ACTIVE_SESSION_NOT_VERIFIED");
});
test("14 deny when session inactive",async()=>{
 const f=fixture();f.state.session.active=false;
 await expectHold(issue(f),"ACTIVE_SESSION_NOT_VERIFIED");
});
test("15 deny after an A-B-A session revision change during read",async()=>{
 const f=fixture();let calls=0;
 f.deps.readSession=async()=>{calls++;if(calls===2)f.state.session.revision++;
  return structuredClone(f.state.session);};
 await expectHold(issue(f),"SESSION_CHANGED_DURING_PROJECTION");
 assert.equal(f.state.issuedCount,0);
});
test("16 transaction re-check blocks change after pre-read",async()=>{
 const f=fixture();f.state.rotateBeforeCommit=true;
 await expectHold(issue(f),"ATOMIC_ISSUE_REJECTED");
 assert.equal(f.state.writes.size,0);
});
test("17 independent owner review absent",async()=>{
 const f=fixture();f.state.review=null;
 await expectHold(issue(f),"OWNER_OR_DOMAIN_PROOF_REJECTED:OWNER_PROOF_PENDING");
});
test("18 no backup evidence prevents issuing",async()=>{
 const f=fixture();f.state.review.backupVerified=false;
 await expectHold(issue(f),"OWNER_OR_DOMAIN_PROOF_REJECTED:OWNER_PROOF_PENDING");
});
test("19 missing source domain proof prevents issuing",async()=>{
 const f=fixture();delete f.state.proofs.original_id;
 await expectHold(issue(f),"OWNER_OR_DOMAIN_PROOF_REJECTED:NO_DOMAIN_SPECIFIC_PROOF");
});
test("20 cannot reuse premium_id proof for gifts",async()=>{
 const f=fixture();f.state.proofs.gifts.domain="premium_id";
 await expectHold(issue(f,"gifts"),"OWNER_OR_DOMAIN_PROOF_REJECTED:NO_DOMAIN_SPECIFIC_PROOF");
});
test("21 wrong original public ID stopped",async()=>{
 const f=fixture();f.state.room.originalId="@DEDA-ABCD";
 await expectHold(issue(f),"OWNER_OR_DOMAIN_PROOF_REJECTED:NO_VERIFIED_HISTORIC_ROOM");
});
test("22 unallowlisted balance fields never appear in view",async()=>{
 const f=fixture();f.state.projects.wallet={balanceDisplay:200,pin:"123456"};
 await expectHold(issue(f,"wallet"),"PROJECTION_NOT_ALLOWLISTED");
 assert.equal(f.state.writes.size,0);
});
test("23 friends view cannot contain real UID roster",async()=>{
 const f=fixture();f.state.projects.friends={friendCount:3,friendUids:[A,B]};
 await expectHold(issue(f,"friends"),"PROJECTION_NOT_ALLOWLISTED");
});
test("24 reject HTML unsanitized displayName",async()=>{
 const f=fixture();f.state.projects.profile={displayName:"<script>",level:1};
 await expectHold(issue(f,"profile"),"PROJECTION_NOT_ALLOWLISTED");
});
test("25 too-large or negative wallet values denied",async()=>{
 const f=fixture();f.state.projects.wallet={balanceDisplay:-5};
 await expectHold(issue(f,"wallet"),"PROJECTION_NOT_ALLOWLISTED");
});
test("26 reject unauthorized admin domain",async()=>{
 const f=fixture();await expectHold(issue(f,"admin"),"INVALID_OR_ADMIN_DOMAIN");
});
test("27 reject wildcard and unknown domain",async()=>{
 const f=fixture();await expectHold(issue(f,"*"),"INVALID_OR_ADMIN_DOMAIN");
 await expectHold(issue(f,"migration"),"INVALID_OR_ADMIN_DOMAIN");
});
test("28 atomic store failure leaves no grant and no audit",async()=>{
 const f=fixture();f.state.failIssue=true;
 await expectHold(issue(f),"OFFLINE_STORE_OR_BACKEND_UNAVAILABLE");
 assert.equal(f.state.writes.size,0);assert.equal(f.state.audit.length,0);
});
test("29 cannot revoke another reader's grant",async()=>{
 const f=fixture();await issue(f);
 f.state.auth.uid=A; // token now maps to A, but session remains B
 await expectHold(revoke(f),"SESSION_NOT_CURRENT");
 assert.equal(f.state.writes.get(B+"|original_id").grant.status,"active");
});
test("30 revoked token cannot revoke or issue",async()=>{
 const f=fixture();await issue(f);f.state.tokenRevoked=true;
 await expectHold(revoke(f),"REVOKE_DENIED_OR_BACKEND_UNAVAILABLE");
 await expectHold(issue(f),"OWNER_OR_DOMAIN_PROOF_REJECTED:TOKEN_NOT_VERIFIED_OR_REVOKED");
});
test("31 atomic revoke failure does not partially revoke",async()=>{
 const f=fixture();await issue(f);f.state.failRevoke=true;
 await expectHold(revoke(f),"REVOKE_DENIED_OR_BACKEND_UNAVAILABLE");
 assert.equal(f.state.writes.get(B+"|original_id").grant.status,"active");
});
test("32 no client-side view materialization, factory required",async()=>{
 const f=fixture();delete f.deps.buildProjection;
 await expectHold(issue(f),"NO_TRUSTED_PROJECTION_FACTORY");
});
test("33 no direct money, gift, or admin mutation methods",async()=>{
 const f=fixture();await issue(f,"wallet");await issue(f,"gifts");
 assert.equal(f.state.writes.get(B+"|wallet").view.payload.balanceDisplay,1000);
 assert.equal(f.state.writes.get(B+"|gifts").view.payload.giftCount,2);
 assert.equal(f.state.audit.every(x=>["issue","revoke"].includes(x.op)),true);
});
test("34 session switch during revocation fails transaction",async()=>{
 const f=fixture();await issue(f);
 const oldRevoke=f.deps.store.revokeAtomic;
 f.deps.store.revokeAtomic=async x=>{
   f.state.session.revision++;
   return oldRevoke(x);
 };
 await expectHold(revoke(f),"ATOMIC_REVOKE_REJECTED");
 assert.equal(f.state.writes.get(B+"|original_id").grant.status,"active");
});
test("35 empty payload never grants",async()=>{
 const f=fixture();f.state.projects.original_id={};
 await expectHold(issue(f),"PROJECTION_NOT_ALLOWLISTED");
});
test("36 only allowlisted display fields passed through unchanged",()=>{
 assert.deepEqual(trustedPayload("profile",{displayName:"DEDA",level:1}),
   {displayName:"DEDA",level:1});
 assert.equal(trustedPayload("profile",{accountKey:key}),null);
});
