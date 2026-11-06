# DEDA 100437 regression: confirmed build-process root cause and safe repair checkpoint
Date: 2026-11-06 (Iraq); status: PLAN ONLY — NO APP SOURCE EDITS / NO APK / NO DEPLOY.

## Owner report
Owner reports signed 100437 unexpectedly resembles a version nearly 100 releases earlier, whereas signed 100436 displayed the intended recent app features. Phone video exhibits older UI (restaurants rather than weekly leaderboard). Any later video supplied by owner must be inspected and observations added before implementation.

## Verified facts and evidence
1. Last known good installation baseline: signed **100436** via workflow `.github/workflows/deda-100436-exact-100420-signed-private-apk-no-play.yml`, reference commit `fea54d7db2e8a24a74267f04a14c9572bcb408ee`. This workflow applies the full app-specific ordered bind chain (including weekly stages 13–28, 100397–100410, 100411, 100413, 100414, 100418), plus separate QA gates.
2. Faulty signed **100437**: GitHub Actions run 42122430760 (success), source `80f5c03e4a25677b448b1593f843995c6d81b356`, workflow `.github/workflows/deda-100437-stage2-preactivation-owner-apk.yml`.
3. 100437 first executes `tools/app_stability/app_package/prepare.py --variant candidate` and then runs `cp -a "$GITHUB_WORKSPACE/lib/." "$project/lib/"`. This overwrites generated and patched Dart files with the repository's raw `lib` tree, while omitting the complete ordered 100436 league / ID / friends / admin bind pipeline. The shipped Dart `lib/main.dart` raw source does not contain Arabic string `المتصدرون` or `الدوري`. Hence a green build verifies successful compilation/signing, not functional parity with 100436.
4. `prepare.py` records a prior internal stage version 100387 before later modifications, which is NOT equivalent to retaining all signed-100436 patch stages. The new build number 100437 cannot prove it includes newer features.
5. The 100437 workflow explicitly sets `DEDA_STEP2_EXISTING_ACCOUNT_ENTRY=false`, `financialRestoreEnabled=false`, and documents that account recovery is not yet functional and no Firebase functions/rules or Play changes are deployed. Therefore it is not a completed recovery release.
6. This regression is independent of Firebase billing. Do not infer that all cloud/local user data has been deleted from UI regression alone.

## Approved safe repair approach (document now, implement only after owner's video review and explicit continuation)
1. Freeze signed 100436 as immutable, verifiable UI/feature baseline; no edits or destructive operations to its branch/source.
2. Build from the **exact 100436 fully patched output / exact reproducible ordered workflow**, not from only the raw repository sources. Avoid `cp -a lib` over built source, or any copy that silently undoes feature patches.
3. Carefully integrate stage-two account recovery code into the 100436-complete application with compatibility review for UID, linked-owner/session/admin, Firebase backend, wallets, league, profile, friends, special IDs, prizes, tasks, and saved places; preserve original signer/package/user data, and do not activate unfinished recovery interfaces.
4. Introduce automated regression gates *before* build or artifact upload: assert leaderboard tile and freeze/countdown, weekly league points/prizes, premium ID/old-ID semantics, friend copy/ID, admin functions and permissions, daily tasks, quiz, wallet/profile and other existing 100436 UX, on the **final assembled sources**. Compare final assembled source hashes/feature manifest with approved 100436 output and ensure new recovery code is actually integrated.
5. Add a **fail-closed gate** that blocks APK when baseline parity isn't demonstrated; compiler/unsigned tests alone do not pass. Run app smoke tests and signed artifact checks on final APK; verify exact sign certificate, applicationId, increasing versionCode and in-place install safety.
6. Separately gate real account recovery: retain existing account and financial recovery disabled until supporting cloud functions, rules, billing/deployment prerequisites and end-to-end two-phone restore tests are ready. Do not claim recovery finished or ready merely because APK builds.
7. Only after all parity gates pass and the owner approves, generate new APK number >100437 for phone QA. Never publish to Play as part of this plan. Do not erase app data, uninstall old app, switch phones or modify users' production financial data during investigative QA.

## Current stop point
- Diagnosis completed; regression repair plan saved, **no code or Firebase deployment authorized or performed here**.
- Await the owner's promised additional video, inspect it, update diagnosis and implementation tests accordingly.
- When resuming, inspect complete workflow source and build logs, then implement on an isolated branch with explicit parity validation against 100436 and no modifications to protected 100436.
