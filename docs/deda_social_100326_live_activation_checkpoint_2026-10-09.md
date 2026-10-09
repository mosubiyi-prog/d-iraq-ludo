# DEDA 100326 — Live activation checkpoint — 2026-10-09

## Scope approved
Activate social-task configuration only, separately from the original eight
daily tasks and the daily login reward. No user wallet, reward, or AdMob payout.

## Outcome of GitHub Actions run 37983045020
- 100326 social policy and manager verification preflight: passed.
- Compared live Firestore rules to reviewed SHA18 def3434ab5add714b7.
- Saved backup BEFORE production change in run artifact:
  DEDA-100326-PRE-ACTIVATION-LIVE-RULES-BACKUP
- Isolated three social rule blocks preserved all previous rules.
- Four tests against exact merged live rules in Firestore Emulator: passed.
- Deployed only Firestore rules to deda-25b88: SUCCESS.
  Expected merged rules SHA18: 3408852ae0fd2dcd4b.
- Deploy of the two NEW social Cloud Functions: FAILED BEFORE FUNCTION CREATION.
  The Cloud Build API cloudbuild.googleapis.com is not enabled, and configured
  Firebase service account cannot enable project APIs.
  Also missing artifactregistry.googleapis.com; Firebase attempted to enable it.
- A subsequent live confirmation workflow can verify rules SHA read-only.
- Application 100326 already has the management UI but cannot yet save or schedule
  because Cloud Functions deployment has NOT completed.
- No sample Telegram social task was saved or published.
- No diamonds, coins, points, manager wallets, or legacy daily tasks changed.

## Required project-owner action
Enable these Google Cloud APIs on project deda-25b88:
- https://console.cloud.google.com/apis/library/cloudbuild.googleapis.com?project=deda-25b88
- https://console.cloud.google.com/apis/library/artifactregistry.googleapis.com?project=deda-25b88

Potential additional requirement: active billing, Cloud Functions v2 build/runtime IAM.
After owner confirms both services are enabled, rerun a safely scoped deployment
of functions:dedaManageSocialTaskTrial and functions:dedaPublishSocialTaskTrial
ONLY (do not redeploy all rules or other functions). Verify deployment success,
then guide owner to restart the installed 100326 app and use Save then Schedule.

Primary run:
https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/37983045020
