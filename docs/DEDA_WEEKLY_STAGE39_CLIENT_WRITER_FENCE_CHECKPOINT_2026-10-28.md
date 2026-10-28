# DEDA Weekly League Stage39 — ORIGINAL client daily-task local writer fence, SAFE QA ONLY

Date 2026-10-28
Branch deda-weekly-stage39-original-client-task-writer-fence-no-deploy-2026-10-28
Parent confirmed successful Stage38 HEAD fc9efbc9c35db9e6e59c7438431d0ba711939ef1
Stage38 CI https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40691995117

## Actual implementation, not a simulated spec
- Audited original lib/main.dart DedaTaskEngine.claimTaskReward: original +5 daily task points are appended to local SharedPreferences key deda_task_points_state_v1_<account> after checking completion.
- Added lib/deda_stage39_task_writer_fence.dart with independent typed routing contract for legacy local, blocked pending trusted backend, and server-only when every migration/identity/fence/issuer requirement is met. A local flag or phone timestamp never itself verifies a server claim.
- Integrated exact fail-closed pre-write guard inside ORIGINAL lib/main.dart, before the awards map, ledger, SharedPreferences mutation. With private flag enabled the +5 local task grant refuses until trusted server integration is ready; current original points are read without deletion or reset, and pilot UI shows an accurate pause message.
- Compile-time flag DEDA_STAGE39_TASK_WRITER_FENCE_QA default false, so original DEDA behavior remains UNCHANGED in all standard builds and deployed old APKs. No remote claim is performed or claimed in this stage.
- Added Flutter tests for default-off original mode, offline cutover refusal, wrong account, missing reviewed migration, missing old-writer fence, and server-only route. The server-only route currently is a planning contract, NOT deployed actual award path.
- GitHub Actions guards original source diff: only the approved import, guard before mutation, pilot message and read-only points return are allowed in main.dart; Firebase, server, backend, old progress archive, Android and pubspec are unchanged. Runs Flutter analysis and UI regressions; no APK build or deployment.

## Strict honest limitation
This gate protects ONLY the original +5 daily task claim local writer in a future QA build where the compile flag is explicitly enabled. It does NOT yet fence separate original lifetime-level +20 XP logic, traffic question rewards or login +10, and it cannot retroactively stop an APK already installed on another phone.
A functioning live cutover needs a trusted server issuer, verified old-client version fences/Rules and per-account manager-reviewed history migration. Stage38 and Stage37 still use demo Firestore and modelled proof/fence. Do not activate this flag in a user APK before the real server flow is available.
No Firebase/Rules/Google Play deployment, real XP, diamond grants, wallet or user data mutation occurred in this stage.

## Remaining release tasks
1. Locate and reconcile original lifetime-level XP local writer and login/quiz award writers with the canonical account and verified receipt source; avoid duplicate local/server grant.
2. Build actual privileged AppCheck + Auth original task-claim producer and real server writer-fence enforcement for old clients; separately approve migration and Rules fix with rollback.
3. Verify 00:00–06:00 lifetime XP preservation while weekly rank frozen, exact-once weekly read/projection, monthly admin history, frames and friend profile, pending gifts in هداياي and agreed winner card.
4. Test signed PRIVATE original APK on real phone and tablet before any approval to deploy.

CI status: require SUCCESS on exact final branch HEAD before calling this Stage39 complete.