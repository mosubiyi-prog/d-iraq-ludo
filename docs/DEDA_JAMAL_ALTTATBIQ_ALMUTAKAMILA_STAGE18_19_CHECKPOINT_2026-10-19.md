# DEDA — «جمال التطبيق المتكاملة» (OWNER PRIVATE RELEASE CHECKPOINT)
Date: 2026-10-19. **This is a named WORKING BRANCH, NOT A SIGNED/INSTALLED APK, NOT Google Play.**

## Name approved by owner
- Arabic build/release title: **جمال التطبيق المتكاملة**
- Integrated scope: Stage18 secure 10,000-diamond identifier proposal and 5,000-diamond design purchase + Stage19 manager-exclusive first 100 identifiers and life-fixed color.
- Work branch: `deda-stage19-jamal-alttatbiq-almutakamila-private-2026-10-19`
- Source safety anchor: `backup-deda-stage19-original100-encrypted33-green-2026-10-19`.
- Phone-safe previous signed APK: DEDA 100358, Android 16 green. Do NOT uninstall, wipe app data, use unverified new signing, or publish without owner acceptance.

## Completed *and verified* in the integrated source branch
1. Protected backup + isolated new branch from prior successful Stage19/100358 + Stage18 sources.
2. Manager dashboard tile of normal compact size, opt-in exclusive navy/turquoise palette. All other admin colors remain unchanged.
3. New light blue-gray exclusive admin page with top-left gift history button, one 50px ID preview per record, gold/diamond/royal/pink draft selection and permanent-color status.
4. Owner original full 100 IDs copied **encrypted** AES-256-GCM (private key never in public code or APK). Owner-original Library JSON and numbered list verified 100/100 in identical order without duplicate. Only authenticated verified-GM server gateway may return complete 100 list.
5. Read-only Flutter Firebase Callable bridge introduced but OFF by default via `DEDA_STAGE19_MANAGER100_READ_LIVE=false`.
6. Server action prototypes: separate owner self-use / gifted recipient flow, permanent color locked after atomic verified transaction, original user identifier remains intact, log history with server timestamp. All server read/use/gift flags OFF by default, not deployed.
7. Stage19 reader now checks **global registry, original share ID and alias collisions** before claiming a reserved ID "available." Fails closed on unverified/duplicate or compromised records.
8. Stage18 previous proposed fixed 10,000 diamond checkout and 5,000 design purchase remain guarded/off and unmodified.

## Testing passed on real GitHub Actions runners
- Previous stage19 unit and Flutter screen audit: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39253410123 — 33/33.
- NEW Firestore Emulator actual transaction races & auth/rules: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39256180581 — 9/9. Includes *10 concurrent gifts*, one winner, permanent color, audit history, no client bypass, and conflicts with existing original/share alias IDs.
- NEW combined Stage18+Stage19 private integration: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39256403945 — **SUCCESS**; 39/39 JS security/checkout tests and 6/6 Flutter widget tests (45 total). No Firebase deploy, real writes or signed APK.
- The "54" tests figure represents 45 integrated source tests + 9 independent Firestore Emulator cases, not 54 tests in one job.
- Test data synthetic; owner original 100 list stays protected. Zero production users, gift diamonds or account state mutated.

## NEVER mark as finished prematurely
- Stage19 #4 is a protected **encrypted source integration only**: real list NOT currently displayed inside installed Android admin screen because server-only Firebase Secret Manager private key and authenticated Callable are NOT live. Key has been successfully downloaded by the owner to the phone. ChatGPT Library upload of a duplicate key backup FAILED due to Library storage quota; do not discard the phone key file.
- Stage19 #7/#8 self-use/gifts: server drafts/emulator tested, but UI action bridges are disabled; no live gift/lock has happened.
- Stage19 #9 the log UI is present, but actual dated gift history only appears after verified backend read is deployed.
- Stage19 #10 fixed admin color for recipient profile across full DEDA UI, original-ID alias routing and friend/share compatibility still require acceptance and release checks.
- Stage19 #11 full Android16 smoke/in-place-upgrade regression & owner testing are pending AFTER real backend integration is reviewed.
- Stage19 #12 private signed APK not built from this branch yet; DON'T imply owner can install a completed release.
- Stage18 checkout stays OFF until immutable global stock, gift/earned/server wallet reconciliation and transaction receipts/alias routing are verified.
- No Firebase production deploy, Google Play AAB, store price changes or money deducted.

## Next safe actions
1. Prepare audited read-only Firebase Callable/Secret Manager operation, package staged server files in the function's deployable source WITHOUT exposing decryption key or first 100 in APK. User's explicit approval before touching live Firebase.
2. Retest real owner-inventory collisions and 100/100 loaded from protected server, admin roles including revoked credentials; client cannot read catalog unless authorized.
3. Complete gifted-use color and ownership display on profile, preserve friends/search/share and existing wallet.
4. Finish Stage18 real checkout purchase safety: bought 5,000 designs, 10,000 stock, verified server diamonds (earned, rewarded, gift and GM).
5. Perform real Emulator and Flutter/navigation regression tests, then generate ONE signed private APK with same signer/Android16 cold-start & in-place update. Owner real-phone approval before Play upload.

Master 12-point contract remains: `docs/DEDA_STAGE19_100_EXCLUSIVE_ADMIN_MASTER_12_POINTS_2026-10-19.md`.

## 2026-10-19: Current canonical manager revocation protection (QA success)
- All Stage19 read, self-use and gift operations now independently require canonical admins/<authUID> to remain active, status active and role general_manager. Prior admin_entry_access allowlist remains necessary, but is not sufficient.
- For self-use and gifting the canonical role proof is read within the SAME Firestore transaction that writes exclusive ID and its lifetime color. Gift protection added as an opt-in option to the staged point15 backend; default legacy behavior unchanged.
- Dedicated Firestore Emulator test revokes admins/<uid> role to employee while leaving the older entry-access record present; full 100 catalog read, self-use and gift are all blocked. No registry writes take place.
- Firestore Emulator run 39258585160 PASS 10/10, including role revocation, collisions, 10-way concurrent gift contention, and immutable lifetime colors.
- Stage18+Stage19 source integration run 39258585219 SUCCESS (39 Node tests and 6 Flutter widget tests). NOTE: these are staged/off in production, not real checkout/owner grants.
- Production functions/index.js and Android release/source were not changed. Next gate remains owner-approved, secret-manager-backed live callable and wallet/alias rollout; no automatic release.

## Stage19: Firebase deploy-root READ-ONLY preview bundle, still no publication — 2026-10-19
- The owner-original encrypted 100 remains the single source of truth in server_private/catalogs. New scripts produce a verified server-side runtime bundle of exactly four files: authenticated AES-GCM ciphertext plus three existing audited reader/decryption dependencies, copied into functions/stage19_private/runtime ONLY in throwaway CI. No plaintext originals, owner secret or user account data in APK or public repo.
- functions/stage19_private/stage19_owner100_readonly_NOT_EXPORTED.js defines ONE preview onCall factory, precisely dedaStage19Exclusive100Read, with enforceAppCheck=true and secrets:[defineSecret(DEDA_STAGE19_ADMIN100_AES_KEY_B64)]. No gift, self-use, purchase or wallet callable is exported. It is NOT imported into production functions/index.js and is NOT a deployed callable. Secret contents never logged.
- Source packaging script tools/deda_stage19_pack_readonly_owner100_functions_2026_10_19.js copies canonical ciphertext and audited reader modules into functions runtime with exact SHA256 byte verification; refuses existing runtime and any production index.js export.
- GitHub Actions https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39260134097 PASSED: seven unit tests verify one-function read-only export, AppCheck/auth/parameter validation BEFORE accessing Secret Manager, no forged role or UID, missing-secret fail-closed, encryption packaging and release isolation.
- Firestore Emulator real integration https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39260634718 PASSED: 11/11 emulator tests, including actual read-only callable + synthetic secret with real Firestore data, revoked admin, AppCheck, ten parallel gift races and permanent color. This does NOT use the real owner's private key or modify production users.
- Stage18+Stage19 combined source and Flutter QA https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39260634883 PASSED: 39 Node tests plus 6 Flutter widgets, no production changes.
- Total independent suites at this checkpoint: 7 new read-only callable + 11 Firestore Emulator + 45 combined source/Flutter = 63 verified test cases. These are separate suites, not 63 tests within one workflow.
- UNFINISHED: link the preview callable into production functions only AFTER the owner explicitly approves a controlled read-only deployment; secret still lives on owner's phone and has NOT been installed into Firebase Secret Manager or backed up in ChatGPT Library (quota was reached). No APK/AAB built. Admin100 remains hidden on installed device until read endpoint deployed.
- When approved, import new read-only factory in a carefully reviewed functions/index.js change, store secret only in Google Secret Manager (never paste into chat/GitHub), package exact runtime ciphertext into functions deployment and compile read flag true in signed owner-only APK. Manager grants, purchased card/ID checkout and recipient permanent-color profile remain gated until separate checks and approval.

## Stage18 real 10,000-diamond Firestore Emulator checkout — green, still NOT LIVE
- Production-neutral 10k checkout source tools/deda_stage18_private_atomic_identifier_checkout_2026_10_19.js was exercised with REAL Firebase Firestore Emulator optimistic transactions. Unit-memory-mock-only tests were insufficient to prove races; this new QA closes that verification gap.
- Isolated emulator test test/deda_stage18_verified10k_checkout_firestore_emulator.test.js: 10/10 PASSED at https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39262366835 . Includes exact server-only 10000 price, owner-approved group 002 sale stock, atomic global sale registry + permanent alias + receipt, idempotent retry, two buyers racing one ID, same buyer racing two IDs against insufficient verified funds, false inventory, local 999999 diamonds excluded, old DEDA share ID collision, and client Firestore write denial.
- Additional manager-wallet safeguarding: GM personal server diamonds count only if the CURRENT canonical admins/<auth uid> record is active, status active and role general_manager, in the same Firestore transaction as debit. A stale admin_entry_access record alone is NOT enough. Verified split 3000 server gift + 7000 personal manager diamonds and denial after revocation, leaving wallet and stock unchanged.
- Combined Stage18 + Stage19 source + Flutter QA run https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39262366832 SUCCESS: 39 Node + 6 Flutter cases.
- Independent current checkpoint test suites: 7 read-only Secret Manager wrapper, 11 private-admin100 Firestore Emulator, 10 market-10k Firestore Emulator, 45 combined Node/Flutter = 73 green test cases across separate CI jobs. These are tests, NOT a release or verified real customer wallet migration.
- Stage18 5,000-diamond card style checkout was previously exercised under Stage16 Firestore emulator, remains entirely separate from this 10k ID checkout; still CLOSED on production. Live status of Group002 proposals remains proposal_only_not_for_sale, no existing stock automatically approved.
- Critical remaining production blockers: reconcile task/ad-earned/local diamonds into a non-double-counted authoritative server wallet after audited migration; owner verify every sellable group002 stock; app-wide aliases/friends/shared locations; secure Firebase Callable with AppCheck + idempotent request; owner-approved server-side privilege changes; signed APK cold-start/in-place Android16 and owner real-phone QA. DO NOT deploy or flip a purchase flag before these are verified.
- Owner personal private AES key for Group001 remains on owner's downloaded phone file; ChatGPT Library storage limit blocked extra upload. Never copy key into code, CI, app, public GitHub or chat transcripts.
