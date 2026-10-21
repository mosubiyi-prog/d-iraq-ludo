# DEDA — Owner-approved QA remediation checklist (2026-10-21)

## Ground truth and safety contract
- Owner works from an Android handset, without a local PC.
- Tested baseline: Stage74 gift inbox APK (source branch `deda-stage74-id-gift-inbox-claim-use-tablet-2026-10-21`, commit `2ec0c4993e1ac1f105cce33cf07c5048abddc5df`).
- Immutable backup: `backup-deda-qa-32-owner-review-2026-10-21`.
- Work only on `deda-qa-32-batch1-no-deploy-2026-10-21` until user-approved APK QA.
- DO NOT mutate production Firestore rules, wallets, user docs, assigned IDs, approval history, premium ID catalogs, signing keys, Play releases or live apps without explicit stage-specific review.
- IMPORTANT: `lib/main.dart` at repository rest is NOT the full phone application. Actual source is reconstructed in Actions; patches must apply after exact reconstruction and fail closed on anchor mismatch.
- Never mistake same phone NUMBER for trusted authenticated ownership; verified phone + permanent server account key and UID are needed, with careful legacy-user recovery.
- An original ID is a stable routing/account anchor; an active premium ID is a public-facing alias. Do not blindly swap the original ID out of existing friend/location/QR lookup paths.
- Pending/failed tests are NOT completed fixes.

## 32 owner observations & acceptance criteria

| # | Work item | 2026-10-21 status |
|---|---|---|
| 1 | Verified phone -> stable server-owned account identity across phones | OPEN; account migration requires audit |
| 2 | Recover published owner-place for historic phone/device change, without creating another place | EMULATOR RULES TEST PASS (run 39575800732); historic real account still unverified |
| 3 | Restore levels, progress, XP across same verified account | OPEN; one user's earlier 0/100 belonged to another account; original returned 40/100 |
| 4 | Protect diamonds, points, purchases, cards, frames, avatars, owned IDs, gifts | OPEN; safety guard required |
| 5 | Preserve business approval, likes, followers, palettes, owner links | OPEN; audit before modification |
| 6 | Prevent mixed UID/session when changing account, no false duplicate sign-ups | OPEN |
| 7 | GM 200-ID direct 'use' button (without grant-to-self) | GM visible precheck corrected from syntax failure at b1547108 to verified baseline at 738696515; still requires successful post-fix Flutter CI and phone test |
| 8 | On Account Info top card display active premium ID; original moves into owned list as return option | OPEN; screenshot shows old 'original active' even after premium use |
| 9 | Display active premium ID consistently across owner profile, settings, friend search, messages, location sharing, public profiles | OPEN; one hero screen working, others not |
| 10 | Use server-owned fixed ID text/color/crown/foil, never mocked or locally claimed style | OPEN; some pieces currently work |
| 11 | Unique reserved/granted/active ID ownership, never duplicate grant | OPEN; existing assignment check appears functional |
| 12 | GM grant/use ledger with verified timestamp, sender/recipient and no duplicate entries | PARTIALLY PASS; grants logged, GM direct uses not confirmed |
| 13 | 'Share your location' page shows active public alias, retains internal routing original ID | OPEN |
| 14 | Receiver's shared-location card shows active sender alias/foil while link still opens safely | OPEN; receipt/delivery PASS, old ID visible |
| 15 | Friend public preview renders active ID and its full premium card | OPEN |
| 16 | Public profile shares approved visible avatar, frame, background, ID card and badge styling | OPEN; screenshot differs |
| 17 | Ensure adequate contrast of friend's displayed name and ID | OPEN |
| 18 | Sync friend's public-facing details safely and preserve privacy of phone, location, account internals | OPEN |
| 19 | Updates to public appearance become visible to others after changes, not merely local cache | OPEN |
| 20 | New premium-ID gift appears in the red 'Hadaya' navigation badge, preserving diamond gift counts | SOURCE + NO-BUILD CI PASS (run 39575469455); phone QA still OPEN |
| 21 | Viewing verified ID-gift inbox clears notification; new grant raises it again; viewing != claiming | SOURCE + NO-BUILD CI PASS (run 39575469455); viewed marker still per device/account, cross-device server sync OPEN |
| 22 | Claim, receipts, history and legacy 10-diamond gift remain intact | Existing receipt/diamond paths preserved in Stage75 patch; needs regression QA |
| 23 | Isolate gift/badge state per account/session/device; cross-device seen synchronization still pending | PARTIAL Stage75 local scoped marker, server persistence OPEN |
| 24 | Preserve four genuine free foil artworks and avoid fake paid buttons/balances | Existing Stage71 baseline, needs visual regression |
| 25 | Owned IDs in Edit Profile: active use/revert, avoid unwanted frames navigation | OPEN; partial owned list works |
| 26 | GM two distinct 100-ID groups remain immutable & manageable | Existing Stage71 baseline, needs regression |
| 27 | Paid cards/ID storefront previously scoped DEFERRED under owner's temporary no-purchase plan | DEFERRED, not silently considered delivered |
| 28 | Test same verified account cross-device with balances, business and progress, not merely another account | NOT DONE |
| 29 | Test GM use/grant/inbox/claim/activate/revert/account info and ledger | PARTIALLY PASS; missing GM direct use |
| 30 | Test active ID & correct styling on all public, social and sharing surfaces | OPEN |
| 31 | Test new gift alert then view without claim, new gift again, preserve diamond alerts | Stage75 NO-BUILD CI PASS; recipient phone QA NOT DONE |
| 32 | Android 16 regression, original signature, owner-only APK, controlled rollback and no Play deployment before owner's approval | OPEN |

## Findings confirmed in the owner's phone test
- First premium ID gift showed in recipient Hadaya, claim completed, appears in owned list, becomes active in owner hero.
- On account settings the original ID still appeared active, contradicting owned-list state.
- Same old original ID showed on shared-location sender form, at receiving peer, and on friend public preview (with missing gold foil).
- Two received location shares were intentional sends at distinct times, NOT a duplication bug.
- GM grant worked, confirmed in ledger and ID list; direct GM 'use' did not.
- `@DEDA-IRAQI` gift later appeared in Hadaya, and was active on original account hero.
- Original account hero returned 40/100 progress and pre-existing balance after user came back; zero in a different account cannot prove data deletion.
- Hadaya navigation icon was missing an alert for newly granted ID gift.

## Batch 1 content and limits
- `lib/deda_stage75_unread_gift_badge.dart`: read-only, original-ID+verified-UID-scoped unseen ID gift watcher and on-device viewed marker, separate from claim.
- `tools/stage_deda_100359_stage75_id_gift_unread_badge.py`: strict reconstruct-time bridge combining existing diamond pending count and new ID gift count.
- `test/deda_stage75_gift_unread_badge_test.dart`: 5 pure unread/count regression tests.
- `.github/workflows/qa-deda-20261021-32-batch1-no-deploy.yml`: reconstruct app and analyze/test, no APK or Firebase deploy.
- LIMITATION: device-local viewed flag is not cross-device read history; implement server-backed seen receipts only with rules/identity audit and separate owner approval. A claimed gift remains a separate permanent server record.

## Owner approval gates
1. GitHub source changes and tests without APK/deploy (approved commencement).
2. Security audit + signed private APK for owner's phone *after* code regression and specific review.
3. Owner screenshots/QA of both original and second account and place-owner migration.
4. Only then, with explicit new command, production Firestore or Play deployment.

## 2026-10-21 verified batch status
- Run [39575469455](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39575469455): full reconstructed-source Stage75 (gift + diamond badge) Flutter QA **SUCCESS**, no APK or deployment.
- Run [39575800732](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39575800732): offline Firebase Emulator historic published-place recovery rules **SUCCESS**, no live server reads/writes.
- Commit b1547108: manager self-use now verifies the original account via source=server and shows a safe-stop message rather than silently returning; awaiting same-branch Flutter QA and owner phone verification.
- The first run failed only at missing source-reconstruction signing environment. The environment was restored without changing keys; subsequent no-build QA passed. Never cite the initial failure as an application runtime defect.

## Additional verified progress on 2026-10-21
- Manager/recipient grant, self-use, no duplicate, immutable ledger and Hadaya receipt: emulator PASS [39577337960](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39577337960), using the CURRENT released Firestore policy read only, no deploy.
- Earlier [39576274472](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39576274472) detected a Dart syntax regression in the attempted GM visible-error patch; it was reconstructed from the immutable Stage74 source and repaired at commit `738696515`. That failed run must not be represented as a pass.
- At commit `1256a4c18`, the Stage71 owned identifier panel now includes a permanent original ID row with explicit server-backed reactivation, without replacing routing original ID or deleting granted rows.
- Public active alias and full style across accounts, header/card synchronization and cross-device progress migration are NOT FIXED yet; keep those items OPEN.

## QA32 continuation checkpoint (latest owner-approved work)
- Signed-app source regression [39577588210](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39577588210) **PASS**: permanent original-ID return row and Stage75 gift badge before profile/header integration.
- Flutter regression [39579079010](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39579079010) **PASS**: Stage71 active-ID UI refresh notifier in actual reconstructed source.
- Stage76 own-ID scope and account header staging: `lib/deda_qa32_active_account_scope.dart`, `tools/stage_deda_100359_qa32_account_active_header.py`, verified-owner snapshot with UID/accountKey check and immutable premium ink. The existing blue top card and its Edit/Switch buttons are preserved; **phone QA NOT DONE**.
- Stage76 share sender visual alias staging: `tools/stage_deda_100359_qa32_share_verified_id_visual.py`, original `_personalId` remains the GPS routing/account ID. **Not yet verified on phone**. The peer's old sender alias still requires authenticated public read integration.
- Stage76 security unit tests `test/deda_qa32_active_account_scope_test.dart` verify valid owner alias, cross-account rejection, original cannot gain counterfeit premium color, unknown colors rejected; Flutter runner **PENDING**.
- Public-style resolver `functions/deda_qa32_public_alias_resolver_NOT_EXPORTED.js` plus seven offline tests **PASS** [39580482875](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39580482875). Not exported from `functions/index.js`, not deployed, requires separate security/release approval and signed-client feature flags before friends/received locations can use it.
- Source-integration latest workflows (account+share): [39579727340](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39579727340), [39580186032](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39580186032). **Check conclusions before claiming success**.
- No real account, original ID, published owner place, diamonds, engagement, Firestore policy, Play version or Firebase deployed functions changed in this branch. No APK/AAB created.

## QA32 status after interruption
- Account and Share source integration [39580186032](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39580186032) **FAILED**: 32/33 widget tests passed, but the old Makani account-info widget test mounted without Firebase. Do not mislabel as passed. The account header + sender share source guards printed PASS before the widget failure; not equivalent to successful full QA.
- Fix at `3f66d01ba`: guard Firebase App initialization before watching auth or displaying a premium alias, preserving original-ID safe fallback. Direct widget regression test added at `c0f4e84f`. Full Flutter regression [39580996221](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39580996221) **PASS**: original + premium account display, sender share, old Makani widget no-Firebase crash regression.
- Unread Hadaya correction `4275a947`: claimed receipts do not re-alert across devices; awaiting gifts from other original accounts are excluded. Two new widget tests staged. Recheck [39581732418](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39581732418); at checkpoint status was PENDING.
- Server-only social resolver offline unit tests [39580482875](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39580482875) PASS 7 tests. **NOT exported/deployed**. Public-profile style synchronization remains pending.
- Still OPEN: full cross-phone progress/wallet/levels and approved place recovery, premium public profile and ID color display, real Use button confirmation on phone, real recipient and friend's identifier sync. Never release without owner phone QA and explicit approval.
- Git branch: `deda-qa-32-batch1-no-deploy-2026-10-21`, exact original backup branch retained. No APK/AAB built or Play production modifications.

## QA32 Stage77 friend full-foil and received sender follow-up
- [39581732418](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39581732418): **SUCCESS**, reconstructed Flutter source/analysis/tests including **33 widget tests**; Stage75 viewed gift and claimed-history filter; QA32 own active header, original-ID return option, sender's own share visible alias.
- [39584293506](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39584293506): **SUCCESS** original Stage50 friend compact/search fallback following support for a new optional PUBLIC full foil builder (no deployment).
- New `lib/deda_stage50_verified_friend_ink_badge.dart` optional `premiumCardBuilder` and pure `DedaStage50PremiumPublicCard`, with full validation of server-confirmed current active ID/assigned color, default fallback for forged/cross-account/non-received values; compact friends and search unchanged.
- `tools/stage_deda_100359_qa32_public_friend_premium_card.py`: guarded single public profile patch that reuses EXACT `DedaPremiumIdCard` artwork (crown/jewels/palettes) from same profile, rather than approximating a different card. Six new regression tests: `test/deda_qa32_public_friend_full_premium_card_test.dart`.
- `tools/stage_deda_100359_qa32_received_location_sender_alias.py`: guarded change to personal sender's VISIBLE ID in received location cards through Stage50 verified public service; place share IDs and GPS original routing unchanged.
- At checkpoint [39584597626](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39584597626) was in progress, [39584970265](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39584970265) pending. **Their final result must be verified before claiming success.**
- Critical deployment limit: Stage50 public callable `dedaPremiumReadPublicIdentifierStyle` is not live / client feature flags OFF; public friends/received-location premium card will remain fallback until separately authorized audited production backend is deployed. NEVER enable fake preview, bypass ownership, or claim phone-level completion from source tests.
- Original 32 owner requirements remain unaltered. Cross-device canonical level/points/diamonds/assets and historical owner-place actual-phone recovery are still unresolved.
- Working branch: `deda-qa-32-batch1-no-deploy-2026-10-21`, baseline `backup-deda-qa-32-owner-review-2026-10-21`. No Google Play upload, Firebase deployment, APK/AAB, wallet or account mutation in this batch.
