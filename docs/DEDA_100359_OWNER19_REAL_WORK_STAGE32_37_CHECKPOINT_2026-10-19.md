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
  * Stage42 full-source workflow `39328083133`: **SUCCESS** — accepted 100359 reconstructed Flutter app, vetted Group002 10k purchase UI included, same four ornate ID artworks preserved, mock lab absent, GM art real, Flutter analyzer + widget checks passed. **NOT a real server purchase, NO APK.**
- No new APK or real Firebase deploy, no real premium purchases, diamonds, grant, alias or group001 admin actions have been enabled. Owner's old 100359 phone version remains unchanged.
- Release hard blockers still exist: server-only original-100 decryption key/Secret Manager provisioning, public Group002 owner-approved inventory, verifiable wallet provenance including 1M GM test balance versus donor pool, AppCheck-enabled signed release configuration, alias/share compatibility, permanent style on recipient profile, secured history, emulator races, APK install/upgrade and owner phone checks. **Do not bypass any gate, do not represent green CI as live ownership**.
- Current working branch remains `deda-100359-19-issues-staged-private-no-deploy-2026-10-19`, original immutable phone backup `backup-deda-100359-phone-open-before-19-fixes-2026-10-19`.

## Key provisioning blocker — private original 100
- Owner Library `/DEDA/LAB_Backups/DEDA_100_IDENTIFIERS_BACKUP.json` retains exactly 100 unique original names, first SALEM, last 2020; old AES key was NOT confirmed persisted in Library/Secret Manager. A newly encrypted catalog cannot be activated until its corresponding private key is durably stored and manually supplied to Secret Manager. Never commit/copy the key, plaintext names or original JSON to public GitHub, app assets, CI logs or APK. Keep existing encrypted release and immutable rollback unchanged until secure key provisioning is verified.


## Single-release policy (owner's instruction)
- Do NOT deliver repetitive unfinished APKs. Preserve one versioned source line based on accepted installed 100359 until ALL 19 agreed features have end-to-end proof; then build ONE new signed private Android 16 owner-review APK with in-place update, without Play auto-publish.
- Mandatory real Firestore Emulator workflow `39329305426`: **SUCCESS**, all 3 jobs green (production no-change guard, isolated emulator 5k card + 10k ID sale + GM color grant race/replay/authorization suites, and checkpoint). These are emulator transactions; production server continues unchanged.
- Production backend remains unchanged, no real balances/grants affected. Group001 server decryption key is not provisioned; neither read nor self-use nor gift can function live until owner-authorized secure provisioning. All frontend/server stage switches default OFF.
- Exact 19-point acceptance document `docs/DEDA_100359_19_ISSUES_OWNER_ACCEPTANCE_GATE_2026-10-19.md` remains the single authority; no stage marked green simply on mock or compilation tests.


## Stage43 — manager-private catalog session and receipt guards (20 October 2026)

- GitHub point of return: `backup-deda-owner19-before-session-guard-2026-10-20`, pinned at `1a06983f2cb681d7b6bd8bfc6e9c59ef5004cfd0` (after the encrypted Group001 catalog was paired with the owner's locally stored new key; NEVER place that key in GitHub).
- Staged private Flutter security fix: `lib/deda_exclusive_ids_admin_page.dart`.
  - Server read response now rejects an auth UID change while awaiting Firebase Callable.
  - Manager screen rechecks active GM role and same UID after remote reads; generation tracking discards stale overlapping requests.
  - Firebase auth stream clears already-loaded private identifiers and grant history on account change.
  - `DedaExclusiveAdminSnapshotVerifier.isSafe` checks the exact 100 consecutive ordered positions, no duplicates, available-versus-owned state, allowed immutable colors, matching 1-to-1 server audit, and chronological history. It does not embed the 100 secret identifier names.
- New synthetic-only Flutter regression suite: `test/deda_owner19_stage43_snapshot_guard_test.dart`; no sensitive names or wallets.
- New NO-DEPLOY GitHub Actions QA: `.github/workflows/qa-deda-owner19-stage43-admin-session-no-deploy.yml`.
- **Verified PASS:** GitHub Actions run `39425004201` / job `verify-private-manager-ui`, including Flutter analyzer, original manager tile regression tests, new snapshot invariants, and production-change guard. No APK/AAB or Firebase/Play deployment.
- This is a **source-level hardening step only**: production manager Read/Gift/Self-use Callable remains unexported and inactive, and the 19-item owner acceptance checklist remains unpassed. It does NOT prove live grants or whole-app colored profile/share identifiers.
- Next priorities: safe Secret Manager provisioning only after owner approval, AppCheck & wallet source-of-truth verification, client-visible permanent color in profile/sharing routes, and signed private Android16 owner acceptance. Do not regenerate incomplete APKs.


## Stage44/45 — strict AES manifest QA and offline owner key preflight (20 October 2026)

- **Stage44 CI repair** accepts exactly one OWNER-PAIRED ENCRYPTED Group001 manifest update under `server_private/catalogs/`, pinned to Git blob SHA `d07198ced5c9019d0eb85e99ee94101db52921e3`. Any unexpected catalog/secret/plaintext entry or change to live Functions, Firebase rules, original Flutter main, Android or assets still fails closed. No encryption key is in the repo.
- Stage32 private security-contract QA `39425713617`: **SUCCESS** after fixing that intentionally strict historical guard. Tested staged 5k/10k/manager logic only, no real checkout/grant.
- Stage37 reconstructed original Flutter application no-APK QA `39425612974`: **IN PROGRESS when this checkpoint was written**, inspect its final Actions conclusion before claiming success; no APK build/deployment.
- New Stage45 owner-tablet-only read-only preflight `tools/deda_owner19_private100_key_preflight_OFFLINE_ONLY.js` validates the owner's `~/.deda-private/key.txt` file (private directory 0700, regular key file 0600, no symlinks) against authenticated AES-GCM ciphertext without logging, transmitting or printing the key or 100 identifiers. It accepts the historical explanatory-text key document by locating base64 candidates and proving exactly ONE authentic 100/100 match, never guessing the secret.
- Synthetic fixture tests `test/deda_owner19_stage45_offline_key_preflight.test.js` exercise AES ciphertext, key-file permission failure, wrong key and symlink refusal. Stage45 GitHub Action `39426243058` **SUCCESS**: offline TEST DATA only, **NOT the owner's actual private key**. Owner can later run the separate preflight locally (after reviewing file path) but nobody should share or paste the key into chat/GitHub.
- Firebase CLI owner tablet login was verified with Firebase project `deda-25b88` and Android application package `com.diraq.ludo.d_iraq_ludo`. These read-only checks do not indicate that server functions are deployed.
- **Still NO production deployment, NO premium Callables exported, NO user diamonds/ownership mutation, NO signed 19-fix APK.** Owner approval is still mandatory for Secret Manager provisioning, AppCheck enforcement and public sale activation. Exact 19 acceptance items remain release-blocked.
