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
