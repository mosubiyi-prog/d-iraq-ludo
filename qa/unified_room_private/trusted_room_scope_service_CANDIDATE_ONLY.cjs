"use strict";
// DEDA PRIVATE QA — trusted SERVER-ONLY planner skeleton, NOT deployed,
// NOT callable, NOT imported into functions/index.js.
// This emits a candidate plan only. It cannot grant access, write Firestore,
// issue Firebase token, or prove ownership of real accounts by itself.
// Never expose this interface to Flutter; all deps must be trusted backend.
// The independently reviewed owner proof is created OUTSIDE this module.
const DOMAINS=Object.freeze(["profile","original_id","premium_id","friends",
  "league","gifts","wallet","places"]);
const allowed=new Set(DOMAINS);
const UID=/^[A-Za-z0-9:_-]{6,128}$/;
const ID=/^@DEDA-[A-Z0-9]{6}$/;
const ACCOUNT=/^(?:07\d{9}|9647\d{9})$/;
const PROVIDERS=new Set(["google.com","password","phone"]);
function hold(reason) {
  return Object.freeze({decision:"HOLD",reason,grantIssued:false,
    productionAccess:false,canMutate:false,canIssueToken:false});
}
function validUID(x) {return typeof x==="string" && UID.test(x);}
async function assessServerProjection({idToken,domain,action="read_projection",nowMs}={},deps={}) {
  if (!allowed.has(domain)) return hold("INVALID_OR_ADMIN_DOMAIN");
  if (action!=="read_projection") return hold("NO_MUTATING_SCOPE");
  if (typeof idToken!=="string" || idToken.length<10 ||
      !Number.isSafeInteger(nowMs) ||
      typeof deps.verifyIdToken!=="function" ||
      typeof deps.readRoomForUid!=="function" ||
      typeof deps.readOwnerReview!=="function" ||
      typeof deps.readDomainProof!=="function")
    return hold("SERVER_DEPENDENCIES_UNAVAILABLE");
  let auth;
  try {auth=await deps.verifyIdToken(idToken,true);}
  catch(_) {return hold("TOKEN_NOT_VERIFIED_OR_REVOKED");}
  if (!validUID(auth?.uid) || !PROVIDERS.has(auth?.provider) ||
      auth?.anonymous!==false)
    return hold("NO_DURABLE_AUTH");
  let room;
  try{room=await deps.readRoomForUid(auth.uid);}
  catch(_){return hold("UNVERIFIED_ROOM_SOURCE");}
  if (!room || !ACCOUNT.test(room.accountKey||"") ||
      !ID.test(room.originalId||"") ||
      typeof room.canonicalAccountId!=="string" ||
      room.canonicalAccountId.length<12 ||
      !Array.isArray(room.historicalUids) ||
      room.historicalUids.length!==3 ||
      new Set(room.historicalUids).size!==3 ||
      !room.historicalUids.every(validUID) ||
      !room.historicalUids.includes(auth.uid))
    return hold("NO_VERIFIED_HISTORIC_ROOM");
  let review;
  try{review=await deps.readOwnerReview(room.canonicalAccountId,auth.uid);}
  catch(_){return hold("INDEPENDENT_REVIEW_UNAVAILABLE");}
  if (!review || review.source!=="independent_server_review" ||
      review.independentlyVerified!==true ||
      review.ownerApproved!==true ||
      review.accountKey!==room.accountKey ||
      review.originalId!==room.originalId ||
      review.canonicalAccountId!==room.canonicalAccountId ||
      review.authUid!==auth.uid ||
      review.backupVerified!==true ||
      review.rollbackDocumented!==true ||
      !Number.isSafeInteger(review.verifiedAtMs) ||
      review.verifiedAtMs>nowMs ||
      nowMs-review.verifiedAtMs>600000 ||
      typeof review.reviewId!=="string" || review.reviewId.length<12)
    return hold("OWNER_PROOF_PENDING");
  let proof;
  try{proof=await deps.readDomainProof(room.canonicalAccountId,domain);}
  catch(_){return hold("DOMAIN_SOURCE_UNAVAILABLE");}
  if (!proof || proof.trustedSource!=="independently_reviewed_domain" ||
      proof.status!=="approved" ||
      proof.domain!==domain ||
      proof.reviewId!==review.reviewId ||
      proof.canonicalAccountId!==room.canonicalAccountId ||
      proof.readerUid!==auth.uid ||
      !validUID(proof.sourceUid) ||
      !room.historicalUids.includes(proof.sourceUid) ||
      proof.originalId!==room.originalId ||
      proof.mayReadSanitizedProjection!==true ||
      proof.mayMutate===true ||
      !Number.isSafeInteger(proof.verifiedAtMs) ||
      proof.verifiedAtMs>nowMs ||
      nowMs-proof.verifiedAtMs>600000)
    return hold("NO_DOMAIN_SPECIFIC_PROOF");
  // Does NOT materialize a view or grant document. No Firebase authorization.
  // Potential future trusted service must create immutable sanitized view,
  // scoped short-lived grant, audit log and revocation mechanism *after* QA.
  return Object.freeze({
    decision:"SERVER_PROJECTION_PLAN_ONLY",
    reason:"INDEPENDENT_OWNER_AND_DOMAIN_REVIEWED_SYNTHETICALLY",
    plan:Object.freeze({
      canonicalAccountId:room.canonicalAccountId,readerUid:auth.uid,
      sourceUid:proof.sourceUid,originalId:room.originalId,domain,
      ownerReviewId:review.reviewId,
    }),
    grantIssued:false,productionAccess:false,canMutate:false,canIssueToken:false,
  });
}
module.exports={assessServerProjection,DOMAINS};
