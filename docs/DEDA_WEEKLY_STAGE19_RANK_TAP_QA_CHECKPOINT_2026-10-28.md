# DEDA 100394 — direct rank card selection, contrast, owner QA

Owner screenshots 2026-10-28 confirm FULL functional sandbox Stage18 100393 actually works on Android:
- Private trial week 2026-10-26, 1st place => +150 shadow gems.
- Next simulated week 2026-11-02, 2nd place => +100 shadow gems, original +150 persists => cumulative 250 shadow gems.
- Third simulated week, 11th place => **0 shadow gems** (confirmed visually by user screenshots). Last confirmed wallet total is 250 from immediately prior result; user did not yet supply updated top-of-screen gem screenshot for the 11th zero test.
- User initially tapped card for second place directly and it did not respond: in 100393 cards are informational ListTiles; only the bottom DropdownButtonFormField has onChanged. User subsequently used dropdown successfully.

## Stage19 owner UI fix in original-app private workspace
- Branch `deda-weekly-stage19-tap-rank-accessibility-100394-private-qa-2026-10-28`; protected signed 100393 remains unchanged.
- Repository-new `lib/deda_weekly_qa_full_trial.dart` on this branch adds a direct onTap for **each** rank 1..10 and 11, only for unfinished **current** test week. Preserves prior-week read-only and disables selection after local test payout.
- Selected card outlined in gold, touch icon added. Clear selection text, gold contrasting dropdown field, legible payout/next week controls. `ValueKey<int>(selected)` keeps DropdownButtonFormField in sync when user chooses via cards.
- **Same** local sandbox key `deda_weekly_qa_earned_shadow_v1_{accountKey}` retains owner's existing 250 and simulated 11th zero receipts across in-place update.
- Original rank podium design, real data placeholder, XP, tasks, ID speed, real Firestore, real user's earned/gifted/admin gems, signing and app package untouched.
- No live leaderboard, genuine server-ranked award or true manager control yet. Manager-only dashboard and per-month archival are separate future protected backend features requiring authorization and actual verified data. No fake names or spendable rewards in private QA.

## Gates
- Python original 100387→stages13/14/16/17/18→stage19 immutable-source check.
- Dart widget taps rank 2 and 11 + existing prizes, exactly-once, weekly archive, cross-account isolation tests.
- GitHub Actions `.github/workflows/qa-deda-stage19-100394-direct-rank-card-tap-qa-no-deploy.yml` builds original-signed, private, same-package DEDA 100394 APK on PASS only. No Google Play publishing.
- End-user Android test requires screenshot of selected rank and remaining 250 after rank11; preserve data, don't uninstall or clear storage.
