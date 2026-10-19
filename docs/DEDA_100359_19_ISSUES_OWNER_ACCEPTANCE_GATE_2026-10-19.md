# DEDA 100359 — Owner 19-point acceptance gate (19 October 2026)

**This document defines required live behavior, NOT evidence that any feature works.**
Owner tested signed 100359 on phone: Android starts, profile survives, but premium sales/grants are unavailable and the QA lab only changes a border. These failures are BLOCKERS. Do not send a replacement APK as "complete" without passing all real-user acceptance cases.

## Immutable baseline and safety
- Baseline commit: `d14e573d1f7f1ab67deff04222aca13c6f928553` (100359, signed).
- Immutable restoration branch: `backup-deda-100359-phone-open-before-19-fixes-2026-10-19`.
- Development branch: `deda-100359-19-issues-staged-private-no-deploy-2026-10-19`.
- Keep approved navigation/routes, owners' places, sign-in, 3 avatars, 3 backgrounds + 3 free frames, existing levels, XP, points, earned diamonds and gifted diamonds, personal ID, followers, friends, 30-minute location sharing, all wallets, administrator access, and existing users. No account migration without reconciliation and verification.
- Original catalog Group001: EXACT **100 unique suffixes**, preserved order and identity from Library `/DEDA/LAB_Backups/DEDA_100_IDENTIFIERS_BACKUP.json`; first SALEM, last 2020. DO NOT embed plaintext private list in APK, public repo or public logs. Server authenticated General Manager only.
- Card design colors = gold, diamond, royal, pink. Card price 5,000 verified diamonds. An ID from individually approved sellable Group002 costs 10,000 verified diamonds; no automatically offering mock candidates.
- All server-sensitive operations require verified Firebase auth, AppCheck, server role/active status, ownership, race-safety, amount fixed server-side, idempotent receipts and re-read. Never rely on client displayed local balance or write production user accounts without dedicated approval and QA.
- Owner QA staged changes are private: NO Play publish and NO Firebase production deployment until owner review. Do not build or enable unsafe feature flags merely to make buttons tappable.

## Acceptance checklist (each FAIL until demonstrated end-to-end)
1. [ ] Compact 4-design shop hero, keep approved artwork and show correct label/price without large duplicated sections.
2. [ ] Live card checkout: authenticated 5,000 verified diamonds, confirmation, one-time debit, server receipt and persisted entitlement.
3. [ ] Use purchased card: button changes to Use only after verified ownership, zero additional debit, persists after restart.
4. [ ] Exact four original elaborate designs (full art, not plain colored border) render on actual ID/profile and after Use.
5. [ ] Remove consumer-facing 25,000 synthetic wallet and test-only grant from final store. Real QA uses server-trusted funds, no synthetic success.
6. [ ] Sell only approved available Group002 IDs at 10,000 verified diamonds; durable ownership and uniqueness; separate from artwork price.
7. [ ] Admin exclusive 100 screen opens with authenticated, AppCheck-verified server data, not a frozen server-placeholder.
8. [ ] Show all exact 100 original IDs in original order, distinct status (available, self-used, granted), permanent owner and color; never duplicate.
9. [ ] GM may select four distinct identifiers and assign four individually chosen real designs (gold, diamond, royal, pink).
10. [ ] GM self-use chosen eligible identifier with server authorization and permanent ownership; old ID remains owned/valid.
11. [ ] GM may grant another eligible reserved ID to a verified recipient by ORIGINAL ID. Exactly-one global owner, atomic audit.
12. [ ] Per-grant selectable color is stored server-side, reflected permanently on recipient card/profile; no mock color border.
13. [ ] History icon at upper-left of admin page opens accurate chronological record of self-used and gifted IDs, recipient and fixed color.
14. [ ] No mock "GM grant" panel in consumer store; real GM grant belongs exclusively in secured administration.
15. [ ] Edit profile displays original + every verified purchased/gifted ID, one active ID, Switch/Use updates actual public/social/sharing routes with consent preserved.
16. [ ] Audit profile 1,000,000 and GM 1,000,000 diamond displays; do not conflate independent wallets. Define source-of-truth spendable balance after server reconciliation; prove totals do not change on read or failed checkout.
17. [ ] Server transactions: atomic debit+entitlement, idempotent request, no double spend, off-account denial, durable receipt, restart persistence, no silent partial state.
18. [ ] Real owner functional cycle: buy/use card, verify exact art, buy ID, grant/switch, logout/reopen/re-authenticate, verify identity/friends and balances. Emulator alone insufficient.
19. [ ] Android 16 clean startup + in-place upgrade with original release signer/hash, app foreground + actual nonwhite UI screenshots, no Flutter exceptions, no changes to production data, manual owner approval before Play.

## Current verified state on 100359
- Confirmed: signed build + Android16 clean and in-place upgrade success; phone shows home UI.
- Failed in owner screenshots: #1,#2,#3,#4,#5,#6,#7,#8,#9,#10,#11,#12,#13,#14,#15,#16,#17,#18 as feature-completeness checks.
- No new release passes this gate just because CI/build/smoke succeeds. Document actual test evidence per row before claiming green.

## Engineering prerequisites
- Existing unexported server draft modules under `tools/deda_intakadha_point13-16*`, `tools/deda_stage18*`, `tools/deda_stage19*` must be reviewed and integrated securely, NOT simply flag-enabled.
- Existing compiled 100359 build is reconstructed by GitHub Actions from prior accepted phone source; modifying raw `lib/main.dart` alone does not patch shipped APK.
- Preserve original encrypted catalog and keep decryption key only in protected server secrets; do not write names into public source.
- Wallet reconciliation and verified reward provenance are release blockers, not reasons to silently spend synthetic/local diamonds.

**Progress contract:** each GitHub commit states exactly what source/test changed and what remains blocked. No "completed" label until end-to-end owner acceptance.
