# DEDA 100374 — owner-requested non-identifier private QA (2026-10-21)

## Decision and boundaries
- Owner explicitly chooses a SMALL non-ID correction APK now and postpones every **premium identifier/alias/use/grant/search/inbox routing** repair to the next separate release.
- Preserve live user accounts, levels, gems, points, purchases, places, original ID, current premium ID, prior claimed gift receipts and historic records. No production Firestore/Cloud Functions/Play release edits or migration without explicit owner approval.
- Based on the exact **phone-tested 100373** commit `9786a4171597fc8ac74eba8b411965affc96e1e0`, source/checkpoint plus `backup-deda-qa-32-owner-review-2026-10-21`. Do not change or force-move either backup or 100373 branch.
- Isolated development branch: `deda-100374-non-id-fixes-private-2026-10-21`.
- Only a new owner-only private APK after Flutter/tests, original signing verification and owner Android 16 tests; absolutely no Google Play update automatically.

## Owner findings and disposition
- **Keep passed:** original-ID location sharing and map opening, 50-gem admin gifting, receipt and claim, previous 10-gem history, premium ID visible on owner's own share/account view, couple portrait/frame/background visible in friend's preview, existing four free ID foil rendering.
- **Non-ID target #1:** `هداياي` home navigation notification did NOT alert according to owner's real recipient test during new 50-gem gift. Screenshot taken after claim cannot alone establish before-claim state, so audit badge data flow and add no-fabrication tests for new pending, viewed, claimed, refresh and account change. Don't send any more real diamonds just for diagnosis.
- **Non-ID target #2:** friends' public profile name/canonical fallback text were unreadably dark in owner's **tablet** screenshot. The latest 100373 reconstructed code already contains white text and has Flutter unit tests; test that actual recipient/second device is using **100374 before claiming a regression was fixed**. Add explicit canonical white-text regression, preserve existing real owner portrait/frame/background/level.
- **Postponed ID items:** recipient location share old visible ID; friend visible original instead of premium; GM gem recipient premium alias lookup fails; disabled 'use' and account verification of owned identifiers; full verified premium foil; server callable and Firestore/cloud account migration; 13 additional LAB frames are NOT automatically part of this small patch.
- **Still critical but not in this mini release:** same-account migration and permanent server recovery of progress/XP/gems/items/place on phone switch; never reset balances or attempt unsafe reconciliation.

## Guardrails, tests and status
- Existing 100373 signed source last passed [GitHub Actions 39628687478](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39628687478), successfully produced original signed APK. Success of that build does not imply all 32 requirements complete.
- New isolated non-build diagnostics workflow [GitHub Actions 39642703133](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39642703133) determines the **actual reconstructed source** for legacy diamond badge and public contrast; do not patch the stale checked-in `lib/main.dart` as if it were the final Flutter app.
- New Flutter regression test: `test/deda_100374_nonid_public_readability_test.dart`.
- Status: **IN PROGRESS / NOT YET A DOWNLOADABLE NEW APK** at creation. Confirm GitHub CI, artifact, signing, package and owner phone only after all pass.
