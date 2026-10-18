# DEDA checkpoint — 18 Oct 2026 — NO BUILD

## Verified reference and branch
- Immutable accepted phone version: 100342
- Protected recovery branch: backup-deda-100342-phone-verified-exact-ci-2026-10-18
- Separate working branch: deda-ids-staged-no-build-2026-10-18
- No APK, no AAB, no Firebase deploy, no Play publishing until the owner asks.

## Point 1 — Identifier management UI, safely staged
- In Account Information > My identifiers, Edit and Switch open a panel **on the same page** (not the portrait/frame editor).
- Original deterministic personal DEDA ID remains unchanged.
- Real premium ownership enumeration and global activation are **NOT implemented**, pending verified account ownership and all share/friend consumers. Disabled activation prevents fake switching.
- Stage modified only: tools/stage_deda_point7_compact_ids_100342.py
- Deferred widget tests: test/deda_point7_compact_ids_100342_test.dart

## Point 2 — Replace exactly THREE locked frame slots (3,4,5)
- Retain 6 total slots: free styles 0..2 **unchanged**, replace locked 3..5 only.
- Premium order in right-to-left second gallery row:
  - slot 3: royal emerald, exact uploaded 850×850 RGBA WebP
  - slot 4: royal gold, exact uploaded 850×850 RGBA WebP
  - slot 5: royal rose, exact uploaded 850×850 RGBA WebP
- Uniform interior geometry calibrated against the transparent center: portrait box at x=26%, y=29.2%, width=48%, height=32.5%; BoxFit.cover **inside clipped oval**; ornaments overlay without stretching photo.
- Same saved avatar for all three; do not shift or change image preference.
- Locked tiles remain visibly locked but NOT veiled, so artwork and photo are visible.
- Tapping a locked tile only sets local _previewFrameStyle, with pinned hero preview; it never persists a frame, makes a purchase, spends coins/diamonds, changes the owner's inventory or touches Firebase.
- Both gallery and public-profile renderers share DedaFramedAvatar; free renderer branch is untouched.
- This is staging code only, **not an installed/validated release**.

### Mandatory exact source artwork (no approximations or generated replacements)
Bundle must be uploaded to repository as:
assets/deda_royal_frames_originals.zip

It must contain exactly these three files at ZIP root:
- royal_frame_0.webp | 259300 bytes | SHA256 9ae19c51cbc7394299b361cb1f8dd07e015898b43e4ecaca0fdb0f4b207a12b5
- royal_frame_1.webp | 260184 bytes | SHA256 a31029b56a4a989feaec25a119b58a8a90c378e6ba3159705d2d5e537f4f299e
- royal_frame_2.webp | 247938 bytes | SHA256 dbd02ca458cf9e94e3a0005134d2b61cb0bdaaf7729893a8cbfe5f75123c249f

**BLOCKER:** The ZIP was prepared from the original user-uploaded files but is not yet in the GitHub repo; code integration must not be labeled complete until the exact archive is committed and static/Flutter widget tests pass. No build was performed.

### Exact staging order after full 100342 source reconstruction:
1. tools/stage_deda_royal_hero_2026_10_17.py
2. tools/stage_deda_royal_avatars_step1_2026_10_17.py
3. tools/stage_deda_point7_compact_ids_100342.py
4. tools/stage_deda_sticky_edit_preview_100343.py
5. tools/stage_deda_royal_locked_frames_2026_10_18.py

These are **final downstream stages** only; preserve all earlier historical source reconstruction stages from the accepted 100342 workflow. The stage is fail-closed if original artwork, hash, or expected source anchor is missing.

### Deferred QA
- Flutter analyze reconstructed lib/main.dart.
- Widget test test/deda_point7_compact_ids_100342_test.dart.
- Widget test test/deda_sticky_edit_preview_100343_test.dart.
- Widget test test/deda_locked_royal_frame_preview_2026_10_18_test.dart.
- Static binary hash and 3-slot guard.
- Later, after owner approval ONLY: signed APK build and real install/cold-launch/login/admin test on phone, plus restore check.

## Safety
Do not modify the stable 100342 branch, main, existing accounts, Firebase rules, functions or balances. Never mark source staging as on-device success. Continue adding agreed points to this same working branch, one at a time.
