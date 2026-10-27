# DEDA Stage13 original 100388 — private QA only
Date: 2026-10-27

## Immutable reference and accepted design
Original signed DEDA 100387 source: a0dd340e8843162ac5fb89784cb54d0be82b23ec.
Owner approved dark navy/gold royal league fixed full-screen, no scrolling, portrait+tablet.
Never edit or overwrite original release, accounts, profile XP, quiz, level, ID, Firestore, gifts or wallets.

## Implementation
- tools/app_stability/app_package/bind_weekly_stage13.py applies the already-validated Stage2+Stage8 league UI binders AFTER restore of signed 100387 candidate into a temporary original app directory. Only main.dart and four new additive Flutter leaderboard files can change; source hashes re-verified. Replaces Restaurants home shortcut in BOTH home layouts; restaurant search remains on map.
- The official app package com.diraq.ludo.d_iraq_ludo and original keystore retained, private candidate versionCode bumped to 100388.
- Same confirmed royal V2 page and its verified read-only current/previous UI contract, but NO DEMO entrants inside the original app; the page displays pending verification with NO live backend.
- tools/app_stability/tests/test_weekly_stage13_original_signed_candidate.py validates full reconstructed 100387 code and invariant sources.
- .github/workflows/qa-deda-weekly-stage13-original-100388-signed-private-apk-no-deploy.yml reconstructs original app, runs guarded source + backend tests, validates original keystore and matching APK signer using established verify.py, and creates a downloadable original-package 100388 APK only if all checks PASS. No Firebase or Play deployment.
- No app account/XP/diamonds touched by source integration. Stage12 370 diamond mock payout tests passed: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40558988555

## Production and QA gates
1. True server-verified canonical account, daily task completion AND actual 20 LEVEL XP receipt on original account across phones; never mint retroactive XP from local booleans.
2. Owner-specified start day of seven-day Iraq week; privileged live current/previous snapshot writer + authenticated read endpoint, verified current active IDs, avatars and names; real Firestore rules and App Check checked before deployment.
3. Audit REAL spendable earned-diamond wallet. Stage12 shadow payout never credits live wallets; weekly rewards 150/100/50/10x7 remain not live.
4. Validate signed APK existence and artifact, original signer, real phone/tablet installation/no overflow, original tasks/IDs/profiles and Play Protect. If blocked, stop and do not bypass.
5. Owner decides separately whether/when to publish an actual approved league on Play.

This is NOT a finished online competition; UI integration is held pending verified server authority and secure rewards. Do not claim signed APK delivered without successful GitHub Actions.
