"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  safeEvidenceAssessment,
  reviewReadiness,
} = require("../functions/deda_100441_owner_split_identity_challenge_review_private_v1");

const ACCOUNT = "9647712345678";
const ID = "@DEDA-ABC123";
const A = "uid-old-owner-A";
const B = "uid-old-registration-B";
const C = "uid-old-social-C";
const now = 1770134000000; // synthetic test time
const cutoff = now - 80000;
const hash = "a".repeat(64);

function historicalSnapshot() {
  return {
    accountKey: ACCOUNT, originalId: ID,
    route: {publicId: ID, kind:"personal", active:true, ownerUid:A},
    directory: {accountKey:ACCOUNT, active:true, createdUid:B},
    credentials: {accountKey:ACCOUNT, active:true, createdUid:B},
    social: {publicId:ID, ownerUid:C},
    originalUser: {accountKey:ACCOUNT, sharePersonalId:ID},
    pinRegisteredUser: {accountKey:ACCOUNT},
    socialUser: {accountKey:ACCOUNT, sharePersonalId:ID},
  };
}
function verifiedProofs() {
  return {
    serverSnapshot:historicalSnapshot(),
    nowMs:now,
    incidentCutoffMs:cutoff,
    pinProof: {
      source:"trusted_server_checker", rateLimitEnforced:true,
      verified:true, accountKey:ACCOUNT, challengeHash:hash,
      verifiedAtMs:now-900,
    },
    independentProof: {
      source:"trusted_independent_verifier", verified:true,
      kind:"pre_enrolled_original_device_key",
      originalUid:A, accountKey:ACCOUNT, challengeHash:hash,
      verifiedAtMs:now-800, priorEnrollmentOrProviderVerified:true,
      enrolledAtMs:cutoff-10000,
    },
    reviewRecord: {
      source:"independent_server_review", ownerApproved:true,
      accountKey:ACCOUNT, reviewedOriginalUid:A, challengeHash:hash,
      originalSnapshotBackedUp:true, rollbackDocumented:true,
      reconciliationPlanDocumented:true,
      adminPrivilegesSeparatelyVerified:true,
      reviewedAtMs:now-100,
      reviewers:["trusted-reviewer-one","trusted-reviewer-two"],
    },
  };
}

test("split history is detected without deciding an owner", () => {
  const observed=safeEvidenceAssessment(historicalSnapshot());
  assert.equal(observed.decision,"HOLD");
  assert.equal(observed.reason,"THREE_UID_SPLIT");
  assert.equal(observed.loginPermitted,false);
});

test("known PIN + phone alone cannot recover a split legacy account", () => {
  const input=verifiedProofs();
  delete input.independentProof;
  const result=reviewReadiness(input);
  assert.equal(result.reason,"NO_TRUSTED_INDEPENDENT_FACTOR");
  assert.equal(result.loginPermitted,false);
});

test("unverified or replayed PIN fails closed", () => {
  const input=verifiedProofs();
  input.pinProof.verifiedAtMs=now-3600000;
  assert.equal(reviewReadiness(input).reason,"NO_VALID_SERVER_PIN_PROOF");
  assert.equal(reviewReadiness({...verifiedProofs(),pinProof:null}).loginPermitted,false);
});

test("recently enrolled device cannot pretend to predate the incident", () => {
  const input=verifiedProofs();
  input.independentProof.enrolledAtMs=cutoff+1;
  assert.equal(reviewReadiness(input).reason,"NO_TRUSTED_INDEPENDENT_FACTOR");
  assert.equal(reviewReadiness(input).loginPermitted,false);
});

test("a different historical account or wrong UID cannot claim this record", () => {
  let input=verifiedProofs();
  input.independentProof.originalUid="new-unknown-uid-D";
  assert.equal(reviewReadiness(input).reason,"NO_TRUSTED_INDEPENDENT_FACTOR");
  input=verifiedProofs();
  input.independentProof.accountKey="9647700000000";
  assert.equal(reviewReadiness(input).reason,"NO_TRUSTED_INDEPENDENT_FACTOR");
});

test("independent recovery factor and dual reviewer must agree on same UID", () => {
  const input=verifiedProofs();
  input.reviewRecord.reviewedOriginalUid=B;
  assert.equal(reviewReadiness(input).reason,"INDEPENDENT_REVIEW_INCOMPLETE");
  input.reviewRecord.reviewedOriginalUid=A;
  input.reviewRecord.reviewers=["one-reviewer","one-reviewer"];
  assert.equal(reviewReadiness(input).reason,"INDEPENDENT_REVIEW_INCOMPLETE");
});

test("a good full review can ONLY become candidate; NEVER a login or transfer", () => {
  const reviewed=reviewReadiness(verifiedProofs());
  assert.deepEqual(reviewed,{
    decision:"CANDIDATE_FOR_SEPARATE_OWNER_REVIEW",
    reason:"NO_AUTHORIZATION_ISSUED",
    loginPermitted:false,
  });
  assert.equal(Object.hasOwn(reviewed,"uid"),false);
  assert.equal(Object.hasOwn(reviewed,"token"),false);
  assert.equal(Object.hasOwn(reviewed,"canModifyAdmin"),false);
});

test("credential shape mismatch still stops even after a good device proof", () => {
  const input=verifiedProofs();
  input.serverSnapshot.credentials.createdUid=A;
  const blocked=reviewReadiness(input);
  assert.equal(blocked.reason,"INCOMPLETE_CANONICAL_PROOF");
  assert.equal(blocked.loginPermitted,false);
});


// OFFLINE CUTOVER REHEARSAL — test fixtures only. No Firebase SDK, no live
// UID authority, no server calls, and no production migration implementation.
// The reviewed proof objects below are SYNTHETIC; the real verifier must
// independently authenticate their provenance before any future cutover.
function syntheticOneAccountDocuments() {
  const s=historicalSnapshot();
  return {
    directory:{...s.directory,revision:10},
    credentials:{...s.credentials,revision:11},
    route:{...s.route,revision:12},
    social:{...s.social,revision:13},
    users:{
      [A]:{accountKey:ACCOUNT,sharePersonalId:ID},
      [B]:{accountKey:ACCOUNT,sharePersonalId:null},
      [C]:{accountKey:ACCOUNT,sharePersonalId:ID},
    },
    // A rehearsal must not invent, zero, duplicate or grant any assets.
    financial:{diamonds:321,receipts:["gift-1","league-1"],weekScore:45},
    admin:{roles:["unrelated-admin"],entryAllowed:false},
    anotherAccount:{accountKey:"9647700000000",ownerUid:"other-real-owner"},
    session:null,
    googleLinked:false,
  };
}

function offlineReconciliationRehearsal(proofs, documents, expectedRevisions) {
  const hold=(reason)=>({
    outcome:"HOLD",reason,changedCollections:[],writeCount:0,
    tokenIssued:false,googleLinked:false,
  });
  const ownerReview=reviewReadiness(proofs);
  if(ownerReview.decision!=="CANDIDATE_FOR_SEPARATE_OWNER_REVIEW" ||
      ownerReview.loginPermitted!==false) return hold("INDEPENDENT_PROOF_REQUIRED");

  const historical=proofs.serverSnapshot;
  if(!documents || !expectedRevisions ||
      !documents.users || !documents.users[proofs.independentProof.originalUid] ||
      documents.users[proofs.independentProof.originalUid].accountKey !==
          historical.accountKey) return hold("TARGET_USER_SOURCE_MISMATCH");

  const checks=[
    ["directory","createdUid",historical.directory.createdUid],
    ["credentials","createdUid",historical.credentials.createdUid],
    ["route","ownerUid",historical.route.ownerUid],
    ["social","ownerUid",historical.social.ownerUid],
  ];
  for(const [name,field,oldUid] of checks) {
    const doc=documents[name];
    if(!doc || doc[field]!==oldUid ||
        !Number.isSafeInteger(expectedRevisions[name]) ||
        expectedRevisions[name]!==doc.revision) {
      return hold("STALE_OR_CONFLICTING_SERVER_SNAPSHOT");
    }
  }
  if(documents.directory.accountKey!==historical.accountKey ||
      documents.credentials.accountKey!==historical.accountKey ||
      documents.route.publicId!==historical.originalId ||
      documents.social.publicId!==historical.originalId) {
    return hold("CROSS_ACCOUNT_SOURCE_MISMATCH");
  }

  // Staged synthetic proposal. Never mutate the original documents; in the
  // real service Auth and Firestore cannot be committed atomically.
  const staged=structuredClone(documents);
  const target=proofs.independentProof.originalUid;
  const changedCollections=[];
  for(const [name,field] of checks) {
    if(staged[name][field]!==target) {
      staged[name][field]=target;
      changedCollections.push(name);
    }
  }
  if(staged.users[target].sharePersonalId!==historical.originalId) {
    staged.users[target].sharePersonalId=historical.originalId;
    changedCollections.push("target-user-projection");
  }
  return {
    outcome:"OFFLINE_PROPOSAL_ONLY",
    changedCollections,staged,writeCount:0,tokenIssued:false,
    googleLinked:false,cutoverAuthorized:false,
  };
}

function syntheticRevisions(docs) {
  return Object.fromEntries(
      ["directory","credentials","route","social"]
          .map(name=>[name,docs[name].revision]));
}

test("offline surgery: no independent proof means no proposed UID changes",()=>{
  const docs=syntheticOneAccountDocuments();
  const before=structuredClone(docs);
  const proofs=verifiedProofs();
  delete proofs.independentProof;
  const result=offlineReconciliationRehearsal(
      proofs,docs,syntheticRevisions(docs));
  assert.equal(result.outcome,"HOLD");
  assert.equal(result.reason,"INDEPENDENT_PROOF_REQUIRED");
  assert.deepEqual(result.changedCollections,[]);
  assert.deepEqual(docs,before);
});

test("offline surgery: A/B/C are candidates only when matching synthetic independent review",()=>{
  for(const uid of [A,B,C]) {
    const proofs=verifiedProofs();
    proofs.independentProof.originalUid=uid;
    proofs.reviewRecord.reviewedOriginalUid=uid;
    const docs=syntheticOneAccountDocuments();
    const before=structuredClone(docs);
    const plan=offlineReconciliationRehearsal(
        proofs,docs,syntheticRevisions(docs));
    assert.equal(plan.outcome,"OFFLINE_PROPOSAL_ONLY");
    assert.equal(plan.writeCount,0);
    assert.equal(plan.tokenIssued,false);
    assert.equal(plan.googleLinked,false);
    assert.equal(plan.cutoverAuthorized,false);
    assert.equal(plan.staged.directory.createdUid,uid);
    assert.equal(plan.staged.credentials.createdUid,uid);
    assert.equal(plan.staged.route.ownerUid,uid);
    assert.equal(plan.staged.social.ownerUid,uid);
    assert.equal(plan.staged.users[uid].sharePersonalId,ID);
    assert.deepEqual(plan.staged.financial,before.financial);
    assert.deepEqual(plan.staged.admin,before.admin);
    assert.deepEqual(plan.staged.anotherAccount,before.anotherAccount);
    assert.equal(plan.staged.session,null);
    assert.deepEqual(docs,before);
  }
});

test("offline surgery: revision race or changed route fails closed without a partial proposal",()=>{
  const docs=syntheticOneAccountDocuments();
  const before=structuredClone(docs);
  const expected=syntheticRevisions(docs);
  expected.route-=1;
  const raced=offlineReconciliationRehearsal(
      verifiedProofs(),docs,expected);
  assert.equal(raced.outcome,"HOLD");
  assert.equal(raced.reason,"STALE_OR_CONFLICTING_SERVER_SNAPSHOT");
  assert.deepEqual(docs,before);
  docs.route.ownerUid="untrusted-different-owner";
  const mismatch=offlineReconciliationRehearsal(
      verifiedProofs(),docs,syntheticRevisions(docs));
  assert.equal(mismatch.outcome,"HOLD");
  assert.deepEqual(mismatch.changedCollections,[]);
});

test("offline surgery: foreign account and reviewer mismatch never produce a plan",()=>{
  const docs=syntheticOneAccountDocuments();
  docs.directory.accountKey="9647700000000";
  assert.equal(offlineReconciliationRehearsal(
      verifiedProofs(),docs,syntheticRevisions(docs)).outcome,"HOLD");
  const proofs=verifiedProofs();
  proofs.reviewRecord.reviewedOriginalUid=B;
  assert.equal(offlineReconciliationRehearsal(
      proofs,syntheticOneAccountDocuments(),
      syntheticRevisions(syntheticOneAccountDocuments())).outcome,"HOLD");
});


// Extend the SAME offline-only recovery rehearsal with journal/replay and
// rollback checks. This is a SYNTHETIC state-machine model, NOT Firebase Admin
// SDK code. A successful result never authorizes a real cutover.
function offlineJournalAndRollbackRehearsal({
  proofs, documents, expectedRevisions, priorJournal = null,
  failAfterStagedStep = null, corruptReadback = false,
}) {
  const before = structuredClone(documents);
  const plan = offlineReconciliationRehearsal(
      proofs, documents, expectedRevisions);
  const safe = (outcome, reason) => ({
    outcome, reason, restored:structuredClone(before),
    actualWriteCount:0, tokenIssued:false, googleLinked:false,
    cutoverAuthorized:false,
  });
  if(plan.outcome !== "OFFLINE_PROPOSAL_ONLY") {
    return safe("HOLD", plan.reason);
  }
  // Only synthetic revisions and a verified test-fixture target enter this
  // key. It is NOT a trustworthy production operation or approval identifier.
  const revisionNames=["directory","credentials","route","social"];
  const key = JSON.stringify([
    proofs.serverSnapshot.accountKey, proofs.independentProof.originalUid,
    ...revisionNames.map(name => expectedRevisions[name]),
  ]);
  if(priorJournal !== null) {
    if(priorJournal.key === key &&
        priorJournal.state === "SIMULATED_COMPLETED") {
      return safe("REPLAY_NOOP", "ALREADY_SIMULATED");
    }
    return safe("HOLD", "PRIOR_JOURNAL_CONFLICT_OR_INCOMPLETE");
  }

  const working=structuredClone(before);
  const target=proofs.independentProof.originalUid;
  for(const [index, section] of plan.changedCollections.entries()) {
    if(section === "target-user-projection") {
      working.users[target] = structuredClone(plan.staged.users[target]);
    } else {
      working[section] = structuredClone(plan.staged[section]);
    }
    // An interruption at ANY stage must not leave a partial proposal as
    // a usable output. The caller only receives a restored synthetic image.
    if(failAfterStagedStep === index + 1) {
      return safe("ROLLBACK_SIMULATED", "INTERRUPTED_STAGED_CHANGE");
    }
  }
  if(corruptReadback) {
    // Deliberate simulated concurrent overwrite, never written to Firebase.
    working.route.ownerUid = "foreign-live-owner";
  }

  const reconciled = [
    working.directory.createdUid,
    working.credentials.createdUid,
    working.route.ownerUid,
    working.social.ownerUid,
  ].every(uid => uid === target) &&
      working.users[target].accountKey === proofs.serverSnapshot.accountKey &&
      working.users[target].sharePersonalId === proofs.serverSnapshot.originalId;
  const protectedDomainsUnchanged = [
    "financial","admin","anotherAccount","session","googleLinked",
  ].every(name => JSON.stringify(working[name]) === JSON.stringify(before[name]));
  const historicalUsersUntouched = [A,B,C].every(uid =>
    uid === target || JSON.stringify(working.users[uid]) ===
      JSON.stringify(before.users[uid]));
  if(!reconciled || !protectedDomainsUnchanged ||
      !historicalUsersUntouched) {
    return safe("ROLLBACK_SIMULATED", "POST_STAGE_READBACK_FAILED");
  }
  return {
    outcome:"SIMULATED_COMPLETED", staged:working,
    journal:{key,state:"SIMULATED_COMPLETED"},
    actualWriteCount:0,tokenIssued:false,googleLinked:false,
    cutoverAuthorized:false,
  };
}

test("offline journal: interrupted staged changes rollback for every target UID",()=>{
  for(const target of [A,B,C]) {
    const proofs=verifiedProofs();
    proofs.independentProof.originalUid=target;
    proofs.reviewRecord.reviewedOriginalUid=target;
    const docs=syntheticOneAccountDocuments();
    const before=structuredClone(docs);
    const plan=offlineReconciliationRehearsal(
        proofs,docs,syntheticRevisions(docs));
    assert.ok(plan.changedCollections.length > 0);
    for(let failedStep=1;failedStep<=plan.changedCollections.length;failedStep++){
      const stopped=offlineJournalAndRollbackRehearsal({
        proofs,documents:docs,expectedRevisions:syntheticRevisions(docs),
        failAfterStagedStep:failedStep,
      });
      assert.equal(stopped.outcome,"ROLLBACK_SIMULATED");
      assert.deepEqual(stopped.restored,before);
      assert.equal(stopped.actualWriteCount,0);
      assert.equal(stopped.cutoverAuthorized,false);
      assert.deepEqual(docs,before);
    }
  }
});

test("offline journal: identical replay does nothing; changed journal refuses",()=>{
  const docs=syntheticOneAccountDocuments();
  const before=structuredClone(docs);
  const args={proofs:verifiedProofs(),documents:docs,
    expectedRevisions:syntheticRevisions(docs)};
  const first=offlineJournalAndRollbackRehearsal(args);
  assert.equal(first.outcome,"SIMULATED_COMPLETED");
  assert.equal(first.actualWriteCount,0);
  assert.equal(first.tokenIssued,false);
  assert.equal(first.googleLinked,false);
  assert.equal(first.cutoverAuthorized,false);
  const replay=offlineJournalAndRollbackRehearsal({
    ...args,priorJournal:first.journal,
  });
  assert.equal(replay.outcome,"REPLAY_NOOP");
  assert.deepEqual(replay.restored,before);
  assert.deepEqual(docs,before);
  const conflict=offlineJournalAndRollbackRehearsal({
    ...args,priorJournal:{...first.journal,key:"different-attempt"},
  });
  assert.equal(conflict.outcome,"HOLD");
  assert.equal(conflict.reason,"PRIOR_JOURNAL_CONFLICT_OR_INCOMPLETE");
  const incomplete=offlineJournalAndRollbackRehearsal({
    ...args,priorJournal:{...first.journal,state:"IN_PROGRESS"},
  });
  assert.equal(incomplete.outcome,"HOLD");
});

test("offline journal: altered readback triggers rollback, protects assets",()=>{
  const docs=syntheticOneAccountDocuments();
  const before=structuredClone(docs);
  const r=offlineJournalAndRollbackRehearsal({
    proofs:verifiedProofs(),documents:docs,
    expectedRevisions:syntheticRevisions(docs),
    corruptReadback:true,
  });
  assert.equal(r.outcome,"ROLLBACK_SIMULATED");
  assert.equal(r.reason,"POST_STAGE_READBACK_FAILED");
  assert.deepEqual(r.restored,before);
  assert.deepEqual(docs,before);
  assert.equal(r.tokenIssued,false);
});

test("offline journal: stale snapshot or missing ownership proof blocks before staging",()=>{
  const docs=syntheticOneAccountDocuments();
  const revisions=syntheticRevisions(docs);
  revisions.social++;
  const r=offlineJournalAndRollbackRehearsal({
    proofs:verifiedProofs(),documents:docs,expectedRevisions:revisions,
  });
  assert.equal(r.outcome,"HOLD");
  assert.equal(r.reason,"STALE_OR_CONFLICTING_SERVER_SNAPSHOT");
  const proofs=verifiedProofs();
  proofs.independentProof=null;
  const noProof=offlineJournalAndRollbackRehearsal({
    proofs,documents:docs,expectedRevisions:syntheticRevisions(docs),
  });
  assert.equal(noProof.outcome,"HOLD");
  assert.equal(noProof.reason,"INDEPENDENT_PROOF_REQUIRED");
});


// ACCOUNT-DOMAIN REHEARSAL: use only synthetic, owner-scoped snapshots. Real
// assets cannot be generated from these fixtures. A missing source is UNKNOWN,
// never a zero balance or a reason to reissue receipts.
function syntheticDomainReadback() {
  const weeklyId="deda-weekly-2026-11-07-DEDA-ABC123";
  const friendUid="unrelated-friend-1";
  const pairKey=[A,friendUid].sort().join("__");
  return {
    friendships:[{
      id:pairKey,pairKey,members:[A,friendUid],
      requesterUid:A,recipientUid:friendUid,status:"accepted",
    }],
    gifts:[
      {id:"existing-gift-1",targetPublicId:ID,amount:10,sourceType:"manual"},
      {id:weeklyId,giftId:weeklyId,targetPublicId:ID,amount:50,
        sourceType:"weekly_league",status:"received"},
    ],
    wallet:{publicId:ID,balance:60},
    weekly:{originalId:ID,score:45},
    premium:{originalId:ID,activeId:"@DEDA-PREMIUM"},
    publishedPlaces:[{placeId:"one-established-place",ownerUid:A}],
  };
}
function offlineDomainReadbackGate(proofs, documents, sources) {
  const hold=reason=>Object.freeze({
    outcome:"HOLD",reason,actualWriteCount:0,
    giftsReissued:0,grantsIssued:0,restorationCertified:false,
  });
  const staged=offlineJournalAndRollbackRehearsal({
    proofs,documents,expectedRevisions:syntheticRevisions(documents),
  });
  if(staged.outcome!=="SIMULATED_COMPLETED" || !sources) {
    return hold("REVIEW_OR_DOMAIN_SNAPSHOT_UNAVAILABLE");
  }
  const originalId=proofs.serverSnapshot.originalId;
  const target=proofs.independentProof.originalUid;
  const historical=new Set([
    proofs.serverSnapshot.route.ownerUid,
    proofs.serverSnapshot.directory.createdUid,
    proofs.serverSnapshot.social.ownerUid,
  ]);
  if(!Array.isArray(sources.friendships)||!Array.isArray(sources.gifts)||
     !Array.isArray(sources.publishedPlaces)|| !sources.wallet||
     !sources.weekly || !sources.premium) {
    return hold("UNPROVEN_DOMAIN_SOURCE_NOT_ZERO");
  }
  const seenPairKeys=new Set();
  for(const item of sources.friendships) {
    if(!item||!Array.isArray(item.members)||item.members.length!==2||
       item.members[0]===item.members[1]||
       !item.members.includes(item.requesterUid)||
       !item.members.includes(item.recipientUid) ||
       item.requesterUid===item.recipientUid ||
       !["accepted","pending","rejected"].includes(item.status)) {
      return hold("FRIENDSHIP_SOURCE_INVALID");
    }
    const pairKey=[...item.members].sort().join("__");
    if(item.id!==pairKey||item.pairKey!==pairKey||
       seenPairKeys.has(item.id)) {
      return hold("FRIENDSHIP_PAIRKEY_COLLISION");
    }
    seenPairKeys.add(item.id);
    // A friend relation still keyed under a different A/B/C UID must receive
    // independent reconciliation, NOT an automatic re-created invitation.
    if(item.members.some(uid=>historical.has(uid) && uid!==target)) {
      return hold("HISTORICAL_FRIEND_UID_REQUIRES_RECONCILIATION");
    }
  }
  const seenGifts=new Set();
  for(const item of sources.gifts) {
    if(!item||typeof item.id!=="string"||!item.id ||
       seenGifts.has(item.id)||
       item.targetPublicId!==originalId ||
       !Number.isSafeInteger(item.amount)||item.amount<=0) {
      return hold("GIFT_RECEIPT_MISSING_OR_DUPLICATE");
    }
    seenGifts.add(item.id);
    if(item.sourceType==="weekly_league" &&
       (item.giftId!==item.id ||
        !/^deda-weekly-20\d{2}-\d{2}-\d{2}-DEDA-[A-Z0-9]{6}$/.test(item.id)||
        !item.id.endsWith("-"+originalId.slice(1))||
        !["received","pending","claimed"].includes(item.status))) {
      return hold("WEEKLY_RECEIPT_PROVENANCE_CONFLICT");
    }
  }
  if(sources.wallet.publicId!==originalId ||
     !Number.isSafeInteger(sources.wallet.balance)||
     sources.wallet.balance<0||
     sources.weekly.originalId!==originalId ||
     !Number.isSafeInteger(sources.weekly.score)||
     sources.weekly.score<0 ||
     sources.premium.originalId!==originalId ||
     typeof sources.premium.activeId!=="string") {
    return hold("WALLET_LEAGUE_OR_PREMIUM_SOURCE_CONFLICT");
  }
  const seenPlaces=new Set();
  for(const place of sources.publishedPlaces) {
    if(!place||typeof place.placeId!=="string"||!place.placeId||
       seenPlaces.has(place.placeId)) {
      return hold("PLACE_SOURCE_INVALID");
    }
    seenPlaces.add(place.placeId);
    if(historical.has(place.ownerUid) && place.ownerUid!==target) {
      return hold("HISTORICAL_PLACE_UID_REQUIRES_RECONCILIATION");
    }
  }
  return Object.freeze({
    outcome:"READBACK_PRESERVED_IN_SYNTHETIC_FIXTURE_ONLY",
    existingFriendships:sources.friendships.length,
    existingGiftReceipts:sources.gifts.length,
    existingPlaces:sources.publishedPlaces.length,
    actualWriteCount:0,giftsReissued:0,grantsIssued:0,
    restorationCertified:false,
  });
}

test("offline domain readback: matching UID preserves existing friend, gifts and league without issuance",()=>{
  const docs=syntheticOneAccountDocuments();
  const original=structuredClone(docs);
  const sources=syntheticDomainReadback();
  const snapshot=structuredClone(sources);
  const result=offlineDomainReadbackGate(verifiedProofs(),docs,sources);
  assert.equal(result.outcome,"READBACK_PRESERVED_IN_SYNTHETIC_FIXTURE_ONLY");
  assert.equal(result.existingFriendships,1);
  assert.equal(result.existingGiftReceipts,2);
  assert.equal(result.existingPlaces,1);
  assert.equal(result.actualWriteCount,0);
  assert.equal(result.giftsReissued,0);
  assert.equal(result.grantsIssued,0);
  assert.equal(result.restorationCertified,false);
  assert.deepEqual(docs,original);
  assert.deepEqual(sources,snapshot);
});

test("offline domain readback: historical friend and place links on another UID require separate review",()=>{
  const docs=syntheticOneAccountDocuments();
  const sources=syntheticDomainReadback();
  const friendUid="unrelated-friend-2";
  const pairKey=[C,friendUid].sort().join("__");
  sources.friendships.push({
    id:pairKey,pairKey,members:[C,friendUid],requesterUid:C,
    recipientUid:friendUid,status:"accepted",
  });
  let result=offlineDomainReadbackGate(verifiedProofs(),docs,sources);
  assert.equal(result.reason,"HISTORICAL_FRIEND_UID_REQUIRES_RECONCILIATION");
  assert.equal(result.restorationCertified,false);
  sources.friendships.pop();
  sources.publishedPlaces[0].ownerUid=B;
  result=offlineDomainReadbackGate(verifiedProofs(),docs,sources);
  assert.equal(result.reason,"HISTORICAL_PLACE_UID_REQUIRES_RECONCILIATION");
  assert.equal(result.actualWriteCount,0);
});

test("offline domain readback: duplicate pair keys and receipts fail closed",()=>{
  const docs=syntheticOneAccountDocuments();
  const sources=syntheticDomainReadback();
  sources.friendships.push(structuredClone(sources.friendships[0]));
  assert.equal(offlineDomainReadbackGate(verifiedProofs(),docs,sources).reason,
      "FRIENDSHIP_PAIRKEY_COLLISION");
  sources.friendships.pop();
  sources.gifts.push(structuredClone(sources.gifts[0]));
  assert.equal(offlineDomainReadbackGate(verifiedProofs(),docs,sources).reason,
      "GIFT_RECEIPT_MISSING_OR_DUPLICATE");
  assert.equal(offlineDomainReadbackGate(verifiedProofs(),docs,sources).giftsReissued,0);
});

test("offline domain readback: missing, cross-account and forged weekly source never means empty/zero",()=>{
  const docs=syntheticOneAccountDocuments();
  const sources=syntheticDomainReadback();
  sources.wallet=null;
  assert.equal(offlineDomainReadbackGate(verifiedProofs(),docs,sources).reason,
      "UNPROVEN_DOMAIN_SOURCE_NOT_ZERO");
  sources.wallet={publicId:"@DEDA-OTHER1",balance:60};
  assert.equal(offlineDomainReadbackGate(verifiedProofs(),docs,sources).reason,
      "WALLET_LEAGUE_OR_PREMIUM_SOURCE_CONFLICT");
  sources.wallet={publicId:ID,balance:60};
  sources.gifts[1].giftId="unrelated-weekly-receipt";
  assert.equal(offlineDomainReadbackGate(verifiedProofs(),docs,sources).reason,
      "WEEKLY_RECEIPT_PROVENANCE_CONFLICT");
  const noOwner=verifiedProofs();
  noOwner.independentProof=null;
  assert.equal(offlineDomainReadbackGate(noOwner,docs,syntheticDomainReadback()).reason,
      "REVIEW_OR_DOMAIN_SNAPSHOT_UNAVAILABLE");
});


// PREMIUM DISPLAY ID REHEARSAL — pure synthetic account/source fixtures.
// An @DEDA premium alias is presentation data, never Firebase Auth UID, a
// substitute for immutable originalId, a session key or an owner grant.
// Actual Stage71 grants and Stage74 receipts require real authenticated
// server reads; this offline test cannot establish historical ownership.
const PREMIUM_COLORS=Object.freeze(["gold","diamond","royal","pink"]);
const PREMIUM_IDS=Object.freeze({
  gold:"@DEDA-GLD001", diamond:"@DEDA-DIA001",
  royal:"@DEDA-ROY001", pink:"@DEDA-PNK001",
});
function syntheticPremiumDisplayEvidence({
  color="gold",kind="self_used",group="001",alias=null,
}={}) {
  const activeId=alias||PREMIUM_IDS[color];
  const record={
    identifier:activeId,recipientOriginalId:ID,
    baseColor:color,kind,group,
  };
  return {
    stage71Active:{originalId:ID,activeId},
    ownedGrants:[record],
    receivedGiftReceipts:kind==="gifted" ? [{
      identifier:activeId,originalId:ID,group,
      receivedAtTrustedServerTimestamp:true,
    }] : [],
    // Optional Spark projections are distinct from Stage71 ownership.
    publicActive:{originalId:ID,activeId,baseColor:color},
    publicRoutes:{[activeId]:{aliasId:activeId,originalId:ID,baseColor:color}},
    requestedDisplayId:activeId,
  };
}
function offlinePremiumDisplayReadback({
  proofs,documents,evidence,liveUid,
}) {
  const stop=(reason)=>Object.freeze({
    outcome:"HOLD",reason,writeCount:0,authTransitions:0,
    loginPermitted:false, ownershipGranted:false,restorationCertified:false,
  });
  const review=reviewReadiness(proofs);
  if(review.decision!=="CANDIDATE_FOR_SEPARATE_OWNER_REVIEW" ||
      review.loginPermitted!==false) return stop("HISTORICAL_OWNER_REVIEW_REQUIRED");
  const originalId=proofs.serverSnapshot.originalId;
  const targetUid=proofs.independentProof.originalUid;
  if(liveUid!==targetUid ||
      documents?.users?.[targetUid]?.accountKey!==proofs.serverSnapshot.accountKey ||
      !/^@DEDA-[A-Z0-9]{6}$/.test(originalId)) {
    return stop("LIVE_AUTH_UID_NOT_ORIGINAL_OWNER");
  }
  // A premium alias is never read from client preferences to resolve Auth.
  // Missing Stage71 source is UNKNOWN, not evidence that no premium ID exists.
  if(!evidence || !evidence.stage71Active) {
    return stop("ACTIVE_PREMIUM_SELECTION_UNVERIFIED_NOT_ZERO");
  }
  const selected=evidence.stage71Active;
  if(selected.originalId!==originalId ||
      typeof selected.activeId!=="string") {
    return stop("ACTIVE_PREMIUM_SOURCE_CROSS_ACCOUNT");
  }
  const active=selected.activeId;
  if(active===originalId) {
    if(evidence.requestedDisplayId!=null &&
       evidence.requestedDisplayId!==originalId) {
      return stop("STALE_PREMIUM_DISPLAY_NOT_ACTIVE");
    }
    return Object.freeze({
      outcome:"SYNTHETIC_CANONICAL_DISPLAY_ONLY",displayId:originalId,
      canonicalId:originalId,authUid:liveUid,writeCount:0,authTransitions:0,
      loginPermitted:false,ownershipGranted:false,restorationCertified:false,
    });
  }
  if(!/^@DEDA-[A-Z0-9]{4,12}$/.test(active) ||
      evidence.requestedDisplayId!==active ||
      !Array.isArray(evidence.ownedGrants)) {
    return stop("UNVERIFIED_OR_STALE_PREMIUM_ALIAS");
  }
  const seen=new Set();
  for(const grant of evidence.ownedGrants) {
    if(!grant||typeof grant.identifier!=="string"||
        seen.has(grant.identifier)) return stop("PREMIUM_GRANT_DUPLICATE_OR_INVALID");
    seen.add(grant.identifier);
  }
  const matching=evidence.ownedGrants.filter(x=>x.identifier===active);
  if(matching.length!==1) return stop("PREMIUM_GRANT_NOT_FOUND");
  const grant=matching[0];
  if(grant.recipientOriginalId!==originalId ||
      !PREMIUM_COLORS.includes(grant.baseColor) ||
      !["001","002"].includes(grant.group) ||
      !["self_used","gifted"].includes(grant.kind)) {
    return stop("PREMIUM_GRANT_OWNER_COLOR_OR_GROUP_CONFLICT");
  }
  if(grant.kind==="gifted") {
    if(!Array.isArray(evidence.receivedGiftReceipts)) {
      return stop("PREMIUM_GIFT_RECEIPT_UNVERIFIED");
    }
    const matches=evidence.receivedGiftReceipts.filter(x=>x?.identifier===active);
    if(matches.length!==1 ||
        matches[0].originalId!==originalId ||
        matches[0].group!==grant.group ||
        matches[0].receivedAtTrustedServerTimestamp!==true) {
      return stop("PREMIUM_GIFT_RECEIPT_UNVERIFIED");
    }
  }
  // Spark publishing can be disabled; absence is not a reason to discard
  // an existing Stage71 grant. If a projection is present it must agree.
  const publicActive=evidence.publicActive;
  if(publicActive!=null &&
      (publicActive.originalId!==originalId ||
       publicActive.activeId!==active ||
       publicActive.baseColor!==grant.baseColor)) {
    return stop("ACTIVE_PREMIUM_PROJECTION_CONFLICT");
  }
  const route=evidence.publicRoutes?.[active];
  if(route!=null &&
      (route.aliasId!==active || route.originalId!==originalId ||
       route.baseColor!==grant.baseColor)) {
    return stop("PREMIUM_PUBLIC_ROUTE_CONFLICT");
  }
  // Never claim a successful Auth recovery. Only the known verified test UID
  // and canonical ID appear here, and no source object is ever mutated.
  return Object.freeze({
    outcome:"SYNTHETIC_PREMIUM_DISPLAY_ONLY",
    displayId:active,canonicalId:originalId,
    authUid:liveUid,baseColor:grant.baseColor,
    writeCount:0,authTransitions:0,loginPermitted:false,
    ownershipGranted:false,restorationCertified:false,
  });
}

test("premium 200: all four colors and both reserved groups stay display-only",()=>{
  for(const uid of [A,B,C]) for(const color of PREMIUM_COLORS)
    for(const group of ["001","002"]) {
      const proofs=verifiedProofs();
      proofs.independentProof.originalUid=uid;
      proofs.reviewRecord.reviewedOriginalUid=uid;
      const docs=syntheticOneAccountDocuments();
      const before=structuredClone(docs);
      const evidence=syntheticPremiumDisplayEvidence({color,group});
      const evidenceBefore=structuredClone(evidence);
      const result=offlinePremiumDisplayReadback({
        proofs,documents:docs,evidence,liveUid:uid,
      });
      assert.equal(result.outcome,"SYNTHETIC_PREMIUM_DISPLAY_ONLY");
      assert.equal(result.displayId,PREMIUM_IDS[color]);
      assert.equal(result.canonicalId,ID);
      assert.equal(result.authUid,uid);
      assert.equal(result.baseColor,color);
      assert.equal(result.authTransitions,0);
      assert.equal(result.writeCount,0);
      assert.equal(result.loginPermitted,false);
      assert.equal(result.ownershipGranted,false);
      assert.equal(result.restorationCertified,false);
      assert.deepEqual(docs,before);
      assert.deepEqual(evidence,evidenceBefore);
    }
});

test("premium 200: received gift requires matching independent Stage74 receipt",()=>{
  const docs=syntheticOneAccountDocuments();
  const evidence=syntheticPremiumDisplayEvidence({
    color:"royal",kind:"gifted",group:"002",
  });
  const valid=offlinePremiumDisplayReadback({
    proofs:verifiedProofs(),documents:docs,evidence,liveUid:A,
  });
  assert.equal(valid.outcome,"SYNTHETIC_PREMIUM_DISPLAY_ONLY");
  evidence.receivedGiftReceipts=[];
  assert.equal(offlinePremiumDisplayReadback({
    proofs:verifiedProofs(),documents:docs,evidence,liveUid:A,
  }).reason,"PREMIUM_GIFT_RECEIPT_UNVERIFIED");
  evidence.receivedGiftReceipts=[{
    identifier:PREMIUM_IDS.royal,originalId:ID,group:"001",
    receivedAtTrustedServerTimestamp:true,
  }];
  assert.equal(offlinePremiumDisplayReadback({
    proofs:verifiedProofs(),documents:docs,evidence,liveUid:A,
  }).reason,"PREMIUM_GIFT_RECEIPT_UNVERIFIED");
  evidence.receivedGiftReceipts[0].group="002";
  evidence.receivedGiftReceipts[0].receivedAtTrustedServerTimestamp=false;
  assert.equal(offlinePremiumDisplayReadback({
    proofs:verifiedProofs(),documents:docs,evidence,liveUid:A,
  }).reason,"PREMIUM_GIFT_RECEIPT_UNVERIFIED");
});

test("premium 200: wrong owner UID, cross-account grant and color mismatch fail closed",()=>{
  const docs=syntheticOneAccountDocuments();
  const evidence=syntheticPremiumDisplayEvidence({color:"diamond"});
  assert.equal(offlinePremiumDisplayReadback({
    proofs:verifiedProofs(),documents:docs,evidence,liveUid:B,
  }).reason,"LIVE_AUTH_UID_NOT_ORIGINAL_OWNER");
  evidence.ownedGrants[0].recipientOriginalId="@DEDA-OTHER1";
  assert.equal(offlinePremiumDisplayReadback({
    proofs:verifiedProofs(),documents:docs,evidence,liveUid:A,
  }).reason,"PREMIUM_GRANT_OWNER_COLOR_OR_GROUP_CONFLICT");
  evidence.ownedGrants[0].recipientOriginalId=ID;
  evidence.ownedGrants[0].baseColor="pink";
  assert.equal(offlinePremiumDisplayReadback({
    proofs:verifiedProofs(),documents:docs,evidence,liveUid:A,
  }).reason,"ACTIVE_PREMIUM_PROJECTION_CONFLICT");
  evidence.ownedGrants.push({...evidence.ownedGrants[0]});
  assert.equal(offlinePremiumDisplayReadback({
    proofs:verifiedProofs(),documents:docs,evidence,liveUid:A,
  }).reason,"PREMIUM_GRANT_DUPLICATE_OR_INVALID");
});

test("premium 200: changing active alias never changes canonical route or Firebase session",()=>{
  const docs=syntheticOneAccountDocuments();
  const before=structuredClone(docs);
  const evidence=syntheticPremiumDisplayEvidence({color:"gold"});
  const first=offlinePremiumDisplayReadback({
    proofs:verifiedProofs(),documents:docs,evidence,liveUid:A,
  });
  assert.equal(first.displayId,PREMIUM_IDS.gold);
  const older=evidence.publicRoutes[PREMIUM_IDS.gold];
  evidence.stage71Active.activeId=PREMIUM_IDS.pink;
  evidence.ownedGrants.push({
    identifier:PREMIUM_IDS.pink,recipientOriginalId:ID,
    baseColor:"pink",group:"001",kind:"self_used",
  });
  evidence.requestedDisplayId=PREMIUM_IDS.pink;
  evidence.publicActive={originalId:ID,activeId:PREMIUM_IDS.pink,baseColor:"pink"};
  evidence.publicRoutes[PREMIUM_IDS.pink]={
    aliasId:PREMIUM_IDS.pink,originalId:ID,baseColor:"pink",
  };
  const next=offlinePremiumDisplayReadback({
    proofs:verifiedProofs(),documents:docs,evidence,liveUid:A,
  });
  assert.equal(next.outcome,"SYNTHETIC_PREMIUM_DISPLAY_ONLY");
  assert.equal(next.displayId,PREMIUM_IDS.pink);
  assert.equal(next.authUid,first.authUid);
  assert.equal(next.canonicalId,first.canonicalId);
  assert.deepEqual(evidence.publicRoutes[PREMIUM_IDS.gold],older);
  evidence.requestedDisplayId=PREMIUM_IDS.gold;
  assert.equal(offlinePremiumDisplayReadback({
    proofs:verifiedProofs(),documents:docs,evidence,liveUid:A,
  }).reason,"UNVERIFIED_OR_STALE_PREMIUM_ALIAS");
  assert.deepEqual(docs,before);
});

test("premium 200: missing activation is unknown; returning to original is display fallback only",()=>{
  const docs=syntheticOneAccountDocuments();
  let evidence=syntheticPremiumDisplayEvidence({color:"pink"});
  delete evidence.stage71Active;
  assert.equal(offlinePremiumDisplayReadback({
    proofs:verifiedProofs(),documents:docs,evidence,liveUid:A,
  }).reason,"ACTIVE_PREMIUM_SELECTION_UNVERIFIED_NOT_ZERO");
  evidence=syntheticPremiumDisplayEvidence({color:"pink"});
  evidence.stage71Active.activeId=ID;
  evidence.requestedDisplayId=ID;
  const r=offlinePremiumDisplayReadback({
    proofs:verifiedProofs(),documents:docs,evidence,liveUid:A,
  });
  assert.equal(r.outcome,"SYNTHETIC_CANONICAL_DISPLAY_ONLY");
  assert.equal(r.canonicalId,ID);
  assert.equal(r.authUid,A);
  assert.equal(r.authTransitions,0);
  assert.equal(r.restorationCertified,false);
});

test("premium 200: alias cannot substitute for UID, independent proof, or session",()=>{
  const docs=syntheticOneAccountDocuments();
  const evidence=syntheticPremiumDisplayEvidence({color:"gold"});
  const noProof=verifiedProofs();
  noProof.independentProof=null;
  assert.equal(offlinePremiumDisplayReadback({
    proofs:noProof,documents:docs,evidence,liveUid:A,
  }).reason,"HISTORICAL_OWNER_REVIEW_REQUIRED");
  assert.equal(offlinePremiumDisplayReadback({
    proofs:verifiedProofs(),documents:docs,evidence,
    liveUid:PREMIUM_IDS.gold,
  }).reason,"LIVE_AUTH_UID_NOT_ORIGINAL_OWNER");
  const foreign=syntheticPremiumDisplayEvidence({color:"gold"});
  foreign.stage71Active.originalId="@DEDA-OTHER1";
  assert.equal(offlinePremiumDisplayReadback({
    proofs:verifiedProofs(),documents:docs,evidence:foreign,liveUid:A,
  }).reason,"ACTIVE_PREMIUM_SOURCE_CROSS_ACCOUNT");
});
