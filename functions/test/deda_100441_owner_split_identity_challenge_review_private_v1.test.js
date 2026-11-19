"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {safeEvidenceAssessment,reviewReadiness,assessBCanonicalConsolidation}=
    require("../deda_100441_owner_split_identity_challenge_review_private_v1.js");
const nowMs=1800000000000;
const incidentCutoffMs=nowMs-5000000;
const originalId="@DEDA-ABC123";
const accountKey="07700000000";
const A="example-old-owner-A",B="example-pin-creator-B",C="example-social-C";
const challengeHash="a".repeat(64);

const snapshot=()=>({
  accountKey, originalId,
  route:{ownerUid:A,publicId:originalId,kind:"personal",active:true},
  directory:{createdUid:B,accountKey,active:true},
  credentials:{createdUid:B,accountKey,active:true},
  social:{ownerUid:C,publicId:originalId},
  originalUser:{accountKey,sharePersonalId:originalId},
  pinRegisteredUser:{accountKey,sharePersonalId:null},
  socialUser:{accountKey,sharePersonalId:originalId},
});
const pin=()=>({
  source:"trusted_server_checker",verified:true,
  rateLimitEnforced:true, accountKey,
  verifiedAtMs:nowMs-1000,challengeHash,
});
const independent=()=>({
  source:"trusted_independent_verifier",verified:true,
  kind:"pre_enrolled_original_device_key",
  accountKey,originalUid:A,verifiedAtMs:nowMs-900,
  priorEnrollmentOrProviderVerified:true,challengeHash,
  enrolledAtMs:incidentCutoffMs-100000,
});
const review=()=>({
  source:"independent_server_review",ownerApproved:true,
  accountKey,reviewedOriginalUid:A,
  originalSnapshotBackedUp:true,rollbackDocumented:true,
  reconciliationPlanDocumented:true,
  adminPrivilegesSeparatelyVerified:true,
  challengeHash,reviewedAtMs:nowMs-500,reviewers:["reviewer-one","reviewer-two"],
});
const check=(opts={})=>reviewReadiness({
  serverSnapshot:snapshot(),pinProof:pin(),independentProof:independent(),
  reviewRecord:review(),nowMs,incidentCutoffMs,...opts,
});
test("A/B/C three distinct UIDs must HOLD, not select a winner",()=>{
  const result=safeEvidenceAssessment(snapshot());
  assert.deepEqual(result,{
    decision:"HOLD",reason:"THREE_UID_SPLIT",loginPermitted:false,
  });
  assert.equal(Object.values(result).some(x=>x===A||x===B||x===C),false);
});
test("a missing canonical owner route cannot authorize anything",()=>{
  const s=snapshot();s.route.active=false;
  assert.equal(safeEvidenceAssessment(s).reason,"INCOMPLETE_CANONICAL_PROOF");
  assert.equal(check({serverSnapshot:s}).decision,"HOLD");
});
test("two UIDs with one shared owner must HOLD",()=>{
  const s=snapshot();s.social.ownerUid=A;
  assert.equal(safeEvidenceAssessment(s).reason,"PARTIAL_UID_SPLIT");
});
test("a fully coherent UID still requires separate Firebase Auth proof",()=>{
  const s=snapshot();s.directory.createdUid=A;s.credentials.createdUid=A;
  s.social.ownerUid=A;
  assert.deepEqual(safeEvidenceAssessment(s),{
    decision:"HOLD",reason:"CANONICAL_RECORDS_MATCH_AUTH_STILL_REQUIRED",
    loginPermitted:false,
  });
});
test("no PIN or PIN-only submission never becomes a login",()=>{
  assert.equal(check({pinProof:null}).reason,"NO_VALID_SERVER_PIN_PROOF");
  assert.equal(check({independentProof:null}).reason,
      "NO_TRUSTED_INDEPENDENT_FACTOR");
  assert.equal(check({independentProof:null}).loginPermitted,false);
});
test("PIN proof must have trusted server origin, rate limit and freshness",()=>{
  assert.equal(check({pinProof:{...pin(),source:"client"}}).decision,"HOLD");
  assert.equal(check({pinProof:{...pin(),rateLimitEnforced:false}}).decision,"HOLD");
  assert.equal(check({pinProof:{...pin(),verifiedAtMs:nowMs-1000000}})
      .reason,"NO_VALID_SERVER_PIN_PROOF");
});
test("a fake local phone or copied premium ID cannot replace an account key",()=>{
  assert.equal(check({pinProof:{...pin(),accountKey:"07711111111"}})
      .decision,"HOLD");
  const s=snapshot();s.originalId="@DEDA-AAAA";
  assert.equal(check({serverSnapshot:s}).reason,"UNVERIFIED_SERVER_SHAPE");
});
test("independent proof must bind a historical account UID, not an arbitrary UID",()=>{
  for (const candidate of [A,B,C]) {
    const proof={...independent(),originalUid:candidate};
    const result=check({independentProof:proof,
      reviewRecord:{...review(),reviewedOriginalUid:candidate}});
    assert.equal(result.decision,"CANDIDATE_FOR_SEPARATE_OWNER_REVIEW");
    assert.equal(result.loginPermitted,false);
    assert.equal("uid" in result,false);
    assert.equal("customToken" in result,false);
  }
  assert.equal(check({independentProof:{
    ...independent(),originalUid:"foreign-owner-not-in-account",
  }}).reason,"NO_TRUSTED_INDEPENDENT_FACTOR");
});

test("review must name same account and proven A/B/C UID as independent factor",()=>{
  assert.equal(check({reviewRecord:{...review(),reviewedOriginalUid:B}})
      .reason,"INDEPENDENT_REVIEW_INCOMPLETE");
  assert.equal(check({reviewRecord:{...review(),accountKey:"07799999999"}})
      .reason,"INDEPENDENT_REVIEW_INCOMPLETE");
  for (const uid of [A,B,C]) {
    const result=check({independentProof:{...independent(),originalUid:uid},
      reviewRecord:{...review(),reviewedOriginalUid:uid}});
    assert.equal(result.decision,"CANDIDATE_FOR_SEPARATE_OWNER_REVIEW");
    assert.equal(result.loginPermitted,false);
  }
});
test("independent proof must have previously trusted binding to an account UID",()=>{
  assert.equal(check({independentProof:{
    ...independent(),originalUid:"unrelated-other-account-uid",
  }}).reason,"NO_TRUSTED_INDEPENDENT_FACTOR");
  assert.equal(check({independentProof:{...independent(),source:"client"}})
      .decision,"HOLD");
  assert.equal(check({independentProof:{...independent(),
    priorEnrollmentOrProviderVerified:false}}).decision,"HOLD");
});
test("stale, mismatched and wrong-issuer second factors fail closed",()=>{
  assert.equal(check({independentProof:{...independent(),
    challengeHash:"b".repeat(64)}}).decision,"HOLD");
  assert.equal(check({independentProof:{...independent(),
    verifiedAtMs:nowMs-1000000}}).decision,"HOLD");
  assert.equal(check({independentProof:{...independent(),
    kind:"user_typed_pin"}}).decision,"HOLD");
});
test("late, absent or ungrounded pre-enrollment never qualifies as old owner proof",()=>{
  for (const enrolledAtMs of [undefined,null,incidentCutoffMs,
    incidentCutoffMs+1,nowMs+1000,0]) {
    const result=check({independentProof:{...independent(),enrolledAtMs}});
    assert.equal(result.reason,"NO_TRUSTED_INDEPENDENT_FACTOR");
    assert.equal(result.loginPermitted,false);
  }
  for (const cutoff of [undefined,null,0,NaN,nowMs+1000]) {
    const result=check({incidentCutoffMs:cutoff});
    assert.equal(result.reason,"NO_TRUSTED_INDEPENDENT_FACTOR");
  }
});
test("independent human review must follow both time-bound proofs",()=>{
  for (const reviewedAtMs of [nowMs-1100,nowMs-950]) {
    const result=check({reviewRecord:{...review(),reviewedAtMs}});
    assert.equal(result.reason,"INDEPENDENT_REVIEW_INCOMPLETE");
    assert.equal(result.loginPermitted,false);
  }
  // Equal timestamps are valid; ordering, not artificial delays, is required.
  const bothNow=nowMs-500;
  const result=check({pinProof:{...pin(),verifiedAtMs:bothNow},
    independentProof:{...independent(),verifiedAtMs:bothNow},
    reviewRecord:{...review(),reviewedAtMs:bothNow}});
  assert.equal(result.decision,"CANDIDATE_FOR_SEPARATE_OWNER_REVIEW");
  assert.equal(result.loginPermitted,false);
});
test("manual review cannot use the same reviewer twice or skip backup",()=>{
  assert.equal(check({reviewRecord:{...review(),reviewers:["same","same"]}})
      .reason,"INDEPENDENT_REVIEW_INCOMPLETE");
  assert.equal(check({reviewRecord:{...review(),
    originalSnapshotBackedUp:false}}).decision,"HOLD");
  assert.equal(check({reviewRecord:{...review(),
    rollbackDocumented:false}}).decision,"HOLD");
  assert.equal(check({reviewRecord:{...review(),
    adminPrivilegesSeparatelyVerified:false}}).decision,"HOLD");
});
test("even fictional complete evidence never authorizes a login, token or merge",()=>{
  const result=check();
  assert.deepEqual(result,{
    decision:"CANDIDATE_FOR_SEPARATE_OWNER_REVIEW",
    reason:"NO_AUTHORIZATION_ISSUED",loginPermitted:false,
  });
  assert.equal("uid" in result,false);
  assert.equal("customToken" in result,false);
});
test("bad/empty snapshot cannot authorize or reveal identities",()=>{
  for(const s of [null,{},[],{accountKey:"000",originalId:"bad"}]){
    const result=check({serverSnapshot:s});
    assert.equal(result.decision,"HOLD");
    assert.equal(result.loginPermitted,false);
  }
});

/* B is the registered canonical TARGET only. These are deliberately
   synthetic tests: passing them never grants rights over A/C or a live UID. */
const bScopes=()=>[
  ["original_id",A],["friends",C],["premium_id",A],
  ["gifts",A],["wallet",A],["league",B],["places",A],
  ["historical_progress",B],
].map(([domain,sourceUid])=>({
  domain,sourceUid,ownerApproved:true,independentVerified:true,
  sourceReceiptSha256:"b".repeat(64),
}));
const bBackups=()=>({
  firestoreAndAuthVerified:true,firebaseStorageVerified:true,
  originalPhoneLocalArchiveVerified:true,
  historicalPurchasesVerified:true,fullFinancialLedgerVerified:true,
  rollbackReadbackVerified:true,
});
function bCheck(options={}){
  return assessBCanonicalConsolidation({
    serverSnapshot:snapshot(),pinProof:pin(),
    independentProof:{...independent(),originalUid:B},
    reviewRecord:{...review(),reviewedOriginalUid:B},
    sourceScopeAttestations:{
      source:"trusted_independent_server_review",accountKey,originalId,
      targetRegistrationUid:B,scopes:bScopes(),
    },
    backupReadbacks:bBackups(),nowMs,incidentCutoffMs,...options,
  });
}
test("B chosen only as registration target; no transfer even when QA proofs complete",()=>{
  const x=bCheck();
  assert.equal(x.decision,"REVIEW_CANDIDATE_B_REGISTRATION_ONLY");
  assert.equal(x.bIsRegistrationUid,true);
  assert.equal(x.readyForIndependentReview,true);
  assert.equal(x.canMerge,false);
  assert.equal(x.canAuthenticate,false);
  assert.equal(x.canTransferAssets,false);
  assert.equal(x.financialRestoreEnabled,false);
  assert.equal(x.productionWrites,false);
  assert.equal(Object.values(x).includes(A)||Object.values(x).includes(B),false);
});
test("A/C factor alone never promotes B to a verified owner",()=>{
  assert.equal(bCheck({independentProof:independent()}).reason,
    "INDEPENDENT_B_OWNERSHIP_NOT_ESTABLISHED");
  assert.equal(bCheck({reviewRecord:review()}).reason,
    "INDEPENDENT_B_OWNERSHIP_NOT_ESTABLISHED");
});
test("fake/duplicate/missing rights scopes refuse a B consolidation",()=>{
  const s={source:"trusted_independent_server_review",accountKey,originalId,
    targetRegistrationUid:B,scopes:bScopes()};
  for(const v of [null,[],s.scopes.slice(1),
    [...s.scopes.slice(0,-1),s.scopes[0]],
    s.scopes.map(x=>x.domain==="friends"?{...x,independentVerified:false}:x),
    s.scopes.map(x=>x.domain==="wallet"?{...x,sourceReceiptSha256:"x"}:x)]){
    const x=bCheck({sourceScopeAttestations:
      v===null?null:{...s,scopes:v}});
    assert.equal(x.canTransferAssets,false);
    assert.equal(x.decision,"HOLD");
  }
  assert.equal(bCheck({sourceScopeAttestations:{...s,source:"client"}})
    .decision,"HOLD");
  assert.equal(bCheck({sourceScopeAttestations:{...s,scopes:
    bScopes().map(x=>x.domain==="original_id"?{...x,sourceUid:B}:x)}})
    .decision,"HOLD");
  assert.equal(bCheck({sourceScopeAttestations:{...s,scopes:
    bScopes().map(x=>x.domain==="friends"?{...x,sourceUid:A}:x)}})
    .decision,"HOLD");
});
test("encrypted cloud backup alone cannot substitute original phone and purchases",()=>{
  for(const missing of Object.keys(bBackups())){
    const backup=bBackups();backup[missing]=false;
    const x=bCheck({backupReadbacks:backup});
    assert.equal(x.reason,"COMPLETE_LOSSLESS_RECOVERY_SOURCES_MISSING");
    assert.equal(x.canMerge,false);
  }
  assert.equal(bCheck({backupReadbacks:null}).decision,"HOLD");
});
test("untrusted canonical lineage and missing independent PIN proof stay blocked",()=>{
  const s=snapshot();s.directory.createdUid="foreign-registry";
  assert.equal(bCheck({serverSnapshot:s}).decision,"HOLD");
  assert.equal(bCheck({pinProof:null}).decision,"HOLD");
  assert.equal(bCheck({independentProof:null}).decision,"HOLD");
});
