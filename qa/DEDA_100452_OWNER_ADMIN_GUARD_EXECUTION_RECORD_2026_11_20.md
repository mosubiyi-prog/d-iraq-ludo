# DEDA — Director directive 01 — isolated owner/admin session safety repair
Date: 2026-11-20 (Iraq)
Status: **PARTIAL SOURCE REPAIR / NOT APPROVED FOR INSTALLATION**
Branch: `deda-100451-owner-admin-session-safe-repair-2026-11-20`
Protected source baseline: `3ef175a780d9cffd93cfe1ef79ebfd21880acfe5` (100451 signed CI source on 100450 working branch).
CI evidence: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/44624706099 — **success**.
No production deployment, Firebase write, Google Play release or replacement APK was performed.

## Original job
Restore stable DEDA login/owner UID and general-manager access without account identity churn, data loss, removal of existing app features, or changing approved UI placements. Complete historical asset recovery only with independently verified provenance. The older 100451 signed APK is **not** an approved owner-device upgrade.

## What was changed (in this isolated branch only)
- `lib/deda_100431_linked_owner_session_policy.dart`: In owner-protected builds, admin sign-out now requires explicit *fresh-server evidence that the current principal has no public DEDA owner session*. Missing evidence fails closed. The published non-pilot behavior is unchanged.
- `lib/deda_backend.dart`: Before admin sign-out, check the active administrator document and the server-side `deda_sessions/{uid}` owner record, reject owner collisions, and recheck the same principal before sign-out. Only read operations; no UID rewrite, deletion, asset movement or owner logout.
- `test/deda_owner_session_compat_private_test.dart`: Add regression cases for dual-role admin/owner UID and missing fresh owner proof, retain old published-path assertions.
- `.github/workflows/deda-100452-owner-admin-session-repair-qa-no-deploy.yml`: Test source guard, Flutter focused tests, legacy auth-conflict merge, full protected source assembly and merged-backend analyzer. **No APK**.

## 15 mandatory oversight areas
| # | Area | Result |
|---|---|---|
| 01 | Repo / protected branches | New isolated branch from verified 100451 source; originals not changed |
| 02 | Duplicate / conflicting source | CI source-merge and reconciliation regression passed |
| 03 | UID / sessions | New owner-session sign-out block passed Flutter policy tests and assembled code |
| 04 | Restoration / Google | **NOT COMPLETE** — historical owner and data recovery not established; removed Google card not reintroduced |
| 05 | Profile | Source-only patch does not edit profile; full behavioral QA not run |
| 06 | Friends / weekly league | Source-only patch does not edit their files; full behavioral QA not run |
| 07 | Diamonds / frames / premium IDs / gifts | No balances or user data touched; full readback/restoration not verified |
| 08 | Daily tasks / quizzes | Not edited; behavioral QA not run |
| 09 | Administration | Logout owner-protection tests passed. **Admin simultaneous access still blocked on shared Auth** |
| 10 | UI placement / feature preservation | No UI file changed. Full feature device check not run |
| 11 | Startup / performance | No device test run |
| 12 | Firebase | No production writes/deploy; checks use `Source.server` |
| 13 | Package / signing | **NO NEW APK BUILT**; previous 100451 remains QA-only |
| 14 | Tests | CI run 44624706099 successful; physical-device test not run |
| 15 | Manager instructions | Directive 01 read and safety stop maintained |

## Hard stops before final approved upgrade
The source still intentionally refuses administrator sign-in when the owner's UID occupies shared `FirebaseAuth.instance`, because a separate full administrator Auth/Firestore lane has **not** been safely wired through every admin data access. The account recovery completion gate remains false; historical assets and conflicted A/B/C/D identities have not been restored or merged. The existing encrypted Firebase read-only backup does not include device-local data or Firebase Storage binaries. Do not install any new QA build over the sole original owner device without verified backup and end-to-end non-destructive device QA.

This is **not** a claim that the user's requested complete APK has been delivered. No manual phone test, full-data restoration, or final release evidence exists as of this record.

## 2026-11-20 — B canonical continuation (same task, no new identity path)
**Director instruction:** Resume the five-point original-account consolidation plan, with B as the historical registration target, preserve A original-ID and C social rights, complete the application only after proved safe. No more A/C/D reselection or alternative "room" solution.
**Prior evidence reused:** 2026-11-13 historical read-only run records, 2026-11-19 Firebase encrypted backup and preceding 100451 build. Historical registry `deda_account_directory.createdUid == deda_credentials.createdUid == B`, original personal-ID owner `A`, social-record owner `C`. This establishes lineage, **not** B sign-in or entitlement to transfer other users' sources.
**Changes:** Existing `functions/deda_100441_owner_split_identity_challenge_review_private_v1.js` received `assessBCanonicalConsolidation`: a strictly offline non-authorizing preflight for B registration, explicitly requires independent B-bound auth review, individually reviewed A/C historical rights with exact original-ID/social UID matching, complete Firebase Auth+Firestore, Storage, device-local archive, purchase ledger and rollback readback. Returns HOLD or separate-review candidate with `canMerge=false`, `canAuthenticate=false`, `canTransferAssets=false` and no Firebase writes. Existing public Auth flows are **unchanged**. Companion tests added to `functions/test/deda_100441_owner_split_identity_challenge_review_private_v1.test.js`; CI workflow `.github/workflows/deda-100452-owner-admin-session-repair-qa-no-deploy.yml` now runs them alongside full protected source checks.
**Evidence:** [GitHub Actions 44631324519](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/44631324519) — **SUCCESS** at source SHA `e159731aa1934f0e9762a7382329b4ff20e04875`: 21 Node tests PASS, 0 FAIL; guarded admin signout source checks pass; focused Flutter tests pass; exact full protected source assembly and Dart analysis pass. This is **NOT** an APK or physical-device test.
**Backup fact verified:** The 2026-11-19 archive manifest includes 2,066 Firestore documents and 632 Firebase Auth user metadata records; Firebase Storage included=false, Auth credential secrets included=false. The encrypted cloud snapshot is not a verified on-device archive of historical purchases, XP, diamond receipts, quizzes or settings.
**Directive 01 oversight 01-15:** (01) isolated version-controlled branch preserved; (02) existing 100441 reviewer reused, no duplicate deployed auth path; (03) B, A and C preserved, no UID mutation; (04) owner restoration and Google **not completed**; (05) profile source protected, no runtime verification; (06) friends/league source rights require separate evidence, no runtime verification; (07) no wallet, ID, frame, gift, or receipt transfer; (08) local tasks, quizzes not available in cloud backup; (09) protected admin code source tests pass but actual parallel admin login remains blocked; (10) no UI or feature position changed; (11) no phone startup/performance test; (12) no Firebase writes/rule deploy/billing; (13) **no new signed APK**; (14) Node 21/21 and focused Flutter+assembly CI successful, not a real-phone pass; (15) instruction 01 and terms read, unsafe claims withheld.
**Status:** PARTIAL SOURCE REPAIR. **Remaining safety gates:** independently authenticated B with provenance for A/C rights, complete asset/local/Storage readbacks, server-authorized permission migration or equivalent safe access on Spark, real original-phone + second-phone verification, confirmed admin entry without replacing DEDA Auth, complete signed Android package and no-loss functional check. Do not mark `completeOwnerDelivery=true` or install an interim candidate on the only original phone.
