# DEDA 100436 — Owner-accepted stable phone UI reference

**Recorded:** 2026-11-02 (Iraq). **Owner instruction:** "سجل نجاح هاي لنسخة وخليها مرجع".
**Decision:** DEDA **100436** is the owner-accepted **baseline for subsequent work**. This replaces the failed 100435 as the reference for the current DEDA UI and league. This does **not** mean full account recovery has been delivered.

## Preserve the exact executable source — do not overwrite it

- Original build/source branch (must remain untouched): `deda-100436-exact-100420-private-signed-qa-no-play-2026-11-02`.
- **Pinned source HEAD SHA:** `fea54d7db2e8a24a74267f04a14c9572bcb408ee`.
- The 100436 source was derived from 100420 SHA `cc4414f473522e3b3dca854d6eee926f2e74e58d`, with only the new isolated 100436 build workflow added to the source branch. The 100436 CI source-diff guard passed.
- The current **documentation checkpoint lives on a SEPARATE branch** `deda-100436-owner-confirmed-success-reference-2026-11-02`, branched from the pinned source HEAD. Use the **pinned source SHA**, not this document branch HEAD, when constructing future releases.
- Signed build CI: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41498505941 — `completed/success`, including source comparison, APK build, signing/package verification and artifact upload.
- Artifact name: `DEDA-100436-EXACT-100420-PHONE-TABLET-QA-APK`. Artifact ID: `13169090494`.
- APK inside artifact: `DEDA-100436-EXACT-100420-PHONE-TABLET-QA.apk`.
- Package: `com.diraq.ludo.d_iraq_ludo`; versionCode `100436`; APK bytes `88416042`.
- APK SHA256 (verified against ZIP SHA256.txt and extracted APK):
  `e75deaaf9f91b45b9357dff7f4890d77421411a58a47464823a99f6f7bfc30b9`.
- Official original certificate SHA256 (verification.json):
  `a53d855b82d1280f324037428421838139ecf2e30174f9fcd0bd1878698b5f4a`.
- Build verification `appLaunched=false` indicates CI did NOT itself launch the Android application; this is separate from the owner's on-device video.

## Owner's phone evidence, 2026-11-02

The owner uploaded `1000102362.mp4` (78.12-second phone screen recording) and explicitly stated the version succeeded and requested it be recorded as the reference.

- Video SHA256 for identification (video bytes **not** copied into this public repository):
  `04cb97c530bbbb770cabcb04b64228ac0c28947b932fa371580f610853a71ad5`.
- Visible in the phone recording: restored DEDA home design with **المتصدرون** card instead of the regressed **مطاعم** entry; user's profile screen with avatar/frame/active displayed ID; friends and add-friend screen; badges/frames; leaderboard ranking screen with weekly top positions; daily tasks; gifts inbox; settings/management entry; return to home.
- This is **owner acceptance of the observed UI and ordinary navigation**. It does not independently prove every backend operation, prize distribution, across-device recovery, nor security of all account flows.

## Critical constraints for future development

1. **Use this pinned 100436 baseline** for all subsequent DEDA builds unless the owner explicitly selects a different newer approved baseline. Never use 100435 or its source tree as a replacement for the current app UI.
2. Keep league, task buttons, original profile layout/frame, friends, admin entry, gifts and related UX at least as complete as this accepted version. **Do not overwrite `lib/main.dart` or assets** with their 100434/100435 counterparts.
3. The prior two days' recovery source remains preserved separately in `deda-100434-step2-verified-original-profile-private-qa-no-deploy-2026-11-01`. Recovery components may be selectively adapted to the baseline **only with explicit diff review, integration checks and owner authorization**.
4. Require automated regression/source checks and evidence of successful signed APK packaging **before** owner device QA; never declare recovery complete on successful code tests alone.
5. For the recovery feature: no claim of full account restoration until a real same-phone-number-plus-PIN original-account flow returns the full verified account on a second phone, with no lost or duplicated points, diamonds, frames, prizes, gifts, premium IDs, settings or league progress; security/UID ownership must be authenticated.
6. **No Google Play upload; no silent Firebase production publish, no live user data mutations**, absent the owner's separate instruction/authorization and security verification.
7. Do not uninstall or erase original handset app data to test a feature not yet verified on both devices. Keep safe rollback path and this source artifact reference.

**Reference result:** 100436 owner-accepted visual/device navigation and signed build — **APP BASELINE ACCEPTED**.
**Open scope:** complete cross-device phone/PIN account recovery — **NOT DELIVERED**.
