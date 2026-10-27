# DEDA Week League Stage23 — public rollout readiness audit (NOT PUBLISHED)

Owner instruction 2026-10-28: complete end-to-end original DEDA weekly league, test, **then launch to users**. This is approval of the goal, not a waiver of correctness or authorization to distribute fabricated rankings or spend real user balances before required backend proofs are available.

## What has already passed
- 100393 on-owner phone: attractive podium, informational modal, local shadow sandbox +150 first, +100 second, +0 eleventh. Owner saw total 250. Real XP still local (100 XP from the player's task ledger), no genuine multiuser standings.
- Stage19 100394 corrected rank selection cards (separate signed QA APK candidate), last CI green.
- Stage20 tested future verified competitor card hooks and original frame verification.
- Stage21 CI fully green: legitimate @DEDA-AAAA active ID, server private same-owner equipment bridge, Flutter strict data decoder, zero live wallet changes.
- Stage22 CI green: podium top three + ranks 4–10 embedded verified tap hooks, original equipped-frame render callback, pending/self friendship safeguards, fixed no-scroll phone/tablet.

## Exact audited launch blockers: source code and deployed system are different
- Current `functions/index.js` contains NO production Cloud Function exporting `dedaWeeklyGrantVerifiedTaskXp`, `dedaWeeklyReadVerifiedStandings`, `dedaWeeklyIssueVerifiedAccountAttestation`, `dedaWeeklyIssueEquippedAppearance`, `dedaWeeklyGrantEarnedPrize`. Module prototypes Stage6/7/9/10/11/12/21 are NOT exported and some are emulator-only. Strings and test fixture signatures DO NOT authorize server-issued rewards.
- Version of `firestore.rules` in tracked branch contains no `deda_weekly_*` rules. Source file is not guaranteed to equal deployed rules; must read and emulate ACTUAL live rules before write.
- `lib/deda_weekly_private_trial_local_xp.dart` uses phone SharedPreferences and is intentionally PRIVATE QA ONLY. It cannot produce credible server-owned +20 level XP daily task claims for multiuser ranking. An ordinary +5 points event (e.g., each correct traffic question) is NOT level XP. The actual local 20 XP and task receipt are independent writes; success of one is not proof the other succeeded.
- `lib/deda_migrated_progress_firebase.dart` has `DEDA_STABILITY_MIGRATED_PROGRESS` default false; the real migration RPC handlers aren't exported in current tracked functions/index.js. Need audit ACTUAL wallet and manager personal millions; weekly 370 new prize diamonds must be independently earned/spendable, never deducted from GM's current million or the separate administrative gift pool.
- Stage22 click-to-view and click-to-add-friend are dependency-injected authentic session callbacks, not yet wired in real `lib/main.dart` with canonical public social identities. Friend requests must recheck same canonical owner and existing relation/pending/self state at server.
- Month archive of verified top ten and owner-only dashboard has NOT yet been implemented on production. It must be immutable history, not mutable XP. The final week start/day calendar is not owner-approved in a production server state.

## Auditable result
- Created `tools/app_stability/deda_weekly_launch_gate_stage23.js`, mandatory source release gate expected to report **BLOCKED_UNTIL_INDEPENDENT_SECURITY_APPROVAL** and explicit false/true evidence. Green CI on this audit means the **block is correctly detected**, not authorization to deploy.
- Created `tools/app_stability/deda_weekly_live_cloud_readonly_audit_stage23.py` and the read-only CI workflow to GET active Firebase Functions names and Firestore Rules metadata for project `deda-25b88`. Uses existing GitHub service account **only for GET**; stores minimal booleans, never any credentials, rules text, user data or account balances. If IAM/access missing => unknown; unknown does not mean deployed or permitted.
- No Firestore writes, wallet or task XP mutations, Play upload, production function export/deployment or new APK.

## Release acceptance gates (must ALL pass before launch)
1. Confirm owner's existing stable original APK/signature/rollback and actual restored account ID across two phones.
2. True account-bound task claim with +20 original LEVEL XP persisted atomically as server authority: once/day/task, same original account across devices, midnight Baghdad and replay/race tests. Neither quiz answer +5 nor daily login +10 ordinary points are automatically +20.
3. Real server-side week calendar, rank sorting top ten and self row, previous results immutable, names/active-ID images/owned equipped frames attested without private fields or bogus 4-char ID rejection.
4. Existing social profile and friend request called ONLY from authenticated session after canonical original owner link verified; pending/accepted/self and account switch tested with two genuine phones.
5. Firestore Rules *deployed snapshot* fetched, reviewed, emulator tested with users, admin roles and malicious clients. App Check + Auth checked, admin read-only registry and monthly top-ten archives verified.
6. Correct live earned diamond wallet source, transactional once/week settled receipts, 370 cap/winners, no GM personal balance or gift pool touched, isolated admin capability proof. Test back-to-back weeks and retry, no fake payout.
7. Fresh real Android 16 owner QA signed APK with portrait card click top1..10, next/previous weeks, 4-letter premium ID, phone/tablet, unexpected loss/network, all previous functionality intact.
8. Owner review of QA results and safe staged Google Play rollout, with rollback. Never auto-upload to Play merely because GitHub CI green.

Point of stop: Stage23 read-only live audit; NO public release until blockers removed with actual issuer/wallet/rules implementations and independent proof.
