# DEDA stage30 — independent backend task evidence, atomic +20 XP and identical weekly ranking

Date 2026-10-28 | Branch `deda-weekly-stage30-trusted-task-proof-emulator-no-deploy-2026-10-28` | **NO LIVE DEPLOY**.

## Why this stage matters
The owner demands real end-to-end task XP, not yet another UI-only release. Stage29 linked synthetic +20 XP receipts and player/manager ranking in memory (33 tests PASS), but did not demonstrate that the reward originated from an independently trusted server action.

Original `lib/main.dart` records successful task completion/claim in account-scoped SharedPreferences. XP+20 for level progress has an independent local persistence path, not a server-authoritative transaction. Thus *no trustworthy production issuer of original level XP currently exists* for weekly ranking. The user-visible receipt +5 ordinary task points or a correct traffic answer is not proof of +20 level XP.

## Actual stage30 implementation
- `functions/deda_weekly_stage30_server_action_proof_emulator_NOT_EXPORTED.js` reads a dedicated **emulator-fixture-only** backend-owned action, checks a current verified canonical account, official Baghdad time/week, stable event ID, exact committed action, original task points claim and exact +20 XP proof, then `tx.create`s exactly one Stage9 task proof. It **does not create the event**, does not trust client task-completion flags, and deliberately does not support unproven UI-only tasks such as `open_map`.
- The guarded Stage9 transaction then issues +20 **shadow-only** XP and a unique weekly receipt; Stage29 builds the exact same ordered row set for competitor and manager previews. All displayed scores, positions and potential prizes are QA-only, and manager approval/payout is disabled.
- Only *two future potentially server-observable task kinds* are modelled: `share_personal_location` and `share_registered_place`. These **do not yet have an actual trusted producer** in deployed DEDA; their action documents are seeded by test Admin SDK fixtures. The existence of a server document/issuer string alone never proves a user actually completed a task: real trusted server handler and rules audit remain prerequisites.
- All new JS is NOT imported by `functions/index.js`. Exact emulator host and `demo-deda-weekly-xp-stage9` project guard make production calls reject.
- `tools/app_stability/stage30/firebase.json` and `firestore.rules` are isolated from repository's production `firebase.json`/`firestore.rules`; all client reads and writes are denied in the stage30 sandbox. Only Admin SDK test setup has access. This is *not* a suggested replacement for live DEDA rules.

## Acceptance verification
- GitHub Actions `.github/workflows/qa-deda-weekly-stage30-real-proof-to-ranking-no-deploy.yml` checks production source immutability, old 33 tests, then starts a genuine Firestore Emulator for account A and B.
- Cases: absent server action denies XP; fake client task request or wrong App Check fails; server action with wrong account, issuer, week, task source or amount fails; task evidence → proof → +20 Stage9 shadow XP → Stage29 one identical manager/player sorted ranking; concurrent requests for two phones linked to original canonical account cannot double-credit; user and manager original wallet documents are bytewise unchanged; new week resets league only; unauthorized Firestore REST clients cannot write/read isolated proof/XP/account data.
- **Do not claim PASS until exact GitHub run succeeds**, and never equate emulator pass with real user data verified.
- No APK/AAB in this stage; the owner chose to defer Google Play, and asked to complete the league before Smart DEDA Heartbeat.

## Hard blockers for NEXT live-integration step
1. Find the legitimate server-side transaction that confirms each original task (including map/quiz tasks, which currently rely on client local flags), and build a trusted task-proof producer that writes +20 original level XP and a receipt atomically. It must be impossible to request XP merely by tapping a button. Reconcile historic honest local XP without erasing old values.
2. Validate actual live authenticated account linkage across device change/UID transitions and original vs premium display ID; real server App Check / original ownership, not emulated issuer strings.
3. Fetch and emulator-test actual deployed Firestore rules, produce **additive reviewed candidate rules** and independently approve and deploy only after owner accepts security findings. Current production code lacks weekly callable exports. Don't deploy any candidate without explicit authorization.
4. Wire real server calendar + player and GM readers, frames/social, archived previous week and monthly top ten; audit real spendable diamond wallet and exactly-once 150/100/50/10 payouts and Hداياي receipt without touching GM million.
5. Signed Android APK, two real accounts/phones, tablet and owner QA. After acceptance, one reviewed AAB Play rollout. No fake ranking or payouts to production.

**Checkpoint:** Stage30 is limited to safe producer contract and genuine emulator proof. Production weekly task XP authority remains **NOT IMPLEMENTED / NOT ENABLED**.
