# DEDA – نقطة توقف تجهيز إصدار Play 100338 من مكاني 100337
**التاريخ:** 15 تشرين الأول/أكتوبر 2026 (العراق)
**الحالة:** سير بناء AAB جارٍ – غير منشور، لا تدّعِ نجاح الحزمة حتى تنتهي الفحوص.

## النسخة المرجعية
- المستودع: `mosubiyi-prog/d-iraq-ludo`.
- مصدر الكود المختبَر على الهاتف: `deda-100337-makani-layout-private-qa-2026-10-14`، الوثيقة `docs/DEDA_100337_MAKANI_CHECKPOINT_2026-10-14.md`.
- اختبار المستخدم: نقل «مكاني» والإعجاب والمتابعة واللون نجحت؛ فتح «إدارة مكاني» بعد الانتظار كان طبيعياً، دون توقيت رقمي أخير. لا يوجد سبب مؤكد للتأخير السابق.
- المرجع الأقدم 100336 نقطة رجوع فقط، وليس مصدر الإصدار القادم.
- نسخة إنتاج Google Play المثبتة تاريخياً 100330؛ لا يمكن التحقق آلياً من حالة Play Console الحالية عبر GitHub.

## إعداد 100338
- فرع البناء المعزول: `deda-100338-play-aab-from-makani-2026-10-15`.
- سير العمل: `.github/workflows/build-deda-100338-makani-play-aab-owner-only.yml`.
- commit إضافة سير العمل: `9a699fc4724fa4354ded40dd9c3c6db21f37daaf`.
- رابط التشغيل: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38640784131
- يبني signed Android App Bundle برقم `100338`، الاسم الافتراضي `1.0.0`.
- حزمة المخرجات المتوقعة فقط بعد نجاح CI: `DEDA-100338-MAKANI-SIGNED-PLAY-AAB-OWNER-REVIEW-NO-AUTO-PUBLISH` (Artifact).
- التغيير الوحيد المقصود عن محتوى APK التجريبي 100337: نوع التغليف APK إلى AAB ورقم إصدار Play إلى 100338. تجري إعادة بناء نفس التسلسل المختبَر واستدعاء نفس اختبارات Flutter وFirebase Emulator.
- يحافظ على توقيع keystore المستخدم سابقاً وعلى package name `com.diraq.ludo.d_iraq_ludo`.
- إعدادات Dart نفسها: تفاعلات حقيقية + Spark live + ألوان أماكن صاحب المكان ON؛ `DEDA_SERVER_AUTOMATIONS_LIVE=false` ورفع شعار المكان من الهاتف OFF. جرس الاعتماد الآلي المؤجل لا يُفعَّل.
- ممنوع تعديل `main` أو نشر Firebase / Firestore / Functions أو حذف حسابات أو رفع التطبيق إلى Play آلياً. لا تمتلك CI هنا خطوة نشر المتجر.

## التسلسل التالي
1. انتظر اكتمال تشغيل GitHub Actions `38640784131`. راجع حالة `spark-security` و`signed-play-aab-owner-upload-only`، ولا تعلن النجاح إلا إذا كان الاثنان `success`.
2. تأكد من وجود Artifact صحيح وموقّع، حجمه وSHA256، فحص `jarsigner`، `versionCode=100338`، هوية `com.diraq.ludo.d_iraq_ludo`، وتعريفات أمان السيرفر.
3. راجع مع مالك التطبيق حالة Play Console الحالية والنسخة القائمة وعدم تجاوز versionCode 100338، ثم حضّر ملاحظات إصدار عربية موجزة، وافحص متطلبات Play Console.
4. **الرفع والنشر الفعلي فقط بعد مراجعة الحزمة وموافقة المالك الصريحة على الإصدار النهائي**. إن تعذر الوصول إلى Play Console، وجّه المالك خطوة بخطوة للرفع ولا تدّعِ النشر.

**تنبيه:** 100337 APK خاص DO NOT PUBLISH؛ أما 100338 AAB هو حزمة مرشحة للنشر بعد اختبار النجاح وليس إعلان نشر.

## نتيجة البناء المعتمدة – 15 تشرين الأول/أكتوبر 2026
- **تحقق مباشر من GitHub Actions**: تشغيل `38640784131` بحالة `completed / success`، SHA بناء `9a699fc4724fa4354ded40dd9c3c6db21f37daaf`.
- `spark-security`: **success**؛ فحوص Firebase Emulator كاملة.
- `signed-play-aab-owner-upload-only`: **success**؛ تشمل Flutter tests، إعادة بناء 100337، توليد 100338 AAB، التوقيع والفحص، ورفع Artifact للمراجعة.
- Artifact موجود وغير منتهي الصلاحية: `DEDA-100338-MAKANI-SIGNED-PLAY-AAB-OWNER-REVIEW-NO-AUTO-PUBLISH`، رقم `11929973915`، حجم الأرشيف `71901619` بايت.
- رابط البناء: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38640784131
- **المتبقي**: مراجعة حالة Google Play Console الحالية ورقم الإصدار الأعلى في كل المسارات، تنزيل AAB ورفعه يدوياً إلى Production وإكمال مراجعة المتجر؛ **لا يوجد نشر تلقائي**. لا تدّعِ أن الإصدار وصل إلى المتجر قبل تأكيد Play Console.
- لم تُغيَّر بيانات Firebase الإنتاجية ولا `main` ولا النسخة المثبتة لدى المستخدمين؛ تم توثيق النتيجة فقط في هذا التحديث.
