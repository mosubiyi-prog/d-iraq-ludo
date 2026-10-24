# Current policy compatibility — GET only, no deployment

24 October 2026 Baghdad. This stage obtains the CURRENT published Firestore Rules definition and checks an additive archive extension on local synthetic data. It does not fetch Firestore user documents, publish a ruleset or change a release.

## Read and privacy boundary

The established CI service account is used only in the two explicit read steps, with OAuth scope `https://www.googleapis.com/auth/firebase.readonly`. ReadOnlyRules exposes GET only for the exact project's cloud.firestore release and immutable ruleset resources, with redirects disabled. Credentials are parsed in memory and never written or printed. Emulator steps have no service-account credential environment and assert a localhost demo project.

Full original/merged policy files and emulator diagnostics remain in a separate mode-700 runner temporary directory (files 600). Only a single sanitized JSON report is uploaded: hashes, counts, dates and synthetic permission observations. No policy source, actual emails/IDs, user documents, keys, APK or production configuration is uploaded. The private/public output trees cannot overlap or include the repository.

A release GET precedes and follows snapshot retrieval; another follows emulator completion. A changed ruleset invalidates the result. The exact immutable source SHA256 is recorded. Four successful Rules API GET calls are expected; OAuth token acquisition is an authentication request, not a rules/data mutation.

## Additive merge boundary

The merger lexes comments and quoted strings, locates the single Firestore documents scope, prefixes the three new helper names, and inserts only the four dedicated archive/reconciliation namespace blocks. It excludes the standalone candidate's users/session/default matches. Removing the inserted span restores the original text byte for byte. Existing namespace/helper collisions, ambiguous scope, malformed source, overlapping wildcard grants and source-size overflow stop the review. It never modifies the original repository rules file or live policy.

An existing wildcard grant that could bypass server-only receipt/state protection is not silently retained and called safe. That case stops for review rather than weakening the new contract or changing old rules automatically.

## Planned local-emulator comparisons

72 checks: 18 legacy permission observations per policy (36), 16 baseline private-namespace denial probes, and 20 merged-policy archive/server-state checks. Synthetic records cover owner/other/manager/unauthenticated actors, a recognized general-manager list permission, existing self-profile update, sessions, public places, requests/support, gift-wallet reads, admin-entry probes and denial of client privilege grants. Both policies are loaded separately into the SAME localhost demo emulator with clean seeded fixtures.

Merged checks cover immutable evidence creation/readback, replacement UID/install of the same fixture account, denied other-account/admin/unauthenticated archive access, server-only receipt/migration/projection writes and preservation of legacy wallet/profile records. The legacy matrix is compared exactly before/after. This validates specified fixtures and additive preservation; it is not all-app UI testing, actual PIN recovery or production rollout.

## Validation status

47 offline Python checks (including previous restoration/harness checks) passed before CI submission. Node/YAML syntax and diff whitespace checks passed. Actual API access, published-policy compatibility and the planned 72 emulator checks remain pending until the workflow result is recorded. No Dart/native transport module, runtime callsite, app signature, wallet or production rule is modified here.

Official API scope references: https://firebase.google.com/docs/reference/rules/rest/v1/projects.rulesets/get and https://firebase.google.com/docs/reference/rules/rest/v1/projects.releases/get . Both document firebase.readonly for these GET operations; create/update release operations are not implemented by this tool.
