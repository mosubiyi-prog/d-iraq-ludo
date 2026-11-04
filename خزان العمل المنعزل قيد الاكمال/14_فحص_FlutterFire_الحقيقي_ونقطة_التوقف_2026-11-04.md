# DEDA — نقطة 1 / فحص FlutterFire الحقيقي: نقطة توقف موثقة

التاريخ: 2026-11-04. **النتيجة: غير مكتمل — لا يجوز ادعاء نجاح ربط Flutter الحقيقي.**

## المرجع الحاكم
قُرئ ملف `00_فكشن فكرة 💭أساس العمل 💪👷💪.md` من الخزان (blob `14309255525a76310ec59dd8d0dd026fd8d7a4b3`) قبل العمل. التزمنا: نفس UID الأصلي؛ لا استرجاع تلقائي عند فتح التطبيق؛ لا حارس جلسات منافس؛ لا تعديل نسخة 100436؛ لا دمج الأكواد الـ12؛ لا Firebase/Play/APK.

## التنفيذ المعزول
- فرع QA: `deda-100436-recovery-journal-firestore-emulator-private-qa-no-deploy-2026-11-04`.
- ملفات اختبار FlutterFire حقيقية على Chrome ضد Auth/Functions/Firestore Emulator في مشروع demo-only، ببيانات وهمية، لا اتصال بحسابات حقيقية.
- أُصلح تحميل مصادر QA في Chrome مؤقتاً عبر نسخ ملفات الاختبار إلى `test/` واستبدال imports الخاصة بـlib إلى `package:d_iraq_ludo/`، مع حذف النسخ عند انتهاء التشغيل. لم يُعدل `lib/`.
- اكتُشف سباق زمني في مرشح إصدار إذن الجهاز عند طلبين متزامنين لنفس installId: قراءة وقت الطلب قبل إعادة محاولة Firestore Transaction كانت قد تجعل الإذن الصادر في طلب موازٍ يبدو «من المستقبل» بميلي ثانية؛ صُحح **في المرشح المعزول فقط** بتسامح ترتيب وقت قدره ثانية واحدة، مع إبقاء حد انتهاء الإذن ومنع منح مزدوج. اختبار قواعد Firestore مرّ في التشغيل اللاحق، ولم تُنشر الدالة.
- اختبارات Dart/Flutter الوحدوية السابقة (13 حالة وصلة) وتحليل Dart ناجحة؛ واختبارات Firestore وAuth/Functions JavaScript Emulator السابقة نجحت. **هذا ليس دليلاً على FlutterFire SDK integration**.

## آخر نتيجة موثقة
- تشغيل [#41886712266](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41886712266) — **FAILED**.
- مرّت خطوات Firestore Emulator وتحليل Dart واختبارات الحارس/الوصلة الوحدوية.
- توقف اختبار Chrome FlutterFire الحقيقي عند أول `Firebase.initializeApp(name: 'deda-flutterfire-phoneA', options: demoOptions)`؛ سجل المرحلة `QA_FLUTTERFIRE_STEP_INITIALIZE_APP_A` ظهر، ولم يظهر سجل الخطوة التالية، ثم **TimeoutException بعد 3 دقائق**. لا نعرف بعد هل السبب تهيئة FlutterFire على Chrome test runner أو تهيئة Firebase JS في بيئة الاختبار. **لم يصل الفحص إلى تسجيل الدخول أو الاتصال بـFunctions/Firestore من Flutter**.
- تشغيلات أقدم فشلت بسبب استيراد ملفات Chrome الافتراضية، وقد عولج هذا الخطأ فقط.

## الحالة والخطوة التالية
- **الحالة:** المرحلة الأولى غير منجزة بالكامل؛ FlutterFire الحقيقي غير مثبت بعد. نمنع تفعيل المرشح.
- يجب فحص آلية `Firebase.initializeApp` في Flutter Chrome test runner وتجربة مسار تكامل متوافق أو Android Emulator فعلي ضمن QA، بدون ربط إنتاجي، ثم إعادة فحص UID الأصلي، إذن الجهاز، الجلسة، واستقلال الجهازين.
- لا نغيّر قاعدة التطبيق أو Firebase الحي، ولا نعيد تعريف النجاح بمجرد مرور JS Emulator.
- نسخة 100436 والأكواد الـ12 الأصلية محفوظة كما هي.
