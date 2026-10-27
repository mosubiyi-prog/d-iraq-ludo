# DEDA Weekly League — Stage11 original-app current/previous read integration
Date: 2026-10-27 | Branch: deda-weekly-stage11-original-app-projection-qa-no-deploy-2026-10-27

## Owner approval / immutable original
Owner tested the royal V2 standalone preview APK on Android and explicitly said it looks successful and ordered completing the remaining changes ON THE ORIGINAL APP. The preview has sample competitors; NEVER ship DEMO users into a live league.

Immutable phone-tested official app reference is DEDA 100387 source a0dd340e8843162ac5fb89784cb54d0be82b23ec. New source branches inherit FROM it; the original branch, tasks, old scores, actual XP, diamonds, login, IDs, wallet, Firebase deployment and Play release remain unmodified.

## This branch actually adds
1. functions/deda_weekly_verified_pair_for_app_NOT_EXPORTED.js: one read-only composition of future canonical account attestation (Stage6), owner-chosen Iraq current+previous 7-day boundaries and private redactor (Stage7), and server-authoritative level-XP receipt rank projector (Stage10). Produces exact privacy-redacted DTO for the verified Flutter decoder/Stage8 native screen. No network endpoint, exports, schedule, Firestore write, task award or payout.
2. functions/tests/deda_weekly_verified_pair_for_app.test.js: simulated two weekly receipts streams; 20 real-formatted earned LEVEL XP per confirmed task; authentic-looking but entirely test-only profiles; overtake, current/previous ranking, one canonical account on two UIDs, HMAC tokens, missing attestation, non-owner calendar, forged quiz-only 5 points, missing previous results, client score/diamond submissions and private-key failures. Source strings alone are not cryptographic proof in production.
3. tools/app_stability/tests/test_weekly_stage11_original_native_integration.py: actually reconstructs original 100387 Flutter source in an isolated temporary directory, invokes the tested Stage2 and Stage8 binders, checks both existing home layouts open the live-data-safe V2 visual page, restaurant quick-entry alone is replaced, original task/backend/quiz/social/public package files byte-identical; prevents any repo mutation.
4. New GitHub Actions QA NO DEPLOY workflow runs these integrated tests and earlier security/layout regression suites. Preserve the original verified release.

## Required unresolved gates — not a working league yet
- PRODUCTION server-issued trusted task completion and actual +20 level-XP award receipt on the same durable cross-device account; never use local SharedPreferences as prize authority and never double-credit the existing user's XP.
- Actual trusted account attestation, server-only Firestore Rules, approved day-of-week/week calendar, protected receipt/profile/snapshot publishers, App Check and QA emulator. Stage11 reads only test fixtures.
- Audit the actual authorized *spendable earned-diamond wallet* and implement exactly-once winner grants (150/100/50/10x7, 370 total). Do not create users/{uid}.diamonds or touch general manager's gift/manager balance. No payout exists in this stage.
- After full guarded integration, deliver ONE original-package signed private 100387-derived APK and physically verify phone/tablet, no scrolling or clipping, real names and active IDs, current/previous weeks and account switching. Public Play deployment needs separate approval.

No claims of real leaderboard availability, diamond credits, live Firebase changes, private APK release, or production CI until verified.


## Confirmed QA status and wallet audit
- First Stage11 GitHub Actions run 40556240490 finished with BOTH jobs SUCCESS:
  https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40556240490
  - Reconstructed ORIGINAL signed-100387-derived code, both leaderboard navigation routes, no DEMO user injection, session/account privacy, staged XP receipt-to-current/previous safe data pair, prior Stage6/7/9/10 regression suite PASS.
  - Dart analyzer and phone/tablet viewport fixed non-scroll UI regression PASS.
- Checked repo functions/index.js (1329 lines): no deployed-export source for dedaReadMigratedProgress or dedaPurchaseMigratedFrame; no weekly issuer, ranker or prize payout export here. This does NOT prove what may be deployed live; audit deployed Firebase environment before any release.
- Checked repo firestore.rules (2445 lines): no deda_weekly-specific protections; README comments explicitly warn rules are an unverified snapshot not necessarily live.
- Checked lib/deda_migrated_progress.dart: distinct earnedDiamonds, giftedBalance, nullable managerBalance, purchasableBalance; manager override means a naive earned+gift total can disagree with spendable balance.
- Checked rules for deda_diamond_gift_balances: this is the protected ADMIN GIFT route, with pending gift -> received credit, NOT verified as an earned weekly-prize credit writer. Never use it for leaderboard prizes, nor users/{uid}.diamonds.
- Conclusion: DO NOT DEPLOY a weekly prize credit (370 diamonds), fake XP records, new rules snapshot or unverified original APK. Live credentialed verification and a genuine earned wallet writer remain mandatory.
