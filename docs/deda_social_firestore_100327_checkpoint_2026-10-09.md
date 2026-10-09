# DEDA 100327 — Firestore-only Telegram social trial checkpoint (2026-10-09)

User agreed to the new approach only if secure and beneficial. Avoid Cloud Build (Iraq country selection unavailable in Google Cloud account).

Branch: deda-social-firestore-no-functions-100327-2026-10-09, based on 100326; protected 100319 navigation untouched.

Direct Firestore collections: deda_social_direct_drafts/featured and deda_social_direct_days/YYYY-MM-DD.
Strict general_manager Firestore rules restrict creates/updates. Rule request.time governs future-day visibility at midnight Asia/Baghdad UTC+03.
Client read uses Firestore Source.server; no offline future preview. User must open/refresh social screen online to see today's task.
First trial supports Telegram follow URL only, configured reward in points/coins/diamonds but rewardsEnabled=false always.
No wallet/AdMob payout, no proof of Telegram membership, no Cloud Functions, no changes to original eight daily tasks or login reward.

Security verified: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/37986233216
Read-only merged LIVE rules baseline sha18 3408852ae0fd2dcd4b; merged candidate sha18 c5b444a132c894e933.
11/11 Firebase security tests passed (7 new, 4 previous), 0 failures.
Flutter QA: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/37986170539 SUCCESS.
Signed APK 100327 workflow https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/37986175847 (verify completion before delivery).

IMPORTANT: Firestore rules for 100327 have NOT been deployed to live. Cloud Functions for 100326 failed deployment due Cloud Build API.
Before production rollout: require explicit owner permission, recheck exact current live rules sha18, deploy only 100327 added blocks surgically, run live manager SAVE/SCHEDULE, test user read after midnight, never deploy all outdated repo rules.
Normal Firestore read/write pricing and quota can apply; no claims of free unlimited service.
