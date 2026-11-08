# DEDA — نقطة توقف المرحلة الثامنة: مختبر Google UID مستقل لأجهزة Android — 2026-11-08

## التفويض والحماية

صاحب المشروع: «تمام عزيزي نمشي على نفس الحذر والانتباه» بعد تقرير المرحلة السابعة عن تجهيز بيئة Firebase اختبار مستقلة وتجربة Google على جهازين حقيقيين.

**النتيجة الآن:** تم تجهيز **مصدر تطبيق Flutter/Android منفصل للاختبار + حارس إعداد Firebase QA + سكربت بناء مشروط بموافقة جديدة**، مع فحوص ناجحة. **لم يُنشأ مشروع Firebase حقيقي للاختبار، ولم تُجر تجربة Google فعلية على جهاز، ولم يُبن APK، ولم يلمس Firebase الحي أو بيانات المستخدمين.**

- المستودع: mosubiyi-prog/d-iraq-ludo.
- فرع المرحلة الثامنة: deda-100441-stage8-isolated-android-google-uid-device-lab-no-deploy-2026-11-08.
- قاعدة المرحلة السابعة: a8d24e911a9b734e4467cccf86a832c4a597b86f.
- نقطة التوقف الأصلية المحمية: 3850c93b7a18e11613a951a32dc520701717a263.
- 100440 و100441 محميتان؛ 100340 ما زالت نسخة المستخدمين، ولم تتغير.
- حساب هاتف المالك A/B/C يبقى مفتوحاً. لا تسجيل خروج، لا إزالة، لا إثبات ملكية بالتابلت ذي الحساب المختلف.

## لماذا احتجنا مختبراً منفصلاً

المستودع الأصلي لا يضم مجلد android/ ثابتاً؛ أعمال البناء التاريخية تولده مؤقتاً باستخدام flutter create. لذلك تم تجهيز مشروع جديد **داخل مجلد مؤقت** بحزمة Android خاصة بالمختبر، مع عدم نسخ تطبيق DEDA أو إعداداته.

تم التأكد من أن معرف مشروع Firebase الحي الموجود بالمستودع هو deda-25b88، وحزمة إنتاج DEDA هي com.diraq.ludo.d_iraq_ludo. المختبر يرفض ذلك المشروع وهذه الحزمة، ويسمح فقط بحزمة com.deda.qa.uiddevice ومشروع Firebase QA جديد **يبدأ معرفه** بـdeda-qa-uid-lab-.

## ما تم إنشاؤه على الفرع المعزول

1. qa/stage8_uid_device_lab/lib/lab_guard.dart
   - يتحقق **قبل أي Firebase.initializeApp** من مشروع مستقل وتطابق Firebase Android App ID/Sender ID وWeb OAuth ID وشكل الإعدادات؛ لا يحتوي أي fallback للإنتاج.
   - يُنتج بصمة SHA-256 قصيرة للـUID لتسهيل مقارنة الجهازين دون إظهار Google token أو البريد.
2. qa/stage8_uid_device_lab/lib/main.dart
   - تطبيق Flutter منفصل بعنوان «مختبر UID — ليس تطبيق ديدا»، مع زر اختيار حساب Google التجريبي وزر خروج من المختبر فقط.
   - يستخدم Firebase.initializeApp **باسم منفصل** وFirebaseAuth.instanceFor(app:qa)، وليس FirebaseAuth.instance الافتراضي؛ يتأكد من أن projectId هو QA.
   - لا يستخدم cloud_firestore أو cloud_functions أو خدمات أصدقاء/آيدي/ماسات أو تسجيل رقم هاتف وPIN أو صلاحيات إدارة. لا تسجيل تلقائي قبل ضغط المستخدم.
3. qa/stage8_uid_device_lab/pubspec.yaml
   - حزَم Flutter/Firebase Auth/Google Sign-In وcrypto فقط؛ منفصلة عن pubspec.yaml الإنتاج.
4. qa/stage8_uid_device_lab/test/lab_guard_test.dart
   - 11 اختباراً حقيقياً ضمن Flutter/Dart: منع الإنتاج، غياب إعدادات QA، تطابق معرفات التهيئة، تغير بصمة UID، تعطيل Google دون إعدادات.
5. qa/stage8_uid_device_lab/tools/preflight_qa_config.py
   - يتحقق من ملف JSON مستقبلي **خارج المستودع** ويقارن المشروع والمفاتيح ومعرف التطبيق وOAuth بمعلومات google-services.json الإنتاجية من دون طباعة المفاتيح أو إجراء اتصالات خادمية.
6. qa/stage8_uid_device_lab/tools/test_preflight_qa_config.py
   - 12 اختباراً Python لحماية عزل مشروع Firebase والحزمة ومفاتيح التهيئة.
7. qa/stage8_uid_device_lab/tools/prepare_qa_android_apk_EXPLICIT_OPT_IN.sh
   - سكربت جاهز للاستخدام لاحقاً **فقط بتصريح منفصل** عبر DEDA_STAGE8_OWNER_APPROVED_QA_BUILD=YES_STAGE8_QA_ONLY + مشروع Firebase QA موجود ومكتمل وملف إعدادات خارجي.
   - يولد Flutter Android جديداً في temp باستخدام flutter create --org com.deda.qa --project-name uiddevice، ويتحقق من applicationId الحقيقي في Gradle، ويرفض google-services.json الإنتاجي، ثم يختبر ويبني Debug QA APK فقط إلى موقع خارج المستودع.
   - **لم يُشغّل هذا السكربت ولم يُنشأ APK**.
8. qa/stage8_uid_device_lab/README.md
   - إجراءات تهيئة Firebase QA مستقل وربط Google OAuth وشهادات SHA في مشروع QA وطريقة فحص هاتفين، بدون استخدام الحساب الأصلي أو رقم حقيقي.
9. .github/workflows/deda-100441-stage8-isolated-android-google-uid-device-lab-no-deploy-2026-11-08.yml
   - وظيفة حماية المصدر وأخرى تولد Android منفصلاً مؤقتاً وتنفذ Flutter analyze/test **دون بناء APK**.
10. هذا التقرير.

## نتائج QA

GitHub Actions run **42482981162**: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/42482981162

- qa-isolation-scope: SUCCESS. 12/12 اختبار Python، وتأكد CI من عدم تغيير ملفات DEDA الإنتاجية أو إصدار APK.
- isolated-flutter-android-project: SUCCESS. إنشاء هيكل مشروع Android جديد بحزمة com.deda.qa.uiddevice، دون google-services.json، تحليل Dart «No issues found»، و11/11 اختبارات Flutter ناجحة.
- **23/23 اختباراً ناجحاً** في هذه المرحلة؛ لا يتضمن هذا العدد اختبارات المراحل السابقة. المراحل السابقة موثقة مستقلة.
- بدايات CI واجهت أخطاء وحدات Dart في اختبارات المختبر الجديد وملف widget_test.dart المولّد تلقائياً، ثم ملاحظة Dart lint بسيطة؛ أُصلحت هذه الأمور داخل الملفات الخاصة بالمختبر فقط. التشغيل النهائي أعلاه نجح.
- ما تغيرت lib/ أو android/ أو assets/ أو pubspec.yaml الإنتاجي ولا functions/ أو firebase.json أو firestore.rules أو google-services.json أو تسجيل الدخول القديم.

## حدود دقيقة

- حارس QA هو حماية محلية وبوابة بناء، وليس إثباتاً أن مشروع Firebase QA الحقيقي قد أنشئ أو أن صلاحياته ومزوّدي Google قد فُحصوا مباشرة.
- لم يُسجّل الدخول إلى Google فعلياً ولم يظهر Account Chooser على هاتف Android. لا يوجد حساب Google QA مرتبط أو مستخدم فعلي في هذا الاختبار. **لا نقول إن اختبار الهاتفين نجح**.
- الاسترجاع الحقيقي A/B/C ما زال معلقاً على إثبات ملكية مستقل؛ التطبيق المنشور 100340 لم يُغيَّر.
- لا توجد تغييرات في أرصدة المستخدمين أو الجوائز والهدايا والإدارة والأصدقاء أو الآيدي.
- عدم امتلاك مشاريع QA مجهزة لا يجيز الرجوع إلى Firebase الإنتاجي لتجربتها.

## بوابة المتابعة والقبول

1. عند التفويض، إعداد Firebase QA مستقل بمعرف جديد من نمط deda-qa-uid-lab-*، تسجيل Android package com.deda.qa.uiddevice، تمكين Google في مشروع QA فقط، وضبط OAuth Web Client وSHA لشهادة Debug اختبارية.
2. التحقق من ملف الإعدادات الخارجي via preflight_qa_config.py؛ إقرار بناء QA Debug فقط بصورة مستقلة مع عدم نشر أي نسخة عامة.
3. تجربة مختبر Google على جهازين اختبار مستقلين بحساب Google جديد، ومقارنة نفس بصمة UID ثم اختبار حساب Google مختلف، وإلغاء النافذة/تبديل الإنترنت/استمرارية الجلسة.
4. بعد ذلك فقط تقييم خطة التسجيل الجديد وربط ملكية رقم هاتف مستقلة؛ لا نقل بيانات أو إعادة ارتباط UID للحسابات القديمة.
5. موافقة صريحة وخطة تراجع ونسخ احتياطي قبل أي تغيير حي في Firebase أو APK الحقيقي أو Google Play.

**الحالة:** مصدر المختبر جاهز للفحص، ومقفل بلا مشروع QA؛ نقطة توقف آمنة، لا APK، لا Firebase deploy، لا مساس بحساب الهاتف الأصلي.
