# DEDA «إنت كدها» — نقطة 16: الربط الخادمي المقفول والفحص الخاص

**تاريخ المرجع:** 2026-10-19. **الموافقة:** صاحب التطبيق أمر بـ«اكمل عزيزي واني اتابع معك الشريط الموجز». لا تفويض للنشر أو حذف بيانات المستخدمين أو ترحيل محافظهم.

## المصدر والنقاط المحمية

- المستودع: `mosubiyi-prog/d-iraq-ludo` (عام).
- فرع تنفيذ الجسر الآمن: `deda-intakadha-point16-backend-bridge-qa-2026-10-19`، منشأ من النقاط 2–15 المعتمدة عند commit `e55890646e1c2aa02333e0fa9d24a33a53680360`.
- نقطة رجوع نقطة 15: `backup-deda-intakadha-point15-verified-before-point16-2026-10-19` عند `cb7bda680cbd4a90edbc63b6786ca183967fe84e`.
- النسخة المرجعية المثبتة على الهاتف 100356: `backup-deda-100356-phone-ui-verified-2026-10-18` ثابت عند `4373b8b30eadc5a284554ca7c021c350e0732caf`.
- لا تعديل على `functions/index.js` أو `firestore.rules` أو `lib/main.dart` أو الملفات الفعلية للخرائط وAndroid؛ تطبيق مرحلي فقط عبر `tools/stage_*.py` على مصدر CI المعاد بناؤه مؤقتًا.

## بوابة الخادم

- `tools/deda_intakadha_point16_gated_callable_gateway_2026_10_19.js` يغطي قراءة/شراء/استخدام البطاقات، قراءة/اختيار المعرّفات المملوكة، تحليل alias إلى المعرّف الأصلي، ومنحة المدير العام المحجوزة.
- جميع المفاتيح `read, cardPurchase, cardUse, identifierUse, alias, adminGrant` **OFF** افتراضيًا. لا تصدير إلى `functions/index.js` ولا نشر Firebase. رقم UID مصدره `request.auth.uid` حصراً، وAppCheck مطلوب مع `enforceAppCheck:true` وتعطيل الطلبات مع attestation مفقود. لا يسمح للعميل بإرسال سعر أو accountKey أو uid أو دور مدير أو قائمة الـ100.
- القائمة الأصلية للـ100 إدارة حصرية يجب أن تبقى بمصدر خاص موثوق للخادم، وليست في GitHub العام أو ملف Dart أو APK. قائمة المجموعة 002 تبقى مرشحات للمعاينة وليست مخزون بيع، ولا سعر بيع معرف فعلي معتمد.
- اختبار Firebase Emulator run `39182017862`: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39182017862 — source-security نجاح، **14/14** حالات AppCheck/UID/5000 ماسة/عدم تكرار خصم/صلاحيات المدير العام/alias بدون إحداثيات/رفض الوصول المباشر؛ **لا حسابات حقيقية**.

## جسر Flutter والتوافق

- `tools/stage_deda_intakadha_point16_authenticated_flutter_calls_2026_10_19.py` يضيف عميل Cloud Functions الموثّق بعد مراحل 2–15 على التطبيق المعاد تجميعه، ويترك `DEDA_PREMIUM_IDS_SERVER_LIVE=false` افتراضيًا، فلا شراء ولا اختيار معرّف عام قبل نشر الخدمات وإعداد Firebase AppCheck. واجهة المدير العام تبقى مخفية، ولا يصير أي خصم محلي للماسات.
- `tools/stage_deda_intakadha_point16_friend_alias_lookup_2026_10_19.py` يحافظ على أصدقاء الحساب وفق UID والمعرّف الأصلي. إضافة lookup باسم مميز 4–12 رمزًا خلف `DEDA_PREMIUM_ALIAS_ROUTING_LIVE=false`؛ ولا يفتح موقعًا أو يمنح إذن متابعة.
- **حاجز رئيسي:** مشاركة المواقع حاليًا تحقق `DedaBackend.isValidPersonalShareId` بصيغة `@DEDA-[A-Z2-9]{6}` وتخزن `recipientPublicId` بالأصل؛ كما أن البحث/الملف/النسخ في مسارات أخرى ما زال يعتمد الآيدي الأصلي. لا تفعّل تغيير الآيدي العام قبل هجرة هذه المسارات واختبارات التكافؤ والأمان لكل من المرسل والمتلقي والـ UID المتجدد.
- **حاجز الإنتاج:** لا توجد إعدادات Firebase App Check للـCallable الجديدة على الأجهزة ولا سجل نشر `functions/index.js`، ومحفظة الماسات المحلية SharedPreferences غير مؤهلة للاقتطاع من الخادم. السعر 5000 لبطاقات التصميم فقط وفق رصيد خادمي مُتحقق؛ مبيعات أسماء الـID بقيت مغلقة.

## فحص Flutter ثم APK خاص

- Workflow مصدر حقيقي: `.github/workflows/qa-deda-point16-client-bridge-full-reconstruction-no-apk.yml` يعيد بناء 100356 ويطبق مراحل 2–15 وجسر 16، ثم يحلل Flutter ويجري فحوص الواجهة والملاحة والملف. فحص `spark-security` نجح؛ **نتيجة التوافق النهائي تُقرأ من GitHub run نفسه وليس من توقعاتنا**. لا APK في هذا المسار.
- مسودة بناء خاصة لم تُفعّل تلقائيًا: `.github/workflows/qa-deda-point16-100357-private-signed-android16-no-play.yml` — `workflow_dispatch` فقط حتى اعتماد الفحص المصدر. هدفها **100357** موقعة بنفس هوية 100356، بوابات `DEDA_PREMIUM_IDS_SERVER_LIVE=false` و`DEDA_PREMIUM_ALIAS_ROUTING_LIVE=false`، ثم فحص Android 16 strict clean launch والترقية داخل محاكي من 100352. لا توليد AAB ولا نشر Play أو Firebase. يجب مراجعة workflow وسجل التوقيع والفحوص قبل مشاركة APK مع المالك.
- لسلامة البيانات: **لا حذف للتطبيق ولا مسح بياناته**. ممنوع وصف أي Build ناجح بأنه آمن للهاتف قبل إثبات تشغيله من سجلات Android 16 وتحديثه داخل المحاكي وملفات SHA256 والتوقيع.
