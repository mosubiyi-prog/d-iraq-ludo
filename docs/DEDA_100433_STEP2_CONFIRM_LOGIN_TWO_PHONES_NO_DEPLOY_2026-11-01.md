# DEDA 100433 — Complete Account Restoration, UI-level login integration checkpoint
Date: 2026-11-01. Private QA branch: `deda-100433-step2-account-confirm-new-phone-ui-private-no-deploy-2026-11-01`.

## Exact user scope
**Goal remains ONE complete point:** original number+PIN account opens on another phone with exact original ID, all XP/level/task points, all diamonds (earned/received/manager), all frames, premium ID, gifts, daily tasks, quiz progress, weekly league, friends and settings; no lost or duplicated money/rewards. Do NOT call this done until real production-safe backed-up data actually hydrates on the second physical device. No added "user points" or unrelated changes.

## Concrete 100433 work done
- `lib/main.dart` now wires two explicit opt-in UI controls under compile-time safety flag:
  - On original phone, **Confirm account** button sits immediately above **Sign out**, as owner requested. It asks for the six-digit PIN via a temporary obscured dialog, links only the proven original anonymous UID through `DedaOwnerUidContinuity.linkExistingOriginalUid`; no PIN in preferences or logs.
  - On another phone, **Sign into confirmed account** button sits beneath old normal sign-in and requests account PIN, uses managed Firebase Auth Email/Password provider with existing `phone@deda-login.invalid` domain, `DedaBackend.personalShareIdForPhone` original routing, then existing local profile login flow after same-UID proof.
  - Both controls are fully gated behind `dedaLinkedOwnerCompatEnabled` with **default false** in `lib/deda_100431_linked_owner_session_policy.dart`. No existing 100340 user sees them in production.
- `lib/deda_pin_auth.dart` and `lib/deda_backend.dart` from prior 100431 were updated for a confirmed non-anonymous owner without treating them as an admin or silently signing out. Old anonymous login remains default.
- `lib/deda_100432_quiz_cloud_continuity.dart` already implements one-time, UI-only old/new phone quiz cloud readback; its added Firestore Rule is staged locally from GET-only live rules and NOT published. It does not credit points/diamonds, nor transfer a premium ID.
- `test/deda_100433_owner_confirmation_ui_test.dart` has 5 real Flutter UI cases: disabled by default, explicit PIN submit only, cancel, incomplete PIN rejection, no private error/PIN exposure.
- All values remain untouched, no Firebase production changes or signed APK/Play publication.

## Verified CI
- [GitHub Actions #41341376893](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41341376893) **SUCCESS** with both jobs:
  - 6/6 actual Firebase Auth emulator original-UID link across two phones and wrong-PIN/collision safeguards.
  - Flutter 5/5 button PIN widget + 9/9 original-owner scope tests + 10/10 old/new quiz restore tests, **30/30 test cases total**, zero failures.
  - Analyzer returned no compile errors but **124 pre-existing or existing static warnings/info notices** across the giant `lib/main.dart`/backend and related files, so the workflow uses `--no-fatal-warnings`. Do not claim zero lints; these warnings did not block tests.
- [GitHub Actions #41339792251](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41339792251): **SUCCESS**, 42/42 quiz-cloud and 100408 unchanged league/prize permission tests, using GET-only LIVE production rules staged into isolated local emulator.

## Why the whole point is STILL OPEN (NOT a request for a new project)
1. The original source UID is not guaranteed globally unique to just one DEDA phone account. `deda_account_directory` Firestore Rules disallow listing, so the client cannot detect two phone accounts created under one historical anonymous UID. Link-to-email could conflate them unless a trusted server verifies exact one-account uniqueness; server-only 100424 HOLD and 100428 scanner are still undeployed.
2. Six-digit PIN + synthetic Firebase email/password is not a strong recovery factor against a determined attacker. Auth abuse protection helps but no source verifies a globally limited PIN attempt ledger. Production review must require stronger assurance before the authenticated UID is permitted to restore financial assets.
3. Financial state/level/task history is partly local to old 100340 phones. The reviewed baseline/once-only ledger prototype and wallet-source controls are NOT cut over, nor protected against old writer races; no complete authoritative snapshot exists for all active legacy accounts.
4. UI-only quiz cloud Rules are not published; backup is currently source/test code, not automatically invoked on real old/new phones. The old Play 100340 app cannot upload new backup schema, and no real Android original or replacement phone acceptance was performed.
5. Frames/premium aliases/received gifts, weekly score, friends/settings still need separate canonical owner-scoped live readback and exact no-duplicate transfer policy.

**Release decision:** private source and emulator QA GREEN; whole-account real recovery / signed APK / production cutover **ON HOLD**. The source-only opt-in UI must NOT be offered as ready for users or called "fully secured" until trust and migration gates are satisfied. There is no Cloud Functions/Billing change or user action needed for this checkpoint.
