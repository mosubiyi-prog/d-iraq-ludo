# DEDA 100332 — Five owner-place improvements staged, no APK build

Date: 2026-10-13
Stage branch: owner-place-map-polish-100332-stage-2026-10-13
Stable Production: 100330, unchanged.
Owner access reference: 100331, unchanged.
Status: source staged, static anchor review completed; NOT built, NOT analyzed, NOT phone-tested and NOT published.

## Decisions staged

1. Destination map north-up: disable gesture rotation only in MapReadyPage, retain pan, pinch zoom, long-press, and all navigation features.
2. Smaller place-name label: compact registered-place label with two-line wrapping and a dynamic label height. Exceptionally long names exceeding two lines still ellipsize to protect map layout; full name remains available in place details.
3. Activity badge: a small circular icon overlaps the left edge of the callout half-inside/half-outside, while the DEDA pin remains. Include car wash, payment outlet, pharmacy, shop, hotel and other categories. Registered markers remain upright in maps that rotate.
4. Inline category hints: local-only, optional suggestion chips beneath the owner place-name field; owner must tap to select. An ambiguous service outlet offers both payment and general service types. Unrecognized categories use the preexisting other + otherCategoryText schema; no new backend data model, no brand-logo guessing, no network requests.
5. Existing workflows preserved: account toggle, drafts, place ID, resubmissions, approval, notifications, owner deletion requests and navigation.

## Files staged

- lib/deda_place_suggestions.dart: classification hints and icon lookup.
- tools/stage_owner_place_map_ux_100332_2026_10_13.py: fail-closed UI-only source patch; does not run by itself.
- tools/validate_owner_place_map_ux_100332_2026_10_13.py: static regression checks after applying patch.
- test/deda_place_suggestions_test.dart: Flutter unit tests, prepared but not executed.

## Strict stop

DO NOT create or run a new APK/AAB build, new Actions release workflow, Firebase deploy or Play publish yet. Wait for the user's additional points before integrating them into the next single private QA build.

## Later, only with user approval

1. Reconstruct the last successful 100331 source, including the owner profile entry restore step.
2. Apply the stage_owner_place_map_ux_100332 patch AFTER the 100331 restore; run dart format and the dedicated 100332 validator.
3. Run Flutter analyze, the prepared Flutter unit tests, and previous 100331/100330 regression suites. Compilation success has NOT yet been verified and might require follow-up fixes.
4. Manual device QA: user/owner switching, both owner entry paths, draft persistence, submissions, name suggestions, two-line labels, half-overlapping badge, north-up destination map, pinch zoom, long press, and navigation unaffected.
5. Only then build one private test APK after explicit confirmation. Production 100330 untouched.

References: GitHub Issues #7 and #8; owner card 100331 accepted by user screenshots on 2026-10-13.
