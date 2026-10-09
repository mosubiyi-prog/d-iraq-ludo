# DEDA — Five approved social tasks changes — 2026-10-09

## Owner instructions
- Stop discussion of forgotten login code recovery; do not mix that work into social tasks.
- Finish the five approved social changes, preserve the accepted navigation and avoid deploying unsafe backend.

## Five approved changes and current status
1. Move small navy/gold social-task card directly below "تسجيل الدخول اليومي": **implemented** in source. Internal golden APK build injects the card after login, before the original eight task cards.
2. Correct clipped Arabic subtitle while keeping card below the original task min height of 94dp: **implemented**. New shorter subtitle: "تابع صفحاتنا وتفاعل مع المنشورات والفيديوهات"; 3 lines permitted, slightly smaller font.
3. Make optional rewarded-ad doubling configurable for **points, coins, diamonds**: **implemented in the manager preview UI**, with a separate toggle and preview amount. **Actual verified AdMob SSV + wallet payout are NOT active.** A plain client callback, URL click, or ad preview must NOT trigger a payment.
4. Save, scheduled publish at Iraq midnight (UTC+03:00), cancel before effective time, only general manager: **staging backend policy and emulator-only store implemented**. Separate collections and audit. NO production functions export or Firestore rules deployment. Real mobile persistence is not switched on until authorized backend integration, testing and rollout.
5. Verify task completion and block duplicate rewards: **fail-closed policy and tests implemented**. No social platform completion API verifier, production idempotent ledger, or AdMob server-to-server validation wired yet; accordingly payout remains blocked. Never interpret viewing, liking or opening a URL as proof.

## Preserved components
- DEDA 100319: accepted golden navigation and other app features.
- DEDA 100323: accepted manager task preview checkpoint.
- DEDA 100324: user-tested social platform and preview form checkpoint.
- All original eight daily tasks and existing reward engine left untouched.
- No update to production Firebase rules, functions/index.js, Google Play, or paid wallet.
- New branch: social-tasks-stage2-approved-five-2026-10-09.
- New QA workflow: .github/workflows/qa-deda-social-stage2-approved-five.yml.
- New Android QA workflow: .github/workflows/qa-deda-social-preview-apk-100325.yml, build number 100325.
- Server policy: functions/deda_social_task_stage2.js.
- Demo store: functions/deda_social_task_stage2_store.js (HARD-GATED to FIRESTORE_EMULATOR_HOST + GCLOUD_PROJECT=demo-deda-social-stage2).
- Tests: tests/stage2_social/social_policy.test.cjs and store_policy.test.cjs; Flutter widget test/deda_social_task_preview_test.dart.

## Critical remaining activation gates
- Review 100325 UI on owner's Android device.
- Build reviewed, authenticated, server-only general manager Firebase API/rules for actual persistent social drafts/schedule/cancel.
- Build trusted completion proof per supported platform (many follow/like APIs do NOT expose per-user verification).
- Implement AdMob rewarded-ad SSV, replay protection, and a server-side atomic idempotent per-user/per-task/per-day ledger for points, coins and diamonds; never withdraw from general manager's wallet.
- Security review, Firebase Emulator tests, fail-closed configurations, rollback plan and explicit owner approval before production deployment.
- Avoid UI promises implying payouts or actual published tasks until these gates pass.
