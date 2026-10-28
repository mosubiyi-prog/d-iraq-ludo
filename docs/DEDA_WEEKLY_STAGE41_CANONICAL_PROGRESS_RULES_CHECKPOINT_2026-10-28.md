# DEDA weekly league — Stage41 canonical recipient + verified-progress Rules private QA

Date: 2026-10-28
Branch: deda-weekly-stage41-canonical-recipient-and-progress-rules-qa-no-deploy-2026-10-28
Parent Stage40 VERIFIED SHA: 2637a24a87fc962e936d6309e5e5a42bcdf328f0
First fully passing Stage41 client attack CI: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40698458295 — 33 tests pass, 0 fail (original Stage33 compatibility included).

## Actual changes in isolated repository branch
- tools/app_stability/deda_weekly_stage41_canonical_progress_rules_candidate.py
  - Reads **ACTUAL currently deployed** Firestore Rules from the already-existing read-only access script, exclusively into the ephemeral GitHub runner. Refuses unknown shapes, original schema drift, overlapping progress matches and duplicate patch.
  - Adds a private candidate-only Rule enforcing original sending UID, different sender/recipient public ID, different receiver UID AND distinct canonical accountKey via the registered recipient share ID and users accounts. Same-account second phone/UID/public ID is rejected even when public ID text differs.
  - Adds explicit private candidate-only closed matches covering trusted migration, original evidence, verified progress, verified receipts, and stage38 fixture collections. IMPORTANT: current live rules already implicitly deny these paths. The locks are defense-in-depth against accidental later allowance; Firestore match ALLOW rules are ORed, so added deny cannot override a future overlapping wildcard ALLOW. Candidate refuses known overlapping matches, and tests the entire downloaded ruleset.
  - The full rules file and service account key are never logged, committed or uploaded; candidate exists only in RUNNER_TEMP and is removed.
- tests/firestore-rules/stage41_canonical_progress_cutover_rules.test.mjs
  - Runs client-authenticated SDK Firestore Rules emulator tests against the complete candidate derived from the production snapshot. Tests original legitimate sender and recipient reading, denial of self-share, same UID second ID, same canonical account across different UID, forged sender and GM client, location mutation/deletion.
  - Explicitly tests DENY of read, create, update and delete for 11 paths x 5 types of client (account owner, another device, manager, outsider, unauthenticated). A manager's client SDK is NOT server-admin authority.
  - Re-runs Stage33 original location-share regression; first pass 33/33 tests, no failure.
- .github/workflows/qa-deda-weekly-stage41-canonical-progress-rules-no-deploy.yml
  - Source guard holds original lib/android/backend/Functions/rules, archived original signed package, progress engine and package dependencies unchanged.
  - Reads deployed rules using existing **read-only** service-account action, runs candidate and two suites in demo emulator, deletes temp files.
- docs/DEDA_WEEKLY_OWNER_PREBUILD_ADDITIONS_REVIEW_GATE_2026-10-28.md
  - Records explicit owner command to provide **concise, comprehensive Arabic all-additions report BEFORE preparing APK** and obtain the owner's review before starting a new private build. Contains future integrated feature checklist; no build permission is inferred.

## Critical honesty & unresolved production gates
1. Candidate is NOT deployed to Firebase. No original user/manager wallets, XP, purchases, prizes, profiles, signed APK/AAB or Play changes.
2. A new Dart flag CANNOT remotely revoke old installed APKs' local SharedPreferences XP/points. Their local writer will continue unless client upgrade and server-enforced migration/account rules safely handle divergence.
3. Existing old local score/social coins/level/migrated purchases must be captured, independently reviewed and preserved, then migrated only after writer fencing and rollback design. An arbitrary client-submitted local balance cannot become trusted backend XP.
4. Stage38's server task proof and old writer fence were emulator fixtures, NOT a real privileged production issuer. No live task receipts, ranking or diamond payouts.
5. The candidate explicitly rejects receiver accounts missing canonical account keys; assess compatibility and completion of legacy account migrations BEFORE requesting owner approval for eventual Rules update.
6. A separate real authenticated original-task producer, App Check, old-client version gate, two-phone real tests, replay protection, original +5/+20/+10 receipt and frozen league-only suppression are still required.

## Owner review before version build
Mandatory: **before any APK/AAB preparation**, provide the owner a short report separating all completed changes, proposed build inclusions, incomplete backend integration and known test issues. Review all requested weekly leaderboard, 10 leaders, prizes, friend/profile taps, frames, monthly GM history, participant winner-card exact owner-approved artwork/text no name or ID, Baghdad freeze and weekly reset, and device data conservation. Do not build until that review.

Status: source changes saved; first candidate CI success 33/33. Final branch-head workflow must show SUCCESS after this checkpoint is committed. No deployment authorization.
