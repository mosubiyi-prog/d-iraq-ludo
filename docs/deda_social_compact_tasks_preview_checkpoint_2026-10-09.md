# DEDA – Social Tasks Compact UI – 2026-10-09

## Owner-approved layout
- Keep the original eight daily tasks unchanged, including «مراجعة مكان مضاف».
- Place the new «مهام التواصل الاجتماعي» directly after «مراجعة مكان مضاف» and before «اختبر مهاراتك».
- Same card width; shorter height than the ordinary task card. Ordinary minimum 94dp; social minimum 78dp.
- DEDA navy and gold, separate social icon and small «عرض» button.
- Subtitle: «تابع صفحاتنا وتفاعل مع المنشورات والفيديوهات لتحصل على مكافآت مميزة».
- Admin dropdown FIRST, in exact order: «صفحة فيس بوك»، «تلي جرام»، «يوتيوب»، «إنستغرام»، «تيك توك»، «أخرى».
- Interaction dropdown: follow page/channel, like post, watch video, like video, other.
- Admin can preview type, title, HTTPS URL, reward unit (points/coins/diamonds), amount and scheduled date. No instant publication, only the future Iraq midnight schedule once supported.
- Likes and views are not evidence of action without trustworthy platform verification. No rewards may be granted by simply opening a link.

## Work completed in isolated source branch
- Branch: social-tasks-compact-preview-2026-10-09, forked from checkpoint-stage14-general-manager-tasks-review-323-2026-10-09.
- Preview widget/catalog: lib/deda_social_task_preview.dart.
- Protected admin form preview: lib/deda_admin_social_task_preview_page.dart.
- Navigation: lib/deda_admin_task_management_page.dart.
- Gated insertion into user list: lib/main.dart, only if DEDA_SOCIAL_TASKS_UI_PREVIEW=true (default false).
- Test: test/deda_social_task_preview_test.dart.
- QA: .github/workflows/qa-deda-social-task-preview.yml.

## Safety boundary
- This is a design prototype and does NOT write to Firebase, launch links, publish, schedule real jobs, verify following/likes or pay rewards.
- No change to daily task identifiers, core wallet, Firebase rules/functions, Google Play or approved 100319 navigation / 100323 APK.
- UI preview date uses device date, not trusted server time.
- Actual feature requires dedicated server-side authorization, midnight publisher, platform-supported verification, idempotent reward ledger, regression QA and explicit production release decision.
