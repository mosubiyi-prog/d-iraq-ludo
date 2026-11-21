# DEDA — إزالة الغبار عن التطبيق كي يستنشق النجاح النقي 🤲
## المرحلة الثانية: هوية Google ثابتة وإدارة مستقلة — نقطة متابعة

**التاريخ:** 2026-11-21  
**المرجع:** تعليمات 01، `docs/DEDA_OFFICIAL_STABILITY_SINGLE_LOGIN_ADMIN_MAP_PLAN_2026-11-21.md`، ونقطة المرحلة الأولى.  
**فرع العمل الوحيد:** `deda-100451-owner-admin-session-safe-repair-2026-11-20`  
**الحالة:** `STAGE2_SOURCE_QA_PASSED / 11_DART_POLICY_TESTS_PASSED / FULL_ASSEMBLY_ANALYZE_EXIT_ZERO / NO_APK / NO_FIREBASE_PRODUCTION_CHANGE / RELEASE_HOLD`. لا يُعلن اكتمال المرحلة الثانية أو نجاح الإدارة على الهاتف.

### قرار المالك الذي يحدد النطاق
ليس شرطاً استرجاع نفس A/B/C أو الماسات/المستوى/المشتريات الشخصية قبل إصلاح التطبيق. يقبل صاحب المشروع UID جديداً **لحسابه الشخصي** ودخول Google ثابتاً، لكنه يتمسك بالخارطة والإدارة وسلامة جميع الأقسام وعدم مسّ حسابات المستخدمين الحاليين. A/B/C لا تُحذف ولا تُنقل منها بيانات دون تفويض. Google لا يمنح الإدارة أو حق الآيدي القديم تلقائياً.

### ما كُتب فعلاً في نفس الفرع
- `lib/deda_stable_google_login_2026_11_21.dart`: تسجيل Google حقيقي من جهة العميل، من خلال GoogleSignIn وFirebaseAuth، بفحص أن UID/Google provider المستخدم يطابق نتيجة SDK. يلزم إجراء مستخدم صريح، ولا يستبدل جلسة Anonymous دون موافقة محددة. جلسة مدير قديمة non-anonymous لا تُستبدل. النتيجة لا تنقل A/B/C ولا تمنح إدارة. حاجز محلي يلغي اعتماد الملف القديم عند إنشاء UID جديد.
- `lib/deda_stage2_google_access_card_2026_11_21.dart`: بطاقة فوق زر تسجيل الخروج في الإعدادات، مع توضيح تغيير الهوية والموافقة المنفصلة. لا تغيير بموضع زر الخروج.
- `lib/deda_stage2_isolated_admin_identity_2026_11_21.dart`: **FirebaseApp ثانوي باسمه** ومصادقة Auth منفصلة وقارئ Firestore مرتبط بنفس التطبيق الثانوي؛ التحقق من `admins/{uid}` ومن `admin_entry_access/{accountKey}` قراءة خادمية `Source.server`، رفض الجلسات/البوابات غير المخولة. خروج الإدارة من التطبيق الثانوي فقط، لا `FirebaseAuth.instance.signOut` على جلسة المستخدم.
- `tools/app_stability/app_package/bind_stage2_google_admin_isolation_2026_11_21.py`: دمج الملفات داخل **نسخة المصدر الكامل المعزولة فقط** بعد حارس المرحلة الأولى، إضافة الاعتماد `google_sign_in: ^6.2.2` على `pubspec.yaml` المعزول فقط، وإبقاء كل الواجهات والخارطة الأصلية.
- `test/deda_stage2_google_and_admin_isolation_policy_test.dart` و`test/test_deda_stage2_source_wiring_2026_11_21.py`: اختبارات موافقة تغيير الهوية، الاستفادة من Google نفسه، رفض تغيير جلسة مدير، رفض منح إدارة دون سجل خادمي مطابق، وثبات موضع بطاقة الإعدادات، ومنع الكتابة في المشروع المحمي.
- `.github/workflows/deda-stage2-google-admin-isolation-source-qa-2026-11-21.yml`: فحص نسخ المصدر الأصلي وتجميع Flutter الكامل ثم التحليل، **بدون APK أو Play أو Firebase deploy**. التشغيل النهائي الناجح: [44856401285](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/44856401285)، ضمن الالتزام بعدم النشر.

### نتائج الاختبارات المثبتة (لا تعني نجاح الهاتف)
- GitHub Actions [44856401285](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/44856401285): وظيفتا `actual-source-safety` و`assembled-full-app-source` **success**.
- 5 اختبارات Python لربط المصدر والنسخ المحمية؛ واختبارات المرحلة الأولى السبعة؛ **11 اختبار Flutter/Dart** لسياسة Google والجلسات وصلاحيات الإدارة، جميعها نجحت.
- أعاد الـCI تجميع النسخة الكاملة من أساسها المحمي، ثم طبّق حارس المرحلة الأولى ووحدات المرحلة الثانية وبطاقة الإعدادات. `flutter analyze --no-fatal-infos --no-fatal-warnings` انتهى بنجاح **دون أخطاء تحليل من نوع error**، لكنه رصد **404 رسائل info/warning** عبر المصدر الكامل، منها اثنتان لتنسيق الأقواس في وحدة الإدارة الجديدة، ولا يجوز وصف التحليل بأنه خالٍ من الملاحظات.
- سجل CI يؤكد: `PASS_STAGE2_GOOGLE_ADMIN_SOURCE_BOUND_QA_ONLY`، `PASS_FULL_ASSEMBLY_MAP_AND_ADMIN_SOURCE_RETAINED_STAGE2_GOOGLE_ADMIN_ISOLATED`، `NOT_PHONE_TESTED_STAGE2_GOOGLE_AND_ADMIN_DASHBOARD_NOT_ACTIVATED_NO_APK_NO_PLAY`.
- فشلت محاولات CI سابقة بسبب اختبار وجود نسخة مماثلة من test داخل تجميع DEDA وبسبب عدم تصدير ثابت تفعيل Google إلى `main.dart`؛ عولجتا قبل التشغيل الناجح. لا ادعاء بنتيجة هاتف أو توحيد Firestore بعد.

### قيود واضحة قبل تفعيل الميزة أو تسليم نسخة
1. **ملف Google OAuth الحالي غير جاهز:** `google-services.json` الموجود في المستودع، مشروع `deda-25b88` والحزمة `com.diraq.ludo.d_iraq_ludo`، يحتوي صفراً من `oauth_client` من النوع Android `client_type:1`، وصفراً من web `client_type:3`. هذا لا يثبت حالة زر Google داخل Firebase Console، لكنه يعني أن إعداد اعتماد Google المطلوب للحزمة والتوقيع/ID token غير موثق في ملف تطبيق DEDA الحالي. لا تفعيل للنشر أو فحص بحساب المالك حتى تُربط SHA/Google provider بطريقة صحيحة ويُحدّث ملف الإعداد المصرح به.
2. **لم نفصل dashboard الإنتاجي بعد:** وحدة التحقق في FirebaseApp الثانوي لا تفتح Dashboard وحدها؛ وظائف `DedaBackend` و`admin_pages.dart` الإدارية ما زالت تعتمد افتراضياً على Firebase Auth/Firestore الافتراضي. يجب توصيل جميع العمليات الإدارية بحساب الإدارة المعزول أو استخدام نفس Google UID بتفويض دور خادمي صريح بعد موافقة، دون استدعاء `signInAdmin` على الجلسة العامة.
3. **ملف DEDA المحلي ليس Google Auth:** شاشة الملف القديمة مرتبطة بهاتف/اسم/نوع حساب وبسجلات Firestore قديمة. إنشاء UID Google لا يجب أن يعيد استخدام/يكتب فوق هوية A/B/C أو يفتح الملف القديم اعتماداً على SharedPreferences. يجب عمل إكمال تسجيل آمن للحساب الجديد، بحماية قواعد Firestore للهوية الجديدة، قبل السماح بالدخول الكامل.
4. لذلك **الرايتان `DEDA_STABILITY_GOOGLE_LOGIN` و`DEDA_STABILITY_ADMIN_ISOLATED_AUTH` مطفأتان افتراضياً**؛ لا تسليم APK بالميزات الجديدة قبل إصلاح البنود الثلاثة والتحقق على هاتف/تابلت والخرائط والإدارة.
5. كل فحوص المصدر الجيدة لا تثبت صلاحيات الإنتاج، ولا تُعدّ بدل اختبار أجهزة حقيقية. لا نغير Firebase Auth users أو Firestore Rules أو بيانات المستخدمين ولا نمس 100342/100436 أو Play.

### القادم وفق نفس الخطة، دون العودة لاسترجاع A/B/C
- إكمال تجهيز Google OAuth للحزمة الرسمية والتوقيع المعتمد بدون تجاوز موافقات Firebase الإنتاجية.
- ربط دخول Google بهوية DEDA جديدة/مقصودة آمنة مع تفريق صارم بين الحساب القديم المعروض وUID الجديد، والمحافظة على المنشور.
- نقل استدعاءات لوحة الإدارة الفعلية إلى مصادقة وإطار صلاحيات آمن، مع إثبات ظهور البطاقة للمخوّل ورفض غير المخوّل دون تبديل UID العام.
- مراجعة الخارطة/المواقع وبقية الأقسام، ثم APK كامل موقّع واختبار على الهاتف والتابلت؛ Play بأمر لاحق صريح فقط.

**الحكم الفني المرحلي:** توفرت أكواد حقيقية لمدخل Google وفصل Auth الإداري، ولكن **توحيد هوية الحساب وتشغيل الإدارة بصورة نهائية لم يُنجزا بعد**. المرحلة الثانية مستمرة ولا يجوز إعلان اكتمالها.

### متابعة تنفيذية موثقة — حماية تسجيل DEDA المحلي (2026-11-21)
- **مراجعة تعليمات 01 والخطة والفرع:** تمت مراجعة ملف التعليمات الإلزامي، الخطة الرسمية، ونتيجة المرحلة الثانية قبل التعديل. لم يُفتح فرع جديد ولم تُمس النسخ 100342/100436 أو إعدادات Firebase الإنتاجية.
- **الخلل المصدرّي المحدد:** إذا أصبحت `FirebaseAuth.currentUser == null` وبقي `deda_logged_in_v1 == true` على الهاتف، كان زر Google قادراً على الانتقال إلى UID جديد ثم تعطيل اعتماد تسجيل DEDA المحلي دون موافقة صريحة على هذه الحالة بالذات.
- **المعالجة:** commit `edc0dbaf910414d8414b5efc52439659076b17f0`. أضيف شرط موافقة صريحة لجلسة DEDA المحلية المحفوظة، وحارس كشف تغيير تسجيل DEDA أثناء اختيار Google، مع checkbox قبل بدء Google عند غياب Firebase principal؛ اختبارات Dart/Python تغطي الحالة.
- **الملفات المعدلة:** `lib/deda_stable_google_login_2026_11_21.dart`، `lib/deda_stage2_google_access_card_2026_11_21.dart`، `test/deda_stage2_google_and_admin_isolation_policy_test.dart`، `test/test_deda_stage2_source_wiring_2026_11_21.py`.
- **الفحص:** تشغيل [44857295055](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/44857295055) — نجح فحصا `actual-source-safety` و`assembled-full-app-source` بالكامل. سجل تجميع Flutter يُظهر `00:00 +12: All tests passed!` (12 اختبار Dart)، إلى جانب 7 اختبارات Python للمرحلة الأولى و5 اختبارات Python لوصل المرحلة الثانية. اختبار الهاتف لم يحدث.
- **الحدود:** الميزتان مطفأتان افتراضياً؛ لم يصدر APK؛ لم يُنفذ Firebase deploy أو Play. صلاحية Dashboard المعزولة، إعداد OAuth/SHA، وإكمال تسجيل DEDA المرتبط بـGoogle والاختبار العملي لا تزال غير منجزة. حالة المرحلة الثانية: `PARTIAL / RELEASE_HOLD`.
