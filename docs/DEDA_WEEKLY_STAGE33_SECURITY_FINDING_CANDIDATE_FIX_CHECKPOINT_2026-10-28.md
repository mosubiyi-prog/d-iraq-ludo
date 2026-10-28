# DEDA Stage33 — live Firestore personal location-share rule gap and safe candidate fix

Date: 2026-10-28  
Protected working branch: `deda-weekly-stage33-live-share-rules-audit-no-deploy-2026-10-28`  
Verified final run: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40626419697  
Status: **CI SUCCESS; 21/21 baseline local-emulator checks and 21/21 additive-rule-candidate checks; ZERO production changes.**

## Verified actual deployed-rule result
- Used service-account GET-only access in GitHub Actions to read **the currently deployed** `cloud.firestore` Rules release from project `deda-25b88`. Copied it only to a temporary GitHub runner file. Never displayed/uploaded that private rules source; erased it afterwards. No production Firestore access/write/deploy from the test.
- First security run https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40626210951: 20/21 expected checks passed. Genuine original share creation and sender/recipient reads worked; client forgeries, unowned/premium sender IDs, nonmatching sender UID, invalid clock/coordinates, invalid share duration, unauthorized deletions, unexpected XP/rank fields and private weekly collection writes were denied.
- **Specific confirmed security gap:** a signed-in user with original sender ID `@DEDA-A12345` could create a `deda_location_shares` record where `recipientPublicId` was **the same original personal ID**. This was permitted by the actual published Rules snapshot in the demo emulator, although Stage30/32 league proof code refuses it. This is a possible self-share misuse path; no proof that any real user obtained points or diamonds, and no production data was read or changed.
- This confirms the live source document creation is **client-originated subject to rules**, not an inherently server-created trusted task/XP event. A valid share document alone does not verify that the original account's independent phone-local +20 level XP was awarded, or that the GPS was physically true.

## Candidate fix and regression results (NOT DEPLOYED)
- Added a tiny ONE-condition candidate inside `match /deda_location_shares/{shareId}` → `allow create`:
  `&& request.resource.data.senderPublicId != request.resource.data.recipientPublicId`
- Script `tools/app_stability/deda_weekly_stage33_private_self_share_rules_candidate.py` computes this **in the private runner ephemeral Rules copy only**, and verifies the delta is exactly one additive condition. It does not modify repository `firestore.rules` and cannot deploy.
- Tests in `tests/firestore-rules/stage33_live_original_share_rules.test.mjs` were run **twice** against the real active Rules snapshot and candidate-patched snapshot:
  - Baseline current Rules: **21/21 PASS**, explicitly verifying the known self-share gap and the 20 other expected behaviors.
  - Candidate-only patched Rules: **21/21 PASS**, self-share rejected while legitimate cross-user personal shares continue to work and existing denials remain intact.
- The protected GitHub Actions job finished `success`; exact job/run URL above. Historical failing diagnostic remains intentionally visible for audit.

## Release blockers and next steps
1. Treat the production self-share issue as an **unresolved live Rules hardening request** until separately reviewed and owner-approved for deployment with rollback. Never silently overwrite the live Rules release or deploy full stale repository rules.
2. Audit live source account/UID ownership across device changes, recipient ownership and authenticated sender, plus App Check/enforcement. The source rules can accept a legitimate share but cannot certify original +20 level XP, task claim, level preservation or eligibility for prizes.
3. Build the actual privileged task-to-original-level-XP atomic server workflow, dedupe per canonical account/day/task, reconcile pre-existing local XP without loss, and ensure midnight weekly scoring cutoff. Only then issue real ranking snapshots and exactly-once pending league gifts in existing `هداياي` with manual claim. Keep GM funds and original balances unchanged.
4. Verify user/GM actual rankings, equipped frames, profile/friends taps, monthly top 10 admin archive, 00–06 frozen results and owner-approved no-name/no-ID winner card. Finish all QA on authentic phone and tablet **before** private signed APK and any Play AAB.
5. Never label Stage33 as production rollout or final ready DEDA. The next private APK and production Firebase changes require separate release QA and explicit owner authorization.

No real APK/AAB, user wallet writes, Cloud Function exports or Play publication were performed in this stage.
