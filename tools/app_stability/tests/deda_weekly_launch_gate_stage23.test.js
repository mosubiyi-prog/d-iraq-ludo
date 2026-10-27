"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const path=require("node:path");
const {check}=require("../deda_weekly_launch_gate_stage23.js");
const ROOT=path.resolve(__dirname,"../../..");
const report=check(ROOT);

test("source snapshot has no production weekly XP issuer or leaderboard callable",()=>{
  assert.equal(report.publicRelease,"BLOCKED_UNTIL_INDEPENDENT_SECURITY_APPROVAL");
  for(const name of [
    "authenticatedServerTaskXpIssuerExported",
    "verifiedMultiUserStandingsCallableExported",
    "canonicalOwnerAttestationExporter",
    "signedEquippedAppearanceIssuerExported",
    "auditedSpendableEarnedPrizePayoutExported",
    "serverOnlyWeeklyCollectionRulesInSnapshot",
  ]) assert.equal(report.trackedRepositoryChecks[name],false,name);
  assert.equal(report.liveUserTaskXpAuthorityEnabled,false);
  assert.equal(report.paidRewardsEnabled,false);
  assert.ok(report.blockers.length>=6);
});
test("original frame/social APIs exist but are not authorized production leaderboard callbacks",()=>{
  assert.equal(report.sourceSafetyChecks.existingFriendshipService,true);
  assert.equal(report.sourceSafetyChecks.socialPageOnlyUsesVerifiedCallbacks,true);
  assert.equal(report.trackedRepositoryChecks.verifiedExistingPublicFriendUiWire,false);
  assert.equal(report.trackedRepositoryChecks.verifiedPublicFriendRequestWire,false);
});
test("private XP trial is local; server-only emulators and new migrated wallet remain isolated",()=>{
  for(const x of [
    "originalTaskXpSourceIsLocalOnly",
    "migratedProgressIsDefaultDisabled",
    "stage9WritesOnlyEmulator",
    "rankerNotExported",
    "verifiedPairNotExported",
    "ownedAppearanceNotExported",
    "prizePathEmulatorOnly",
  ])assert.equal(report.sourceSafetyChecks[x],true,x);
  assert.equal(report.independentProductionRuntimeAndFirestoreRulesVerified,false);
});
test("readiness cannot be inferred just because source UI, prototypes and CI pass",()=>{
  assert.equal(report.publicRelease,"BLOCKED_UNTIL_INDEPENDENT_SECURITY_APPROVAL");
  assert.ok(report.distinctRequiredGates>=8);
  assert.equal(report.notes.some(x=>x.includes("green CI")),true);
});
