# DEDA 100377 — exact owner artwork integration for six earned level badges

Owner's source image: supplied `1000099764.png`, original 1536×1024,
3 columns × 2 rows; reference SHA256 `7465a291854fc937486886dde6b08b348f0899eef0b26c8be7e732a892289f4b`.
This is the owner reference, NOT an AI-generated substitute.

## Completed safe-source integration
- GitHub blob `b8e1a019b7b31a249d1042e1b9a592747bb24514` committed as
  `assets/deda_owner_level_badges/owner_approved_six_rank_badges_768x512.webp`
  at commit `7dba8e739d7cdd2179efe36c0e4a0b8e01ec7288`.
  It is a 768×512 WebP composite, 98,380 bytes, SHA256
  `e1bccc20524499208c694f71df9432a6c3b75be0a08ad50de99e91cf723672f9`.
  Each 256×256 thumbnail is only scaled from the correct original screenshot
  panel, never redesigned or replaced.
- Exact gallery visual mapping:
  1. top-left gold / الذهبي
  2. top-middle silver / الفضي
  3. top-right emerald / الزمردي
  4. bottom-left diamond / الألماسي
  5. bottom-middle royal / الملكي
  6. bottom-right legendary / الأسطوري
- `pubspec.yaml` includes the new assets directory.
- `lib/deda_100377_level_achievements_page_staged.dart` uses
  `DedaOriginalSixLevelBadgeArt` with 3×2 sprite cropping.
  Each verified/enrolled tile shows the original artwork even when the
  *status remains verification pending*, with lock indicator.
  Gallery ordering and the per-tier progress lookup are independent:
  do NOT infer Gold Level 1 from a numeric index or corrupt levels.
- Source gate `test/test_deda_100377_point10_owner_six_badge_art_source.py`
  asserts the actual WebP bytes and SHA plus no write/spend methods.
- Flutter widget `test/deda_100377_point11_achievements_locked_preview_widget_test.dart`
  asserts all six image crops load from the real Flutter bundle and still
  cannot show unverified earned badges.
- Dedicated Flutter QA https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39835585787 **SUCCESS**.

## Hard release restrictions (do NOT call point10/11 complete)
- Six badges are LEVEL-ACHIEVEMENTS only; purchasing old cosmetic badges has
  no authority over them and there is NO diamond/coin payment here.
- `DEDA_100377_LEVEL_ACHIEVEMENTS_APPROVED` defaults OFF.
- Preliminary Silver 1, Gold 10 policy conflicts with owner's existing
  `مستوى ذهبي 1` wording. This MUST be reconciled against server-proven
  account rank and the owner's rank requirements before granting/unlocking.
- Exact original owner art linked to the source gallery does not prove it
  shows correctly in the installed phone/tablet version. Owner-signed private
  APK and device acceptance still required.
- The three approved Point05 moonlit avatars remain unverified/missing.
- Source compile/run QA for all 13 points is separate:
  https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39835628763
  (check latest conclusion; this document does NOT claim final result).
- Existing released app, rollback branch, Firebase, gem balance, points,
  level, owner entitlement and Google Play are untouched.
