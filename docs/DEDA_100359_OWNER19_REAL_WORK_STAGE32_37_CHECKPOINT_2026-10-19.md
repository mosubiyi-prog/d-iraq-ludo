# DEDA 100359 owner 19 issues: work checkpoint — 19 October 2026

**INCOMPLETE / NO REPLACEMENT APK / NO DEPLOYMENT.**
This is a durable record of verified **code staging**, not a claim that the owner's 19 app behaviors are usable. Owner expects all 19 items fully operational, actual artwork, actual verified balances, actual GM privileges, and a phone-tested signed build; do NOT repeat 100359's mock-function mistake.

## Immutable baseline
- User-installed and launched 100359 head `d14e573d1f7f1ab67deff04222aca13c6f928553` (signed run `39301846613`, Android16 clean & in-place green).
- Backup `backup-deda-100359-phone-open-before-19-fixes-2026-10-19`.
- Development `deda-100359-19-issues-staged-private-no-deploy-2026-10-19`.
- Master 19 acceptance requirements: `docs/DEDA_100359_19_ISSUES_OWNER_ACCEPTANCE_GATE_2026-10-19.md`.
- Owners' other original identities, authentic role, levels, earned diamonds, 1,000,000 GM personal test balance and GM donor pool must not be combined, rewritten or prematurely spent.

## Actually staged and tested (NOT live)
1. Private original 100 suffix length mismatch solved: Group001 supports 4–12 characters, Group002 sale suffix still independently requires six; no plaintext list embedded in phone.
   `tools/deda_stage18_private_atomic_identifier_checkout_2026_10_19.js`.
2. New strict single server Gateway for old point13/14 card checkout and use, point15/16 verified owned IDs, stage18 10k only-inventory-approved sale, stage19 GM manager self-use/gifts and exclusive original catalog read.
   `tools/deda_100359_owner19_combined_gateway_private_2026_10_19.js`.
3. Separate lazy AppCheck/FirebaseAuth server facade; rejects unauthenticated before touching AES catalog secret; distinct ordinary card actions do not load the private 100 key or fake wallet.
   `tools/deda_100359_owner19_lazy_server_callables_PRIVATE_NOT_EXPORTED_2026_10_19.js`.
4. Dormant GM page read/use/gift remote Function callbacks with response verification; server owner private catalog never embedded.
   `lib/deda_exclusive_ids_admin_page.dart`, default launch flags OFF.
5. Compact approved four **real** premium-foil designs with actual `DedaPremiumIdCard` artwork preserved. Only a stage script has been authored, **not yet proven on reconstructed Flutter app**:
   `tools/stage_deda_100360_compact_four_real_foils_after_100359.py`.
6. Stage37 strict workflow uses the **exact original 100359 source reconstruction**, disables final APK build, then tests Stage35 changes on real generated Flutter source (not model-only tests).
   `tools/qa_reconstruct_100359_then_stage35_no_apk.py`;
   `.github/workflows/qa-deda-100359-stage37-real-source-artwork-no-apk.yml`.

## CI evidence
- Runs `39317005498`, `39317343838`, `39317473421`, `39317723659`, `39318703691`, `39319648217`: verified SUCCESS on incremental code/security/Flutter regression tests; not proof of live user transactions.
- Stage37 exact-reconstructed-source run `39320364898` was started and needs result inspection, fix any blockers, and re-run before claiming its stage green.
- Previous Stage35 source unit test CI failures (`39318451965`, `39318552219`) were corrected and subsequent `39318703691` passed; do not misreport these as consumer-function success.
- No APK/AAB for the 19-point repair and no Firebase/Play deploy.

## Current hard release blockers
- Need owner-only server AES secret/key provisioning for the original 100 in Secret Manager and proof of EXACT 100/100 original sequence; ciphertext exists in public repo but clear private key has not been confirmed provisioned.
- Current public `functions/index.js` deliberately does **not** export or deploy any premium/GM callables; staged server functions alone cannot activate real buying or admin lists. Current phone switches OFF.
- `pubspec.yaml` currently lacks `firebase_app_check`; privately signed owner Android installs must be properly attested/registered with Firebase AppCheck before enforced callable access. Never bypass auth/role or AppCheck to make UI appear functional.
- Historical 1M GM personal diamonds were self-created test balance; GM donor pool separate. Need audited spendable-wallet provenance and customer/owner approval. Existing local ad points/diamonds cannot be silently migrated or spent.
- Group002 candidate proposals are **not** approved sellable stock. Needs collision checks, explicit owner selection, verified server inventory and list/checkout/readback.
- Immutable GM ID-per-color artwork on actual profile, owned ID list/active ID routing, historic friend and share aliases not all implemented.
- Real end-to-end Firestore Emulator race/rollback tests, authenticated client widget tests, signed Android16 fresh and in-place runtime and owner-phone checks all remain to be completed.
- **ZERO of the 19 acceptance checklist items should be marked green solely on this staged work.**

## Restart instructions for a lost ChatGPT conversation
Read this checkpoint and the master 19 checklist; verify working-branch head and current Actions runs (especially `39320364898`). Continue only from GitHub branch and immutable backup; preserve original 100359 owner phone install. Do NOT start another mock simulator. Do NOT declare finished or give user a new APK until the complete 19-point server/client/phone acceptance evidence is real.


## Owner continuation (20 October 2026) — NO CLAIM OF 19 FEATURES COMPLETE

- Owner explicitly requested ALL 19 agreed corrections, one fully integrated *real* signed phone version, without further fake purchases/grants. Keep 19-point master acceptance list UNCHANGED.
- Stage37 `39326964122`: **SUCCESS** — true signed-100359 source reconstructed on GitHub without APK build, four actual premium artworks preserved in compact layout; mock purchase/grant lab navigation removed; GM preview linked to original DedaPremiumIdCard renderer; Flutter analyzer/integration suite green. This verifies UI *source* only, not phone experience or backend.
- Stage38 source: `tools/stage_deda_100360_remove_fake_store_sandbox.py` deletes the RAM fake 25k laboratory from final consumer-store routing (not customer data). Verified staged test.
- Stage39 source: `tools/stage_deda_100360_real_admin_foils_on_reconstructed_source.py` reuses full gold/diamond/royal/pink foil instead of plain coloured border in GM manager preview. It is reconstructed against real Flutter source, avoids a duplicated fake rendering implementation.
- Stage41 real stock server module `tools/deda_100359_stage41_verified_sale_list_private_2026_10_20.js`: only server-owner-approved Group002 inventory priced exactly 10k; filters global registry, alias, legacy public ID collisions. Gateway adds `dedaPremiumListAvailableIdentifiers` (AppCheck/auth) behind OFF default flag `listSale`; staged checks at `test/deda_100359_stage41_verified_sale_list.test.js`.
- Stage41 security workflow `39327415409`: **SUCCESS** (all staged unit/security tests; no production deployment).
- Stage42 private Flutter UI `lib/deda_stage42_verified_sale_panel.dart` and surgical reconstructed-shop patch `tools/stage_deda_100360_verified_group002_only_store.py`:
  * If server/client live flags BOTH enabled AFTER authorized release: replaces *mock candidate* list with **server-confirmed** Group002 stock, fixed 10k, confirmation dialog, immutable idempotency request ID on retry, Firestore transaction receipt and cross-account-safe owned-ID readback, no local wallet decrease.
  * If server flags disabled: no fake sale or wallet-debit claims; original 100359 preview-only list remains as historical non-purchasable preview.
  * Stage42 source compile/reconstruction workflow `39328083133` started; **CHECK result before marking it valid**.
- No new APK or real Firebase deploy, no real premium purchases, diamonds, grant, alias or group001 admin actions have been enabled. Owner's old 100359 phone version remains unchanged.
- Release hard blockers still exist: server-only original-100 decryption key/Secret Manager provisioning, public Group002 owner-approved inventory, verifiable wallet provenance including 1M GM test balance versus donor pool, AppCheck-enabled signed release configuration, alias/share compatibility, permanent style on recipient profile, secured history, emulator races, APK install/upgrade and owner phone checks. **Do not bypass any gate, do not represent green CI as live ownership**.
- Current working branch remains `deda-100359-19-issues-staged-private-no-deploy-2026-10-19`, original immutable phone backup `backup-deda-100359-phone-open-before-19-fixes-2026-10-19`.
