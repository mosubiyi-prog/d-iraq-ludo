# DEDA weekly leaderboard | Stage 2 tested checkpoint
Date: 2026-10-27 | NO DEPLOY | NO APK | NO WALLET / XP WRITES

## Traceable stable reference
- Original owner-phone-verified and Google Play Protect-accepted: DEDA 100387 (private QA build).
- Immutable base SHA: `a0dd340e8843162ac5fb89784cb54d0be82b23ec`.
- Original 100387 APK GitHub Action: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40512928957
- Approved design reference: owner's single dark-navy/gold leaderboard image in ChatGPT conversation; NO alternative images requested.
- Approved owner constraints: remove **Restaurants home tile and its home navigation** from both screen layouts, use same place/size for leaderboard home card, preserve restaurant search via Map, open a single-screen non-scroll leaderboard, match reference arrangement/spacing as closely as real-device layout allows. Protect all working DEDA sections.

## Stage 1 result
- Pure `lib/deda_weekly_leaderboard_policy.dart` read-only contract; status PASS.
- Prize policy: #1 150 diamonds, #2 100, #3 50, #4–10 10 each; total exactly **370**.
- One-point overtake, task-count/time tie-breaking, exclusion of unverified rows, separation of weekly scores from historical XP, displaying nonwinner own rank.
- Stage 1 CI PASS: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40521583292

## Stage 2 result
- Branch: `deda-weekly-leaderboard-stage2-ui-no-deploy-2026-10-27`.
- Flutter widget: `lib/deda_weekly_leaderboard_page.dart` with dark-navy/gold podium/top 3, ranked 4–10, tabs current/previous, remaining-time display, signed-in user's position, reward amounts and informational footer. It accepts ONLY provided read-only data; unverified/absent data renders an explicitly pending/empty state, not invented users.
- No scrolling widgets (`ListView`, `CustomScrollView`, `SingleChildScrollView`) inside the leaderboard. Layout reflows/scales for constrained phone screens; IDs remain LTR. A narrow-screen text overflow was detected, fixed and independently re-tested. **Final color/spacing fidelity against the owner's image still requires a real-phone rendered screenshot/owner review.**
- Binder: `tools/app_stability/bind_weekly_leaderboard_stage2.py` applies to the temporary *restored and already task-integrated source*, NOT the 100387 repository main file. Replaces BOTH legacy home restaurant cards, one in landscape/compact and one in portrait, with `DedaLeaderboardHomeCard` routing to `DedaWeeklyLeaderboardPage`. Completely removes home restaurants entry variable and associated tile navigation, while keeping restaurants available on map.
- Binder tests confirm restored traffic quiz, backend accounts, social code and pubspec are byte-identical; binder refuses repo paths and rejects accidental double application.
- Widget QA: `test/deda_weekly_leaderboard_page_test.dart`: 320x568, 390x844, 600x960 screens, no scroll, tabs, authenticated 12th-place information. Full stage 2 PASS: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40526431586
- Git compare from 100387: only new docs, pure leaderboard model/UI, bind script, tests and CI workflows. No legacy app code, signing material, Firebase config, APK prepare script, published Play release, task/XP/diamond wallets or Firestore Rules were edited.

## Critical blocker for real standings/diamond payments
- In currently shipped/restored source `DedaTaskEngine` records task award points with phone-keyed `SharedPreferences`, not a trusted cloud-wide event history. Users reaching higher profile levels through tasks is real-world evidence of visible progression, NOT evidence that phone-local totals can securely award 370 diamonds to 10 people.
- Present functions `deda_daily_reward_shadow_ledger.js`, `deda_daily_task_share_verifier.js` explicitly say EMULATOR/shadow-only; no real wallet credit/external deployment. Stage 2 deliberately does not claim these are production server validators.
- Backend work not done: confirm canonical level/XP ownership against existing profiles and login, verify qualifying weekly task events in server with replay protection across two devices, exclude manager bonus, use server-defined weekly cycle and countdown, rank public pseudonymous accounts with safe Firestore rules, and transactionally credit each finished weekly prize into existing diamond wallet exactly once per (serverWeekId, UID) with audit and rollback/reconciliation. No system-level static week start day has been accepted by owner.
- **No fake points and no automatic award from Flutter**. Stage 2 is NOT ready for owner APK or launch while verified standings are missing. Real consumer UI defaults to pending rather than counterfeit ranking.

## Next isolated work stage (3)
1. Read-only audit of canonical real user task points vs level XP and diamond wallet grant path; map actual active Cloud Functions and rules and identify authoritative server UID.
2. Create emulator-only, pure server ranking/event-dedupe policy and tests; do not export/deploy or credit real users.
3. Resolve weekly start boundary and trusted source with owner, document exact interface.
4. Integrate live backend and only then make a separate signed private QA build from reference, with secure grants left off until audited and explicitly approved.
5. Owner tests on Android; separately check Play Protect, no scroll, exact reference visual layout, and no user/account regression.

Stage 2 status: **CODE WRITTEN + TESTS PASS; NOT INSTALLED, NOT LIVE, NO SERVER PRIZE PAYOUT**.
