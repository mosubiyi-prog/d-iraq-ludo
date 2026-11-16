"use strict";
const {test}=require("node:test");
const assert=require("node:assert/strict");
const {assessServerProjection,DOMAINS}=require("./trusted_room_scope_service_CANDIDATE_ONLY.cjs");
const A="QA_HISTORICAL_UID_A",B="QA_HISTORICAL_UID_B",C="QA_HISTORICAL_UID_C",D="QA_UNKNOWN_UID_D";
const original="@DEDA-ABC123",key="9647712345678",canonical="DEDA_CANONICAL_ROOM_QA_12345",now=1800000000000;
const fixture=()=>({
  auth:{uid:B,provider:"google.com",anonymous:false},
  room:{canonicalAccountId:canonical,accountKey:key,originalId:original,
    historicalUids:[A,B,C]},
  review:{source:"independent_server_review",independentlyVerified:true,
    ownerApproved:true,accountKey:key,originalId:original,
    canonicalAccountId:canonical,authUid:B,backupVerified:true,
    rollbackDocumented:true,verifiedAtMs:now-20000,
    reviewId:"SERVER_REVIEW_QA_001"},
  proof:{trustedSource:"independently_reviewed_domain",status:"approved",
    domain:"original_id",reviewId:"SERVER_REVIEW_QA_001",
    canonicalAccountId:canonical,readerUid:B,sourceUid:A,
    originalId:original,mayReadSanitizedProjection:true,
    mayMutate:false,verifiedAtMs:now-20000},
});
const ctx=x=>({
  verifyIdToken:async(token,checkRevoked)=>{
    assert.equal(checkRevoked,true,"must check revoked Auth ID token");
    if(x.revoked) throw Error("revoked");
    return x.auth;
  },
  readRoomForUid:async uid=>{assert.equal(uid,x.auth.uid);return x.room;},
  readOwnerReview:async (cid,uid)=>{assert.equal(cid,canonical);return x.review;},
  readDomainProof:async (cid,domain)=>{assert.equal(cid,canonical);return x.proof;},
});
const go=async(x,domain="original_id",action="read_projection")=>
  assessServerProjection({idToken:"SYNTHETIC_TOKEN_ONLY_12345",domain,action,nowMs:now},ctx(x));
async function hold(mut,reason,domain="original_id",action="read_projection"){
  const x=fixture();mut(x);const result=await go(x,domain,action);
  assert.equal(result.decision,"HOLD");assert.equal(result.reason,reason);
  assert.equal(result.grantIssued,false);assert.equal(result.canMutate,false);
}
test("01 B with independent owner + original-ID scope gets PLAN not grant",async()=>{
  const result=await go(fixture());
  assert.equal(result.decision,"SERVER_PROJECTION_PLAN_ONLY");
  assert.equal(result.grantIssued,false);
  assert.equal(result.productionAccess,false);
  assert.equal(result.canIssueToken,false);
  assert.equal(result.plan.readerUid,B);
  assert.equal(result.plan.sourceUid,A);
});
test("02 all eight supported domains require their own proof",async()=>{
  assert.equal(DOMAINS.length,8);
  for(const domain of DOMAINS){
    const x=fixture();x.proof.domain=domain;
    const r=await go(x,domain);assert.equal(r.decision,"SERVER_PROJECTION_PLAN_ONLY");
    assert.equal(r.grantIssued,false);
  }
});
test("03 admin cannot inherit old GM role",async()=>hold(()=>{},
  "INVALID_OR_ADMIN_DOMAIN","admin"));
test("04 no wildcard domain",async()=>hold(()=>{},"INVALID_OR_ADMIN_DOMAIN","*"));
test("05 never allow spend",async()=>hold(()=>{},"NO_MUTATING_SCOPE","wallet","spend"));
test("06 never allow gift claim",async()=>hold(()=>{},"NO_MUTATING_SCOPE","gifts","claim"));
test("07 never allow legacy write",async()=>hold(()=>{},"NO_MUTATING_SCOPE","original_id","rekey"));
test("08 revoked ID token",async()=>hold(x=>{x.revoked=true;},"TOKEN_NOT_VERIFIED_OR_REVOKED"));
test("09 anonymous UID",async()=>hold(x=>{x.auth.anonymous=true;},"NO_DURABLE_AUTH"));
test("10 unverified PIN only",async()=>hold(x=>{x.auth.provider="pin-only";},"NO_DURABLE_AUTH"));
test("11 D is not enrolled in historical room",async()=>hold(x=>{
  x.auth.uid=D;x.review.authUid=D;x.proof.readerUid=D;
},"NO_VERIFIED_HISTORIC_ROOM"));
test("12 historical duplicate UID",async()=>hold(x=>{
  x.room.historicalUids=[A,A,C];
},"NO_VERIFIED_HISTORIC_ROOM"));
test("13 no independent owner review",async()=>hold(x=>{
  x.review=null;
},"OWNER_PROOF_PENDING"));
test("14 PIN approval not independent",async()=>hold(x=>{
  x.review.source="local_pin_only";
},"OWNER_PROOF_PENDING"));
test("15 independent review must be bound to current UID",async()=>hold(x=>{
  x.review.authUid=C;
},"OWNER_PROOF_PENDING"));
test("16 backup must be preserved",async()=>hold(x=>{
  x.review.backupVerified=false;
},"OWNER_PROOF_PENDING"));
test("17 old owner review expires",async()=>hold(x=>{
  x.review.verifiedAtMs=now-700000;
},"OWNER_PROOF_PENDING"));
test("18 scoped domain does not open another",async()=>hold(x=>{
  x.proof.domain="friends";
},"NO_DOMAIN_SPECIFIC_PROOF"));
test("19 section proof must match review challenge",async()=>hold(x=>{
  x.proof.reviewId="OTHER_SERVER_REVIEW";
},"NO_DOMAIN_SPECIFIC_PROOF"));
test("20 source UID must be A, B or C",async()=>hold(x=>{
  x.proof.sourceUid=D;
},"NO_DOMAIN_SPECIFIC_PROOF"));
test("21 no cross account projection",async()=>hold(x=>{
  x.proof.originalId="@DEDA-XYZ999";
},"NO_DOMAIN_SPECIFIC_PROOF"));
test("22 per-domain proof must be fresh",async()=>hold(x=>{
  x.proof.verifiedAtMs=now-700000;
},"NO_DOMAIN_SPECIFIC_PROOF"));
test("23 no client-declared mutation",async()=>hold(x=>{
  x.proof.mayMutate=true;
},"NO_DOMAIN_SPECIFIC_PROOF"));
test("24 proof is not a receipt of ownership if not independently reviewed",async()=>hold(x=>{
  x.proof.trustedSource="client_payload";
},"NO_DOMAIN_SPECIFIC_PROOF"));
test("25 deny read if dependent proof lookup fails",async()=>{
  const x=fixture();
  const deps=ctx(x);
  deps.readDomainProof=async()=>{throw Error("network");};
  const r=await assessServerProjection({
    idToken:"SYNTHETIC_TOKEN_ONLY_12345",domain:"original_id",
    action:"read_projection",nowMs:now},deps);
  assert.equal(r.decision,"HOLD");assert.equal(r.reason,"DOMAIN_SOURCE_UNAVAILABLE");
});
