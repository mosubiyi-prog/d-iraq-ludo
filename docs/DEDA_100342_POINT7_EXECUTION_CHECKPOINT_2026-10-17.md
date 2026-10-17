# DEDA 100342 — Point 7 started; owner requested full next-release development
Date: 2026-10-17; state: **work in progress, NOT approved/released**.

## Safety branches created
- Immutable recovery for accepted 100341 before new work: `backup-deda-100341-before-point7-and-frames-2026-10-17`, initially at `941e67be44e8c44da778e57fbcbbc50842164f97`.
- Development: `point7-compact-ids-sticky-preview-frames-2026-10-17`.
- Previous recovery: `backup-deda-100340-before-profile-royal-2026-10-17`.
- Do not touch production or Google Play.

## Real source audit
- Downloaded `DEDA-100340-PROFILE-STEP1-POSTRECONSTRUCTION-SOURCE-ONLY` artifact (GitHub Actions run 38982080679). Inspected 1,132,528-byte assembled `main.dart`; `lib/main.dart` raw repo is not equivalent.
- Existing `DedaAccountInfoPage` shows only phone and account type, exactly as owner's screenshot.
- Existing `DedaEditProfilePage` shows an avatar preview INSIDE a scrolling ListView: sticky preview is NOT yet implemented.
- Royal stage 100341 added three approved avatar assets, safe old-choice migration, top-left edit pencil, and ID read-only in edit profile. 100341 private QA run 38990051627 previously passed and owner confirmed large royal couple portrait on real phone; do not infer other pending tasks are complete.
- Current core `DedaBackend.personalShareIdForPhone(phone)` derives original personal ID from account key/phone; `deda_share_ids` ownership registration and Firestore `currentUserHasShareId` rules depend on this existing account/UID setup. No verified owned premium ID routing/activation is present. **Never merely change a client-side ID label**. Atomic ownership/lookup migration, legacy aliases, friend/public profile and send/receive location invariants need separate emulator tests before enabling.

## Implemented now on development branch
1. `tools/stage_deda_point7_compact_ids_100342.py` adds a compressed real-ID card to **Account information**, stylistically sized similarly to the existing yellow level card, shows original ID as small inline chip; supports real "Edit" navigation. The "Switch" control is intentionally disabled with explanatory notice, pending verified globally consistent ownership/routing. Phone and account-type controls preserved; no Firebase, diamond, friends, or maps mutation. Commit `723109065fc6dfb669b31430b1d793045daeb2b2`.
2. `test/deda_point7_compact_ids_100342_test.dart` asserts the card size <=126 logical px on test screen, real ID displayed, and switching is disabled. Commit `80fa55762e7d5de10be69e37d1acdff46ea9b81a`.
3. Private safe build workflow `.github/workflows/qa-deda-100342-point7-compact-ids-private-apk-no-deploy.yml`, commit `01b6796ece7149c718287c90e4151e8a04fc3f5d`; reconstructs accepted 100341 source, applies point7 UI stage, re-runs previous migration, diamonds, security and Flutter tests, builds signed **100342** APK with no publish.
4. Latest checked QA run `38995553199`: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38995553199 . Was **IN PROGRESS** as of checkpoint. Do not claim APK success until run jobs and artifact verified.

## Still NOT done (critical)
- Real authoritative owned premium identifiers and safe switching, original ID/aliases, all ID-based routing, Firebase rules + Emulator tests. No backend update was made.
- Sticky fixed-size avatar preview under edit appbar with scrolled image/frame choices and temporary locked-frame previews.
- Three premium transparent royal frames (850x850 WebP from user: 1000097470.webp, 1000097473.webp, 1000097486.webp), precise inner aperture, elegant animated shimmer, three free legacy frames unchanged on first row, paid preview-only frames on next row; no prices until owner sets them after remaining frames.
- Full Flutter integration and real-device screenshots/user acceptance. No Play upload.

## Next action
1. Check run 38995553199; if failed read exact job logs and fix only on work branch, trigger a new private QA build. Confirm compact card on real phone against level-card reference (do not infer visual match from analyzer).
2. Implement ID ownership/routing in isolated emulator-tested stages. **Do not activate unverified premium identifiers.**
3. Sticky preview + new image/frame asset staging, paid-only temporary previews with motion, then owner tests. Keep fixed/scrolling layers separate.
4. Use `docs/DEDA_NEXT_RELEASE_LOCKED_SCOPE_2026-10-17_BEFORE_IMPLEMENTATION.md` as owner contract; review every bullet before claiming complete.
