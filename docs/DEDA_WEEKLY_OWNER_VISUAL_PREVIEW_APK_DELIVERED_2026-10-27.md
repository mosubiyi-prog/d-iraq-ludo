# DEDA weekly leaderboard — OWNER VISUAL PREVIEW APK delivered
Date 2026-10-27.

## USER-DELIVERABLE (VISUAL-ONLY SEPARATE ANDROID APP)
- Built **SUCCESS**, GitHub Actions run https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40547751828
- Artifact ID: 12753044245; GitHub artifact name: `DEDA-WEEKLY-LEADERBOARD-VISUAL-PREVIEW-APK`.
- ZIP includes actual installable `DEDA-WEEKLY-LEADERBOARD-VISUAL-PREVIEW.apk` and READ-ME/SHA256.
- Exact APK SHA256: `df1f452dd43e5a3159afb34d4f7c3c18f1b0ceea26c4a3cf2535cb36a2eb3a6f`.
- Size: 45,578,604 bytes. ZIP download from GitHub Actions is expected to expire after 14 days, by 2026-11-10.
- Android package/applicationId: **`iq.deda.weeklypreview`**. IMPORTANT: DIFFERENT from production `com.diraq.ludo.d_iraq_ludo`; can install side-by-side, does NOT update the signed DEDA 100387. Original signing keystore/secrets were NOT used; Flutter preview build uses its own default debug signing in a release-formatted APK.
- Starts on a simple visual home showing the actual staged leaderboard home card and Open Ranks action. Tap card to see the current/previous week toggle, top-3 podium, positions 4–10, own rank #12, prizes and countdown on the same fixed/non-scrolling Flutter leaderboard page; responds to phones/tablets.
- The separate package has NO Firebase config, NO phone login, NO XP/diamond writes, NO production rewards/network tasks. Demo identities and XP are deliberately illustrative multiples of 20 (not signed verified server standings). Screen header and footer explicitly label **معاينة تجريبية / معاينة تصميم فقط**.
- Fixed prior standalone launcher overflow on 320×568. Successful final CI runs Dart analysis and Flutter preview widget tests across five phone/tablet layouts; Gradle release build and upload-artifact PASS. Locally re-extracted APK ZIP SHA256 matches uploaded manifest; APK ZIP integrity validated.
- This provides an actual Android UI review **only**; not the full DEDA app, not real leaderboard back-end, not production ready, not screenshot pixel-match. Check the user's actual phone and tablet and gather adjustments before integrating the final owner-approved design.
- If Android/Play Protect blocks install, DO NOT advise disabling safeguards; investigate and use a verified distribution channel or signed private test build.

## Still missing before official integrated DEDA APK
1. Trusted server-issued XP claim receipts with canonical account continuity across phones. Current task XP is local SharedPreferences and may fail to write after ordinary task points.
2. Server-only approved seven-day week schedule and reliable current+previous snapshots. Owner has not selected a weekday.
3. Exactly-once real existing spendable diamond wallet payout: 150, 100, 50 and 7 x 10 = 370 total, no operator fake balances.
4. One properly signed DEDA private integrated APK using reviewed backend, tests of both responsive home routes, real portrait/tablet comparison with owner's picture, no Play publication until separately owner-approved.

All original signed 100387 files, Firestore rules, Cloud Functions exports, tasks, quiz, XP, user balances and Play settings unchanged on this source-only preview branch.
