# DEDA Stage24 live deployed Firestore Rules adversarial emulator QA — COMPLETE

## Confirmed actual evidence (2026-10-28)
- GitHub Actions [run 40602458794](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40602458794) **SUCCESS**.
- Authenticated read-only GET fetched *active deployed Firestore ruleset* of `deda-25b88`. Copy was stored only in a private GitHub runner temp `.rules` file, without publication of source or credentials. The script deleted that temp file.
- LOCAL Firestore Emulator ran under **demo** project `demo-deda-stage24-live-rules-client-attack`, never connected to production collections.
- Rules Unit Testing **24 of 24 test groups passed**, each exercising 4 operations = **96 denied client operations** (get/set/update/delete): eight server-only weekly paths × three caller identities: anonymous, normal authenticated user, simulated general manager with active management record.
- Protected paths: `deda_weekly_xp_receipts/{weekId}/events/{id}`, `deda_weekly_standings/{weekId}`, `deda_weekly_identity_attestations/{uid}`, `deda_weekly_competition_config/current`, `deda_weekly_verified_equipped_public/{hash}`, `deda_weekly_public_profiles/{hash}`, `deda_weekly_prize_receipts/{id}`, `deda_weekly_earned_wallets/{hash}`.
- **All evaluated operations were refused by the exact deployed Rules snapshot.** Stage23 discovered that the weekly paths were not explicitly named in the rules, but this emulator test proves the selected client accesses were DENIED under the deployed snapshot. Do not inaccurately claim an explicit deny policy or every possible wildcard attack is formally covered.
- Runner performed NO Firebase writing, no user identity query, no wallet, XP or friend records changes, no APK/AAB creation, no Google Play publication. The active ruleset in production was never modified.
- Test code: `tests/firestore-rules/stage24_weekly_live_rules_attacks.test.mjs`.
- Read-only GET helper: `tools/app_stability/deda_weekly_live_rules_emulator_fetch_stage24.py`. Workflow: `.github/workflows/qa-deda-weekly-stage24-actual-live-rules-client-attacks-no-deploy.yml`.

## Launch state still BLOCKED, but one major security uncertainty has been resolved
Existing production Rules deny client manipulation of future protected weekly documents in the 96 tested cases. However, real league cannot launch until an authenticated, privileged and rule-protected account+claim issuer proves original +20 level XP task awards and the original ID survives phone change; audited real multiuser ranker and week configuration are deployed; original equipped frame ownership is checked on server; authenticated original social profiles friend actions are wired and tested with two real devices; and a separate verified earned wallet handler atomically grants 370 weekly prize diamonds with no admin wallet draw or double grant. The general manager's monthly top-ten archives/administration also remain a separate feature to build and verify.

IMPORTANT: The first run failed due test declaration syntax, not because an attacker bypassed rules. Corrected branch run above passes all 24 groups. No production rollout or real gems payout was attempted.
