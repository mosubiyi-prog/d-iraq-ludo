# DEDA 100378 owner-approved 18-point repair — 2026-10-23
## Authorization and baseline
Owner explicitly authorized implementation in this conversation on 2026-10-23, after reviewing scope.
Baseline: 7accb3053419dfc63b03bfc9a8c7a3a281f75f39.
Successful original APK workflow: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39869442313
Backup: backup-deda-100378-before-owner18-2026-10-23.
Working branch: deda-100378-owner18-fixes-2026-10-23.
No Play publication authorized. Final deliverable: privately signed APK, existing signing identity verified.
## Scope and order
1. Fixed backup and isolated working branch. DONE.
2. Preserve unrelated accounts/map/navigation/places/tasks/ads; do not inspect or modify unrelated functionality. Do not reset currency, levels, ownership or identity records.
3. 13 original paid frames: 1000 diamonds each using existing original purchase system, persistent ownership and working Use.
4. Correct store free/paid/owned labels and purchases inventory.
5. Account-owned cosmetic restoration, isolated across account/device changes.
6. Consistent diamonds/gold; screenshot 998925 diamonds / 30 gold is evidence, NEVER an instruction to mint or overwrite funds.
7. Restore @DEDA-IRAQI only from verified ownership; reference photo shows #010 granted to @DEDA-AQPYXJ.
8. Owned ID selection and activation persist to account.
9. Active ID visible across already-agreed identity surfaces and received shares. Two intentionally sent shares are not a duplicate bug.
10. Approved six badges: GOLD 1–9; SILVER 10–19; EMERALD 20–29; DIAMOND 30–39; ROYAL 40–49; LEGENDARY 50+. Explain ranges to users; display current rank next to profile level. Owner's image is artwork reference.
11. Six free avatars total: retain original top three royal portraits, replace lower three classic portraits with newly approved feminine blue / masculine emerald / shared couple burgundy images generated in this conversation. NO old missing moonlit-art dependency.
12. Same source image dimensions/crop/rendering as previous three; approved inner display 111×111. Verify original implementation rather than distort images.
13. Restore exact original two-column admin catalog, original 100 right and additional 100 left, numbered golden cards, preserve all data.
14. Admin grant and self-use operate correctly and preserve existing grants.
15. Correct frame names.
16. Sticky profile preview during cosmetic scrolling; preserve three free royal frames.
17. Verify gifts/notifications related to these changes.
18. Verify targeted changes, build, certificate, checksum; deliver APK and honest test results. No automatic publication.
## Reporting
For each point: observed cause, actual change, verification, remaining device checks. Code/design visibility or a green build is not proof of functional success.
On a blocker, report actual state. No claim of completion without evidence.

## Verified implementation checkpoint (revision 4, not yet delivered)
- Working implementation: e4be3d3a90fd162848176b7133d6e23abf0bf6ed.
- Current private build/QA run: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39888600527
- Independent synthetic account/rule QA passed 11 tests in run 39888493867: account isolation, monotonic inventory, missing-receipt authorization, legitimate new-device UID with unchanged canonical owner route, immutable received-grant public projection repair, concurrent frame lock, and denial of foreign account writes.
- Exact 100378 generated baseline staging passed offline; only the explicitly allowed profile/shop/wallet classes changed. No currency amount, XP, grant, account session or private ID document was rewritten.
- Read-only server diagnosis: original 200 catalog intact; @DEDA-IRAQI is already granted and received by @DEDA-AQPYXJ and selected active. Both public projections were absent. App repairs only those projections after verifying the immutable ownership/receipt/current-account proof.
- Server GM wallet observed 998850 diamonds and gift wallet 60. These are observations, not instructions to overwrite or force screenshot totals. Local earned balances were not read or replaced.
- Three complete approved 1536x1536 portraits restored and SHA256 matched. An earlier CI check correctly rejected truncated uploaded copies before APK generation.
- Remaining gates: final Flutter analysis/widgets, signed APK build, signer comparison to 100378, isolated Android16 upgrade and cold launch, tested scoped cosmetic/public projection policy activation, private artifact delivery. No Play publication.
- Real-account purchases, grant changes and live wallet deductions have NOT been performed as QA. Device/account end-to-end outcomes must not be claimed from unit tests alone.

## Signing material incident (already disclosed to owner)
A temporary public CI source export accidentally included the encrypted existing signing keystore without its passwords. Artifact 12471093600 was deleted and the artifact list verified empty; the exporter now includes only Dart source and pubspec. A prior download cannot be excluded. The existing signing identity is preserved for app update compatibility. Review the upload-key exposure before any future store release; no key rotation or Play publication has been performed.

## Resumed after workspace interruption
The original workspace became unavailable while GitHub Actions continued independently. Run 39889625246 subsequently passed all 20 final interface tests and built the signed APK, then stopped at certificate text parsing before artifact delivery or server policy activation. A read-only reference-certificate run (39948365906) established that current Android Build Tools emit `V2 Signer:` instead of `Signer #1`. A parser accepting both forms now requires exactly one distinct certificate and exact equality; three offline negative/compatibility tests pass. No signing key was changed. Current full verification run: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39948539871 . Delivery remains pending final certificate comparison and Android16 installation checks.

## Final automated gates passed, private delivery preparation
Run 39948539871 succeeded in all four jobs: isolated-cosmetics, private-apk, android16-smoke and activate-tested-cosmetic-backup. APK source 934cfd4a99e9e8b1beadee870ea374cabae25f6d. APK 83,426,364 bytes; SHA256 52e9345528978d0944b8fe8a28cc1715395bfec624bf2c38f9c2157a3990a1da. Certificate SHA256 a53d855b82d1280f324037428421838139ecf2e30174f9fcd0bd1878698b5f4a exactly matches 100378. APK artifact 12499044608.
Android16 artifact 12499808902: previous APK installed and updated, then fresh new APK installed; both processes remained running, both screenshots reached the original login, no fatal log signatures. No real account login, purchase, grant, share or notification delivery was performed. All three packaged approved portraits match exact SHA256.
Tested cosmetic/public projection policy released, no Firestore user documents or balances modified. Previous ruleset d9a1cf1e-a13b-4216-852f-e0b6054ce26e; new ruleset f064b9f9-74b7-4bde-b7d8-290d076a68a6; tested candidate SHA256 9ef41b19bc07bc67052ea76d0d7099f497f0430f4f8d013ac2bc46455f89beed. Rollback reference artifact 12499548694. Never roll back over another maintainer's later ruleset.
Real-account feature outcomes remain device QA items as listed in the delivery record. Install over 100378 without uninstalling to preserve original local-only data. No Play publication. Prior encrypted-keystore incident remains disclosed above and in delivery notes.

Delivery files are present locally in delivery/. Library prepared upload explicitly failed before finalization with library_storage_limit_exceeded; no Library files were saved or deleted. APK remains in verified GitHub artifact 12499044608 until 2026-11-22. Final Arabic QA record is docs/DEDA-100379-QA.md. Return direct APK and QA record sandbox links, disclose Library retention failure and signing-file incident. Do not delete existing files to resolve quota without explicit owner instructions.
