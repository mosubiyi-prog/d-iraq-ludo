# DEDA 100336 — Spark/Firestore-only engagement & dynamic owner color (QA stage)

**Branch:** `deda-100336-spark-firestore-safe-stage-2026-10-14` (isolated from Production, `main`, 100335 signed APK and all stored user/owner data). **No APK, no Firebase deploy, no accounts modified.**

## Precisely two approved features
1. **Like/follow with real totals:** Use `deda_spark_reactions/{placeId}/users/{accountKey}` private reaction booleans, and `deda_spark_totals/{placeId}` public aggregate numbers. Both updates happen in a single Firestore transaction and the accompanying candidate Security Rules validate exact per-user old/new change using `getAfter`. Never read/list any other user's reaction. Identity requires an existing verified `users/{uid}` and `deda_sessions/{uid}` pair for the same DEDA `accountKey`, so rotating the Firebase UID cannot duplicate the reaction. No fake initial counts. Red like/blue follow/gold follower counter UI remains independent of owner palette.
2. **Fourteen colors:** Verified place owner may update ONLY `themeIndex` (integer 0..13) on an already approved and published place. Existing name, approval history, GPS, status, availability and owner data unchanged. Existing 100336 marker uses owner theme for name/background/icon ring/DEDA badge when available and neutral grey for all when absent.

## Isolation and rollout gates
- `firestore.rules` and `firebase.json` — **UNCHANGED** (critical legacy routes/account protections).
- Experimental rules live in **`firestore.spark.qa.rules`** and are used only with **`firebase.spark.qa.json`**, targeting `demo-deda-spark-100336` Firestore Emulator, NOT the actual `deda-25b88` database.
- Client service modifications are isolated in `lib/deda_place_engagement_service.dart` and `lib/deda_place_branding_service.dart`. Runtime direct mode requires two explicit Dart flags: `DEDA_PLACE_ENGAGEMENT_LIVE=true` and `DEDA_SPARK_FIRESTORE_LIVE=true` (owner color additionally requires `DEDA_OWNER_PLACE_BRANDING_LIVE=true`). Defaults all remain **false**. Existing Firebase Cloud Functions paths remain available in the adapters.
- Previous 100336 full Flutter **21/21** and 24 Firebase Emulator/Node security tests passed on callable mode. Spark-mode guards additionally test forged/unauthorized atomic totals, cross-account read denial, actual 14-color owner-only updates, verified account-UID rotation, and untouched `users` and `deda_sessions`.
- Before considering deployment of anything to production: verify **actual currently deployed rules** and narrowly merge/test only the two Spark collections + owner `themeIndex` permission; **DO NOT overwrite** production rules with a local snapshot. Ensure no access regression for existing user accounts or admin capabilities; get owner's explicit approval of the exact deployment scope and Firebase service access. Test two real DEDA accounts before marking live and producing a signed 100336 APK.
- Spark is billed per database usage / quotas, not "unlimited free" automatically. Monitor reads/writes and avoid excessive reads.


## Updated validated isolated QA (2026-10-14)

- [Spark Firestore real rules/transactions run **38602463964**](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38602463964): **SUCCESS — 8 tests passed, 0 failed**. Confirms old user/session documents byte-for-byte unchanged, UID rotation idempotency, two-account simultaneous actions (with bounded read-fresh transaction retries), rejection of both stand-alone and **atomic** count forgeries, 14 owner-only palette colors, rejected unauthorized access, and legacy server-only counters still protected. The first extra concurrency test failed safely, and this final run demonstrates the corrected contention strategy.
- [Initial Spark client Flutter source workflow **38601807199**](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38601807199): **SUCCESS — 21 Flutter tests and clean analyzer**. The final update to the bounded-retry client is still subject to its newest Flutter QA job.
- IMPORTANT: both feature flags and the direct mode flag are still OFF by default. This is a tested **staging approach**, NOT a live production rollout. No existing user account, PIN, session, location, approved place, or on-device application was changed.


## Production-readonly live-rule merge checkpoint — 2026-10-14

**LIVE production rules were fetched successfully, not guessed:** DEDA project `deda-25b88`, Firestore ruleset `projects/deda-25b88/rulesets/2891ea9d-8bcb-4fc3-b677-525fd3d6881a`, live SHA-256 `df9fbbbfa30ade3bae6859e4d8dbc2f84660e3d6b77915d54dd1b5184e0ec8b4`.

- The deployed rules **do NOT match** repository `firestore.rules` (local SHA-256 `36ee21462d55a354928d49b7548e17cb84289b34652ad0177eb678b3848f05b4`). DO NOT deploy repository's old `firestore.rules` directly. Current production lacks the un-deployed legacy `deda_place_engagement_totals` rule, which is expected/allowed; the Spark backend uses separate collections.
- Created a **read-only** script that appends exactly the `deda_spark_reactions` and `deda_spark_totals` match blocks plus supporting functions, and inserts a **separate narrow owner-only themeIndex permission** without modifying or deleting any published `allow` clauses. Proves the entire merged preview reverses byte-for-byte to actual live source.
- [Run 38605416682](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38605416682): **SUCCESS**. Live rules GET HTTP 200, exact-additive scope validated, original live rules backup created as private GitHub Actions artifact `DEDA-100336-LIVE-ORIGINAL-RULES-READONLY-BACKUP` (artifact ID `11914913827`, expires **2026-11-13**). Fully merged preview SHA-256 `5788863fd1fd27d965ea5ba367fedcfe0fc2f0b530289fd25535ed7c85e2b25e`.
- **8/8 Firestore Emulator tests passed on THE EXACT MERGED LIVE PREVIEW**, covering preservation of existing user/session data, independent two-account follows/likes, rotated UIDs, simultaneous transactions and anti-forgery, 14 owner-only colors, and rejection of unauthorized writes. Original production rules were NEVER changed.
- Full Spark Flutter source QA previously [run 38602498023](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38602498023) **SUCCESS**, 21 Flutter widget tests, analyzer clean, and original navigation/admin/drafts checked.
- **NOT LIVE YET.** Actual production rule deployment and two-real-user-account device QA are still outstanding. No signed 100336 APK has been built with the direct mode enabled. Never misstate source/emulator QA as a live backend release.
- **Next gated operation:** obtain the owner's explicit final permission for **Firestore rules-only deployment** (no Functions, no data writes, no Google Play), using the exact LIVE baseline and reviewed preview SHA as dual stop checks; immediately reread published rules afterwards and abort on any baseline drift. A rollout must include a rollback copy of the original live rules, saved before deployment.


## Explicit-approval release preparation (still NOT active)

- Prepared an **inert** production-rules-only workflow template at `docs/ops_templates/deploy-deda-100336-spark-firestore-EXPLICIT-APPROVAL-ONLY.yml`. It is **outside** `.github/workflows`, so it cannot trigger or deploy.
- Release template freezes exact production baseline SHA `df9fbbbfa30ade3bae6859e4d8dbc2f84660e3d6b77915d54dd1b5184e0ec8b4` and additive candidate SHA `5788863fd1fd27d965ea5ba367fedcfe0fc2f0b530289fd25535ed7c85e2b25e`, saves the full original rules with a new private 90-day backup artifact, re-tests the merged preview in the Firestore Emulator, checks production still unchanged *immediately before* the single `firebase deploy --only firestore:rules` command, and independently verifies the deployed rules against the exact preview source afterwards. It has **no Cloud Functions, APK, Google Play or user/account data mutation**.
- Added a separate read-only verifier `tools/deda_100336_spark_release_baseline_guard.py` for the before/after exact snapshots.
- [Inert template QA run 38606219367](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38606219367) **SUCCESS**, including explicit assertion that the ACTIVE deployment workflow file does not exist.
- **NEXT: ask for distinct explicit authorization to publish Firestore security rules only** on `deda-25b88`. A general approval to continue coding/QA does not activate production changes. After authorized rules deployment, produce a *private* correctly signed 100336 APK with 3 direct-mode compile-time gates enabled and test with 2 real accounts before any Play update.
