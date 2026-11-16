"use strict";
/*
 * DEDA UNIFIED ROOM — EXPLICIT FIRESTORE+AUTH EMULATOR-ONLY GATEWAY.
 * DO NOT EXPORT/DEPLOY. NOT a production proof verifier.
 *
 * - Uses an existing, independently verified Firebase Auth UID.
 * - NO createUser / signInAnonymously / custom token / UID migration.
 * - QA review records are synthetic fixtures; not proof of real ownership.
 * - Reads historical QA source only after domain/owner review.
 * - Atomic grant + sanitized projection + audit, or atomic revocation.
 * - Rechecks owner proof, domain scope, session and source inside transaction.
 * - No service account, live credentials or production Firestore connection.
 */
const crypto = require("node:crypto");
const {Timestamp} = require("firebase-admin/firestore");
const {trustedPayload} = require("./room_grant_lifecycle_PRIVATE_OFFLINE_QA.cjs");
const PROJECT = "demo-deda-room-live-additive-compare";
const FIRESTORE_HOST = "127.0.0.1:8088";
const AUTH_HOST = "127.0.0.1:9099";
const DOMAINS = new Set(["profile","original_id","premium_id","friends",
  "league","gifts","wallet","places"]);
const doc = (db,path) => db.doc(path);
const paths = Object.freeze({
  uidIndex: uid => "qa_room_uid_index/"+uid,
  room: cid => "qa_room_accounts/"+cid,
  review: (cid,uid) => "qa_room_owner_reviews/"+cid+"/readers/"+uid,
  proof: (cid,domain) => "qa_room_domain_proofs/"+cid+"/domains/"+domain,
  source: (uid,domain) => "qa_room_historical_sources/"+uid+"/domains/"+domain,
  session: uid => "qa_room_sessions/"+uid,
  view: (uid,domain) => "deda_unified_room_private_views/"+uid+"/domains/"+domain,
  grant: (uid,domain) => "deda_unified_room_read_grants/"+uid+"/domains/"+domain,
  audit: key => "qa_room_audit_events/"+key,
});
function assertLab({db,auth,clock}) {
  if (process.env.FIRESTORE_EMULATOR_HOST !== FIRESTORE_HOST ||
      process.env.FIREBASE_AUTH_EMULATOR_HOST !== AUTH_HOST ||
      process.env.GCLOUD_PROJECT !== PROJECT ||
      (db?.app?.options?.projectId !== PROJECT && db?.projectId !== PROJECT) ||
      typeof auth?.verifyIdToken !== "function" ||
      typeof db?.runTransaction !== "function" ||
      typeof clock !== "function") {
    throw Error("QA_SAFE_STOP_EMULATOR_ONLY_OR_PROJECT_MISMATCH");
  }
}
const digest=(...parts)=>crypto.createHash("sha256").update(parts.join("|")).digest("hex");
const data=snapshot=>snapshot.exists ? snapshot.data() : null;
const equal=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const matchSession=(actual,expected,plan)=>{
  return !!actual && actual.active===true &&
    actual.uid===expected.uid && actual.uid===plan.readerUid &&
    actual.canonicalAccountId===expected.canonicalAccountId &&
    actual.canonicalAccountId===plan.canonicalAccountId &&
    actual.revision===expected.revision &&
    Number.isSafeInteger(actual.revision) &&
    actual.sessionNonce===expected.sessionNonce &&
    typeof actual.sessionNonce==="string" && actual.sessionNonce.length>=12;
};
function reviewStillValid(review,plan,now) {
  return !!review && review.source==="independent_server_review" &&
    review.independentlyVerified===true && review.ownerApproved===true &&
    review.backupVerified===true && review.rollbackDocumented===true &&
    review.reviewId===plan.ownerReviewId &&
    review.originalId===plan.originalId &&
    review.canonicalAccountId===plan.canonicalAccountId &&
    review.authUid===plan.readerUid &&
    Number.isSafeInteger(review.verifiedAtMs) &&
    review.verifiedAtMs<=now && now-review.verifiedAtMs<=600000;
}
function proofStillValid(proof,plan,now) {
  return !!proof && proof.status==="approved" &&
    proof.trustedSource==="independently_reviewed_domain" &&
    proof.reviewId===plan.ownerReviewId &&
    proof.canonicalAccountId===plan.canonicalAccountId &&
    proof.readerUid===plan.readerUid &&
    proof.sourceUid===plan.sourceUid &&
    proof.originalId===plan.originalId &&
    proof.domain===plan.domain &&
    proof.mayReadSanitizedProjection===true &&
    proof.mayMutate!==true &&
    Number.isSafeInteger(proof.verifiedAtMs) &&
    proof.verifiedAtMs<=now && now-proof.verifiedAtMs<=600000;
}
function makeEmulatorGateway({db,auth,clock=()=>Date.now()}={}) {
  assertLab({db,auth,clock});
  const read=(path)=>db.doc(path).get().then(data);
  const store={
    environment:"isolated-fake-only",
    async issueAtomic({plan,session,view,grant,expectedOwnerReview}) {
      assertLab({db,auth,clock});
      if (!DOMAINS.has(plan?.domain) ||
          expectedOwnerReview!==plan.ownerReviewId ||
          !equal(trustedPayload(plan.domain,view?.payload),view?.payload) ||
          grant?.readerUid!==plan?.readerUid ||
          grant?.sourceUid!==plan?.sourceUid ||
          grant?.originalId!==plan?.originalId ||
          grant?.domain!==plan?.domain ||
          !Number.isSafeInteger(grant?.issuedAtMs) ||
          !Number.isSafeInteger(grant?.expiresAtMs) ||
          grant.expiresAtMs-grant.issuedAtMs!==300000) return false;
      const uid=plan.readerUid,domain=plan.domain,cid=plan.canonicalAccountId;
      const refs={
        session:doc(db,paths.session(uid)),
        room:doc(db,paths.room(cid)),
        review:doc(db,paths.review(cid,uid)),
        proof:doc(db,paths.proof(cid,domain)),
        source:doc(db,paths.source(plan.sourceUid,domain)),
        grant:doc(db,paths.grant(uid,domain)),
        view:doc(db,paths.view(uid,domain))
      };
      return db.runTransaction(async tx=>{
        // ALL reads before writes. Revalidate after any concurrent mutation.
        const [sess,room,review,proof,source,prior] = await Promise.all([
          tx.get(refs.session),tx.get(refs.room),tx.get(refs.review),
          tx.get(refs.proof),tx.get(refs.source),tx.get(refs.grant)
        ]);
        const now=clock();
        const rm=data(room),src=data(source);
        if (!matchSession(data(sess),session,plan) ||
            !rm || rm.canonicalAccountId!==cid ||
            rm.originalId!==plan.originalId ||
            !Array.isArray(rm.historicalUids) ||
            !rm.historicalUids.includes(uid) ||
            !rm.historicalUids.includes(plan.sourceUid) ||
            !reviewStillValid(data(review),plan,now) ||
            !proofStillValid(data(proof),plan,now) ||
            !src || src.canonicalAccountId!==cid ||
            src.originalId!==plan.originalId ||
            src.sourceUid!==plan.sourceUid ||
            src.domain!==domain ||
            !equal(trustedPayload(domain,src.payload),view.payload) ||
            grant.issuedAtMs>now || grant.expiresAtMs<=now ||
            prior.exists) return false;
        const auditId=digest("issue",uid,domain,plan.ownerReviewId);
        tx.set(refs.view,view);
        tx.set(refs.grant,{...grant,
          issuedAt:Timestamp.fromMillis(grant.issuedAtMs),
          expiresAt:Timestamp.fromMillis(grant.expiresAtMs)});
        tx.create(doc(db,paths.audit(auditId)),{
          action:"issue",readerUid:uid,domain,sourceUid:plan.sourceUid,
          originalId:plan.originalId,canonicalAccountId:cid,
          ownerReviewId:plan.ownerReviewId,at:Timestamp.fromMillis(now),
          sessionRevision:session.revision
        });
        return true;
      });
    },
    async revokeAtomic({readerUid,domain,session}) {
      assertLab({db,auth,clock});
      if (!DOMAINS.has(domain)||!session||session.uid!==readerUid)
        return false;
      const sRef=doc(db,paths.session(readerUid));
      const gRef=doc(db,paths.grant(readerUid,domain));
      return db.runTransaction(async tx=>{
        const [s,g]=await Promise.all([tx.get(sRef),tx.get(gRef)]);
        const now=clock(),current=data(g);
        if (!matchSession(data(s),session,{
          readerUid,canonicalAccountId:session.canonicalAccountId
        }) || !current || current.readerUid!==readerUid ||
            current.domain!==domain) return false;
        if (current.status==="revoked") return true;
        if (current.status!=="active") return false;
        tx.update(gRef,{status:"revoked",revokedAt:Timestamp.fromMillis(now)});
        tx.create(doc(db,paths.audit(digest("revoke",readerUid,domain,
          String(now),String(session.revision)))),{
          action:"revoke",readerUid,domain,
          canonicalAccountId:session.canonicalAccountId,
          sessionRevision:session.revision,at:Timestamp.fromMillis(now)
        });
        return true;
      });
    }
  };
  const deps={
    qaMode:"isolated-fake-only",store,clockMs:clock,
    async verifyIdToken(idToken,checkRevoked){
      assertLab({db,auth,clock});
      if(checkRevoked!==true)throw Error("REVOCATION_CHECK_REQUIRED");
      const claims=await auth.verifyIdToken(idToken,true);
      return {uid:claims.uid,provider:claims.firebase?.sign_in_provider,
        anonymous:claims.firebase?.sign_in_provider==="anonymous"};
    },
    async readRoomForUid(uid) {
      assertLab({db,auth,clock});
      const index=await read(paths.uidIndex(uid));
      if (!index || index.uid!==uid ||
          typeof index.canonicalAccountId!=="string")return null;
      const room=await read(paths.room(index.canonicalAccountId));
      return room && room.canonicalAccountId===index.canonicalAccountId &&
        Array.isArray(room.historicalUids) &&
        room.historicalUids.includes(uid)?room:null;
    },
    async readOwnerReview(cid,uid){return read(paths.review(cid,uid));},
    async readDomainProof(cid,domain){return read(paths.proof(cid,domain));},
    async readSession(uid){return read(paths.session(uid));},
    async buildProjection(plan){
      assertLab({db,auth,clock});
      if (!DOMAINS.has(plan?.domain)) return null;
      const source=await read(paths.source(plan.sourceUid,plan.domain));
      if(!source || source.canonicalAccountId!==plan.canonicalAccountId ||
         source.sourceUid!==plan.sourceUid ||
         source.originalId!==plan.originalId ||
         source.domain!==plan.domain)return null;
      return trustedPayload(plan.domain,source.payload);
    }
  };
  return Object.freeze(deps);
}
module.exports={makeEmulatorGateway,PROJECT,FIRESTORE_HOST,AUTH_HOST,paths};
