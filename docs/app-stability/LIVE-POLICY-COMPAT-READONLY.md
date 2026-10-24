# Current policy compatibility — GET only, no deployment

24 October 2026 Baghdad. This stage obtains the CURRENT published Firestore Rules definition and checks an additive archive extension on local synthetic data. It does not fetch Firestore user documents, publish a ruleset or change a release.

## Read and privacy boundary

The established CI service account is used only in the two explicit read steps, with OAuth scope `https://www.googleapis.com/auth/firebase.readonly`. ReadOnlyRules exposes GET only for the exact project's cloud.firestore release and immutable ruleset resources, with redirects disabled. Credentials are parsed in memory and never written or printed. Emulator steps have no service-account credential environment and assert a localhost demo project.

Full original/merged policy files and emulator diagnostics remain in a separate mode-700 runner temporary directory (files 600). Only a single sanitized JSON report is uploaded: hashes, counts, dates and synthetic permission observations. No policy source, actual emails/IDs, user documents, keys, APK or production configuration is uploaded. The private/public output trees cannot overlap or include the repository.

A release GET precedes and follows snapshot retrieval; another follows emulator completion. A changed ruleset invalidates the result. The exact immutable source SHA256 is recorded. Four successful Rules API GET calls are expected; OAuth token acquisition is an authentication request, not a rules/data mutation.

## Additive merge boundary

The merger lexes comments and quoted strings, locates the single Firestore documents scope, prefixes the three new helper names, and inserts only the four dedicated archive/reconciliation namespace blocks. It excludes the standalone candidate's users/session/default matches. Removing the inserted span restores the original text byte for byte. Existing namespace/helper collisions, ambiguous scope, malformed source, overlapping wildcard grants and source-size overflow stop the review. It never modifies the original repository rules file or live policy.

An existing wildcard grant that could bypass server-only receipt/state protection is not silently retained and called safe. That case stops for review rather than weakening the new contract or changing old rules automatically.

## Local-emulator comparisons

72 checks: 18 legacy permission observations per policy (36), 16 baseline private-namespace denial probes, and 20 merged-policy archive/server-state checks. Synthetic records cover owner/other/manager/unauthenticated actors, a recognized general-manager list permission, existing self-profile update, sessions, public places, requests/support, gift-wallet reads, admin-entry probes and denial of client privilege grants. Both policies are loaded separately into the SAME localhost demo emulator with clean seeded fixtures.

Merged checks cover immutable evidence creation/readback, replacement UID/install of the same fixture account, denied other-account/admin/unauthenticated archive access, server-only receipt/migration/projection writes and preservation of legacy wallet/profile records. The legacy matrix is compared exactly before/after. This validates specified fixtures and additive preservation; it is not all-app UI testing, actual PIN recovery or production rollout.

## Validation status

The initial CI source `5a529156854f38bf197a8c45a824909ebfe54c70` passed both [published-policy comparison 40087368309](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40087368309) and [all four source regression jobs 40087368231](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40087368231). All 72 synthetic comparisons passed, including exact equality of the 18 old permission observations before/after. Four Rules API GETs succeeded; zero production document API calls and zero production mutations. The release remained unchanged throughout. Original source SHA256: `9ef41b19bc07bc67052ea76d0d7099f497f0430f4f8d013ac2bc46455f89beed`. Candidate source SHA256: `1f4156dd8731b6267c1ac45d128b63821ba7c4f76edc1d26fc640b787c227d60`.

The downloaded artifact contained only the sanitized report; ZIP SHA256 `f31afb2ccd888d8086576e00de48333556d685090145e0672a3e7f032ecd6714` matched GitHub. The current checked report, including the later PIN extension below, is LIVE-POLICY-COMPAT-RESULTS-2026-10-24.json; the initial 72-case version remains in git history. Full rules were neither downloaded here nor committed. These results apply to that immutable ruleset and the specified synthetic fixtures, not future policy changes or full-app behavior.

A follow-up preserves UTF-8 bytes explicitly through private-file storage and verification, including CRLF policy text. Local Python checks are now 48/48; the byte-preserving follow-up passed published-policy run 40087907277 (72/72), and the subsequent PIN run below validates the same implementation. No Dart/native transport module, runtime callsite, app signature, wallet or production rule is modified here.

Official API scope references: https://firebase.google.com/docs/reference/rules/rest/v1/projects.rulesets/get and https://firebase.google.com/docs/reference/rules/rest/v1/projects.releases/get . Both document firebase.readonly for these GET operations; create/update release operations are not implemented by this tool.


## PIN-to-archive compatibility follow-up

The emulator suite now additionally attempts 10 client-rule cases on each original/merged policy, plus one bridge from client-proven sessions to the new evidence path (93 total cases). The separate synthetic account has NO privileged-seeded session/users/profile/credentials. Normal client requests create its directory/credential transaction, submit PIN proof, open a session, create its profile/users binding, sign in from a replacement UID/install, and restore the trusted install on another UID without a new PIN proof. Denial cases cover wrong PIN, untrusted install, cross-account session switch, foreign-UID writes and unreadable credential/proof documents. The merged bridge must preserve original capture provenance while the two newly client-proven UIDs read it.

Payloads and order were compared with immutable 100380 `deda_pin_auth.dart`, SHA256 `884ffcc7eeb81533f22507670976b390269402ea8591c46745b6df182c6cc786`. Token identities are still rules-unit-testing fixtures. This checks Firestore contract compatibility; it does not execute Dart PinAuth, actual anonymous token issuance, UI local lockout, physical phones or app restoration. This follow-up passed [run 40088043427](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40088043427) on source `c0995d64f9701a27871a9af788e351113db206ca`: **93/93** with no failures. Original and merged policy hashes match the initial comparison; four GETs and the release lease stayed valid. The downloaded ZIP contained only rules-compat-report.json and matched SHA256 `a2e207a8d6acd90a1098b9256a3b81bc06b6a241119097c67e35b0da7c7ae1bc` (artifact 12557553662). All 21 added PIN/bridge checks passed. Full [source-regression run 40088043453](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40088043453) passed all four jobs. Logs verify Python48, Node78, standalone emulator74 and measured Dart/widget groups 38/30/13/21/36/35/43/27/40/29; selected strict analysis had no issues, with the same 181 inherited main warnings/infos. No further code changes followed these checks.
