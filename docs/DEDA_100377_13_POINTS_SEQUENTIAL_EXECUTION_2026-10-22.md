# DEDA 100377 — OWNER 13-POINT SEQUENTIAL IMPLEMENTATION CHECKPOINT
Date: 2026-10-22. Strict owner policy: **work in original numbered order; give exact changed-file/test evidence before proceeding to the next point.**

## Immutable protections
- Actual approved owner APK baseline: 100377, original source commit `f4da0bfd52affaea8a4d45e2ac15498bc0cea280`; GitHub run 39691301046. Not a proven fully functioning paid store.
- Independent immutable rollback branch: `backup-deda-100377-pre-13-points-2026-10-22` at that original commit.
- Stage changes ONLY on `deda-100377-13-points-sequential-qa-2026-10-22`.
- Do NOT push to Play, deploy Firebase rules/functions, alter production wallets, rewrite canonical IDs or perform paid transactions absent explicit review and verified secure purchase permission.
- Owner phone + second tablet/cross-account checks are mandatory; a green CI badge alone does not certify functionality.
- DO NOT skip or mark a point complete until its acceptance test passes; avoid repeatedly patching each app screen.

## Exact ordered register
1. **13 authentic paid LAB frames**: each 1000 diamonds, native original preview, explicit confirmation, server-atomic one-time debit + receipt + permanent account entitlement, verified multi-device ownership, no preview debit. **IN PROGRESS — not live**.
2. **Correct frame names**: show each authentic LAB name instead of repeating «وردي ملكي». PENDING.
3. **Three native royal free frames**: verify Use/Persist/Public, no charge, sticky preview. PENDING.
4. **Wallet**: display verified user's diamonds/coins across Profile/Edit/Tasks/Shop, investigate owner's ~1M personal balance vs 999025 shown, never merge admin gift pool nor silently spend local/minted unverified values. PENDING.
5. **Replace exactly three legacy cartoon avatars** with approved moonlight trio (couple, moon princess, moon prince); keep original three and all six free, preserve selected avatar. PENDING.
6. **Premium identifier on public profile**: active @DEDA-IRAQI versus old @DEDA-AQPYXJ, active artwork/crown and readable name. PENDING.
7. **Share recipient + friend card**: trusted active alias and foil across phone/tablet; two deliberate shares are NOT duplicates. PENDING.
8. **Manager gifts**: recipient lookup by original and premium IDs to same account, gift records/claim/read notification «هداياي» intact. PENDING.
9. **Persist & restore** avatar/frame/background/IDs/badges/owned inventory/level/points on reopen and across authenticated devices. PENDING.
10. **Six premium LEVEL badges**: silver/gold/emerald/diamond/royal/legendary, no photos; automatically earned from verified levels, consistent with existing "ذهبي 1" naming and never rewrite XP. PENDING.
11. **«شاراتك وإنجازاتك»** display six badges, level threshold, open/locked, progress to unlock and rule explanation. PENDING.
12. **Rename account card to «متجري»** as canonical personal ownership view for IDs/avatars/frames/backgrounds/badges/all purchased or granted profile items, preserve separate acquisition store. PENDING.
13. **Unified ownership/active identity for 200 GM IDs throughout the application**: manager «استخدام» fails server account confirmation; edit profile shows old ID; ensure single verified active alias/cosmetic source for every location, app session, original ID fallback, manager self-use/grant, photo/frame/background, across devices; secure GM authorization. PENDING. Points 6–8 are separately tested prerequisites for point 13.

## Point 01 actual code edits (staged, NOT approved for real money)
- `lib/deda_lab_frame_secure_checkout.dart`: exactly 13 IDs at fixed 1000, reject invalid ID, require Firebase Auth + account session and original ID, Firestore wallet/receipt/entitlement atomic transaction, duplicate readback protects against second charge. **Default live flag OFF**.
- `lib/deda_lab_frame_purchase_action.dart`: confirmation UX and retry after ambiguous network result, only verified purchase can become "Use"; locked label until approval.
- `tools/stage_deda_100377_point01_lab_frame_checkout_private.py`: attaches secure-gated action AFTER real app 16-frame reconstruction; previews paid frames on sticky picture WITHOUT persisting them, changes frame cache upper bound to 18 only, blocks saving premium choice without verified receipt.
- `test/deda_100377_point01_lab_frame_checkout_contract_test.dart`: fixed 13 at 1000, identifiers input guard, disabled by default.
- `.github/workflows/qa-deda-100377-point01-secure-lab-frame-source-no-deploy.yml`: reconstructs exact real baseline, executes patcher and Flutter tests/analysis; **no APK or Firebase deploy**.

## Point 01 still blocking COMPLETION
1. CI must pass on **actual reconstructed** Flutter code and tests (check exact workflow run).
2. Firestore Emulator must verify real deployed-policy-compatible wallet-only debit denied, atomic 1000 receipt+entitlement, duplicate/replay concurrency, insufficient verified balance, UID/manager isolation, gift claim preservation.
3. Reconcile spendable task/AdMob/manager displayed diamonds; user's displayed 999025 is not proof spendable. Existing local wallet is not a safe server transaction source.
4. Explicit OWNER approval and secure rollout of necessary backend rules; no silent deployment.
5. Private signed Android APK + same-device/reopen/second-device acceptance. Until then #1 remains OPEN, do NOT call purchase functional.

## Gate
Continue number 01 only until the above safety/functional tests pass. Then issue exact per-file/QA brief, and begin number 02. No user data touched by these commits.

## Point 01 additional implementation and honest QA status (same day)
- Created `tools/deda_100377_point01_lab_frame_rules_candidate_NO_DEPLOY.py`: 13-frame fixed 1000 wallet debit + immutable receipt + owned record; uses audited Stage69 live-rules-compatible candidate source, **offline only**, no published changes.
- Changed `lib/deda_lab_frame_secure_checkout.dart` receipt/owned paths to account-scoped `/{originalId}/frames/{frameId}`, allowing secure ownership readback even before records exist; transaction writes `lastLabFrameId` plus immutable receipt ID.
- Reconstructed app QA run `39753826753` failed safely on brittle generated edit-profile `selected` source anchor, not wallet or data loss. Adapted guard.
- Subsequent run `39754557501` failed safely on different real `onTap` syntax; updated script to target the real 16-frame grid InkWell only.
- Latest workflow update `9394830eafeb9a592941ab3451427862d0a3fbec` preserves exact generated `lib/main.dart` in a temporary PRIVATE QA artifact for source-grounded debugging and cancels superseded runs.
- Point01 is STILL OPEN: do not say 13 frames are purchasable, do not turn on feature flag, do not use account's displayed manager/test million as spendable, do not proceed to point02 until real stage/tests and backend authorization pass.


## Point01 continuation — actual security test evidence
- Corrected actual reconstructed 100377 frame edit profile integration to reuse existing preview field rather than duplicating selected/tap source anchors. Commit afee08c10d307109c05b1ff778eab5a58dfb6474.
- Flutter contract tests 3/3 PASSED: exactly 13 premium frames at fixed 1000, rejects unknown identifiers/product, default live checkout OFF. Analyzer caught redundant braces and unused temporary; fixed in 962879986517fe7c8825afa5d7768e7ee3e9ff03.
- Added real Firestore Emulator rules test via live policy READ-ONLY; run 39758153113 SUCCESS: **6 PASS, 0 FAIL** (atomic debit + receipt/entitlement, replay, wallet-only debit, tampered price/product, insufficient, stranger, unauthenticated).
- https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39758153113
- Flutter real source run 39757765693 still awaiting final result at this checkpoint.
- **NO Firebase deploy, NO live wallet writes, NO Play publish, NO APK yet. Point01 remains OPEN until trusted spendable balances, owner permission and phone/tablet acceptance.**
