# DEDA 100344 - Owner exact-scope checkpoint, 17 October 2026

Status: DEVELOPMENT ONLY; NOT OWNER-APPROVED; NOT PUBLISHED.

## Recovery and source
Work branch: point7-compact-ids-sticky-preview-frames-2026-10-17
Immutable stable backup: backup-deda-100341-before-point7-and-frames-2026-10-17
Source reconstruction: final main.dart is assembled in the private GitHub Actions workflow; raw lib/main.dart is not the owner screenshot's source.

## Locked requirements
1. Compact account-information ID card navy royal with gold accents; current white ID chip and yellow card rejected by owner.
2. Edit opens owned ID information inline UNDER the card, never navigates to profile editing or a bottom sheet.
3. Show true original ID and all genuinely owned premium IDs (purchases and admin gifts); one active identity, all aliases reserved. Switching must propagate to friends, public profile, lookup, sending/receiving location and all clients, without touching UID, XP, diamond balances or wallets.
4. Existing share ID and gift rights depend on stable original ID. A cosmetic switch is unsafe: disabled until verified ownership registry, atomic routing and emulator security tests pass.
5. Sticky picture/frame preview directly below Edit Profile appbar. Only galleries and lower settings scroll.
6. Existing three free frames at indexes 0..2 unchanged. Three owner paid-only locked frame previews at indexes 3..5. NO price set, NO purchase and NO diamonds debit.
7. Exact original RGBA transparent WebPs 850x850:
   - gold deda_frame_gold_royal.webp SHA256 a31029b56a4a989feaec25a119b58a8a90c378e6ba3159705d2d5e537f4f299e
   - ruby deda_frame_ruby_royal.webp SHA256 dbd02ca458cf9e94e3a0005134d2b61cb0bdaaf7729893a8cbfe5f75123c249f
   - emerald deda_frame_emerald_royal.webp SHA256 9ae19c51cbc7394299b361cb1f8dd07e015898b43e4ecaca0fdb0f4b207a12b5
8. Inner transparent opening measured (center region bbox x209..640 y225..567); photograph and frame remain separate; face scaled near .39 and centered high enough to avoid crown and pendant. Confirm visually on device.
9. Trial tap of locked frame updates only pinned preview and shows معاينة فقط. It does not update saved frame/inventory/currency. New gemstone soft shimmer is confined to active fixed preview; thumbnails static for map performance.
10. Do not merge main or deploy to Firebase/Play until final owner phone acceptance and security review.

## Implementation files
- tools/stage_deda_point7_compact_ids_100342.py
- tools/stage_deda_point7_royal_inline_100343.py
- tools/stage_deda_sticky_edit_preview_100343.py
- tools/stage_deda_royal_frames_preview_100344.py
- test/deda_point7_compact_ids_100342_test.dart
- test/deda_point7_royal_inline_100343_test.dart
- test/deda_sticky_edit_preview_100343_test.dart
- test/deda_royal_frames_preview_100344_test.dart

## Still pending
Server-verified premium owned ID read-list and real switching, phone acceptance, release decision. UI must never mislead about ownership. A successful CI only means build passed.
