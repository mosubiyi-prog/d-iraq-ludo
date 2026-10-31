# DEDA 100419 — OWNER APPROVED Firebase Stage71 Public Active-ID READ ONLY — deployed

**Scope:** LIVE Firebase production Firestore Rules for `deda-25b88`, no APK build, no Google Play, no user document mutations, no wallets or prizes.

## Actual verified release
- GitHub Actions run: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41243025369
- Job: `124660645831`, result: **success**.
- Previous exact production ruleset: `projects/deda-25b88/rulesets/edb6ba64-21e7-4d90-8ce0-8d506f1191fc`
- Previous SHA256: `ca282cfbb31dae3e934bfb833c4cdc8b5b1714fc27686ffaf2d7296f7436814f`
- **Currently deployed and independently read back ruleset:** `projects/deda-25b88/rulesets/9f11d792-0d1e-4a28-bd72-606459b5c659`
- New SHA256: `273d20ffa0196709af7742dbf8f3fb4137edc2f3c7bb56f5e80d2c3506c62cb1`
- Rollback metadata uploaded as GitHub Artifact `DEDA-100419-OWNER-APPROVED-ACTIVE-GET-ROLLBACK-RULESET-METADATA`, ID `13057459163`.

## Exactly what changed
- Changed ONLY `allow get` for `deda_stage71_active_identifier/{originalId}`, preserving old owner GET.
- Added read for authenticated users only when original personal public route exists and is active; the row is absent (verified original route => normal ID) or contains ONLY `originalId`, `activeId`, `updatedAt`.
- All owner-only `create,update` and forbidden `list,delete` unchanged, as are all other rules byte-for-byte. Anonymous users cannot read, foreign users cannot modify selection, private granted registry remains inaccessible.

## Safety gates
- Freshly read actual live baseline matched pinned release name and SHA256 exactly.
- Rules emulator tested candidate **6 passed, 0 failed**, including legacy 340 normal/premium, unauthenticated denies, stranger update denies, owner update and private-field-denied.
- Publish script validated exact surgical difference, rechecked current rules immediately before creating and releasing ruleset, retained rollback metadata, and independently verified deployed ruleset name + SHA256 after deployment.

## Important limit
- **The LIVE Firebase read permission is active now.**
- The new 100418 Flutter legacy-reader source is gated behind `DEDA_100418_LEGACY340_ACTIVE_READ_APPROVED`, default false. Previously installed 100414 cannot use this new path without a newly-built APK containing the gated code compiled with flag enabled.
- No APK was built because owner expressly requested report before building.
- No on-device checks of three friends were done yet; don't claim their IDs display until the owner tests a signed new APK.
- Do not make Play uploads, manual Firebase data migrations, add further rule changes or rebuild until owner reviews this checkpoint and gives the separate build instruction.
