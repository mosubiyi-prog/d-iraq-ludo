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


## Point01 final QA update — 2026-10-22
- SECURE BACKEND EMULATOR: run 39758153113 SUCCESS, 6/6 PASS, 0 FAIL. This validates synthetic 1000-diamond atomic wallet debit + receipt + ownership under audited read-only active-policy-derived rules, guards replay, tampered/free/unknown frame, inadequate funds, different account and unauthenticated use.
- RECONSTRUCTED FLUTTER REAL APP SOURCE: run 39757765693 SUCCESS. Patched actual restored 100377 edit profile, retained sticky preview, three existing free royals, same canonical original ID and unchanged existing features. 3 point01 contract tests PASS, Flutter analyze two new files NO issues, all existing Flutter/source tests in workflow PASS, no APK compiled.
- Work branches protected: backup-deda-100377-pre-13-points-2026-10-22 at f4da0bfd52affaea8a4d45e2ac15498bc0cea280, development deda-100377-13-points-sequential-qa-2026-10-22.
- IMPORTANT STATUS: Point01 source+emulator stage PASSED but owner acceptance gate remains OPEN. Do NOT call real 1000-diamond purchasing usable or mark point01 done. Active Firebase rules remain unchanged and checkout compile flag stays false; verified gift wallet excludes unverified displayed AdMob/task and GM manager historical sums. Do not enable without safe wallet reconciliation, owner-approved policy rollout, and two-account phone/tablet QA.
- OWNER-REQUIRED ORDER: Points 02–13 NOT touched; proceed only after point01 real functional acceptance. No Play/Firebase/live user wallet modifications and no signed APK built by this stage.

## Owner screenshot clarification and Point01 UI/restore continuation — 2026-10-22
- OWNER correction: the current badge/frame store already successfully purchased a badge; **reuse its existing visual Buy → Use/Active flow**, do not invent a second store or assume the same backend safely handles paid LAB frames. Screenshots show purchase and an activated badge; **not** a successful purchase of the 13 new LAB frames.
- Point01 fix commit `23a6f831914affbeff1e691bd2732e2182f0ab58`: `lib/deda_lab_frame_purchase_action.dart` now renders familiar `FilledButton` for Buy and `OutlinedButton` for Use (after verified ownership), displays checkout errors and insufficient verified funds, and ignores stale previous-account/frame readbacks after account switch. No local debit invented.
- Point01 security commit `173e42e00041860881dbd680f5fd9ee718ec492a`: `lib/deda_lab_frame_secure_checkout.dart` reads account proof + receipt + owned records from **Source.server**, not offline cache. Keep canonical original ID for ownership; no wallets modified.
- Point01 QA commit `dcf8e8e31ca211930d0bda0b22b674d2a8b4406f`: `test/deda_100377_point01_lab_frame_checkout_contract_test.dart` checks exactly 16 authentic catalog entries (3 free, 13 paid, price 1000 and reversible paid style mapping) and refuses fake enabled purchase while feature is off.
- Point01 reopen fix commit `dbc75cabda753b002ee1702e7875fe820ad19a2f`: `tools/stage_deda_100377_point01_lab_frame_checkout_private.py` revalidates server ownership when saving a previously owned paid frame after relaunch, rather than depending only on an ephemeral session Set.
- Latest real source CI link: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39760580439 (verify actual conclusion before reporting PASS).
- **Still explicitly NOT COMPLETED**: real 1000-diamond purchasing remains disabled until safe spendable wallet sources are reconciled, user explicitly approves any necessary production Firestore policy rollout, and signed phone/tablet acceptance proves no double debit or phantom ownership. No changes to Firebase production, Play, or live balances. Do NOT start point02 until Point01 actually passes.

## Point01 safe-rollout compatibility finding — 2026-10-22
Owner consent to carefully reviewed Frame01 rules rollout has been received. This is **not** permission to alter user balances or disrupt the existing successful badge checkout.

### Exact discovered incompatibility (block live deploy)
- The working **existing** badge/frame purchase UI in `tools/style_badges_frames_100273_2026_10_05.py` calls `DedaDiamondsWallet.spend(price)`.
- Existing wallet patch `tools/social_ui_wallet_fixes_100270_2026_10_04.py` uses local earned diamonds FIRST; when insufficient, it debits the remote received-gift remainder via `DedaBackend.spendPersonalGiftedDiamonds` (an unreceipted client balance decrease allowed by the earlier Firestore rules).
- New 13-LAB-frame checkout in `lib/deda_lab_frame_secure_checkout.dart` would debit **only** `deda_diamond_gift_balances/{originalId}`, ignoring the local earned, ad/task and historical manager wallet. Displayed personal totals do not guarantee this particular balance.
- The proposed production policy from Stage69 + Point01 deliberately removes the old unreceipted wallet-decrease allowance to prevent forged debits. This also potentially **breaks existing badge/frame purchases funded in part or entirely from the remote gift balance**. Publishing now without replacing the old checkout's client debit path is **NOT acceptable**.
- Do not restore insecure arbitrary balance decrements as a shortcut; do not mint local diamonds into a server wallet without verified origin.

### Concrete safe progress
- The existing real reconstructed Flutter source QA run `39760580439` completed SUCCESS after the Point01 account switch, server-only readback and reopen verification corrections.
- Expanded Firestore emulator regression: approved synthetic purchase, replay/price/owner/insufficient guards, real pending gift claim-once, and simultaneous two-tap purchase. `39762158911` SUCCESS, 8 tests PASS, zero FAIL. Emulator used a published-rules-derived **temporary** candidate, never live database.
- Added `test/test_deda_100377_point01_legacy_checkout_compatibility.py` as a source audit showing that the legacy original store and new LAB checkout currently use different spendable sources. Wired into the read-only emulator CI workflow.
- The safe next engineering prerequisite is to reconcile legitimate, securely attested diamond sources with the legacy store purchases, and provide an atomic receipt-backed replacement for any client-only gift-wallet spend before production rules activation. Preserve gift claiming and existing owned items, then rerun the entire compatibility and concurrency suite.
- Point01 **NOT COMPLETED** / Firebase live policy **NOT DEPLOYED** / no owner wallet write / no Play publish. Point02 remains untouched. Owner phone+tablet end-to-end acceptance remains mandatory.

## Point01 additive Firebase live activation / signed 100378 owner APK — 2026-10-22
- Owner explicitly consented to carefully scoped rules activation after preserving the proven legacy badge purchase and gifts; owner asked to finish point01 only before point02.
- New **legacy-compatible additive policy**, from exact active rules hash prefix `12473b12e32f5888`: `tools/deda_100377_point01_legacy_compatible_rules_NO_DEPLOY.py`. Legacy gifted-wallet debit and gift claim source remain byte-identical, while paid LAB frame new receipt+ownership requires a trusted 1000-unit wallet decrease in one transaction. This does not convert local ad/task/million balance into spendable verified cloud funds and does not remove preexisting legacy direct-debit limitation.
- Firestore Emulator 11/11 synthetic tests PASS `39763504230`: legacy badge gift-funded debit still succeeds; pending gifts claim once; new paid frame 1000 debit, receipt and ownership; replay, two simultaneous requests, 2 independent frames charging separately, insufficient, 900/tamper/free/unknown, fake receipt/markers, cross-account and unauthenticated rejection.
- Live rules guarded CI `39763825716` SUCCESS. Reran 11/11 emulator checks, pinned original published policy SHA prefix `12473b12e32f5888`, saved private rollback, published ONLY exact additive rules, and verified read-back. Post-deploy live SHA prefix `53bd7bd53e15f628`. NO user documents or balances written; NO Play/APK deployment in this rules workflow.
- Private owner APK workflow `.github/workflows/build-deda-100378-point01-owner-private-signed-apk-no-play.yml` launched run `39764130961`: original app signing and 100377 reconstruction plus point01 frame checkout/Flutter QA, compile-time `DEDA_LAB_FRAME_ATOMIC_CHECKOUT_APPROVED=true` only if **read-only current live rules SHA matches `53bd7bd53e15f628`**. Private artifact versionCode 100378, never Google Play.
- **Owner acceptance still OPEN until actual signed APK artifact success plus real phone/tablet purchase/use and account-specific verified gift wallet entitlement**. Original earning-local diamonds & historical million are not silently mintable server funds; don't mislead owner about overall 999k screen display. If only local diamonds exist, the new frame checkout may reject despite high total, and point01 remains unfinished; no fake purchase. Point02 untouched.

## Owner latest consolidation order — 2026-10-22
- Owner's latest explicit directive: **stage points 01→13 sequentially with an exact per-point source/QA brief, preserve each step in the SAME development branch, and produce ONE integrated signed owner-test APK after all points have been staged**. No intermediate APK per point, no Play publish. Final phone/tablet acceptance remains essential before declaring the complete app verified.
- Failed private 100378 run `39764130961` was diagnosed from job `119775259833`: point01 checkout patch ran **before** the 16 native LAB frames renderer, and its safe guard rejected the absent `children: List<Widget>.generate(16, ...)` marker. This failure created NO APK and changed no live balances.
- Commit `88a998e4` corrected the source stage order and a Python indentation error in the 100378 workflow, disabled all automatic triggers and hard-gated its old private APK job (`if: false`); that historical workflow is NOT the planned integrated 13-point release workflow. **Do not unfreeze/build until 13-point source bundle and owner checks are ready.**
- Point01 code/emulator QA had previously passed 11/11 synthetic rule tests plus reconstructed Flutter source. LIVE additive legacy-compatible rules were already deployed via owner-approved guarded run `39763825716`; no new rules or user-data changes in this continuation. **Actual frame buy/use/reopen and verified-wallet spendability remain UNCONFIRMED until final integrated APK tests; point01 does not have a live owner-accepted PASS.**
- Point02 implementation `tools/stage_deda_100377_point02_exact_frame_names.py` now binds styles 6..18 to `DedaLabPremiumFrameStyles.byProfileStyle(index)!.nameAr` from the original 16-frame catalog, no longer mislabels 13 paid frames `وردي ملكي`. Free royal 3/4/5 labels remain unchanged; paid name rows can wrap three lines.
- Point02 source guard `test/test_deda_100377_point02_exact_frame_names_source.py` checks 16 authentic titles, 13 unique paid/3 free, and the generated Flutter UI binding. Applied AFTER point01 in source-only QA workflow. Run `39766174285` launched (record actual conclusion once verified). No new server wallet or owner profile updates, no APK, no Play/Firebase deployment from this QA.
- Next: inspect Point02 CI results, then perform Point03 three-free-frame use/persist/sticky-preview verification and proceed in original numeric order. Never invent device test results.
