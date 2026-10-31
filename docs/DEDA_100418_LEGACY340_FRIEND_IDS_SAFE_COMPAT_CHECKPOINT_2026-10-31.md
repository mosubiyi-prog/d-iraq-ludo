# DEDA 100418 — Owner-safe old Play 100340 friend ID compatibility checkpoint
**Date:** 2026-10-31
**Branch:** `deda-100418-legacy340-public-active-read-candidate-no-deploy-2026-10-31`

## Definitive regression
Prior friend badges displayed canonical IDs from `deda_social_profiles/deda_friendships` even when `deda_public_active_aliases` didn't exist. At 100410 the unifier replaced the visible fallback with `جارِ تأكيد الآيدي...` whenever the NEW public projection was missing. Old Play 100340 clients don't publish that new projection, so their old normal IDs disappeared in 100414 despite verified names, levels and avatars arriving. **This is a 100410 compatibility regression, not proof of poor user network.**

Showing old original directly is dangerous for members who activated premium aliases; missing public projection cannot prove premium is absent.

## Authenticated live rule audit
Published production Firestore Stage71 rule currently allows `get` ONLY by `stage71SelfRecipient(originalId)`. A signed-in friend's device therefore cannot verify another user's selected premium/normal ID. This is a strict server permission barrier, not fixable safely by displaying unverified old IDs in Dart alone.

## Completed isolated candidate
1. Source `lib/deda_legacy340_active_selection_100418.dart` reads only public `deda_share_ids` route + authoritative Stage71 ACTIVE selection, authenticated and scoped to viewer UID; rejects cached/pending writes and malformed selection. Missing server Stage71 row means normal ONLY if server public route verified. Never uses wallet/private registry or changes account keys.
2. `tools/app_stability/app_package/bind_weekly_100418_legacy340_friend_active_compat.py` binds selected ID to friend badges, leaderboard and copy via existing unified display, prevents original fallback for premium, and displays premium as plain text when authoritative color not publicly available (never invents foil).
3. Old requests are reference counted/cancelled; auth rotation and server timeout fail closed; no infinite "pending" on known permission denial.
4. Feature flag `DEDA_100418_LEGACY340_ACTIVE_READ_APPROVED` defaults **FALSE**. No signed build will use this route without explicit reviewed rules activation.
5. Source retains 100417 ordered owner backfill plus accepted admin and 10-slot prize fixes from 100414.

## Current live-Firebase rules candidate — NOT deployed
`tools/deda_100418_legacy340_public_active_read_candidate_no_deploy.py` reads exact CURRENT production rules and creates a local emulator-only candidate which adds a narrowly limited authenticated `get` of `deda_stage71_active_identifier/{originalId}` ONLY when a valid original ID has an active public personal share route and the selection document has ONLY `originalId`, `activeId`, `updatedAt`. It does not allow list, anonymous reads, changes to existing create/update rules, private grant registry, UID, scores, diamonds, gifts or admin.

Any actual production permission change is privacy/security-sensitive and needs owner approval after reviewing this exact rule diff; do not deploy automatically. No users' data was read or changed in this work.

## CI results
- [100418 real production rules isolated emulator](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41241439655): PASS **6/6**. Old 340 with premium but NO new projection returns ACTIVE premium; old normal with missing Stage71 returns verified normal; anonymous/invalid route/list/foreign write denied; self-owner write unaffected; malformed private source denied.
- [100418 integrated source QA](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41242126931): PASS with Flutter analyze no fatal errors, 100418 tests **4/4**, 100410 tests **4/4**, friend copy tests **4/4**, and all previously-required 100413/100414 tests. Nonfatal Dart lint warnings remain.

## Honest completion gates
- **NOT YET live**: Actual Firebase rules unchanged. 100418 compatibility flag OFF. No APK 100418 has been built or phone-tested.
- Next required decision: explicit authorization of *only the narrow active-selection authenticated GET* after reviewing rule diff; then sign a 100418 PRIVATE APK with flag enabled and phone/tablet test normal friends still on Play 100340, premium ID, copy, friend/requests loading latency; never publish Play without owner's separate instruction.
- Backend schema has no publicly available selected-color for an old premium owner; UI displays verified alias text without made-up color until owner published a verified premium projection. Do NOT claim identical premium foil in all conditions.
- Even after identity route proven, weak network/social page loading latency is a separate performance item; do not claim it fixed until measured with phone video.
- No Smart Guardian features added.
