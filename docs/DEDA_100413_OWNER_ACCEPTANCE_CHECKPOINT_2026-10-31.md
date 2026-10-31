# DEDA 100413 — owner QA checkpoint — 2026-10-31
Status: SOURCE QA green; **NO APK, NO PLAY, NO FIREBASE DEPLOY**.

## What is actually changed
- Reassembled actual accepted DEDA 100396 signed-app source through 100410.
- Integrated 100411 friend-ID copy and canonical recipient resolution (no comma, no bidi, no guess).
- Integrated 100412 responsive prize form (stable Firestore stream, local draft reason >=8, distinct error messages, no payout).
- In 100413, restored the missing 100409 owner-verified public projection hook in the shared active-ID owner reader; normal IDs are no longer skipped at that verified publication point.
- Removed N * expensive owner-only Firestore queries from public friend/leaderboard labels; the owner-only read runs once from Home without blocking first frame.
- Preserved the original fail-closed administration card visibility and existing server manager/session/phone checks; removed only the redundant admin-entry *gateway read* on each tap.
- No original account-ID rekeys; gifts, wallets, XP, frame ownership, leaderboard score keys and Firestore security rules remain untouched.

## GitHub verification
- Run: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41227773901
- 21 of 21 Flutter source tests pass: friend copy 4, prize draft 4, unified active ID 4, authenticated publication 4, GPS/account isolation 5.
- dart analyze completed without compile errors; existing lint/info issues remain.
- No physical phone/tablet validation or live-user Firestore migration executed.

## Critical unresolved owner acceptance
1. The public normal-ID projection can only be published for a fully authenticated, server-verified owner. Older users whose `users.sharePersonalId` is missing may be blocked by the *already-live* Spark security rules even though Stage71 active ownership accepts their legacy route. Do NOT assume every old friend's ID is now shown: audit this legacy condition and request explicit owner approval before any production data migration/rule change.
2. Never display an original ID of a user with an unconfirmed premium status as a fallback. Missing projection remains unknown until safe server proof.
3. The admin login **first-attempt** transient network/auth failure is NOT fixed. The improvement eliminates one redundant read on admin tile tap, not credential/login flow delays.
4. Verify the 100413 Home owner prewarm against cold-start asynchronous Firebase auth; if auth is not ready yet, a later authenticated retry may be needed.
5. Check actual friend profile + copying + recipient share + received share, leaderboard rank 2 and all competitors, administrator entry and first login, prize reason retention and atomic plan write on Android handset/tablet before approving any APK for release.
6. Private owner build only; no Google Play deployment and no automatic diamond settlement.

## Safety
Reference 100342 / 100396 and the 100410, 100411, 100412 branches remain untouched. The 100413 branch is a separate candidate. No modifications to live Firebase, diamonds, or users' records in this QA run.
