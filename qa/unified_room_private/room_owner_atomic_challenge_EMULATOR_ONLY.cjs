"use strict";
/*
 * DEDA — ONE-USE CHALLENGE & SIGNED REVIEW-CANDIDATE LEDGER.
 * Strictly Firebase Auth + Firestore EMULATOR. Never exported by functions/index.
 * No actual owner verification, cross-UID grant, token issue, money credit,
 * UID mutation, Google linking, or production access. Signed QA keys are fake.
 * Even an accepted signature creates a REVIEW CANDIDATE, NOT authorization.
 */
const {randomBytes,createHash}=require("node:crypto");
const {evaluateProofSourceForRoom}=
 require("./room_owner_proof_source_binding_PRIVATE_QA.cjs");
const PROJECT="demo-deda-room-live-additive-compare";
const FIRESTORE_HOST="127.0.0.1:8088",AUTH_HOST="127.0.0.1:9099";
const DOMAINS=new Set(["profile","original_id","premium_id","friends",
  "league","gifts","wallet","places"]);
const UID=/^[A-Za-z0-9:_-]{6,128}$/;
const ACCOUNT=/^(?:07\d{9}|9647\d{9})$/;
const ORIGINAL=/^@DEDA-[A-Z0-9]{6}$/;
const DURATION=5*60*1000;
const hash=s=>createHash("sha256").update(s).digest("hex");
const record=s=>s.exists?s.data():null;
const hold=reason=>Object.freeze({
  decision:"HOLD",reason,
  productionAccess:false,authTokenIssued:false,uidChanged:false,
  crossUidRead:false,crossUidWrite:false,financialCredit:false,
  adminAccess:false
});
const response=(decision,extra={})=>
 Object.freeze({...hold(decision),decision,...extra});
const paths=Object.freeze({
  index:uid=>"qa_room_uid_index/"+uid,
  room:cid=>"qa_room_accounts/"+cid,
  session:uid=>"qa_room_sessions/"+uid,
  challenge:(uid,domain)=>"qa_room_owner_challenges/"+uid+"/domains/"+domain,
  evidence:(uid,domain)=>"qa_room_owner_signed_evidence/"+uid+"/domains/"+domain,
  candidate:(uid,domain)=>"qa_room_owner_review_candidates/"+uid+"/domains/"+domain,
  keys:()=>"qa_room_trust_keys/active",
  audit:id=>"qa_room_owner_challenge_audit/"+id
});
function makeAtomicOwnerChallenge({db,auth,clock=()=>Date.now()}={}){
  const assertLab=()=>{
    if(process.env.GCLOUD_PROJECT!==PROJECT ||
       process.env.FIRESTORE_EMULATOR_HOST!==FIRESTORE_HOST||
       process.env.FIREBASE_AUTH_EMULATOR_HOST!==AUTH_HOST||
       (db?.app?.options?.projectId!==PROJECT&&db?.projectId!==PROJECT)||
       typeof db?.runTransaction!=="function"||
       typeof auth?.verifyIdToken!=="function"||
       typeof clock!=="function")
      throw Error("QA_SAFE_STOP_EMULATOR_ONLY");
  };
  assertLab();
  const doc=path=>db.doc(path);
  async function principal(idToken){
    assertLab();
    if(typeof idToken!=="string"||idToken.length<10)return null;
    try{
      const claims=await auth.verifyIdToken(idToken,true);
      const provider=claims.firebase?.sign_in_provider;
      if(!UID.test(claims.uid||"") ||
         !["google.com","password","phone"].includes(provider))
        return null;
      return {uid:claims.uid,anonymous:false,provider};
    }catch(_){return null;}
  }
  function validRoomSession(uid,index,room,session){
    return !!index&&!!room&&!!session&&index.uid===uid&&
      typeof index.canonicalAccountId==="string"&&
      index.canonicalAccountId===room.canonicalAccountId&&
      room.canonicalAccountId===session.canonicalAccountId&&
      ACCOUNT.test(room.accountKey||"")&&ORIGINAL.test(room.originalId||"")&&
      Array.isArray(room.historicalUids)&&room.historicalUids.length===3&&
      new Set(room.historicalUids).size===3&&
      room.historicalUids.every(x=>UID.test(x))&&
      room.historicalUids.includes(uid)&&
      session.active===true&&session.uid===uid&&
      Number.isSafeInteger(session.revision)&&session.revision>0&&
      typeof session.sessionNonce==="string"&&session.sessionNonce.length>=12;
  }
  async function createChallenge({idToken,domain}={}){
    assertLab();
    if(!DOMAINS.has(domain))return hold("INVALID_DOMAIN");
    const person=await principal(idToken);
    if(!person)return hold("UNVERIFIED_DURABLE_AUTH");
    const uid=person.uid,now=clock();
    if(!Number.isSafeInteger(now)||now<=0)return hold("INVALID_SERVER_CLOCK");
    const nonce=randomBytes(32).toString("hex"),challengeHash=hash(nonce);
    const outcome=await db.runTransaction(async tx=>{
      const idx=record(await tx.get(doc(paths.index(uid))));
      const cid=idx?.canonicalAccountId;
      if(typeof cid!=="string"||cid.length<12)return hold("NO_VERIFIED_ROOM");
      const refs={
        room:doc(paths.room(cid)),session:doc(paths.session(uid)),
        challenge:doc(paths.challenge(uid,domain)),
        candidate:doc(paths.candidate(uid,domain))
      };
      const [r,s,old,existing]=await Promise.all([
        tx.get(refs.room),tx.get(refs.session),
        tx.get(refs.challenge),tx.get(refs.candidate)]);
      const room=record(r),session=record(s),previous=record(old);
      if(!validRoomSession(uid,idx,room,session))
        return hold("SESSION_OR_HISTORIC_ROOM_CHANGED");
      if(existing.exists)return hold("DOMAIN_REVIEW_ALREADY_EXISTS");
      if(previous && previous.active===true &&
         previous.consumed!==true&&previous.expiresAtMs>now)
        return hold("ACTIVE_CHALLENGE_ALREADY_EXISTS");
      const challenge={
        issuer:"trusted_server_only",active:true,consumed:false,
        domain,readerUid:uid,canonicalAccountId:cid,
        originalId:room.originalId,accountKey:room.accountKey,
        sessionRevision:session.revision,sessionNonce:session.sessionNonce,
        challengeHash,issuedAtMs:now,expiresAtMs:now+DURATION
      };
      tx.set(refs.challenge,challenge);
      tx.create(doc(paths.audit(hash(["issued",uid,domain,challengeHash].join("|")))),{
        action:"challenge_issued",readerUid:uid,domain,
        canonicalAccountId:cid,challengeHash,atMs:now
      });
      return response("QA_CHALLENGE_ISSUED",{
        challengeHash,nonce,expiresAtMs:now+DURATION
      });
    });
    return outcome;
  }
  async function finalizeReviewCandidate({idToken,domain}={}){
    assertLab();
    if(!DOMAINS.has(domain))return hold("INVALID_DOMAIN");
    const person=await principal(idToken);
    if(!person)return hold("UNVERIFIED_DURABLE_AUTH");
    const uid=person.uid,now=clock();
    if(!Number.isSafeInteger(now)||now<=0)return hold("INVALID_SERVER_CLOCK");
    return db.runTransaction(async tx=>{
      // Every value is loaded from the server's emulator transaction.
      // No client-provided originalUid, accountKey, PIN, review or trust key.
      const index=record(await tx.get(doc(paths.index(uid))));
      const cid=index?.canonicalAccountId;
      if(typeof cid!=="string"||cid.length<12)return hold("NO_VERIFIED_ROOM");
      const refs={
        room:doc(paths.room(cid)),session:doc(paths.session(uid)),
        challenge:doc(paths.challenge(uid,domain)),
        evidence:doc(paths.evidence(uid,domain)),keys:doc(paths.keys()),
        candidate:doc(paths.candidate(uid,domain))
      };
      const [rs,ss,cs,es,ks,existing]=await Promise.all([
        tx.get(refs.room),tx.get(refs.session),tx.get(refs.challenge),
        tx.get(refs.evidence),tx.get(refs.keys),tx.get(refs.candidate)]);
      const room=record(rs),session=record(ss),challenge=record(cs);
      const evidence=record(es),keys=record(ks);
      if(!validRoomSession(uid,index,room,session))
        return hold("SESSION_OR_HISTORIC_ROOM_CHANGED");
      if(existing.exists)return hold("CANDIDATE_ALREADY_RECORDED");
      if(challenge?.domain!==domain||evidence?.domain!==domain||
         challenge?.readerUid!==uid||evidence?.readerUid!==uid||
         challenge?.consumed!==false||challenge?.active!==true||
         challenge?.expiresAtMs<=now)
        return hold("CHALLENGE_CONSUMED_EXPIRED_OR_SCOPE_MISMATCH");
      const deps={
        qaMode:"isolated-fake-only",environment:"isolated-fake-only",
        verifyIdToken:async (_token,checkRevoked)=>{
          if(checkRevoked!==true)return null;
          return person;
        },
        readSession:async()=>session,
        readRoomForUid:async()=>room,
        readChallenge:async()=>challenge,
        readSignedEvidence:async()=>evidence,
        readTrustAnchors:async()=>keys
      };
      const assessment=await evaluateProofSourceForRoom({
        idToken,domain,nowMs:now},deps);
      if(assessment.decision!=="SIGNED_PROOF_REVIEW_CANDIDATE")
        return hold("INDEPENDENT_SIGNED_SOURCE_NOT_ESTABLISHED");
      // This is a signed-evidence CANDIDATE awaiting true external
      // provenance, never an entitlement. Atomic marker prevents replay.
      tx.update(refs.challenge,{
        active:false,consumed:true,consumedAtMs:now
      });
      tx.create(refs.candidate,{
        state:"pending-independent-real-world-provenance",
        readerUid:uid,canonicalAccountId:cid,domain,
        challengeHash:challenge.challengeHash,
        signatureEvidenceRef:evidence.attestation.evidenceRef,
        createdAtMs:now,grantsAccess:false,grantsWrite:false
      });
      tx.create(doc(paths.audit(hash(["candidate",uid,domain,
         challenge.challengeHash].join("|")))),{
        action:"signed_candidate_only",readerUid:uid,domain,
        canonicalAccountId:cid,challengeHash:challenge.challengeHash,
        atMs:now,productionAccess:false
      });
      return response("QA_SIGNED_CANDIDATE_RECORDED",{
        proofCandidate:true,realWorldOwnerVerified:false
      });
    });
  }
  return Object.freeze({createChallenge,finalizeReviewCandidate});
}
module.exports={makeAtomicOwnerChallenge,paths,PROJECT,FIRESTORE_HOST,AUTH_HOST};
