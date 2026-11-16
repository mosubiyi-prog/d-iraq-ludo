// REUSED UNCHANGED from functions/deda_logical_room_independent_proof_GATE_PRIVATE_NOT_EXPORTED.js on deda-logical-room-private-offline-preflight-2026-11-16.
// This QA copy preserves existing crypto contract; not a production service.
'use strict';
// DEDA logical identity room: offline, fail-closed signature validation only.
// NOT imported by functions/index.js. No Firebase, Flutter, Auth, grants,
// account merging, PIN changes, rights mapping, or network access.
// A signed attestation is evidence for review, NEVER a login authorization.
const { verify, createPublicKey } = require('node:crypto');
const UID = /^[A-Za-z0-9_-]{6,128}$/;
const DIGEST = /^[0-9a-f]{64}$/;
const ID = /^[A-Za-z0-9_-]{3,80}$/;
const MAX_AGE_MS = 10 * 60 * 1000;
const fail = (reason) => Object.freeze({
  decision: 'HOLD', reason, loginPermitted: false,
  crossUidReadPermitted: false, crossUidWritePermitted: false,
  adminEntryPermitted: false, financialGrantPermitted: false,
  createTokenPermitted: false, createUidPermitted: false,
});
const fixedFields = ['version', 'kind', 'accountKey', 'originalUid',
  'challengeHash', 'evidenceRef', 'issuedAtMs', 'expiresAtMs', 'enrolledAtMs',
  'verifierId'];
function payloadOf(record) {
  const out = {};
  for (const k of fixedFields) out[k] = record[k];
  return Buffer.from(JSON.stringify(out), 'utf8');
}
function ed25519SignatureIsValid(publicKeyPem, payload, signature) {
  if (typeof publicKeyPem !== 'string' ||
      typeof signature !== 'string' ||
      !/^[A-Za-z0-9+/]{86}==$/.test(signature)) return false;
  try {
    const key = createPublicKey(publicKeyPem);
    if (key.asymmetricKeyType !== 'ed25519') return false;
    const bytes = Buffer.from(signature, 'base64');
    return bytes.length === 64 && verify(null, payload, key, bytes);
  } catch (_) { return false; }
}
function validateIndependentProof({serverRecord, attestation, reviewers,
  trustedKeys, nowMs} = {}) {
  // All parameters MUST eventually come from independently authenticated
  // server-side reads and approved trust anchors. The module cannot attest
  // to their provenance and MUST NOT be exposed as an HTTP/callable endpoint.
  if (!serverRecord || !attestation || !Array.isArray(reviewers) ||
      !trustedKeys || !Number.isSafeInteger(nowMs)) return fail('MISSING_TRUSTED_INPUT');
  const historical = [serverRecord.originalUidA,
    serverRecord.originalUidB, serverRecord.originalUidC];
  if (!historical.every(x => typeof x === 'string' && UID.test(x)) ||
      !serverRecord.accountKey ||
      typeof serverRecord.accountKey !== 'string' ||
      typeof serverRecord.challengeHash !== 'string' ||
      !DIGEST.test(serverRecord.challengeHash) ||
      serverRecord.challengeActive !== true) return fail('SERVER_STATE_NOT_VERIFIED');
  if (attestation.version !== 1 ||
      !['pre_enrolled_factor', 'independent_verified_recovery_factor'].includes(attestation.kind) ||
      attestation.accountKey !== serverRecord.accountKey ||
      !historical.includes(attestation.originalUid) ||
      attestation.challengeHash !== serverRecord.challengeHash ||
      typeof attestation.evidenceRef !== 'string' ||
      !ID.test(attestation.evidenceRef) ||
      !ID.test(attestation.verifierId || '') ||
      !Number.isSafeInteger(attestation.issuedAtMs) ||
      !Number.isSafeInteger(attestation.expiresAtMs) ||
      attestation.issuedAtMs > nowMs ||
      nowMs - attestation.issuedAtMs > MAX_AGE_MS ||
      attestation.expiresAtMs < nowMs ||
      attestation.expiresAtMs - attestation.issuedAtMs > MAX_AGE_MS ||
      attestation.expiresAtMs <= attestation.issuedAtMs ||
      !Number.isSafeInteger(attestation.enrolledAtMs)) {
    return fail('ATTESTATION_SCOPE_OR_TIME_INVALID');
  }
  if (attestation.kind === 'pre_enrolled_factor' &&
      (!Number.isSafeInteger(serverRecord.incidentCutoffMs) ||
       attestation.enrolledAtMs <= 0 ||
       attestation.enrolledAtMs >= serverRecord.incidentCutoffMs)) {
    return fail('FACTOR_NOT_PRE_ENROLLED');
  }
  // The verifier is NOT a reviewer and the two reviewers must be distinct.
  const verifier = trustedKeys.verifiers?.[attestation.verifierId];
  if (!verifier || verifier.active !== true ||
      !ed25519SignatureIsValid(verifier.publicKeyPem, payloadOf(attestation),
        attestation.signature)) return fail('INDEPENDENT_VERIFIER_SIGNATURE_INVALID');
  if (reviewers.length !== 2 ||
      reviewers.some(x => !x || !ID.test(x.reviewerId || '') ||
        x.reviewerId === attestation.verifierId) ||
      reviewers[0].reviewerId === reviewers[1].reviewerId) {
    return fail('TWO_DISTINCT_REVIEWERS_REQUIRED');
  }
  const reviewPayload = Buffer.from(JSON.stringify({
    version: 1, accountKey: attestation.accountKey,
    originalUid: attestation.originalUid,
    challengeHash: attestation.challengeHash,
    evidenceRef: attestation.evidenceRef,
    verifierId: attestation.verifierId,
    issuedAtMs: attestation.issuedAtMs,
  }), 'utf8');
  for (const reviewer of reviewers) {
    const trusted = trustedKeys.reviewers?.[reviewer.reviewerId];
    if (!trusted || trusted.active !== true ||
        !ed25519SignatureIsValid(trusted.publicKeyPem, reviewPayload,
          reviewer.signature)) return fail('REVIEW_SIGNATURE_INVALID');
  }
  // This never authorizes a domain, cross-UID access, finances or admin.
  return Object.freeze({ ...fail('SEPARATE_AUTHORIZATION_REQUIRED'),
    decision: 'SIGNED_EVIDENCE_CANDIDATE_FOR_SEPARATE_REVIEW',
    reason: 'PROVENANCE_REQUIRES_TRUSTED_SERVER_AND_REAL_VERIFIER',
  });
}
module.exports = {validateIndependentProof};
