# DEDA Stage17 — 100358 Private signed Android16 verified checkpoint — 2026-10-19

## Source and rollback
- Verified CI source SHA: `fecbd0a4e689f589a104904fe90582ba395a8c62`.
- Work branch: `deda-100358-stage17-signed-private-android16-2026-10-19`.
- Exact rollback branch (same verified SHA): `backup-deda-100358-android16-private-qa-green-2026-10-19`.
- Prior 100357 signed QA artifact retained; 100356 phone-verified and 100352 references preserved.
- No real Firebase/Play deployment, no changes to production user accounts, diamonds or login credentials.

## Passed exact CI tests
- GitHub run: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39236929321 : completed, conclusion success, 3/3 jobs success.
- Spark Firebase security emulator: success.
- Private signed APK creation: success. Source reassembly includes point17, 23/23 Flutter tests, Kotlin runtime DEX guard and art SHA checks.
- Android16 API 36 strict clean install launch: pass. Android16 in-place install -r of 100358 over reference 100352: pass. Both show alive DEDA PID, foreground app, no unhandled Flutter/platform exception in PID logs.
- KVM permission check successful BEFORE emulator setup/launch, no APK rebuild for smoke.

## Exact artifact and signature
- Private signed APK Artifact ID `12179509840` (not Android log artifact). Artifact name: `DEDA-100358-ALL-POINTS-PRIVATE-SIGNED-OWNER-REVIEW-NO-PLAY`.
- APK inside: `DEDA-100358-ALL-POINTS-OWNER-PRIVATE-SIGNED.apk`.
- Exact APK SHA256: `02a4147f81c4fbe1fc9f7a8580a9b128af021e2707393c2b740a4a3d80d5ad6d`.
- APK signing certificate SHA256: `a53d855b82d1280f324037428421838139ecf2e30174f9fcd0bd1878698b5f4a` — matched signed 100342.
- Package `com.diraq.ludo.d_iraq_ludo`, versionCode 100358, versionName 1.0.0.
- Android16 logs (NO APK) Artifact ID `12180477192`, name `DEDA-100358-STRICT-ANDROID16-LOGS-NO-APK`.
- APK built ONLY for private owner review, not published to Google Play.

## Owner-approved stage17 behavior
- Compact blue My IDs card remains in editing. Verified owned identifiers appear below it.
- Four premium cosmetic ID card previews/actions are inside store, not in editing. Price 5,000 diamonds per card.
- 100 Group 002 candidate identifiers display price 10,000 diamonds as a preview, NOT actual sellable inventory.
- Private first 100 identifiers remain admin-reserved and never packaged/publicly listed.
- Premium checkout and alias switches are disabled with `DEDA_PREMIUM_IDS_SERVER_LIVE=false` and `DEDA_PREMIUM_ALIAS_ROUTING_LIVE=false`.
- Do not enable production payments before wallet reconciliation, real authenticated callable AppCheck, sale inventory, globally unique registry and ID-based friend/share/search migration and owner review.

## Phone test caution
- Emulator passes do not replace real phone acceptance. Do not uninstall existing DEDA or clear data.
- Use the APK from artifact 12179509840 (not the log-only artifact); first verify filename and package, update in-place. On Android install error, stop and report screenshot; never erase app data to force install.
- Confirm reopen, profile, original IDs, owned IDs, royalty avatar/frame/background, diamond balance, admin control, map and friends before any publication.