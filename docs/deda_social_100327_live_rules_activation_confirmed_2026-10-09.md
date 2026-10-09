# DEDA 100327 — Production Firestore-only social rule activation verified

Date: 2026-10-09. Project: deda-25b88.
Owner explicitly requested completion of activation, with the already-installed APK 100327 and no new APK.

GitHub Actions: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/37988794157
Conclusion: SUCCESS (signed in as configured service account).
Original live published Firestore rules SHA18: 3408852ae0fd2dcd4b.
Candidate new published live rules SHA18: c5b444a132c894e933.
Old published rules were preserved byte-for-byte and two new protected collections added:
- deda_social_direct_drafts/featured
- deda_social_direct_days/YYYY-MM-DD
Original live rules backup artifact in the run: DEDA-100327-ORIGINAL-LIVE-RULES-PRE-DEPLOY (90 days).

Security tests against EXACT deployed candidate: 7 new emulator tests passed + 4 historical social security tests passed, zero failures.
Live Firestore publication ran with firebase-tools --only firestore:rules. Final read-only Firestore Rules API check confirmed exact SHA18 c5b444a132c894e933 and identical bytes to tested rules.
Cloud Functions not deployed; no Cloud Build API needed; no APK, Google Play, legacy daily task, login task, navigation, wallet, ad or reward payout changes.
No social-task draft has been saved, scheduled or published by this deployment. The user's installed APK 100327 is now eligible for GM-only live save/schedule.

NEXT USER ACTION (not yet verified): reopen DEDA 100327 social admin page while online. The connection message should clear (no document => new revision 0). Set platform Telegram, action Follow, title + link https://t.me/DEDA_Iraq, configured reward, then press Save draft in Firebase once. Capture screenshot showing Firestore status draft revision 1. Select future Iraq day, press Schedule after owner confirms desired date. User page can fetch it online only on its scheduled Baghdad day, not before.
No wallet payout or Telegram subscription verification in this first trial; visiting link is not completion proof.

Never claim save/schedule was tested on a real owner session until screenshot is received.
