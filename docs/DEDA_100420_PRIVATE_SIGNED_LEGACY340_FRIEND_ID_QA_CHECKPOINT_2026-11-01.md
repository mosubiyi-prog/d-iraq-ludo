# DEDA 100420 — Legacy Play 100340 Friend IDs — private signed QA delivery checkpoint

Date: 2026-11-01. **No Google Play upload and no additional Firebase mutations.**

## Proven live backend
- Live project: `deda-25b88`, exact production active-id READ rule verified in build job.
- Expected deployed ruleset: `projects/deda-25b88/rulesets/9f11d792-0d1e-4a28-bd72-606459b5c659`
- Expected SHA256: `273d20ffa0196709af7742dbf8f3fb4137edc2f3c7bb56f5e80d2c3506c62cb1`.
- 100419 activation: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41243025369
- Security emulator approved exact single-read candidate: six tests passed, no failed. Owner-only writes / private ID registry unchanged.

## Real signed private QA APK
- Successful signed APK GitHub Actions: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41243501948
- Artifact: `DEDA-100420-PRIVATE-PHONE-TABLET-QA-APK`, id `13058576639`; ZIP 49,200,590 bytes.
- Inside: `DEDA-100420-PRIVATE-PHONE-TABLET-QA.apk`.
- APK size 88,416,042 bytes.
- APK SHA256: `1b14060b6642997e6eb58e179f1f69f84bf093c4f1442a5441f144a96d475a8f`.
- Original signing certificate SHA256 retained: `a53d855b82d1280f324037428421838139ecf2e30174f9fcd0bd1878698b5f4a`.
- Same package `com.diraq.ludo.d_iraq_ludo`; versionCode 100420; verification.py succeeded.
- Feature enabled in **actual signed APK** by `--dart-define=DEDA_100418_LEGACY340_ACTIVE_READ_APPROVED=true`. Explicit flag-on Dart test passed 5 cases and earlier normal off tests passed 4; all previous 100414 admin/prizes and copy tests passed.
- Distinguishes verified old normal (absent Stage71 but valid server personal route) vs premium selected Stage71. Never infer normal from missing optional public alias. Per-ID listener shared with ref counts, server-only data, fails closed.
- Assembled from verified original source; `100417` ordered legacy owner proof incorporated.

## Outstanding real-device validation — DO NOT OVERCLAIM
- GitHub CI does NOT test actual user session, device network speed, actual three friends' existing Firestore documents, or Android phone/tablet startup. `appLaunched: false` in verifier.
- User must update in place without clearing app data, open Friends, identify all three friends' normal/premium IDs, tap exact copy, open friend public profile, Requests and League, and ensure admin login and prize editor remain working.
- Friend Requests slowness has **not** been independently solved/benchmarked by this ID-only correction. Log if slow, do not automatically change Firestore or backfill other accounts.
- No current user data or diamonds modified; no Firestore deploy in 100420; no Play upload.

## QA first
- Stop and diagnose on failure; do not declare friend-ID problem solved until phone screenshots/video demonstrate it.
- Do not add unrelated Smart Guardian or other feature.
