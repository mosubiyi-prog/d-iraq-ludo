# DEDA weekly leaderboard — phone and tablet fixed-viewport QA checkpoint
Date: 2026-10-27 | NO APK/AAB | NO FIREBASE/PLAY DEPLOY

## Accepted reference
- The owner's dark navy and gold screenshot is the ONLY approved visual layout and spacing reference. The complete leaderboard MUST fit in one screen without page scrolling or vertical/horizontal lists; top three podium, 4–10 table, current user's own rank, weekly tabs and countdown, prize footer.
- The user explicitly wants BOTH phone and Android tablet compatibility, in portrait and landscape orientations. Preserve composition and prevent wide landscape tablets stretching the podium cards horizontally.
- DEDA 100387 remains the protected phone-tested fallback at commit `a0dd340e8843162ac5fb89784cb54d0be82b23ec`. NEVER modify original app/main.dart, backend, XP, task points, wallets, Firestore rules, cloud functions or production Play release.

## Actual implementation added in this isolated branch
- Branch: `deda-weekly-leaderboard-phone-tablet-viewport-qa-no-deploy-2026-10-27` from completed Stage 8.
- `lib/deda_weekly_leaderboard_page.dart`: uses a centered, one-viewport **2:3 proportional stage** bounded by safe available height and width. On portrait phones fills available phone width; on very wide tablets/landscape centers a proportionally sized leaderboard canvas rather than stretching score columns and podium to extreme widths.
- The stage contains the original approved component arrangement and proportional scaling of text, medals, avatars, fields and padding based on both available dimensions. It remains **non-scrollable**, uses SafeArea for system/status/navigation bars, and does not crop records.
- `test/deda_weekly_phone_tablet_viewport_test.dart`: verified test fixtures with 12 users (top 10 and current user in rank 12), prize amounts and both week tabs. Eight device sizes including phones (320×568, 390×844, 412×915), tablets (600×960, 800×1280, 1024×1366), landscape tablet (1280×800) and wide emulator (2560×1600). Asserts no scroll, no framework overflow/exception, centered stage exactly matching 2:3/phone width constraint, top/prize/user content displayed, tabs preserve layout; additionally asserts 32px status and 24px navigation safe insets.
- `.github/workflows/qa-deda-weekly-phone-tablet-fit-no-deploy.yml`: CI guard verifies the signed-100387 original app, XP, wallets, Firebase, rules and release/build sources byte-for-byte unmodified. Runs Dart analyzer, new 8-screen responsive tests, previous stage2 fixed-screen, stage4 earned-points and stage8 safe-account-switch Flutter widget regression tests.

## Verified CI
SUCCESS: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40543359204
All included widget and static checks PASS; this is real Flutter layout QA **in an automated test environment**, not yet an APK verified on the owner's physical phone/tablet. It is not a pixel-diff match against the supplied screenshot. Such real-device visual review remains REQUIRED before declaring exact-image parity.

## User's 4 still-outstanding live-delivery steps
1. Secure authoritative 20 LEVEL XP task-reward events and same-account cross-device persistence. Current 100387 XP task evidence is local to SharedPreferences. A client-supplied point count, cloud boolean or arbitrary XP field is NOT secure for real diamond rewards. Server-owned proof and actual XP credit must be verified; no retroactive guessing.
2. Approved and issued current/previous weekly competition calendar/snapshots and automatic ordering from real verified XP, without phone numbers, fake rankings or a guessed start day.
3. Original production *spendable* diamond wallet audit, then server-only exactly-once idempotent 370-diamond prize settlement using unique (weekId,canonicalAccountKey) keys with admin audit and retry safety. Never touch the GM personal million or admin gifts.
4. Integrate reviewed backend and all staged UI into ONE private signed APK, owner tests on phone and tablet (no scroll, no crop, design fidelity, Play Protect), then separate explicit production-release decision.

No live server callable, identity issuer, scoring ledger, authorized wallet-credit transaction or deployed APK is implemented by this viewport change. Original stable version is safe. The default leaderboard will remain pending, not populated with invented players, until the trusted backend exists.
