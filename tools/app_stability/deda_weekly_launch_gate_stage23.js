"use strict";
/**
 * DEDA Stage23: audit CURRENT TRACKED REPOSITORY as a public release gate.
 * This is not a production state inspector or launch toggle.
 * Never reports READY from repository text: independent production audit,
 * rules emulation, cross-device owner QA, payment wallet review and signed
 * build must ALL precede a separately approved deployment.
 */
const fs=require("node:fs");
const path=require("node:path");

function check(root) {
  const read=name=>fs.readFileSync(path.join(root,name),"utf8");
  const indexed=read("functions/index.js");
  const rules=read("firestore.rules");
  const pay=read("lib/deda_migrated_progress_firebase.dart");
  const xp=read("lib/deda_weekly_private_trial_local_xp.dart");
  const stage9=read("functions/deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
  const stage10=read("functions/deda_weekly_receipts_to_standings_NOT_EXPORTED.js");
  const stage11=read("functions/deda_weekly_verified_pair_for_app_NOT_EXPORTED.js");
  const stage21=read("functions/deda_weekly_server_equipped_public_bridge_NOT_EXPORTED.js");
  const stage22=read("lib/deda_weekly_leaderboard_tap_surface.dart");
  const social=read("lib/deda_social_service.dart");
  const reward=read("functions/deda_weekly_prize_shadow_settlement_NOT_EXPORTED.js");
  const exp=Object.freeze({
    authenticatedServerTaskXpIssuerExported:
      /\bexports\.dedaWeeklyGrantVerifiedTaskXp\s*=/.test(indexed),
    verifiedMultiUserStandingsCallableExported:
      /\bexports\.dedaWeeklyReadVerifiedStandings\s*=/.test(indexed),
    canonicalOwnerAttestationExporter:
      /\bexports\.dedaWeeklyIssueVerifiedAccountAttestation\s*=/.test(indexed),
    signedEquippedAppearanceIssuerExported:
      /\bexports\.dedaWeeklyIssueEquippedAppearance\s*=/.test(indexed),
    auditedSpendableEarnedPrizePayoutExported:
      /\bexports\.dedaWeeklyGrantEarnedPrize\s*=/.test(indexed),
    serverOnlyWeeklyCollectionRulesInSnapshot:
      /match\s+\/deda_weekly_xp_receipts\s*\/\s*\{/.test(rules) &&
      /match\s+\/deda_weekly_standings\s*\/\s*\{/.test(rules) &&
      /match\s+\/deda_weekly_identity_attestations\s*\/\s*\{/.test(rules),
    verifiedExistingPublicFriendUiWire:
      /DedaWeeklyLeaderboardPage\([\s\S]{0,3000}onOpenExistingPublicProfile\s*:/.test(
        read("lib/main.dart")),
    verifiedPublicFriendRequestWire:
      /DedaWeeklyLeaderboardPage\([\s\S]{0,3000}onSendExistingFriendRequest\s*:/.test(
        read("lib/main.dart")),
  });
  const auditedProperties={
    originalTaskXpSourceIsLocalOnly:
      /SharedPreferences/.test(xp)&&/PRIVATE QA ONLY/.test(xp),
    migratedProgressIsDefaultDisabled:
      /defaultValue:\s*false/.test(pay),
    stage9WritesOnlyEmulator:
      /FIRESTORE_EMULATOR_HOST/.test(stage9)&&
      /demo-deda-weekly-xp-stage9/.test(stage9),
    rankerNotExported:
      /NOT EXPORTED/.test(stage10) &&
      !indexed.includes("deda_weekly_receipts_to_standings_NOT_EXPORTED"),
    verifiedPairNotExported:
      !indexed.includes("deda_weekly_verified_pair_for_app_NOT_EXPORTED"),
    ownedAppearanceNotExported:
      !indexed.includes("deda_weekly_server_equipped_public_bridge_NOT_EXPORTED"),
    prizePathEmulatorOnly:
      /FIRESTORE_EMULATOR_HOST/.test(reward) &&
      !indexed.includes("deda_weekly_prize_shadow_settlement_NOT_EXPORTED"),
    existingFriendshipService:
      social.includes("sendFriendRequest(")&&social.includes("findByPublicId("),
    socialPageOnlyUsesVerifiedCallbacks:
      !stage22.includes("FirebaseFirestore") &&
      stage22.includes("onSendExistingFriendRequest"),
  };
  const blockers=Object.entries(exp).filter(([,yes])=>!yes).map(([name])=>name);
  if(blockers.length===0)blockers.push(
    "independentLivePrivilegesAndWalletRulesAndAppCheckAuditsNotYetApproved");
  const required=Object.keys(exp).length+1;
  return Object.freeze({
    stage:"23",
    publicRelease:"BLOCKED_UNTIL_INDEPENDENT_SECURITY_APPROVAL",
    trackedRepositoryChecks:exp,
    sourceSafetyChecks:auditedProperties,
    blockers,
    distinctRequiredGates:required,
    independentProductionRuntimeAndFirestoreRulesVerified:false,
    paidRewardsEnabled:false,
    liveUserTaskXpAuthorityEnabled:false,
    notes:[
      "No existing user-level XP, account, wallet, frame or friendship records were read or written.",
      "A GitHub green CI is not a live backend, real user session or Play approval.",
      "Client XP and client-selected frames are not sources of authoritative competition outcomes.",
      "Weekly rewards are minted only via an approved audited earned-wallet ledger, never from GM personal diamonds.",
    ],
  });
}
if(require.main===module) {
  const result=check(path.resolve(__dirname,"../.."));
  process.stdout.write(JSON.stringify(result,null,2)+"\n");
  // For a readiness AUDIT the expected finding BLOCKED must exit zero.
  // A DEPLOY workflow must require a separate signed owner and live gate.
}
module.exports=Object.freeze({check});
