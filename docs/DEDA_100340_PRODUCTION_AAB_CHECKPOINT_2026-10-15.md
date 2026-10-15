# DEDA – نقطة توقف حزمة Google Play AAB رقم 100340
**التاريخ:** 15-10-2026 (العراق)
**الحالة المبدئية:** بناء AAB قيد التنفيذ، وليس منشوراً.

## المرجع الميداني الصحيح
- المستودع: `mosubiyi-prog/d-iraq-ludo`.
- APK رقم **100340** اختبره صاحب التطبيق على هاتفه وأكد «كلشي نجح»، مع ملاحظة أن زوم بداية الرحلة ممكن يحتاج تصغيراً إضافياً مستقبلاً؛ اتُخذ القرار بإرجاء تعديل الزوم وعدم تغيير شيء قبل النشر الحالي.
- فرع APK المختبر: `deda-100340-map-pin-nav-zoom-private-qa-2026-10-15`، GitHub Actions run `38663377057`، build commit `acbc821402d4b1bb20a66cdbe199c31a46599d3b`، SUCCESS.
- فرع احتياطي لدوران الخريطة 100339: `backup-deda-100339-rotation-owner-accepted-2026-10-15`، لا يُمس.
- حزمة 100338 AAB القديمة **غير معتمدة للنشر** بعد ظهور المشكلات سابقاً.
- **لا تغير أي كود فعلي أو Dart defines عن بناء APK 100340 المقبول**. المطلوب حزمة AAB متطابقة بالميزات `1.0.0 / versionCode 100340`.

## إعداد نشر 100340
- فرع الحزمة: `deda-100340-play-aab-owner-review-2026-10-15`.
- GitHub workflow: `.github/workflows/build-deda-100340-play-aab-owner-review-no-auto-publish.yml`.
- تشغيل GitHub Actions: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38666134678
- Firebase Emulator tests + Flutter analyzer + اختبارات 100339/100340 (دوران، تثبيت الدائرة بالإحداثيات، ألوان الإعجاب والمتابعة، ومكاني)، ثم إنتاج حزمة `flutter build appbundle --release --build-number=100340`.
- Flutter/Dart defines مطابقة لتشغيل APK 100340: `USE_NEXT_GEN_SDK=true`، `DEDA_DAILY_TASK_DISPLAY_PREVIEW=false`، `DEDA_SOCIAL_TASKS_UI_PREVIEW=true`، `DEDA_SERVER_AUTOMATIONS_LIVE=false`، `DEDA_PLACE_ENGAGEMENT_LIVE=true`، `DEDA_SPARK_FIRESTORE_LIVE=true`، `DEDA_OWNER_PLACE_BRANDING_LIVE=true`، `DEDA_OWNER_PLACE_LOGO_UPLOADS_LIVE=false`.
- Package ID: `com.diraq.ludo.d_iraq_ludo`؛ إصدار `versionName 1.0.0`؛ `versionCode 100340` يطابق الـAPK الخاص (AAB وAPK لنفس الإصدار للرفع المنفصل فقط).
- شهادة توقيع APK المختبر المرجعية `SHA256: a53d855b82d1280f324037428421838139ecf2e30174f9fcd0bd1878698b5f4a`؛ يجب التأكد من تطابقها مع AAB عبر `keytool -printcert -jarfile` مع اختبار jarsigner، وتوثيق SHA256 للحزمة بعد استخراجها.
- الخرج المتوقع: GitHub Artifact `DEDA-100340-OWNER-ACCEPTED-SIGNED-GOOGLE-PLAY-AAB-NO-AUTO-PUBLISH` وفيه `DEDA-100340-MAKANI-GEO-PIN-NAVIGATION-SIGNED-PLAY.aab`، `SHA256SUMS`، معلومات الشهادة، ملاحظات الإصدار العربية.
- **ممنوع** نشر Firebase أو قواعد أو Functions أو تعديل بيانات حسابات/أماكن المستخدمين أو النشر التلقائي لـGoogle Play.
- لا نرفع AAB إلى Play Console ولا نزعم إتاحته للجمهور حتى يتحقق صاحب التطبيق من آخر versionCode في لوحة Play Console ويرفع الملف ويؤكد صلاحية التطبيق ونشر Production هناك؛ GitHub build لا يثبت حالة Play الفعلية.

## المتابعة
1. افحص تشغيل `38666134678`، ولا تعتبر الحزمة ناجحة إلا إذا كانت جميع jobs `completed / success` وArtifact صحيحاً.
2. حمل ملف ZIP عبر GitHub artifact، وافحص محتوياته وSHA256 ثم استخرج AAB باسم الملف الأصلي دون إعادة بناء أو تغيير كود.
3. سلّم للمستخدم AAB المباشر مع ملاحظات الإصدار، ثم وجّهه خطوة بخطوة لـGoogle Play Console، بدون حذف النسخة المنشورة أو تغيير حسابات المستخدمين.
4. إذا واجه Play Console رفض إصدار أو شهادة أو بلد، توقف واطلب صورة رسالة الرفض؛ لا تُنشئ رقم إصدار جديداً بغير حاجة.

**المسؤول عن النشر العام النهائي:** مالك التطبيق عبر Play Console.


## النتيجة النهائية: AAB مُوقّع ومتحقَّق منه
**GitHub Actions النهائي:** https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38666295959 — `completed / success`، workflow SHA `84be4b657bf869d5d2e4b4716e65ba77fe5ae41e`. كلتا وظيفتي `spark-security` و`signed-private-phone-apk` نجحتا (اسم الوظيفة موروث، لكن الأمر المنفذ `flutter build appbundle --release --build-number=100340`، وليس APK).
- Artifact رقم `11943270791`: `DEDA-100340-OWNER-ACCEPTED-SIGNED-GOOGLE-PLAY-AAB-NO-AUTO-PUBLISH`.
- تم تنزيل وفحص الأرشيف/استخراج الملف إلى `/mnt/data/DEDA-100340-MAKANI-GEO-PIN-NAVIGATION-SIGNED-PLAY.aab`؛ هذا مسار الملف المحلي المؤقت لدى ChatGPT.
- **AAB size:** `72426142 bytes` (~69.07 MiB).
- **AAB SHA-256:** `88ab46201decd965cfa47bf4f0a0e1090b312a50e61ceca97cfc37815fdbda1c`؛ مطابق لملف `SHA256SUMS` من GitHub Artifact.
- **شهادة تحميل/توقيع AAB SHA256:** `a53d855b82d1280f324037428421838139ecf2e30174f9fcd0bd1878698b5f4a`، **مطابقة تماماً** للشهادة الموجودة في ملف `certificate.txt` من Artifact الـAPK الذي وافق عليه مالك التطبيق. أكد `keytool` المطابقة على ملف AAB الذي تم تنزيله، ونجح `jarsigner -verify`، مع تنبيهات غير مانعة للتوقيعات القديمة في JarInputStream (خروج صفر).
- تأكدت من سلامة ZIP داخل AAB و`BundleConfig.pb` و`base/manifest/AndroidManifest.xml` و`base/dex/classes.dex`، ووجود توقيع `META-INF/*.SF`. فحص GitHub تحقق من رقم `100340` وpackage `com.diraq.ludo.d_iraq_ludo` وبقاء خصوصيات الإطلاق المؤجل.
- يحتوي الأرشيف كذلك `RELEASE_NOTES_AR.txt` و`READ-ME-FIRST.txt` و`upload-certificate.txt` و`source-commit.txt`، ونسخة release notes مستخرجة مؤقتاً إلى `/mnt/data/DEDA-100340-GOOGLE-PLAY-RELEASE-NOTES-AR.txt`.
- **حالة إصدار المتجر:** الحزمة مكتملة وصالحة للتقديم إلى Google Play Console بناء على فحوص CI والمحلية، لكنها **لم تُرفع ولم تُنشر** في Production بعد. مطلوب من المستخدم التأكد من أعلى versionCode في Play Console ومتطلبات Play App Signing، ثم مراجعة الإنذار/الملاحظات وقبول طرح الإصدار بنفسه.
- **لا تعدّل نسخة 100340 المعتمدة ولا تولّد 100341 بلا حاجة.** نسخ الرجوع باقية، ولا يوجد نشر Firebase أو تغييرات حسابات المستخدمين.
