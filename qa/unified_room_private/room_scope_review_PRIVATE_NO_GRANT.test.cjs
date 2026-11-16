"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {planRoomRead, DOMAINS} = require("./room_scope_review_PRIVATE_NO_GRANT.cjs");
const A="HISTORICAL_UID_A_123", B="HISTORICAL_UID_B_123", C="HISTORICAL_UID_C_123";
const D="UNKNOWN_UID_D_123";
const key="9647712345678", id="@DEDA-ABC123";
const now=1800000000000;
const base={
  origin:"private-offline-synthetic",
  auth:{uid:B, anonymous:false,provider:"durable-verified",epoch:13},
  session:{uid:B,epoch:13,accountKey:key},
  room:{accountKey:key,originalId:id,historicalUids:[A,B,C]},
  review:{status:"INDEPENDENT_OWNER_REVIEWED",accountKey:key,originalId:id,callerUid:B,
          reviewedAtMs:now-15000,separatelyAudited:true,reviewId:"REVIEW_SYNTHETIC_001"},
  scope:{domain:"original_id",accountKey:key,originalId:id,readerUid:B,sourceUid:A,
         independentlyReviewed:true,sourceStatus:"HISTORIC_UNMODIFIED",
         reviewId:"REVIEW_SYNTHETIC_001"},
  domain:"original_id",action:"read_projection",nowMs:now,
};
const clone=()=>structuredClone(base);
function result(x){return planRoomRead(x)}
function hold(change,why) { const x=clone();change(x);const a=result(x);
  assert.equal(a.decision,"HOLD");assert.equal(a.reason,why);
  assert.equal(a.grantsAccess,false);assert.equal(a.grantsWrite,false); }
test("01 scope reviewed: read plan candidate only, never a grant",()=>{
  const a=result(clone());assert.equal(a.decision,"READ_PLAN_CANDIDATE");
  assert.equal(a.grantsAccess,false);assert.equal(a.issuesToken,false);
  assert.equal(a.requiresTrustedServerEnforcement,true);
});
test("02 all 8 named domains but no universal wildcard",()=>{
  assert.equal(DOMAINS.size,8);
  for(const name of DOMAINS){let x=clone();x.domain=name;x.scope.domain=name;
    assert.equal(result(x).decision,"READ_PLAN_CANDIDATE");}
  hold(x=>{x.domain="*";x.scope.domain="*";},"UNKNOWN_DOMAIN");
});
test("03 fail closed unknown UID D",()=>hold(x=>{
  x.auth.uid=D;x.session.uid=D;x.review.callerUid=D;x.scope.readerUid=D;
},"INVALID_OR_UNLINKED_HISTORICAL_ROOM"));
test("04 fail closed anonymous",()=>hold(x=>x.auth.anonymous=true,
  "NO_DURABLE_AUTH_OBSERVATION"));
test("05 fail closed PIN or unverified provider",()=>hold(x=>x.auth.provider="pin-only",
  "NO_DURABLE_AUTH_OBSERVATION"));
test("06 fail closed absent trusted snapshot marker",()=>hold(x=>x.origin="client",
  "NO_SYNTHETIC_REVIEW_CONTEXT"));
test("07 fail closed UID switched after fetch",()=>hold(x=>x.session.uid=A,
  "SESSION_IDENTITY_CHANGED_OR_MISSING"));
test("08 fail closed A-B-A observer epoch change",()=>hold(x=>x.session.epoch=12,
  "SESSION_IDENTITY_CHANGED_OR_MISSING"));
test("09 fail closed different accountKey",()=>hold(x=>x.session.accountKey="9647800000000",
  "SESSION_IDENTITY_CHANGED_OR_MISSING"));
test("10 fail closed duplicate historic UID",()=>hold(x=>x.room.historicalUids=[A,A,C],
  "INVALID_OR_UNLINKED_HISTORICAL_ROOM"));
test("11 fail closed unreviewed cross UID source",()=>hold(x=>x.scope.independentlyReviewed=false,
  "NO_DOMAIN_SPECIFIC_SOURCE_REVIEW"));
test("12 fail closed scope from another user",()=>hold(x=>x.scope.readerUid=A,
  "NO_DOMAIN_SPECIFIC_SOURCE_REVIEW"));
test("13 fail closed source not A/B/C",()=>hold(x=>x.scope.sourceUid=D,
  "NO_DOMAIN_SPECIFIC_SOURCE_REVIEW"));
test("14 fail closed unrelated domain scope",()=>hold(x=>x.scope.domain="friends",
  "NO_DOMAIN_SPECIFIC_SOURCE_REVIEW"));
test("15 fail closed approval tied to other account",()=>hold(x=>x.review.accountKey="9647800000000",
  "NO_RECENT_INDEPENDENT_OWNER_REVIEW"));
test("16 fail closed local trustedInstall or PIN-only review",()=>hold(x=>x.review.status="PIN_VERIFIED",
  "NO_RECENT_INDEPENDENT_OWNER_REVIEW"));
test("17 fail closed stale independent review",()=>hold(x=>x.review.reviewedAtMs=now-700000,
  "NO_RECENT_INDEPENDENT_OWNER_REVIEW"));
test("18 fail closed missing independent audit",()=>hold(x=>x.review.separatelyAudited=false,
  "NO_RECENT_INDEPENDENT_OWNER_REVIEW"));
test("19 fail closed mismatched challenge/review ID",()=>hold(x=>x.scope.reviewId="OTHER_CHALLENGE_999",
  "NO_DOMAIN_SPECIFIC_SOURCE_REVIEW"));
test("20 fail closed copied premium alias as original ID",()=>hold(x=>x.room.originalId="@DEDA-ABCD",
  "INVALID_OR_UNLINKED_HISTORICAL_ROOM"));
test("21 refuse wallets debit even with all proofs",()=>hold(x=>{
  x.domain="wallet";x.scope.domain="wallet";x.action="spend";
},"NO_CROSS_UID_MUTATION"));
test("22 refuse gift claim even with all proofs",()=>hold(x=>{
  x.domain="gifts";x.scope.domain="gifts";x.action="claim";
},"NO_CROSS_UID_MUTATION"));
test("23 refuse league XP award even with all proofs",()=>hold(x=>{
  x.domain="league";x.scope.domain="league";x.action="award_points";
},"NO_CROSS_UID_MUTATION"));
test("24 admin remains independent admins/UID role",()=>hold(x=>{
  x.domain="administration";x.action="read_projection";
},"ADMIN_UID_ROLE_SEPARATE"));
test("25 no map or owner reassignment",()=>hold(x=>x.action="reassign_owner",
  "NO_CROSS_UID_MUTATION"));
test("26 scope cannot claim historical data was rewritten",()=>hold(x=>{
  x.scope.sourceStatus="REKEYED";
},"NO_DOMAIN_SPECIFIC_SOURCE_REVIEW"));
test("27 expired or replayed per-section review ID",()=>hold(x=>x.scope.reviewId="short",
  "NO_DOMAIN_SPECIFIC_SOURCE_REVIEW"));
test("28 no review for changed UID",()=>hold(x=>x.review.callerUid=A,
  "NO_RECENT_INDEPENDENT_OWNER_REVIEW"));
test("29 no account ID transfer",()=>hold(x=>x.scope.originalId="@DEDA-XYZ999",
  "NO_DOMAIN_SPECIFIC_SOURCE_REVIEW"));
test("30 missing review always HOLD",()=>hold(x=>delete x.review,
  "NO_RECENT_INDEPENDENT_OWNER_REVIEW"));
