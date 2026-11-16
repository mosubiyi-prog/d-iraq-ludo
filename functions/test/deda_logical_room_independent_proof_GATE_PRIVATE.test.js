'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { generateKeyPairSync, sign } = require('node:crypto');
const { validateIndependentProof } = require('../deda_logical_room_independent_proof_GATE_PRIVATE_NOT_EXPORTED');
function keys() {
  const pair = generateKeyPairSync('ed25519');
  return { privateKey: pair.privateKey,
    publicKeyPem: pair.publicKey.export({type:'spki',format:'pem'}) };
}
const verifier = keys(), first = keys(), second = keys();
const nowMs = 1700000000000;
const serverRecord = {accountKey:'account-test-only',originalUidA:'testUidAA',
  originalUidB:'testUidBB', originalUidC:'testUidCC',
  challengeHash:'a'.repeat(64),challengeActive:true,incidentCutoffMs:1600000000000};
const trustedKeys = {verifiers:{externalVerifier:{...verifier,active:true}},
  reviewers:{reviewerOne:{...first,active:true},reviewerTwo:{...second,active:true}}};
function signed(input = {}) {
 const attestation = {version:1,kind:'pre_enrolled_factor',
   accountKey:serverRecord.accountKey,originalUid:'testUidAA',
   challengeHash:serverRecord.challengeHash,evidenceRef:'externalReceipt001',
   issuedAtMs:nowMs-5000,expiresAtMs:nowMs+5000,enrolledAtMs:1500000000000,
   verifierId:'externalVerifier', ...input};
 const payload = {}; for(const k of ['version','kind','accountKey','originalUid',
  'challengeHash','evidenceRef','issuedAtMs','expiresAtMs','enrolledAtMs','verifierId'])
  payload[k]=attestation[k];
 attestation.signature=sign(null,Buffer.from(JSON.stringify(payload)),verifier.privateKey).toString('base64');
 const reviewPayload=Buffer.from(JSON.stringify({version:1,
  accountKey:attestation.accountKey,originalUid:attestation.originalUid,
  challengeHash:attestation.challengeHash,evidenceRef:attestation.evidenceRef,
  verifierId:attestation.verifierId,issuedAtMs:attestation.issuedAtMs}));
 const reviewers=[{reviewerId:'reviewerOne',signature:sign(null,reviewPayload,first.privateKey).toString('base64')},
 {reviewerId:'reviewerTwo',signature:sign(null,reviewPayload,second.privateKey).toString('base64')}];
 return {serverRecord,attestation,reviewers,trustedKeys,nowMs};
}
test('genuine signatures remain REVIEW ONLY; never authorize',()=>{
 const res=validateIndependentProof(signed());
 assert.equal(res.decision,'SIGNED_EVIDENCE_CANDIDATE_FOR_SEPARATE_REVIEW');
 for(const key of ['loginPermitted','crossUidReadPermitted','crossUidWritePermitted',
  'adminEntryPermitted','financialGrantPermitted','createTokenPermitted','createUidPermitted'])
 assert.equal(res[key],false);
});
test('tampered UID is rejected even if signatures were valid before tampering',()=>{
 const data=signed();data.attestation.originalUid='testUidBB';
 assert.equal(validateIndependentProof(data).decision,'HOLD');
});
test('wrong historical UID is rejected',()=>{
 const data=signed({originalUid:'strangerUid'});
 assert.equal(validateIndependentProof(data).decision,'HOLD');
});
test('wrong or revoked verifier key rejected',()=>{
 const data=signed();data.trustedKeys={...data.trustedKeys,verifiers:{externalVerifier:{...data.trustedKeys.verifiers.externalVerifier,active:false}}};
 assert.equal(validateIndependentProof(data).decision,'HOLD');
});
test('reviewer cannot be reused twice',()=>{
 const data=signed();data.reviewers[1]={...data.reviewers[0]};
 assert.equal(validateIndependentProof(data).decision,'HOLD');
});
test('tampered reviewer signature is rejected',()=>{
 const data=signed();data.reviewers[1].signature=data.reviewers[0].signature;
 assert.equal(validateIndependentProof(data).decision,'HOLD');
});
test('expired evidence is rejected',()=>{
 const data=signed({issuedAtMs:nowMs-20000,expiresAtMs:nowMs-1000});
 assert.equal(validateIndependentProof(data).decision,'HOLD');
});
test('a factor enrolled after the incident is rejected',()=>{
 const data=signed({enrolledAtMs:serverRecord.incidentCutoffMs+1});
 assert.equal(validateIndependentProof(data).decision,'HOLD');
});
test('an inactive server challenge is rejected',()=>{
 const data=signed();data.serverRecord={...data.serverRecord,challengeActive:false};
 assert.equal(validateIndependentProof(data).decision,'HOLD');
});
test('a signature from an untrusted new key is rejected',()=>{
 const data=signed();data.trustedKeys={...data.trustedKeys,verifiers:{externalVerifier:{...keys(),active:true}}};
 assert.equal(validateIndependentProof(data).decision,'HOLD');
});
