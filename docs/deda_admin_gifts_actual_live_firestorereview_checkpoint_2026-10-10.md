# DEDA — Live Firestore administrative gift activation checkpoint (2026-10-10)

**STATUS: REVIEW COMPLETE, NO PRODUCTION DEPLOY YET.** Owner-approved 100329 APK and rollback 100327 unchanged.

## User-approved recipient behavior
- General manager selects verified user via personal `@DEDA-...` ID, checks name/public avatar/frame, selects amount/reason and confirms. Deduct exact amount ONLY from 1,000,000 ADMIN gift pool during transaction creation.
- Recipient opens EXISTING bottom home tab `هداياي`, sees official DEDA logo, sender, date, reason and amount. Gift remains `pending` and adds **zero** spendable diamonds until the user explicitly presses `استلام الهدية`.
- Claim atomically changes `pending` to `received` and credits recipient spendable wallet exactly once; a second claim fails. In-app record persists. No auto-claim.
- Admin wallet top-up back to 1,000,000 every 24h is **NOT enabled** and cannot run from untrusted client. Requires later trusted scheduler/backend; owner personal GM wallet separate.
- Friend-to-friend gift shop 50 items / 80% recipient 20% virtual store commission remains **deferred**.

## Real read-only production inspections (deda-25b88)
- Real current released rules SHA18: `c5b444a132c894e933` (full SHA `c5b444a132c894e933e8eec782d64b05c5ab2f6f770ffb0cea6fe6919b5e9ae6`), collected by GitHub Actions run `38070479186` through Firebaserules API GET ONLY.
- Existing LIVE source **already contains historical** `deda_admin_diamond_wallets`, `deda_diamond_gifts`, `deda_diamond_gift_balances` and separate personal manager-million wallet. Never deploy the divergent dev rules as a wholesale replacement.
- Old live gift creations permitted **standalone pending gift insertion without a matching manager wallet debit**, and manager wallet updates did **not require a paired gift creation**. Old recipient wallet ownership used `currentUserHasShareId`, less restrictive than accountKey + personal owner binding.
- `tools/deda_preview_merge_live_admin_gifts_2026_10_10.py` implements a SHA-pinned reversible surgical merge from the EXACT live source: replaces ONLY the 3 gift-related collection rules, adds 6 auth/transaction helper functions, does not modify any unrelated source bytes.
- Merged preview SHA18: `df9fbbbfa30ade3bae`. GitHub Actions `38070720612`: REVERSE DIFF PROOF PASSED, 17 Firestore emulator tests passed (10 gift/manual-claim+personal-wallet security and 7 prior 100327 social/admin regressions), ZERO failures. No Google Play, Firebase rules or user-data writes.
- Real owner-provided personal ID `@DEDA-AQPYXJ`: live share ID exists, kind=personal, active=true, ownerUid populated, registered user matches/accountKey exists. Original historical owner UID's `deda_sessions` is absent (expected possible UID rotation); read-only `users` query on the same personal DEDA ID found newer authenticated session(s) sharing registered accountKey. GitHub Actions `38070870290` confirms `VERIFIED_VALID_ROTATED_SESSION_CANDIDATE=True`; no IDs, phone, emails, tokens, names or account keys logged.
- Actual exact live rules snapshot was safely backed up as a private short-lived GitHub Actions artifact `DEDA-ACTUAL-LIVE-RULES-2026-10-10-READONLY-NO-DEPLOY` on run `38070542664`; expiry 1 day. Merged *preview only* artifact on run `38070720612`, expiry 1 day. Neither deployed.
- Full golden Flutter reconstructed source `38070066591`: 16 Flutter tests pass; offline DEDA official logo, manual gift claim and gift history, admin verified target preview, all three deferred server services OFF.

## Next safe stage
1. Request explicit owner confirmation before changing LIVE Firebase Security Rules. This conversation's approval was to **review live rules in preparation for activation**, not an unqualified production deployment approval.
2. On explicit approval, refresh actual live SHA (safe stop if changed), perform same strict isolated 3-rule merge, rerun real emulator tests, retain rollback ruleset name/hash and deploy **only the Firestore rules**, not functions, data or APK.
3. Create separately signed APK above 100329 from fully accepted navigation baseline + verified manager gift UI + branded receiver inbox; verify build and signing, owner install/phone acceptance.
4. Pilot with 2 real accounts: manager sends 10 💎 to tester (not manager's personal wallet); confirm pending view/no spendable credit, explicit receiver claim, +10 one time, second attempt rejected, GM gift budget -10, personal GM budget unchanged, audit and user notification.
5. Do NOT activate 24h gift pool refill, friends coins/diamond transfers, Telegram subscription auto rewards, 10s PIN, or 30s place acceptance from this flow.

**No gift-money movement or Firestore production mutation has occurred from this checkpoint.**
