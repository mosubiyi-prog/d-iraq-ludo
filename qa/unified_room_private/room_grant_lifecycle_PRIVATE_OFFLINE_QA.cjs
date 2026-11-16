"use strict";
// DEDA PRIVATE OFFLINE QA ONLY. NOT a deployed Function, API or auth service.
// Uses a fake trusted backend and a fake atomic store. Never reaches Firebase.
// It never signs in, makes UIDs, changes user profiles, spends assets or
// creates auth tokens. A successful result is NEVER production authorization.
const {assessServerProjection} = require("./trusted_room_scope_service_CANDIDATE_ONLY.cjs");
const DOMAINS = Object.freeze({
  profile: ["displayName", "level"],
  original_id: ["publicId"],
  premium_id: ["displayId", "color"],
  friends: ["friendCount"],
  league: ["weeklyPoints"],
  gifts: ["giftCount"],
  wallet: ["balanceDisplay"],
  places: ["publishedPlaceCount"],
});
const allowed = new Set(Object.keys(DOMAINS));
const durationMs = 5 * 60 * 1000;
const uid = x => typeof x === "string" && /^[A-Za-z0-9:_-]{6,128}$/.test(x);
const failure = reason => Object.freeze({status:"HOLD",reason,productionAccess:false,
  authTokenIssued:false,accountUidChanged:false});
const ok = (status,domain) => Object.freeze({status,domain,productionAccess:false,
  authTokenIssued:false,accountUidChanged:false});
function valueOkay(key,v) {
  if (["level","weeklyPoints","friendCount","giftCount","publishedPlaceCount","balanceDisplay"].includes(key))
    return Number.isSafeInteger(v) && v >= 0 && v <= 1000000000;
  if (typeof v !== "string" || v.length < 1 || v.length > 96) return false;
  if (key === "publicId") return /^@DEDA-[A-Z0-9]{6}$/.test(v);
  if (key === "displayId") return /^@DEDA-[A-Z0-9]{4,12}$/.test(v);
  if (key === "color") return ["gold","diamond","royal","pink"].includes(v);
  return key === "displayName" && !/[<>]/.test(v);
}
function trustedPayload(domain,raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const keys=Object.keys(raw), permitted=DOMAINS[domain];
  if (!permitted || keys.length === 0 || keys.length > permitted.length ||
      !keys.every(k=>permitted.includes(k) && valueOkay(k,raw[k]))) return null;
  return Object.freeze(Object.fromEntries(keys.map(k=>[k,raw[k]])));
}
function stableSession(x,plan) {
  return x && x.active===true && x.uid===plan.readerUid &&
    x.canonicalAccountId===plan.canonicalAccountId &&
    typeof x.sessionNonce==="string" && x.sessionNonce.length>=12 &&
    Number.isSafeInteger(x.revision) && x.revision>0;
}
function sameSession(a,b) {
  return a.uid===b.uid && a.canonicalAccountId===b.canonicalAccountId &&
    a.revision===b.revision && a.sessionNonce===b.sessionNonce && b.active===true;
}
function offlineDeps(deps,requireWrite=true) {
  return deps?.qaMode === "isolated-fake-only" &&
    deps.store?.environment === "isolated-fake-only" &&
    typeof deps.clockMs==="function" &&
    typeof deps.readSession==="function" &&
    typeof deps.verifyIdToken==="function" &&
    typeof deps.readRoomForUid==="function" &&
    typeof deps.readOwnerReview==="function" &&
    typeof deps.readDomainProof==="function" &&
    (!requireWrite || (typeof deps.store.issueAtomic==="function" &&
      typeof deps.store.revokeAtomic==="function"));
}
async function issueFixture({idToken,domain}={},deps={}) {
  if (!allowed.has(domain)) return failure("INVALID_OR_ADMIN_DOMAIN");
  if (typeof idToken!=="string" || idToken.length<10 || !offlineDeps(deps))
    return failure("NO_ISOLATED_TRUSTED_BACKEND");
  const now=deps.clockMs();
  if (!Number.isSafeInteger(now) || now<1) return failure("INVALID_SERVER_CLOCK");
  const review=await assessServerProjection(
    {idToken,domain,action:"read_projection",nowMs:now},deps);
  if (review.decision!=="SERVER_PROJECTION_PLAN_ONLY")
    return failure("OWNER_OR_DOMAIN_PROOF_REJECTED:"+review.reason);
  const plan=review.plan;
  try {
    const before=await deps.readSession(plan.readerUid);
    if (!stableSession(before,plan)) return failure("ACTIVE_SESSION_NOT_VERIFIED");
    // This factory must be an injected trusted backend function, never a
    // client-supplied payload, ID alias or Firebase SDK bypass.
    if (typeof deps.buildProjection!=="function")
      return failure("NO_TRUSTED_PROJECTION_FACTORY");
    const raw=await deps.buildProjection(plan);
    const payload=trustedPayload(domain,raw);
    if (!payload) return failure("PROJECTION_NOT_ALLOWLISTED");
    const after=await deps.readSession(plan.readerUid);
    if (!stableSession(after,plan) || !sameSession(before,after))
      return failure("SESSION_CHANGED_DURING_PROJECTION");
    // Atomic store implementation MUST re-check active session INSIDE its
    // transaction before granting. This test fake does that.
    const expiresAtMs=now+durationMs;
    const view=Object.freeze({
      readerUid:plan.readerUid,domain,canonicalAccountId:plan.canonicalAccountId,
      sourceUid:plan.sourceUid,originalId:plan.originalId,scopeVersion:1,
      payload
    });
    const grant=Object.freeze({
      readerUid:plan.readerUid,domain,canonicalAccountId:plan.canonicalAccountId,
      sourceUid:plan.sourceUid,originalId:plan.originalId,scopeVersion:1,
      status:"active",proofKind:"independent_verified",
      issuedAtMs:now,expiresAtMs
    });
    const committed=await deps.store.issueAtomic({
      plan,session:before,view,grant,expectedOwnerReview:plan.ownerReviewId
    });
    if (committed!==true) return failure("ATOMIC_ISSUE_REJECTED");
    return ok("QA_FIXTURE_ISSUED",domain);
  } catch(_) {
    return failure("OFFLINE_STORE_OR_BACKEND_UNAVAILABLE");
  }
}
async function revokeFixture({idToken,domain}={},deps={}) {
  if (!allowed.has(domain)) return failure("INVALID_OR_ADMIN_DOMAIN");
  if (typeof idToken!=="string" || idToken.length<10 || !offlineDeps(deps))
    return failure("NO_ISOLATED_TRUSTED_BACKEND");
  try {
    // Separate identity check: revocation does not require asset ownership
    // evidence, since revocation only reduces access.
    const auth=await deps.verifyIdToken(idToken,true);
    if (!uid(auth?.uid) || auth.anonymous!==false ||
        !["password","google.com","phone"].includes(auth.provider))
      return failure("NO_DURABLE_OWNER_SESSION");
    const current=await deps.readSession(auth.uid);
    if (!current || current.active!==true || current.uid!==auth.uid)
      return failure("SESSION_NOT_CURRENT");
    const revoked=await deps.store.revokeAtomic({
      readerUid:auth.uid,domain,session:current
    });
    if (revoked!==true) return failure("ATOMIC_REVOKE_REJECTED");
    return ok("QA_FIXTURE_REVOKED",domain);
  } catch(_) {
    return failure("REVOKE_DENIED_OR_BACKEND_UNAVAILABLE");
  }
}
module.exports={issueFixture,revokeFixture,trustedPayload,DOMAINS};
