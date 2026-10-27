# Stage22 DEDA verified week ranks — tap-to-profile and friend, owned frame
Date: 2026-10-28. User owner asked to continue to real weekly league with every ranked player's true actively equipped frame and click-to-open public profile or add friend. Original APK 100393 remains safely on phone and QA 100394 separate; no live backend changes.

## Concrete protected source changes
- New `lib/deda_weekly_leaderboard_tap_surface.dart`: wraps ANY fixed-size rank content without extra scrolling, changes only interactivity. On verified OTHER user's card opens action bottom sheet. Sends no request automatically. The existing authenticated main-app coordinator must provide public-profile and DedaSocialService friend request callbacks. Unknown, pending, accepted and self relation prevent duplicate/self request.
- `lib/deda_weekly_leaderboard_page.dart`: top-three podiums and rank 4–10 identities (and owner's viewer row, self-disabled) now wrap their existing visual geometry in the new pressable. Optional `drawOriginalEquippedAvatar` receives only the Stage21 **server-backed identity and equipped styles**. Missing evidence or callback retains neutral avatar; no viewer's locally equipped cosmetics borrowed.
- `test/deda_weekly_leaderboard_verified_rank_tap_stage22_test.dart`: trusted gold podium tap and optional frame, rank 4 tap, pending relation and self block, missing server proof safe fallback; existing phone/tablet fixed viewport and Stage21 strict DTO regression rerun.
- No production Firestore, original DEDA `main.dart`, level XP, task claims, social friendship database, real wallet, frames owned, weekly rewards, Firebase/Play/signing changes.
- New branch `deda-weekly-stage22-verified-rank-tap-own-frame-qa-no-deploy-2026-10-28` based Stage21 verified ID/equipment schema. CI `.github/workflows/qa-deda-weekly-stage22-verified-podium-tap-frame-no-deploy.yml`.

## Honest delivery boundary
- Stage20/21/22 provide a verified view contract and UI hookups **only**. Current real DEDA 100393 leaderboard has no approved live XP authority or outfit proof issuer, so there are no REAL ranked players to tap. Callbacks to the actual existing friendship navigation are NOT wired by original app until the security-backed account issuer and canonical social user mapping are verified.
- Missing signed server proof disables interactions and frame rendering rather than displaying invented names or spending diamonds. NO APK from this stage and NO live Play update.
- Next actual server prerequisites: privileged successful original daily TASK claim +20 level XP transactional proof, validated current/previous Baghdad weekly calendar, per-account immutable public identity and current equipment proof issuer, private rules and AppCheck read, then integrate callbacks to DedaSocialService and public profile with real two-device tests. Afterwards monthly top-ten owner-only archive and audited earned-wallet real payout.

Rollback: owner-approved 100393, 100394 owner private candidate, and Stage21 root unchanged.
