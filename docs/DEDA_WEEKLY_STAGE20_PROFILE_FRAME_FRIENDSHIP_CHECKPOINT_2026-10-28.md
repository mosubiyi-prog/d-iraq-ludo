# DEDA Weekly league Stage20 — verified equipped frame, public profile tap, add friend

User requested that ALL real leaderboard competitors display their own **currently equipped** authentic DEDA frame/avatar and that tapping podium / rows allows viewing a public personal profile or adding the competitor as a friend.

## Existing implementation fact check
- Original DEDA already has `DedaFramedAvatar` (in main.dart), and `DedaSocialService.sendFriendRequest`, `DedaSocialService.findByPublicId` in lib/deda_social_service.dart. Do not create a second friendship store, fake purchases, or another identity system.
- Original `DedaSocialProfile` fields include avatarStyle/frameStyle, but the legacy public social document does NOT certify currently owned and equipped premium frames for another user's account. `DedaOwner18Cosmetics` stores native owned frame data under original canonical ID and needs proper authenticated server verification. Merely reading local preferences or putting frameStyle in a client-writable profile is NOT ownership proof.
- The Stage10 FUTURE server standings issue only displayName, activePublicId and opaque participantId; active alias may legally be 4 characters. Opaque league participantId MUST NOT be presumed equal to the social service's Firebase auth UID.
- Real player standings and actual payout backend remain OFF, so current 100393/100394 league shows verified-unknown empty rows. The newly created reusable UI is NOT yet exposed in owner APK. This checkpoint avoids falsely claiming operational global profiles.

## Stage20 tangible protected code
- `lib/deda_weekly_competitor_public_card.dart`: strict typed verified league/public owner profile projection; will use existing DedaFramedAvatar only when authoritative backend evidence verifies equipped frame belongs to that EXACT original-ID owner; otherwise neutral default avatar. Supports premium @DEDA-AAAA alias and strict name/phone privacy checks.
- Tapping a verified NON-SELF competitor opens profile/friend action sheet. Existing public profile and friendship callbacks MUST be supplied by the authenticated main-app coordinator. Prevents sending a friend request for own account and disables duplicate actions for existing/pending friendships. If callback/auth verified identity missing, disabled, not falsely functional.
- `test/deda_weekly_competitor_public_card_test.dart`: widgets test genuine frame builder, profile action, request friend, pending request, self, missing proof, 4-character alias, privacy restrictions.
- CI workflow runs only code analysis/widget tests and original-account/wallet/auth/live-backend unchanged guard. No APK, no Firebase deploy, no Play, no real user changes.

## Next required integration after verified server reader exists
1. Authenticated SERVER reads verified active public ID + canonical original ID + currently EQUIPPED frame/portrait (ownership and same owner proof). The user public-profile projection must include only permitted display data, no phone, email, balances or admin status.
2. Populate DedaWeeklyServerSnapshotPair/DedaLeaderboardProfile with those fields ONLY from same verified week and signed auth session; no mock/leaderboard local QA invented frame.
3. Embed the interactive card into both podium places 1–3 and ranks 4–10, plus personal-place row, preserving no-scroll/phone+tablet layout.
4. From tap, delegate to existing public profile navigation and DedaSocialService friend request after re-fetch canonical original public social target/UID and checking friend state and viewer session. The friend request must be explicit, not sent by opening a profile.
5. QA with TWO real accounts, one frame bought/equipped, a 4-char premium active ID, not-friends / pending / accepted / self / account switch / network failures. Only then consider owner APK/production.

Stable owner phone APK 100393 remains untouched. Latest private rank-card response branch 100394 independently protected. No real weekly leaderboard deployment or diamond payout here.
