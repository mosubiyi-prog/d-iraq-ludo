# DEDA 100406 — Owner Phone QA findings, 31 October 2026

Original owner screenshot: 1000101809.jpg in conversation. **DEDA 100405 worked for real league scoring:** visible user "سالم حسن" scored 20 weekly XP and took rank 1 on original fixed leaderboard. Do NOT regress the Firestore score key, prize values, location sharing, real XP, wallet or approved 100405.

## Four exact owner concerns
1. Minutes/seconds overflow below header clock; owner does NOT want them at all. Keep **days + hours only** inside the existing clock card.
2. Avatar is the anonymous person icon rather than the user's selected image.
3. Purchased/equipped frame is not shown over that avatar.
4. Leaderboard displays the ORIGINAL personal ID, not the ACTIVE PREMIUM ID. User expects the currently selected premium ID to be the only displayed and searched ID in all user-facing sections as soon as use is confirmed. Hidden stable original account key must be preserved for existing gifts, account recovery, shares, friends, Firestore document ownership, and XP; NEVER delete original server records as a shortcut.

## Verified backend evidence — no account or wallet mutation
- GitHub Actions 41170344134 read-only inspected the **exact screenshot** original identifier `@DEDA-AQPYXJ`: active Stage71 premium identifier exists, verified Spark public alias projection exists and **matches** the active Stage71 identifier.
- Weekly score document keyed by original ID exists with real 20 XP. Alias changes must not rename that score document.
- `deda_social_profiles/@DEDA-AQPYXJ` already has server-saved avatarStyle and frameStyle values, both nondefault. Its ownerUid does NOT match the currently mapped `deda_share_ids` owner UID, and users/deda_sessions accountKey were not equal under that old route; this may reflect restored accounts and is **not proof the server presentation is fully migrated**. Do not silently transfer ownership or erase identity history.
- Main direct league reader in 100405 didn't fetch either public alias or appearance and omitted `publicAppearance`. Its guarded safe screen did NOT forward the existing `drawOriginalEquippedAvatar` callback. These are the concrete UI reasons the photo/frame were not presented in the league despite existing data.
- Earlier 41170237902 audit of `@DEDA-D62UEB` concerned a separate historical original ID, **not** the screenshot league score key; do not conflate them, reset either account, or imply the other account has the visible score.

## Separate 100406 source changes, NOT accepted 100405
- `lib/deda_weekly_firestore_direct_bridge_100406.dart` reads verified alias and avatar/frame from publicly approved server records; does not rekey scores or issue XP.
- `lib/deda_weekly_leaderboard_safe_screen_100406.dart` forwards the real original app avatar painter.
- `tools/app_stability/app_package/bind_weekly_100406_league_display_fixes.py` injects that painter into BOTH existing official DEDA league routes and removes the overflowing minute/second text; verifies exact 100405 SHA metadata before altering only disposable workspace.
- `test/deda_weekly_100406_days_hours_only_test.dart` tests compact clock in phone/tablet viewports.
- Signed private QA build on `deda-100406-league-active-id-avatar-frame-clock-no-play-2026-10-31` only; 100405 stays untouched, no Play.

## NOT YET PROVEN
- Real-device account recovery/global UI uses must be audited by a single stable ACTIVE DISPLAY ID API; original server route remains internal, never shown while a verified premium active ID exists.
- A clean Flutter compile and owner phone/tablet proof must succeed before calling 100406 complete.
- Public profile ownerUid mismatch needs account-safe reconciliation without changing awards, purchased IDs, original route owner, or social graph.
- Server-independent task proof + real diamond settlement remain separate unresolved 100405 award gates. 100406 does not automatically enable payouts.
