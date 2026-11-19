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
