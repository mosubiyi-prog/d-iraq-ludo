# DEDA Stage27: original full app integration of navy GM league management tile — private QA 100395

2026-10-28 | NO PROD DEPLOY | NO FIRESTORE WRITES | NO PLAY UPLOAD

## Reason and protected baseline
Stage26 signed off only an isolated Flutter manager overview and a repository admin dashboard source edit. The accepted app is actually assembled from a separately verified source archive by the Stage13–19 bind chain. A green standalone widget test does **not** prove the new admin card will be inside the installed original DEDA. Stage27 closes that specific integration gap without modifying or replacing the accepted original.

The verified Stage19 owner QA 100394 was successful in GitHub Actions run 40595626072, and the accepted original 100387 SHA a0dd340e8843162ac5fb89784cb54d0be82b23ec remains protected. This stage works from protected Stage26 commit 62cea03ba505c8a1987b077a8186e49e787e6c22 on a new branch.

## Concrete source changes
- `tools/app_stability/app_package/bind_weekly_admin_league_stage27.py`: requires fresh original candidate with all earlier immutable source hashes and exact 100394 metadata. It patches **only the TEMP workspace** `lib/admin_pages.dart` by inserting one `إدارة الدوري` card in the original manager grid after exact unique source anchors, and copies the Stage26 `lib/deda_admin_league_page.dart` into the TEMP workspace.
- Old `lib/admin_pages.dart`, `lib/main.dart`, all accounts, tasks, Firebase, Flutter wallet, XP, profiles, store, maps, package, Firestore Rules and `functions/index.js` remain exactly as before within repository history. The temporary admin patch never replaces the complete original admin dashboard with an unverified/stale repository file.
- Access: tile only when active `general_manager` role; destination independently re-reads the original admin authority and refuses access on missing/inactive/non-GM proof.
- Color: approved `#133F65` deep navy, matching the original three-column compact manager tiles; overview navy/gold.
- The private page offers read-only navigation/status sections, top-ten/podium placeholders, planned prizes, and future monthly archive. It expressly has **no live ranks**, and league start/stop, earned-wallet awards, real admin toggle remain inactive.

## Guarded CI
`.github/workflows/qa-deda-weekly-stage27-original-admin-league-100395-private-no-deploy.yml`:
1. Ensures branch changes preserve accepted source, Firebase rules/wallet/session functions, and previously passing Stage13/18/19 tests.
2. Reconstructs the exact full signed-source original candidate through the earlier Stage13+14+16+17+18+19 bind chain; then applies the new fail-closed Stage27 original admin binder.
3. Compiles/tests against the **real restored original admin/backend**, not Stage26's independent stub. Verifies safe Dart widget tests and existing league sandbox regressions.
4. Only if preceding gates all pass: signs same-package **100395 private owner QA APK**, verifies package+signer against 100379 signed reference, uploads time-limited CI artifact. Never uploads anything to Play or touches Firebase. Failure or source anchor mismatch blocks instead of deleting/rewriting real admin code.

## Still not production complete
Actual server-issued once-per-day +20 XP level receipts, original canonical account across two devices, genuine rank snapshots and active equipped frames, verified social friend/profile callbacks, GM-only live archive read rules, proven spendable earned-wallet payout (370 max full weekly top ten), owner week-calendar approval and final two-device acceptance are not solved by this UI build. Production league control/settlement is **intentionally off**.

No claims of a completed signed APK until CI's final artifact and verification are green.

## CI correction trace — exact owner-safe failures, fixed in isolated build code
- Run 40605759809: original SHA-verified administration formats `supportRead` as a **two-line** permission expression. Stage27's initial one-line exact-string guard correctly refused any mutation; it is now adapted to the verified archive's precise two-line expression. SHA-verified archive structure audit 40607118316 passed; three direct archive/binder tests added.
- Run 40607269528: original admin integration, new direct SHA-verified binder tests and Flutter widget tests passed, but complete Android release compilation revealed two **pure UI source dependencies** introduced into the current Stage22 leaderboard implementation after older Stage19 100394 originally built: `deda_weekly_competitor_public_card.dart` and `deda_weekly_leaderboard_tap_surface.dart`. The Stage13 binder copied an older four-file whitelist and did not include those two current modules. The next Stage27 fix checks these imports and presentation-only content, then copies just these two files to the verified TEMP workspace and hashes both in its build metadata. No original repo app, wallet, rules or account files changed.
- Don't claim 100395 is ready until a newer run passes complete signed APK build + original signer/package verification + private artifact upload. Failed runs have NO APK; no Firestore/Play release or spendable prize writes occurred.
