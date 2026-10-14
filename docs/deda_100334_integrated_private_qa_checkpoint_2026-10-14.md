# DEDA 100334 — integrated private QA checkpoint (2026-10-14)

Repository: mosubiyi-prog/d-iraq-ludo
Development branch: deda-heartbeat-integrated-stage-2026-10-14
Untouched backup: backup-heartbeat-integrated-qa-pass-2026-10-14 at 3f585be711c469b09f6f281f9684e0cb6350cf91
APK source commit: fcddcfe59fc6fd3a32f0cc10952b1b01d51ed17b
Successful workflow: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38553539798
Artifact: 11889765363 — DEDA-100334-HEARTBEAT-COMPACT-ADMIN-PRIVATE-TEST-APK-DO-NOT-PUBLISH

## Verified deliverable

- Actual APK manifest: com.diraq.ludo.d_iraq_ludo, versionName 1.0.0, versionCode 100334.
- APK bytes: 71,527,143.
- APK SHA-256: 6cea87f5ff4ddb7514c70c99b706b06a4cec8faff07101846ca46a93fd5aa4e5.
- Release signature verified with apksigner (v2, one signer).
- Certificate SHA-256: a53d855b82d1280f324037428421838139ecf2e30174f9fcd0bd1878698b5f4a.
- Downloaded ZIP digest matched GitHub's artifact digest; extracted APK digest and source-commit metadata matched the successful run.
- No Firebase production deployment, Google Play publication, live data backfill or customer-data mutation was performed.

## Seven agreed points — code versus actual activation

| Point | Verified implementation and remaining limitation |
| --- | --- |
| 1. Approval bell | Server-authored, deterministic create-only notice on first approval transition is staged and unit tested. Existing owner inbox/read markers retained. Server release still requires owner approval. Old approvals were not backfilled; a separately reviewed migration would be needed. |
| 2. Duplicate approval ID/date | UI strips only generated redundant number/date lines; dedicated certificate fields and original stored administrative messages remain intact. Included in APK reconstruction. |
| 3. Likes, following, real counts | Verified-account, account-stable, idempotent server transactions; client totals/reaction access denied. Concurrent emulator tests pass. APK live engagement flag remains false; this is not a live activation claim. |
| 4. Fourteen colours | Seven vivid/pastel pairs, coloured fields and published map branding paths included. Local owner-scoped preview persists. Server owner-only public colour transaction accepts 0..13, denies another owner, invalid indices and hidden places. Public publishing flag remains false. |
| 5. Phone image selection | Owner UI has no gallery-selection control and renders the shared activity identity. Uploads remain disabled; existing published assets are preserved. Unused legacy helper remains unreachable from the owner UI. |
| 6. Compact auto approval | Compact single-row control above administrative requests, preserving existing authority and separate PIN recovery panel. Widget test verifies height under 100 px. |
| 7. Shared activity symbols | Integrated staging script applied to owner identity/name field and registered map marker variants. OSM navigation and other map logic retained. |

## Current-request changes

1. Private APK workflow now runs on the integrated development branch, applies integrated activity symbols, and waits for Firestore Emulator success.
2. Added a real emulator colour transaction test covering all 14 indices and impersonation/hidden-place denial.
3. Manifest verification checks the actual Android package against google-services.json, then checks versionCode 100334.
4. Artifact includes APK, manifest, signing certificate, source SHA and checksum.

The first new run 38551768904 built and signed the APK and passed Flutter/emulator tests, but delivery verification failed because the initial checker incorrectly used a shortened package name. No APK from that failed run was delivered. The checker was corrected against the repository's Firebase Android registration, and the final successful run rebuilt and rechecked the app. This checkpoint identifies only the final verified file.

## Validation

- Node business tests: 16 passed, zero failures (engagement, approval bell, branding).
- Firebase Emulator on final workflow: 6 passed, zero failures; synthetic demo project only. Covers own inbox/read marker, spoofed notice denial, forged counters denial, direct colour write denial, concurrent follow/like transactions and all 14 owner colour transactions.
- Flutter selected regression groups: 20 + 18 + repeated 20 tests passed in the successful build. The final 20 repeat the first regression group; do not count these as 58 unique tests.
- Flutter analyzer exited successfully with existing warnings/information permitted by the established workflow. This is not an analyzer-clean claim.
- Source guards cover drafts/submission/edit/resubmission, account scope, accepted navigation reconstruction, 16 ms camera follow, arrow, touch return, flag and existing feature locks.
- APK integrity, actual manifest, signature and local download provenance checked.

## Exact next step

Owner device QA of this private APK. Backend-dependent approval notices, likes/follows and public colour saving require a separately authorized Firebase release and client feature activation after reviewing the deployed baseline. Do not silently enable these features or publish Google Play. Historical approval backfill, physical driving tests and hardware/account-switching end-to-end tests were not performed in this session.

Keep main, Production 100330 and the supplied backup unchanged. Never describe this private UI APK as all seven live features already enabled.
