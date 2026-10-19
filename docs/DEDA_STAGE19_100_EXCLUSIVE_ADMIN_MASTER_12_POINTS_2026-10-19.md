# DEDA — المرحلة 19: إدارة الـ100 معرّف الحصرية
**19 October 2026 · Owner-approved master checklist · PRIVATE QA ONLY**

## Immutable source and safety
- Phone/emulator-proven signed 100358: CI run 39236929321 (3/3 jobs success; 23/23 Flutter tests; Android16 clean startup and in-place update pass). APK SHA256 02a4147f81c4fbe1fc9f7a8580a9b128af021e2707393c2b740a4a3d80d5ad6d.
- Stage18 isolated 10,000 diamond checkout tested 12/12 at run 39241689780, NOT DEPLOYED. Keep that code untouched in a sibling scope.
- Base commit of this stage: 810c2fe096ddd2521cbc6f1935e4f0c7c5eedc85.
- Safety backup before stage19: backup-deda-before-stage19-private-admin100-2026-10-19.
- Working branch: deda-stage19-admin100-private-ui-no-deploy-2026-10-19.
- The actual exclusive 100 are in OWNER PRIVATE ChatGPT Library folder /DEDA/LAB_Backups: DEDA_100_IDENTIFIERS_BACKUP.json, DEDA_100_IDENTIFIERS_NUMBERED.txt, and archive DEDA_LAB_COMPLETE_100_ARCHIVE_V2.zip. JSON has 100 unique names; first SALEM and last 2020, original saved designs gold. NEVER COMMIT this catalog, full names, or owner auth details to public repository, Android app or emitted logs. Any future backend needs owner-approved private server-only secret/manifest; UI does not get raw private list except via manager-authenticated, AppCheck-enforced, paginated API.
- No Firebase/Google Play deployment or real account/diamonds/ID mutations until tests and owner's explicit approval.

## Owner-approved 12-point sequential plan (NEVER skip)
1. **Point of return**: new protected starting branch/backup; review stable source and preserve all previous work.
2. **Admin dashboard tile**: add "إدارة المعرّفات الحصرية" visible ONLY to authenticated general_manager; EXACT same grid tile dimensions as other admin dashboard tiles (3 columns on a phone).
3. **Distinctive colors/background**: tile navy + glowing turquoise, unlike the 4 user card colors; the admin ID-management PAGE background is pale blue-gray with soft turquoise relationship, while other admin pages retain their original colors.
4. **Load the original 100**: server-only 100/100 catalog from owner-private backup IN ORIGINAL ORDER and without public packaging; show real verified ownership and available counts; if backend missing, fail closed and show no fake list.
5. **Internal ID cards**: ONE preview card per exclusive ID, same ~50px height and proportional width as the four preview cards in user ID store; NO 4 duplicated copies per ID.
6. **Per-ID color selector**: 4 choices gold, diamond, royal, pink. Free preview/change ONLY before committing the reserved ID. Color exists as a proposed draft until server confirms use/grant.
7. **Self-use / gift to recipient**: two explicit manager-only actions; gift chosen by recipient's registered original DEDA ID and verified on server; require confirmation; no client-side accountKey, price or role trust.
8. **Permanent color lock**: at successful confirmed self-use or gift, permanently record the selected color with this ID on server. Never permit color changes, duplicate grants, reassignment, or client spoofing afterward; atomic transaction.
9. **Grant log top LEFT 📜**: dated, server-confirmed chronological audit of gifted IDs, recipient ID, fixed color, granted/confirmed status, plus separate self-use history; never fabricated from phone preferences.
10. **Display in recipient's profile**: server-verified owned list; permanent exclusive color and original ID preserved; client must not override its exclusive color with purchased cosmetic cards; global alias/friend/share routing safety enforced before launch.
11. **Tests**: Firestore Emulator with admin/non-admin roles, conflicting concurrent grants, irrevocable color, idempotency, rotated authentication, privacy, navigation/profile/diamonds regression; Flutter widget and responsive width tests.
12. **Private APK**: only after stage19 UI+backend tests pass, signed same-certificate private Android 16 cold-start/in-place update QA, then owner tests on own phone. No Play publication without owner's approval.

## Distinct product policies to preserve
- The first 100 owner-admin IDs are NOT purchasable. Once used or gifted, lifetime-fixed color on that ID.
- Group002 ID sale preview price 10,000 diamonds is separate from the first 100; standard user IDs can use any purchased 5,000-diamond cosmetic style. Normal styles NEVER change the special exclusive fixed color.
- Only general_manager role may see/access management tile; server must independently enforce current session, manager role, AppCheck, record ownership and audit.
- No loss of original ID, users, phone login, points, levels, diamonds, gifts, saved places, routes, maps, friends, or existing account state.

## Execution checkpoints
- [x] #1 Verified safe base, created standalone private work branch and recovery branch.
- [x] #2 Admin-only dashboard tile and route.
- [x] #3 Colors and page background.
- [ ] #4 Manager-authenticated server catalogue read (private source stays private).
- [ ] #5 Single-card 50px preview list.
- [ ] #6 Color selection before commitment.
- [ ] #7 Self-use/gift server route.
- [ ] #8 Permanent server color lock.
- [ ] #9 Top-left dated grant log.
- [ ] #10 Profile rendering with verified lifetime color.
- [ ] #11 Flutter and Firebase Emulator tests.
- [ ] #12 Private signed APK, Android 16 and owner phone testing.

Important: Each checked item means actually implemented and verified; adding a UI preview never means backend grant or real purchase are enabled.


## VERIFIED checkpoint after first stage19 batch — 2026-10-19
- UI branch GitHub Actions run 39246736431: success, 6/6 Flutter widget tests pass. Owner-approved manager-only tile is added to lib/admin_pages.dart, exactly the same DedaAdminCompactCard footprint as existing cards, using opt-in exclusiveNavyTurquoise palette; no existing cards styled differently.
- Admin page lib/deda_exclusive_ids_admin_page.dart: soft blue-gray background; navy/turquoise header; 📜 dated-grants history action physically TOP-LEFT; one 50px single preview card per server-verified exclusive ID; four draft color chips; proposed self-use and gift actions are DISABLED until audited production Callables. No sensitive IDs embedded in code or APK.
- Separate staged reader tools/deda_stage19_private_exclusive_catalog_reader_2026_10_19.js checks authenticated general-manager session, entire 100 owner-private list, unique original order, ownership and fixed color, and dated receipt. Requires private manifest injection SERVER-ONLY, no Firebase production exports.
- Combined security/source QA run 39247331980: **SUCCESS**. 7/7 isolated server-reader unit tests and 6/6 Flutter widget tests passed (13 tests across independent suites). No live reads/debits/writes, APK/AAB, Firebase/Play deployment.
- User-authorized #2 and #3 UI finished and tested. #4 remains IN PROGRESS: private catalog is NOT injected or deployed yet; the actual 100 records do not appear in phone UI until authenticated server API is complete. #5/#6/#9 have interface shells only, not usable verified live data/actions.
- Important: manager gifts and self-use with immutable one-time color, secure server audits, app-wide profile/alias integrity, Firebase Emulator race tests, and owner-only signed phone APK remain pending as points #7–12. Do not mark them done prematurely.


## Latest checkpoint: Staged permanent-color actions — 2026-10-19
- New private source-only module: tools/deda_stage19_private_fixed_color_manager_actions_2026_10_19.js.
- It reuses the verified point15 atomic admin gift transaction with immutable assignedColor. Its separate admin self-use transaction verifies current manager credentials, original account and registered ID, exclusive owner-only private catalog membership, all global ID collisions and previous ownership ledger; then writes registry/alias, owned-list active ID and dated self-use receipt as ONE transaction. This is STAGED only, NOT deployed or wired to 100358.
- New isolated tests test/deda_stage19_exclusive_fixed_color_actions.test.js: reject unauthorized users, reserved list omissions, wrong palette choices, repeat gifts/recolors, and preserve original ID after successful self-use.
- GitHub Actions run 39247903405: SUCCESS — 7/7 private-catalog reader tests, 7/7 self-use/gift tests, 6/6 Flutter widgets, 20/20 across separate suites. This is NOT full Firebase Emulator race validation.
- Color draft choice on page is local preview only. No permanent colors / gift transactions happen on-device because the action bridges remain null. No production Firebase mutation, no Google Play, no APK.
- Before production wiring: AppCheck-enforced callable layer, owner-private catalog secret, real Firestore emulator transaction race tests, dated grant-read contracts, compatibility with alias/search/share and fixed-color profile display, and explicit owner approval.
