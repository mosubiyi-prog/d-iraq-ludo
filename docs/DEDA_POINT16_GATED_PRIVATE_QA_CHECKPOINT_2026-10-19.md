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
- **بعد نجاح المصدر الكامل 39182017754** تم تشغيل بناء النسخة الخاصة 100357 على GitHub run `39182575850`: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39182575850. مسار البناء الخاص `.github/workflows/qa-deda-point16-100357-private-signed-android16-no-play.yml` ذو تفعيل push على فرع QA فقط، وهو بناء خاص لا نشر Firebase ولا Play. لم يثبت نجاحه أو إنتاج APK في لحظة تسجيل هذا التحديث؛ يُفحص سجله أولًا. هدفها **100357** موقعة بنفس هوية 100356، بوابات `DEDA_PREMIUM_IDS_SERVER_LIVE=false` و`DEDA_PREMIUM_ALIAS_ROUTING_LIVE=false`، ثم فحص Android 16 strict clean launch والترقية داخل محاكي من 100352. لا توليد AAB ولا نشر Play أو Firebase. يجب مراجعة workflow وسجل التوقيع والفحوص قبل مشاركة APK مع المالك.
- لسلامة البيانات: **لا حذف للتطبيق ولا مسح بياناته**. ممنوع وصف أي Build ناجح بأنه آمن للهاتف قبل إثبات تشغيله من سجلات Android 16 وتحديثه داخل المحاكي وملفات SHA256 والتوقيع.

## نتائج QA مؤكدة قبل توقيع APK

- GitHub Actions `39182017754`: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39182017754 — نجاح مصدر 100356 كامل بعد مراحل 2–15+16، 23/23 Flutter app tests ناجحة، وتحليل المصدر أكمل بــ229 ملاحظة غير قاتلة. `spark-security` ناجح. لم ينشأ APK في هذا الاختبار.
- GitHub Actions `39182017862`: 14/14 Firebase Emulator، Python guard suite والمصادقة وAppCheck والـ alias والماسات والـ 100 محجوزة. لم تنشر وظائف حقيقية.
- نسخة بناء خاصة **100357** تحت الاختبار، مع عزل مفاتيح تفعيل `DEDA_PREMIUM_IDS_SERVER_LIVE=false` و`DEDA_PREMIUM_ALIAS_ROUTING_LIVE=false`، لا ملف APK صالح للمستخدم حتى نجاح التوقيع/Android16 strict.


## نتيجة بناء 100357 الموقّع وفحص Android16 — تصحيح بيئة CI

- Run `39182575850` بتاريخ 2026-10-19: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39182575850 — **نجحت** وظيفتا `spark-security` و`private-signed-apk`، لكن الفحص الشامل انتهى Failure لأن **خطوة محاكي Android 16 فشلت قبل بدء المحاكي**.
- APK الأصلي النهائي الناتج **موجود فعليًا في Artifact `12157421726`**، اسمه `DEDA-100357-ALL-POINTS-PRIVATE-SIGNED-OWNER-REVIEW-NO-PLAY`، وفي داخله `DEDA-100357-ALL-POINTS-OWNER-PRIVATE-SIGNED.apk`. الحجم المضغوط للأثر نحو 38MB. تاريخ الصلاحية المعلن حتى 2026-11-09.
- بصمة SHA256 **لـAPK وليس ZIP الأثر**: `f5659a118c6345bca0703e22a4905275278279f246d344270450c459d74bad04`؛ `versionCode=100357` و`packageName=com.diraq.ludo.d_iraq_ludo`. تقرير APKSigner: مطابق لنفس شهادة توقيع 100342 المرجعية التي استُخدمت كأساس موثّق لتحديث 100356. فحص Kotlin/R8 DEX نجح. رسالة log القديمة تقول `versionCode=100356` بشكل نص ثابت لكن إثبات `aapt` يعرض بوضوح 100357.
- فشل Android16 JOB ليس فشل تشغيل DEDA: خطوة `Verify emulator acceleration really usable` تحققت من `/dev/kvm` ثم حاولت تنفيذ `$ANDROID_HOME/emulator/emulator -accel-check` **قبل تثبيت Android Emulator SDK**، فأرجعت `No such file or directory` وexit127. **لم تبدأ أي عملية cold start أو in-place upgrade**، ولذلك لا يجوز القول إن 100357 ناجحة/فاشلة على Android16.
- أُنشئ smoke مستقل لا يعيد بناء أو توقيع APK `.github/workflows/qa-deda-point16-100357-android16-smoke-existing-apk-no-rebuild.yml` على نفس فرع QA. يستخدم بالضبط APK السابق بعد SHA256، ويثبّت المحاكي عبر `android-emulator-runner` قبل فحص KVM، ويختبر clean install ثم الترقية 100352→100357 بدون مسح بيانات أثناء الترقية، ويحفظ سجلات Flutter PID والتطبيق. Run **`39186312722`**: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39186312722. انتظر نتيجته الموثقة قبل إرسال APK للمستخدم.
- إلى أن ينجح تشغيل Android16 ويُراجَع فحص الحسابات: **100357 ليس بعد نسخة للتثبيت على هاتف المالك**. عدم نشر Firebase أو Play؛ بوابتا شراء ID وتبديل alias مطفأتان أصلًا.

## المحاولة الدقيقة بعد فشل المحاكي — 2026-10-19

- فحص SHA256-pinned 100357 المستقل `39186312722` **فشل بعد 16 دقيقة** داخل android-emulator-runner، قبل تنفيذ smoke script/adb install. السبب مؤكد من سجلات emulator: `ProbeKVM: This user doesn't have permissions to use KVM (/dev/kvm)` ثم `ERROR: x86_64 emulation currently requires hardware acceleration!` وانتهى `Timeout waiting for emulator to boot`. لم يحدث أي crash مثبت للتطبيق؛ الهاتف/production لم يلمسا.
- أضيف إلى `.github/workflows/qa-deda-point16-100357-android16-smoke-existing-apk-no-rebuild.yml` فحص وتمكين صلاحية `/dev/kvm` عبر `sudo chmod a+rw /dev/kvm` **قبل** تشغيل android-emulator-runner؛ KVM check داخل strict.sh يبقى بعد تثبيت emulator SDK. لم تُمس ملفات Flutter/Android والإمضاء ولا APK.
- محاولة إعادة الفحص: `39187667852` https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39187667852 على commit `7bb09445b02b6cc6735bca0221f7f2779492724e`. نفس ملف APK ببصمة `f5659a118c6345bca0703e22a4905275278279f246d344270450c459d74bad04` من الأثر 12157421726؛ لا إعادة بناء. **لا تعلن نجاح التشغيل حتى يكتمل job ويثبت logfile clean+in-place أو حدد العائق الجديد بوضوح.**
