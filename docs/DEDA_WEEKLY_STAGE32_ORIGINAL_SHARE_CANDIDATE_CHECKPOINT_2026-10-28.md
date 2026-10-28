# DEDA Stage32 — original location-share candidate, real Firestore emulator only

**Date:** 2026-10-28  
**Branch:** `deda-weekly-stage32-original-share-candidate-emulator-no-deploy-2026-10-28`  
**CI:** https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40625917028  
**Result:** SUCCESS, all three jobs complete; original source unchanged. Previous run 40625871988 failed a CI static marker because `PROJECT` was correctly imported rather than spelled inline; corrected and independently rerun successfully.  
**NO FIREBASE DEPLOY / NO LIVE XP / NO APK / NO AAB / NO PLAY**

## Actual implemented progress
- Read the shape authored by original `DedaBackend.createLocationShare` in `lib/deda_backend.dart` and current repo `firestore.rules`: the app creates `deda_location_shares/{id}` with Firebase server timestamps, sender UID, original personal `@DEDA-XXXXXX`, original recipient ID and location metadata.
- `functions/deda_weekly_stage32_original_share_candidate_NOT_EXPORTED.js` securely composes stage30 original-share inspection and stage31 06:00 anchored seven-day calendar. It rejects an absent/forged/outdated/changed share, invalid UID/session/original alias/ownership, and everything created in the 00:00–06:00 freeze interval.
- Server-only ADMIN SDK simulator atomically creates **one** protected `deda_weekly_stage32_share_candidates_fixture_only` record per `(canonical original account, Baghdad day, personal-share task)`, even with a repeated source event or concurrent retries. Two-device account migration remains a separate production gate.
- All records explicitly state `candidateOnly:true`, `originalLevelXpApplied:false`, `weeklyXpGranted:false` and `payoutEnabled:false`. No stage9 XP receipts or proof, no real wallet changes and no giveaway. No Cloud Function exported from `functions/index.js`.
- Existing shadow emulator rules deny all ordinary client reads/writes. Tests exercised original-shaped source docs and forged sender/public premium alias/UID, wrong time/coordinates/status, source replay, ownership/session spoof, midnight freeze, week transition, attempted client Firestore writes, no original level/wallet change.

## Remaining blocker before real league
This private candidate is **not** a trusted production original-task XP grant. The actual application has a phone-local `DedaTaskEngine` and independent `+20 LEVEL XP` persistence; the server cannot claim that a location-share document alone proves that award occurred. A live production task authority must establish a canonical account across device changes, audit actual deployed share Rules, verify original successful task claim without client-faked evidence, reconcile historical level XP safely and atomically issue an exactly-once original XP receipt. Until then rank/payout must remain disabled.

## Owner commitment
Finish actual task-to-ranking and server rewards; then verified top ten, monthly admin history, 00:00 final freeze, 06:00 pending My Gifts and **exact owner-approved congratulation card with NO name, ID or avatar**; then signed complete private APK tested on phone/tablet; only after the owner's review an AAB. Add only subtle optional animation while preserving approved card content.
