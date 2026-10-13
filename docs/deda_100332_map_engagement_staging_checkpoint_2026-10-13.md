# DEDA 100332 — follow/like and map-focus staging checkpoint
Date: 2026-10-13
Branch: owner-place-map-polish-100332-stage-2026-10-13
Production 100330: unchanged. Successful owner-access reference 100331: unchanged.

## 1–5 previous staging, not compiled yet
Map rotation restriction in destination picker, smaller two-line name callout, half-outside circular activity badge, optional type suggestions while entering a place, and preservation of owner place drafts/requests/notifications.

## 6–11 new staging, not compiled yet
- Tap a registered place: retain legacy selectMapPlace() / selectedDestination / route preview, while focusing map camera on chosen place with MapController. No replacement of 'choose destination', 'show route', 'start navigation' or driving UI.
- For the selected published place only, place the three-item tiny overlay above the compact place-name callout. In RTL order: green person-with-plus, outline heart that turns **solid red** only after successful like, people icon with a real follower number. Follow state displays green person/check.
- Hide this bar on blank map tap, long-press destination selection, route launch, search, switching filters and shrinking/zooming out to map overview.
- Follow and like are distinct account-scoped actions and unlike/unfollow is possible. Server counts and status are read only from callable functions. No invented values or direct user writes to engagement Firestore collections.
- Server stage: get/set callable functions, DEDA session+user account identity matching, stable published_places document ID, idempotent transactional counts. Explicit Firestore rules deny direct follower-document reads and writes.
- **Feature disabled by default** until server code, security rules, and device integration are tested and deliberately deployed with user approval. Therefore no promise of immediate working interactions in current APK.
- Original owner page (Manage My Place) and its drafts/requests/notifications untouched. Future **owner dashboard for followers/likes/counts** intentionally deferred because user has additional ideas to discuss.

## New stage files
- lib/deda_place_engagement_bar.dart
- lib/deda_place_engagement_service.dart
- functions/deda_place_engagement.js
- functions/tests/deda_place_engagement.test.js
- test/deda_place_engagement_bar_test.dart
- tools/stage_place_engagement_core_100332_2026_10_13.py
- tools/stage_place_engagement_map_100332_2026_10_13.py

## Source apply sequence ONLY after receiving user authorisation to build
1. Recreate accepted golden source and apply the 100331 profile-card restore patch.
2. Run tools/stage_owner_place_map_ux_100332_2026_10_13.py.
3. Run tools/stage_place_engagement_core_100332_2026_10_13.py, then tools/stage_place_engagement_map_100332_2026_10_13.py.
4. Format, run analyzer and previously prepared static tests and Flutter tests. Run Node unit tests for server and Emulator rules tests. Fix compilation/regression issues before any APK.
5. Review production Firestore rules against live rules (source snapshot may be stale!), callable security, user session binding, privacy, rates and counts under concurrency. No automatic functions or rules deployment.
6. Wait for owner's additional requested features inside the 'إدارة مكاني' page; incorporate decisions before authorizing ONE new signed private APK.
7. Test old routes, voice and navigation, screenshots, owner data preservation. No public Play launch without user sign-off.

State: GitHub files saved only. No scripts run, no Flutter analyze, no Node/Flutter tests executed, no APK or production deploy.
