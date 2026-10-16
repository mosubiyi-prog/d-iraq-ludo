# DEDA — Profile Royal Step 1 | Safety Baseline | 2026-10-17

## Status
- AUDIT / PLANNING ONLY. No Flutter profile UI implementation has been committed, no production/Play deploy, no live Firebase updates.
- Recovery branch **backup-deda-100340-before-profile-royal-2026-10-17** is frozen at commit `b9c2181ac01ef942e05bcdbcf40ce0dbeb34e5c9`.
- Isolated working branch: `profile-royal-step1-3avatars-4frames-2026-10-17`.
- The most recent repository AAB workflow for `100340` succeeded (GitHub Actions run `38666295959` on 2026-10-15). Successful AAB build is **not** proof of current Google Play availability, approval, or owner installation.
- Owner reference: approved royal navy/purple + gold profile mockup from chat dated 2026-10-17. This is a layout reference, not working Flutter source.

## CRITICAL: Do not modify raw lib/main.dart blindly
The repository's raw `lib/main.dart` at the 100340 branch is **not the final app source**. The build workflow `.github/workflows/build-deda-100340-play-aab-owner-review-no-auto-publish.yml`:
1. Restores `lib/main.dart` from `backup-deda-100319-user-accepted-2026-10-08`.
2. Reconstructs features through `tools/build_100318_user_heading_camera.sh` (and previous task, points, level, profile, diamond, frames, navigation scripts).
3. Injects additional 100330–100340 feature fixes into that build pipeline before compiling an AAB.
Thus a raw-file preview can differ materially from the accepted 100330/100340 phone build. Never use `main` branch as the release base: its tip was at `fe8be028...`, older than the accepted release.

## Visual acceptance criteria — top of “ملفي”
- Replace only the top profile hero layout with a luxury gold/navy/purple card: large centered image with a separate cosmetic frame, then current name, real DEDA ID (copy still functions), level and existing level badge.
- Preserve account member/status text (as appropriate) and edit entry point.
- Existing progress bar, points, friends, diamonds, photo and edit cards stay below the hero as genuine working widgets, NOT hard-coded sample numbers.
- Match approved reference dimensions/colors/positions as closely as actual Android/Flutter layout allows. Get owner acceptance from an **actual phone APK screenshot** before proceeding.

## Three avatar options — free
- Male royal portrait, female royal portrait, couple portrait; use the three exact user-approved files as assets, no generative substitution, no bundled frame around portraits.
- Show as selectable FREE options (no gem deductions); preserve previous user selections while migrating away from older six cartoon choices. Do NOT reset unrelated local preferences.
- Avatar and purchasable frame are separate visual layers. Avoid cutting faces when displayed in a small circle.

## Four frames — staged, not selected yet
- From 16 preserved DEDA LAB original WebP frames, first select exactly four with the owner. Use real transparent frame assets (not preview portraits). Keep original artwork and polish.
- Establish shared measurements and carefully bounded shimmer/glow animation for performance; avoid affecting navigation/map responsiveness.
- Do not unlock paid inventory, rewrite prices, or change ownership/purchase state in this stage. Existing 3 free frame options remain valid until migration rules are reviewed.

## ABSOLUTE non-regression rules
- Presentation-only: no edits to Firebase rules, functions, backend account balances, tasks, rewards, level mathematics, user XP, friends, purchase ledger, diamond wallet or profile-visible diamond sum.
- Existing points, level and diamonds are LIVE account values; they must remain live across upgrades. Never embed the mockup figures in code.
- Preserve `lib/deda_profile_visible_diamonds.dart` behavior (ordinary earned + gifted and separately authorized manager personal wallet as applicable).
- Test old selected avatars/frame preferences and safe fallback; verify account persistence and no lost purchases.
- Run Flutter analyze and existing regression tests; compare synthetic account data before/after using an isolated test environment. Avoid any real-user mutation.
- No auto-publish, no Play upload, no deployment; get explicit owner approval after each screenshot and test report.

## Next safe technical action
1. Reconstruct and EXPORT the final post-patch 100340 `lib/main.dart` from isolated CI, without publishing; inspect actual profile widget sections and relevant wallet/level bindings.
2. Build a separate 1st-stage royal hero presentation patch against the post-reconstruction source, with a guard that aborts if expected markers are missing.
3. Run offline tests + private screenshot APK; require approval for the next phase (3 avatars, then 4 frames).
4. Make a new precise checkpoint: branch, commit, run, result, screenshot and next action.

## Links
- Golden build: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38666295959
- Backup branch: https://github.com/mosubiyi-prog/d-iraq-ludo/tree/backup-deda-100340-before-profile-royal-2026-10-17
- Working branch: https://github.com/mosubiyi-prog/d-iraq-ludo/tree/profile-royal-step1-3avatars-4frames-2026-10-17
