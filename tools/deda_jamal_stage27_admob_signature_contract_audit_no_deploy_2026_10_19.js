"use strict";

/**
 * DEDA Stage27: evidence-aware preproduction audit of signature contract.
 *
 * This module MUST NOT verify real Google SSV, deliver diamonds, fetch keys,
 * rewrite the user's existing ad wallet or enable purchases. Its job is to
 * make release blockers explicit until primary-source Google documentation
 * and a real Google-signed callback have been examined.
 *
 * NEVER infer provider identity just because an ECDSA signature verifies
 * with a key generated inside an offline test.
 */

const {readFileSync} = require("node:fs");
const {resolve} = require("node:path");

const ROOT=resolve(__dirname,"..");
const SOURCES=Object.freeze({
  stage22:"tools/deda_jamal_stage22_admob_ssv_ecdsa_staged_no_deploy_2026_10_19.js",
  stage24:"tools/deda_jamal_stage24_offline_ssv_key_freshness_no_deploy_2026_10_19.js",
  stage26:"tools/deda_jamal_stage26_reward_receipt_status_readonly_2026_10_19.js",
  functionsIndex:"functions/index.js",
  main:"lib/main.dart",
});

function readRepoSources(){
  const out={};
  for(const [name,path] of Object.entries(SOURCES)){
    out[name]=readFileSync(resolve(ROOT,path),"utf8");
  }
  return out;
}
function inspectStage27SignatureContract(sources){
  if(!sources||typeof sources!=="object"||Array.isArray(sources)||
      Object.keys(SOURCES).some(k=>typeof sources[k]!=="string")){
    throw Object.assign(new Error("audited-source-bundle-required"),{
      code:"failed-precondition",
    });
  }
  const proof={
    stagedECDSACryptoPresent:sources.stage22.includes("verifyEcdsa(") &&
      sources.stage22.includes("Buffer.from(message") &&
      sources.stage22.includes("base64url"),
    verifierRejectsUnrecognizedKeys:sources.stage22.includes(
      "untrusted-provider-signature-key"),
    verifierRejectsDuplicateFields:sources.stage22.includes(
      "duplicate-or-unknown-signed-field"),
    callbackRequiresServerNonce:sources.stage22.includes(
      "unknown-or-expired-server-ad-challenge"),
    callbackHasOnceOnlyReceipt:sources.stage22.includes(
      "ad-challenge-already-consumed"),
    serverRewardPolicyForcedOff:sources.stage22.includes(
      "policy.verifiedForProduction!==false"),
    strictlyOfflineStage22:sources.stage22.includes(
      "STAGE22_OFFLINE_ECDSA_EMULATOR_ONLY"),
    offlineKeySourceMarkedNonGoogle:sources.stage24.includes(
      "OFFLINE_GENERATED_FAKE_EC_KEYS_NOT_GOOGLE"),
    readbackDoesNotClaimGoogle:sources.stage26.includes(
      "officialGoogleAdMobSSVVerified:false"),
    noStage22LiveBackendExport:!sources.functionsIndex.includes(
      "deda_jamal_stage22_admob_ssv_ecdsa"),
    noStage24LiveBackendExport:!sources.functionsIndex.includes(
      "deda_jamal_stage24_offline_ssv_key"),
    noStage26LiveBackendExport:!sources.functionsIndex.includes(
      "deda_jamal_stage26_reward_receipt_status"),
    noStage27AdRewardUiInstalled:!sources.main.includes(
      "deda_jamal_stage27_admob_signature_contract_audit"),
  };
  const auditProblems=Object.entries(proof).filter(([,ok])=>ok!==true)
    .map(([name])=>name);
  const primaryEvidence=Object.freeze({
    officialGoogleAdMobSSVSpecChecked:false,
    officialGoogleOwnedKeySourceIndependentlyVerified:false,
    callbackRawQueryCanonicalizationMatchedToGoogleReference:false,
    signatureEncodingMatchedToGoogleReference:false,
    authenticGoogleSignedTransactionExercised:false,
    productionAppCheckAndEndpointReviewed:false,
    legacyDiamondProvenanceMigrationApproved:false,
  });
  return Object.freeze({
    auditStage:"27",
    scope:"local-repository-signature-and-release-blocker-review",
    auditedSourceChecks:Object.freeze(proof),
    missingSourceSafetyChecks:Object.freeze(auditProblems),
    independentOfficialEvidence:primaryEvidence,
    sourceGuardConsistent:auditProblems.length===0,
    liveAdMobProviderVerified:false,
    realGoogleSSVIntegrationCertified:false,
    realPurchaseEnabled:false,
    allowedToDeploy:false,
    allowedToMintLiveDiamonds:false,
    currentUserAdRewardsUnchanged:true,
    note:"OFFICIAL_CURRENT_GOOGLE_PRIMARY_SOURCE_NOT_VERIFIED_NO_WEB_ACCESS",
  });
}
function assertNotProductionReady(report){
  if(!report||report.allowedToDeploy!==false||
     report.allowedToMintLiveDiamonds!==false||
     report.realGoogleSSVIntegrationCertified!==false ||
     report.liveAdMobProviderVerified!==false ||
     !report.independentOfficialEvidence ||
     Object.values(report.independentOfficialEvidence).some(v=>v!==false)){
    const error=new Error("stage27-blocked-no-official-provider-proof");
    error.code="unavailable";
    throw error;
  }
  return "RELEASE_BLOCKED_OFFICIAL_GOOGLE_EVIDENCE_MISSING";
}

module.exports={
  inspectStage27SignatureContract,readRepoSources,assertNotProductionReady,
};
