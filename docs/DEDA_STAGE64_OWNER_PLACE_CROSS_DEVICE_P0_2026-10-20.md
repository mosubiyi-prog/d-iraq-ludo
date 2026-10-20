# DEDA Stage64 — P0: Recover published owner place on a replacement phone (20 October 2026)

**BLOCKS NEXT PLAY RELEASE AND OWNER19 COMPLETE APK. NO LIVE CHANGE / NO APK / NO DEPLOY.**

## Real support report
A DEDA place owner reports an approved place still visible on the public map after over a month. After moving to a different Android phone and signing in using the same name and phone number, the old place is absent from "Manage my place". Do not call the place deleted: its publication and old ownership have NOT been inspected in the real database.

## Confirmed code-level mechanism
- The accepted original OwnerPlacePage stores its current `_placeId` in `SharedPreferences` key `deda_owner_place_id_v2_<accountKey>`. This local key does NOT move with the SIM/phone number or to the replacement device.
- `_OwnerPlacePageState._loadState()` only reads the locally cached ID, optionally migrates an OLD key from that SAME device, then loads the known document by ID. With no key it falls back to `_loadDraftOnly()`. There was no authenticated Firestore re-discovery of approved places in that path.
- `DedaPinAuth.signIn()` creates a `deda_sessions/{newAnonymousUid}` with accountKey after checking the DEDA six-digit PIN (or previously trusted installation). Anonymous Firebase UID may change between phones.
- Some old helpers only search `published_places` by `ownerUid`; these do NOT find a place under a different UID. Other helpers use `accountKey`, making behavior inconsistent.
- Account normalization in public `accountKeyForPhone` only removes non-digits (07... vs 9647... may differ). DO NOT silently match arbitrary numbers/name or transfer account ownership. The published `accountKey` might be missing on old documents. No live user case is concluded until controlled authorized inspection.

## Stage64 source fix (NOT DEPLOYED)
New script `tools/stage_deda_owner_place_cross_device_recovery_stage64.py` patches the **exact reconstructed 100359 owner Flutter source**, never raw historical `lib/main.dart` alone:
1. `DedaBackend.recoverPublishedPlaceForSignedInOwner(expectedAccountKey)` verifies that the current PIN-authenticated/trusted DEDA anonymous session's Firestore accountKey exactly matches the active profile accountKey.
2. Read only `published_places` where `accountKey == verified session accountKey AND published == true`, max 2. Never match only name, place phone, public location, ownerUid or raw account input.
3. If 1 match, cache ONLY the returned immutable document ID locally, then existing owner page read/edit uses the same place approval and analytics records; no rewrite of `ownerUid`, followers, likes, title, map pin, photo, date or approval.
4. If >1 match, session invalid, Firestore permissions/index fail, or account session changes, **fail closed**, display an Arabic/English error, keep editing/duplicate creation disabled for that state. No local success or manual transfer.
5. If zero matches under a verified session, do NOT claim the missing place has been deleted, or attempt matching by unverified phone format; manual escalation and server-side identity review for legacy records is required.

## Outstanding acceptance gates
- Reconstructed-source Flutter analyzer and owner-page regression tests; **emulator real-document query tests** against staged rules and composite-index check. Production Firestore rules may differ from repo, and Stage62 proved live drift.
- True PIN-recovered same logical account on 2 phones (different UID), exact original place and approval number, no duplicate; stranger/new unverified UID cannot claim; mismatched normalized phone, old UID-only / missing accountKey, >1 place, offline, revoked device, expired session and sign-out all fail safely.
- Verify downstream owner-only color/branding Cloud Function and like/follow access; `ownerUid` is NOT migrated in Stage64. Design server-side owner-binding canonical logical account after authenticated recovery before claiming full continuity (owner notifications, all permissions).
- Support case manual recovery must be audited: verified person, verified account, original immutable place ID/approval, admin-assisted change only with signed server authorization, never by matching just name or phone. Do NOT delete or recreate the user's original place.
- Security: harden canonical phone formatting and DEDA PIN authentication/recovery (server throttle, no session spoofing); stage is NOT a phone-SMS proof system.
- Release acceptance: physical new Android phone, same DEDA account, all original place data/engagement and editing restored; original phone unaffected; no unrelated account accessible.
- Stage63 original nineteen premium-ID/store acceptance gates remain separate and NONE is considered passed by this code-stage test. No Play deploy while either P0 owner recovery or 19-gate functional case is unresolved.

## Safeguards
Use branch `deda-owner-place-cross-device-recovery-stage64-2026-10-20` derived from `c1a27b297088868d367f3babb2d9218d1b5dd14b`. Original 100359 installed backup, 100360 owner's visual APK, published Play version, all real accounts, private 100 original identifier key, Firebase Functions and Firestore published rules MUST remain untouched. No premature APK or AAB.


## Stage65 continuation — joined real shop/admin + owner-place recovery (20 Oct 2026)
- Existing Stage64 automation run [39490604840](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39490604840) is verified **SUCCESS**, both Firebase Rules Emulator and the exact reconstructed Flutter owner screen, without APK or deployment. It confirms implementation source test only; not customer phone recovery.
- Stage65 workflow `.github/workflows/qa-deda-stage65-owner19-store-admin-phone-recovery-no-deploy.yml` rebuilds the exact accepted 100359 Flutter application, stages the complete previously audited Stage35/39/42/48/49/50/51 premium shop / four original art / admin and social identifier view, and finally injects Stage64 owner recovery in that same generated source. It compiles analyzer/widget tests and guards removal of mock purchase lab. Run [39492084847](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39492084847) initiated; outcome must be read from Actions. **NEVER claim it green without verifying final result.**
- Stage63 independent real Firestore Emulator integrated transactions [39484637273](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39484637273) previously passed all 6/6 isolated end-to-end cases. **Still NOT real customer store/admin**: production `functions/index.js` has no exports for the 15 premium purchase/GM routes; Stage59 enforces local-demo emulator only; Firebase project GitHub service account lacks `cloudfunctions.functions.list/get/create/update`; published Firestore wallet rules differ from proposed source; real Secret Manager key/100 inventory/verified spending wallet/AppCheck not activated. Never set flags to ON or charge local diamonds as a workaround.
- Nonnegotiable owner deliverable remains ONE actual signed private phone APK with WORKING purchases (5k card / 10k approved ID), four real persistent styles, exclusive GM original100 display/self-use/gift/history, existing users' verified wallets, and safe cross-device owner-place recovery. Then Android16 in-place upgrade and owner phone tests. **NO Google Play publishing** unless owner explicitly approves later.
